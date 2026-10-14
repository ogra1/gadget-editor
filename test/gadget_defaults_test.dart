// Integration tests for the Defaults section of [GadgetContent]: the
// per-setting trash icons in the snap-ID cards delete a single setting
// (round-tripping through gadget.yaml), and the snap-ID block — and the
// whole `defaults` section — is pruned only once it is empty.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:gadget_editor/app/widgets/gadget_content.dart';

const _gadgetYaml = '''
name: pc
defaults:
  core20:
    refresh-motivation: timely
    hold: true
  core22:
    debug: 1
''';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gadget_defaults_test.');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeTemp(String name, String content) {
    final file = File('${tempDir.path}/$name');
    file.writeAsStringSync(content);
    return file;
  }

  dynamic readBack(String path) => loadYaml(File(path).readAsStringSync());

  /// Tall viewport so the Defaults tree is on-screen without scrolling.
  Future<void> pumpContent(WidgetTester tester, String filePath) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GadgetContent(
          content: File(filePath).readAsStringSync(),
          filePath: filePath,
          onStatusUpdate: (m) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Taps the [index]th per-setting icon and confirms (or cancels) the
  /// dialog.
  Future<void> tapSettingDelete(WidgetTester tester, int index,
      {required bool confirm}) async {
    await tester.tap(find.byTooltip('Delete setting').at(index));
    await tester.pumpAndSettle();
    expect(find.text('Delete Default'), findsOneWidget);
    await tester.tap(find.text(confirm ? 'Delete' : 'Cancel').last);
    await tester.pumpAndSettle();
  }

  testWidgets('deletes one setting, keeps the siblings (file + UI)',
      (tester) async {
    final file = writeTemp('gadget.yaml', _gadgetYaml);
    await pumpContent(tester, file.path);

    // core20 shows both settings with their per-setting icons.
    expect(find.text('refresh-motivation:'), findsOneWidget);
    expect(find.text('hold:'), findsOneWidget);
    expect(find.byTooltip('Delete setting'), findsNWidgets(3));

    // Delete 'hold' (the second setting overall).
    await tapSettingDelete(tester, 1, confirm: true);

    // The tree no longer renders it...
    expect(find.text('hold:'), findsNothing);
    expect(find.text('refresh-motivation:'), findsOneWidget);
    // ...and the on-disk YAML agrees.
    final defaults = readBack(file.path)['defaults'];
    expect(defaults['core20'].keys.toList(), ['refresh-motivation']);
    expect(defaults['core22']['debug'], 1);
  });

  testWidgets('cancelling keeps the setting', (tester) async {
    final file = writeTemp('gadget.yaml', _gadgetYaml);
    await pumpContent(tester, file.path);

    await tapSettingDelete(tester, 0, confirm: false);

    expect(find.text('refresh-motivation:'), findsOneWidget);
    final defaults = readBack(file.path)['defaults'];
    expect(defaults['core20'].keys.toList(), ['refresh-motivation', 'hold']);
  });

  testWidgets('the snap-ID block is pruned once its last setting goes',
      (tester) async {
    final file = writeTemp(
        'gadget.yaml',
        'name: pc\ndefaults:\n  core20:\n    a: 1\n    b: 2\n'
            '  core22:\n    c: 3\n');
    await pumpContent(tester, file.path);

    // Delete 'a' then 'b': core20 disappears, core22 remains.
    await tapSettingDelete(tester, 0, confirm: true);
    expect(find.text('a:'), findsNothing);
    await tapSettingDelete(tester, 0, confirm: true);
    expect(find.text('b:'), findsNothing);
    expect(find.text('Snap: core20'), findsNothing);
    expect(find.text('c:'), findsOneWidget);

    final defaults = readBack(file.path)['defaults'];
    expect(defaults.keys.toList(), ['core22']);
  });

  testWidgets('the defaults section is pruned when the last snap ID goes',
      (tester) async {
    final file =
        writeTemp('gadget.yaml', 'name: pc\ndefaults:\n  core20:\n    a: 1\n');
    await pumpContent(tester, file.path);

    await tapSettingDelete(tester, 0, confirm: true);

    expect(find.text('a:'), findsNothing);
    final yaml = readBack(file.path);
    expect(yaml.containsKey('defaults'), isFalse);
    expect(yaml['name'], 'pc');
  });
}
