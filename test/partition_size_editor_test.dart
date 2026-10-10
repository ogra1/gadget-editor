// Widget tests for [PartitionSizeEditor].
//
// The editor is a dialog with a single "Size" field; saving writes the
// partition's `size` back into the gadget YAML structure list and reports
// through [onSave]/[onPartitionChanged]/[onStatusUpdate]. Tests round-trip
// through a real temp file.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:gadget_editor/app/widgets/partition_size_editor.dart';

void _noopCancel() {}

Future<void> pumpEditor(
  WidgetTester tester, {
  required String partitionName,
  required String volumeName,
  required String? filePath,
  String? currentSize,
  required Function(String) onSave,
  Function() onCancel = _noopCancel,
  Function(String)? onStatusUpdate,
  Function()? onPartitionChanged,
}) {
  final captured = <String>[];
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: PartitionSizeEditor(
          partitionName: partitionName,
          volumeName: volumeName,
          filePath: filePath,
          currentSize: currentSize,
          onSave: onSave,
          onCancel: onCancel,
          onStatusUpdate: onStatusUpdate ?? (m) => captured.add(m),
          onPartitionChanged: onPartitionChanged,
        ),
      ),
    ),
  ));
}

Future<void> tapSave(WidgetTester tester) async {
  // Save is async: it does real file I/O and shows an indeterminate
  // CircularProgressIndicator while in flight, so pumpAndSettle would time
  // out (the spinner never settles and real I/O ignores fake-async time).
  // Run the pumps in a real-async zone so the I/O actually completes.
  await tester.runAsync(() async {
    await tester.tap(find.text('Save'));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  });
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('partition_size_test.');
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

  const String baseGadgetYaml = '''
name: pc
volumes:
  pc:
    structure:
      - name: mbr
        size: 1M
      - name: boot
        size: 200M
      - name: root
        size: 1G
''';

  testWidgets('updates the size of the named partition only', (tester) async {
    final file = writeTemp('gadget.yaml', baseGadgetYaml);
    String? saved;
    var changed = false;
    final statuses = <String>[];
    await pumpEditor(
      tester,
      partitionName: 'root',
      volumeName: 'pc',
      filePath: file.path,
      currentSize: '1G',
      onSave: (s) => saved = s,
      onStatusUpdate: (m) => statuses.add(m),
      onPartitionChanged: () => changed = true,
    );

    // The field is pre-filled with the current size.
    expect(find.text('1G'), findsWidgets);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Size'), '2G');
    await tapSave(tester);

    final structure = readBack(file.path)['volumes']['pc']['structure'];
    expect(structure[0]['name'], 'mbr');
    expect(structure[0]['size'], '1M',
        reason: 'untouched partition must keep its size');
    expect(structure[2]['name'], 'root');
    expect(structure[2]['size'], '2G',
        reason: 'the targeted partition must get the new size');
    expect(saved, '2G');
    expect(changed, isTrue, reason: 'onPartitionChanged must fire');
    expect(statuses.last, contains('updated successfully'));
  });

  testWidgets('accepts unitless and unit-suffixed sizes', (tester) async {
    final file = writeTemp('gadget.yaml', baseGadgetYaml);
    await pumpEditor(
      tester,
      partitionName: 'boot',
      volumeName: 'pc',
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (_) {},
    );

    // Unitless (sector count).
    await tester.enterText(find.widgetWithText(TextFormField, 'Size'), '440');
    await tapSave(tester);
    expect(
        readBack(file.path)['volumes']['pc']['structure'][1]['size'], '440');

    // Unit-suffixed.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Size'), '512M');
    await tapSave(tester);
    expect(
        readBack(file.path)['volumes']['pc']['structure'][1]['size'], '512M');
  });

  testWidgets('rejects an empty size via form validation without writing',
      (tester) async {
    final file = writeTemp('gadget.yaml', baseGadgetYaml);
    final before = File(file.path).readAsStringSync();
    var saved = false;
    await pumpEditor(
      tester,
      partitionName: 'root',
      volumeName: 'pc',
      filePath: file.path,
      currentSize: '1G',
      onSave: (_) => saved = true,
      onStatusUpdate: (_) {},
    );

    // Clear the pre-filled size so the field is empty.
    await tester.enterText(find.widgetWithText(TextFormField, 'Size'), '');
    await tapSave(tester);

    // The form validator (not the status bar) surfaces the empty-size error,
    // and the save never runs.
    expect(find.text('Please enter a size'), findsWidgets,
        reason: 'empty size must be flagged by the form validator');
    expect(saved, isFalse,
        reason: 'an invalid (empty) size must not trigger a save');
    expect(File(file.path).readAsStringSync(), before,
        reason: 'a rejected save must not touch the file');
  });

  testWidgets('reports an error when the partition is not found',
      (tester) async {
    final file = writeTemp('gadget.yaml', baseGadgetYaml);
    final before = File(file.path).readAsStringSync();
    final statuses = <String>[];
    await pumpEditor(
      tester,
      partitionName: 'does-not-exist',
      volumeName: 'pc',
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    await tester.enterText(find.widgetWithText(TextFormField, 'Size'), '1G');
    await tapSave(tester);

    expect(statuses.last,
        'Error: Partition or volume structure not found.');
    expect(File(file.path).readAsStringSync(), before);
  });

  testWidgets('reports an error when no file path is provided',
      (tester) async {
    final statuses = <String>[];
    await pumpEditor(
      tester,
      partitionName: 'root',
      volumeName: 'pc',
      filePath: null,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    await tester.enterText(find.widgetWithText(TextFormField, 'Size'), '1G');
    await tapSave(tester);

    expect(statuses.last, 'Error: No file path provided');
  });

  testWidgets('cancels without writing', (tester) async {
    final file = writeTemp('gadget.yaml', baseGadgetYaml);
    final before = File(file.path).readAsStringSync();
    var cancelled = false;
    await pumpEditor(
      tester,
      partitionName: 'root',
      volumeName: 'pc',
      filePath: file.path,
      onSave: (_) => fail('onSave must not fire on cancel'),
      onCancel: () => cancelled = true,
      onStatusUpdate: (_) {},
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    expect(File(file.path).readAsStringSync(), before);
  });
}
