import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:gadget_editor/app/widgets/simple_kernel_cmdline_editor.dart';

void _noopCancel() {}

/// Pumps the editor inside a minimal [MaterialApp] so [Form]/[Navigator]
/// work. The editor is add-only, so [kernelCmdline] is passed but unused.
Future<void> pumpEditor(
  WidgetTester tester, {
  required String? filePath,
  required Function(dynamic) onSave,
  Function() onCancel = _noopCancel,
  Function(String)? onStatusUpdate,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SimpleKernelCmdlineEditor(
        kernelCmdline: null,
        filePath: filePath,
        onSave: onSave,
        onCancel: onCancel,
        onStatusUpdate: onStatusUpdate ?? (_) {},
      ),
    ),
  ));
}

/// Selects [type] (`allow`/`append`/`remove`) from the "Parameter type"
/// dropdown. The menu labels are capitalized (`Allow`, ...), so [type] is
/// mapped to its display label. The menu item is the last matching [Text]
/// (the overlay menu renders after the form), which also disambiguates the
/// selected item that appears in both the field and the menu.
Future<void> selectType(WidgetTester tester, String type) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  final label = type[0].toUpperCase() + type.substring(1);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kernel_cmdline_test.');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeTemp(String name, String content) {
    final file = File('${tempDir.path}/$name');
    file.writeAsStringSync(content);
    return file;
  }

  /// Parses the file and returns the document (a YamlMap); callers index it
  /// with `[]` (values come back as YamlMap/YamlList, which also support `[]`).
  dynamic readBack(String path) =>
      loadYaml(File(path).readAsStringSync());

  Future<void> enter(WidgetTester tester, String parameter, String value) async {
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Kernel parameter name'), parameter);
    if (value.isNotEmpty) {
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Value (optional)'), value);
    }
    await tester.pump();
  }

  Future<void> tapAdd(WidgetTester tester) async {
    await tester.tap(find.text('Add'));
    await tester.pump();
  }

  testWidgets('appends a parameter to an existing sub-section',
      (tester) async {
    final file = writeTemp('gadget.yaml', '''
kernel-cmdline:
  allow:
    - console=ttyS0
    - debug
''');

    dynamic saved;
    final statuses = <String>[];
    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (d) => saved = d,
      onStatusUpdate: (m) => statuses.add(m),
    );

    await enter(tester, 'quiet', '');
    await selectType(tester, 'allow');
    await tapAdd(tester);

    final kc = readBack(file.path)['kernel-cmdline'];
    final allow = kc['allow'];
    expect(allow.length, 3, reason: 'existing entries must survive the append');
    expect(allow[0], 'console=ttyS0');
    expect(allow[1], 'debug');
    expect(allow[2], 'quiet', reason: 'value-less param stored bare');
    expect(statuses.last, 'Kernel parameter added successfully');
    expect(saved, isA<Map>());
  });

  testWidgets('stores a bare parameter when no value is given', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');

    await pumpEditor(tester, filePath: file.path, onSave: (_) {});

    await enter(tester, 'debug', '');
    await selectType(tester, 'allow');
    await tapAdd(tester);

    final kc = readBack(file.path)['kernel-cmdline'];
    expect(kc['allow'], ['debug']);
  });

  testWidgets('stores parameter=value when a value is given', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');

    await pumpEditor(tester, filePath: file.path, onSave: (_) {});

    await enter(tester, 'loglevel', '4');
    await selectType(tester, 'append');
    await tapAdd(tester);

    final kc = readBack(file.path)['kernel-cmdline'];
    expect(kc['append'], ['loglevel=4']);
  });

  testWidgets('creates a missing sub-section at the end of the section',
      (tester) async {
    final file = writeTemp('gadget.yaml', '''
kernel-cmdline:
  allow:
    - console=ttyS0
''');

    await pumpEditor(tester, filePath: file.path, onSave: (_) {});

    await enter(tester, 'debug', '');
    await selectType(tester, 'remove');
    await tapAdd(tester);

    final kc = readBack(file.path)['kernel-cmdline'];
    expect(kc['allow'], ['console=ttyS0']);
    expect(kc['remove'], ['debug']);
  });

  testWidgets('creates the whole section when it is missing', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');

    await pumpEditor(tester, filePath: file.path, onSave: (_) {});

    await enter(tester, 'console', 'ttyS0');
    await selectType(tester, 'allow');
    await tapAdd(tester);

    final kc = readBack(file.path)['kernel-cmdline'];
    expect(kc['allow'], ['console=ttyS0']);
    // The rest of the document is preserved.
    expect(readBack(file.path)['name'], 'pc');
  });

  testWidgets('rejects an empty parameter', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');
    final statuses = <String>[];

    await pumpEditor(
      tester,
      filePath: file.path,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    await enter(tester, '', '4');
    await tapAdd(tester);

    expect(statuses.last, 'Error: Please enter a parameter');
    expect(readBack(file.path).containsKey('kernel-cmdline'), isFalse);
  });

  testWidgets('reports an error when no file path is provided', (tester) async {
    final statuses = <String>[];

    await pumpEditor(
      tester,
      filePath: null,
      onSave: (_) {},
      onStatusUpdate: (m) => statuses.add(m),
    );

    await enter(tester, 'quiet', '');
    await tapAdd(tester);

    expect(statuses.last, 'Error: No file path provided');
  });

  testWidgets('clears the form fields after a successful save', (tester) async {
    final file = writeTemp('gadget.yaml', 'name: pc\n');

    await pumpEditor(tester, filePath: file.path, onSave: (_) {});

    await enter(tester, 'quiet', '');
    await selectType(tester, 'allow');
    await tapAdd(tester);
    await tester.pump();

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Kernel parameter name'),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.controller.text, isEmpty);
  });
}
