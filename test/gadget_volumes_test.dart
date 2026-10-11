// Widget tests for the volume-name edit in [GadgetVolumesSection].
//
// A volume name can be changed in place. The edit must not accept an empty
// (or whitespace-only) value: that used to silently leave a blank chip with
// no error. These tests assert the field snaps back to the original name and
// reports an error, and that a valid rename still round-trips to the file.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/app/widgets/gadget_volumes.dart';
import 'package:gadget_editor/app/widgets/editable_text_field.dart';
import 'package:yaml/yaml.dart';

const _volYaml = '''
name: pc
volumes:
  pc2004:
    bootloader: grub
    structure:
      - name: system-seed
        size: 1G
        role: system-seed
        type: M
''';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gadget_volumes_test.');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeYaml(String content) {
    final f = File('${tempDir.path}/gadget.yaml');
    f.writeAsStringSync(content);
    return f;
  }

  Future<void> pumpSection(
    WidgetTester tester, {
    required String filePath,
    required List<String> statuses,
  }) async {
    final doc = loadYaml(File(filePath).readAsStringSync());
    final volumes = (doc is YamlMap) ? doc['volumes'] : null;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GadgetVolumesSection(
          volumes: volumes,
          filePath: filePath,
          refreshCallback: () {},
          onStatusUpdate: (m) => statuses.add(m),
        ),
      ),
    ));
  }

  // Tap the volume-name chip to expand it into a field. It's the only
  // [EditableTextField] in the tree (the partition pencil is a bare Icon,
  // not an [EditableTextField]).
  Future<void> openEditor(WidgetTester tester) async {
    await tester.pump();
    expect(find.byType(EditableTextField), findsOneWidget);
    await tester.tap(find.byType(EditableTextField));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  }

  testWidgets('saving an empty volume name is rejected and snaps back',
      (tester) async {
    final file = writeYaml(_volYaml);
    final statuses = <String>[];
    await pumpSection(tester, filePath: file.path, statuses: statuses);

    await openEditor(tester);
    // Replace the name with nothing, then save.
    await tester.enterText(find.byType(TextField).at(0), '');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    // Error is reported and the field is back to the original name (chip).
    expect(statuses, contains('Error: Volume name cannot be empty'));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('pc2004'), findsOneWidget);
    // The file was not touched: the volume key is unchanged.
    expect(file.readAsStringSync(), contains('pc2004'));
  });

  testWidgets('saving a whitespace-only volume name is also rejected',
      (tester) async {
    final file = writeYaml(_volYaml);
    final statuses = <String>[];
    await pumpSection(tester, filePath: file.path, statuses: statuses);

    await openEditor(tester);
    await tester.enterText(find.byType(TextField).at(0), '   ');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(statuses, contains('Error: Volume name cannot be empty'));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('pc2004'), findsOneWidget);
    expect(file.readAsStringSync(), contains('pc2004'));
  });

  testWidgets('a valid volume rename still round-trips to the file',
      (tester) async {
    final file = writeYaml(_volYaml);
    final statuses = <String>[];
    await pumpSection(tester, filePath: file.path, statuses: statuses);

    await openEditor(tester);
    await tester.enterText(find.byType(TextField).at(0), 'pc26');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(statuses, contains('Volume name updated successfully'));
    expect(find.text('pc26'), findsOneWidget);
    expect(find.text('pc2004'), findsNothing);
    // The rename actually landed on disk.
    expect(file.readAsStringSync(), contains('pc26:'));
    expect(file.readAsStringSync(), isNot(contains('pc2004:')));
  });
}
