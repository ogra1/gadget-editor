import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gadget_editor/app/widgets/api_key_section.dart';
import 'package:gadget_editor/app/widgets/gadget_content.dart';
import 'package:gadget_editor/services/gadget_yaml_service.dart';
import 'package:gadget_editor/services/prepare_device_hook_service.dart';

/// The store API key is a single scalar edited inline (no dialog). These tests
/// cover [ApiKeySection] in isolation, plus end-to-end round trips through
/// [GadgetContent] backed by real temp files — including the prepare-device
/// hook lifecycle (created when missing, never overwritten).
void main() {
  group('ApiKeySection', () {
    Widget wrap(String key, {ValueChanged<String>? onSave}) {
      return MaterialApp(
        home: Scaffold(
          body: ApiKeySection(
            key: const ValueKey('api-key-section'),
            currentKey: key,
            onSave: onSave ?? (_) {},
          ),
        ),
      );
    }

    testWidgets('shows the title and subtitle', (tester) async {
      await tester.pumpWidget(wrap('abc123'));
      expect(find.text('Store API Key'), findsOneWidget);
      expect(
        find.textContaining('Used by the prepare-device hook'),
        findsOneWidget,
      );
    });

    testWidgets('renders the current key in the editable field',
        (tester) async {
      await tester.pumpWidget(wrap('abc123'));
      expect(find.text('abc123'), findsOneWidget);
      // The label caption is drawn above the chip.
      expect(find.text('MODEL_APIKEY'), findsOneWidget);
    });

    testWidgets('renders an empty chip when no key is set', (tester) async {
      await tester.pumpWidget(wrap(''));
      expect(find.text('abc123'), findsNothing);
      expect(find.text('MODEL_APIKEY'), findsOneWidget);
    });

    testWidgets('editing + saving calls onSave with the new value',
        (tester) async {
      String? saved;
      await tester.pumpWidget(wrap('old-value', onSave: (v) => saved = v));
      await tester.tap(find.text('old-value'));
      await tester.pump();
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.enterText(field, 'new-value');
      await tester.tap(find.byIcon(Icons.check));
      await tester.pump();
      expect(saved, 'new-value');
    });

    testWidgets('cancelling does not call onSave', (tester) async {
      var calls = 0;
      await tester.pumpWidget(wrap('old-value', onSave: (_) => calls++));
      await tester.tap(find.text('old-value'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(calls, 0);
    });
  });

  group('GadgetContent end-to-end (temp file round trip)', () {
    late Directory tempDir;
    late File gadgetFile;
    final hookService = PrepareDeviceHookService();

    // gadget.yaml holds the architecture content and carries NO hooks.
    const gadgetDoc = '''
name: pc
version: 26-0.1
base: core26
''';

    // snap.yaml holds the snap metadata, including the prepare-device hook
    // where the store API key actually lives.
    const snapDoc = '''
name: pc
version: 26-0.1
base: core26
type: gadget
hooks:
  prepare-device:
    environment:
      MODEL_APIKEY: 'initial'
''';

    const bareSnapDoc = '''
name: pc
version: 26-0.1
base: core26
type: gadget
''';

    const customHook = '#!/bin/sh\n# my vendor-specific hook\necho done\n';

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('api_key_e2e.');
      gadgetFile = File('${tempDir.path}/gadget.yaml');
      gadgetFile.writeAsStringSync(gadgetDoc);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    /// Expands the editor, commits [key], returns nothing (status captured
    /// via the closure in each test).
    Future<void> commitKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.text('Store API Key'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), key);
      await tester.tap(find.byIcon(Icons.check));
      await tester.pump();
    }

    testWidgets('saves the key into snap.yaml, leaving gadget.yaml alone',
        (tester) async {
      final snapFile = File('${tempDir.path}/snap.yaml');
      snapFile.writeAsStringSync(snapDoc);
      String? status;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GadgetContent(
            content: gadgetDoc,
            filePath: gadgetFile.path,
            snapFilePath: snapFile.path,
            onContentChanged: (_) {},
            onStatusUpdate: (m) => status = m,
          ),
        ),
      ));

      expect(find.text('Store API Key'), findsOneWidget);

      await commitKey(tester, 'real-key-123');

      expect(status, 'Store key saved');
      final snap = GadgetYaml.fromFile(snapFile.path);
      expect(snap.getApiKey(), 'real-key-123');
      expect(
        snap.toMap()['hooks']['prepare-device']['environment']['MODEL_APIKEY'],
        'real-key-123',
      );
      final gadget = GadgetYaml.fromFile(gadgetFile.path);
      expect(gadget.getApiKey(), isNull);
      expect(gadget.toMap().containsKey('hooks'), isFalse);
    });

    testWidgets(
        'saving a key into a snap with no hook creates an executable hook',
        (tester) async {
      final snapFile = File('${tempDir.path}/snap_bare.yaml');
      snapFile.writeAsStringSync(bareSnapDoc);
      String? status;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GadgetContent(
            content: gadgetDoc,
            filePath: gadgetFile.path,
            snapFilePath: snapFile.path,
            onContentChanged: (_) {},
            onStatusUpdate: (m) => status = m,
          ),
        ),
      ));

      // No hook on disk yet.
      final hookPath = hookService.scriptPathFor(snapFile.path);
      expect(File(hookPath).existsSync(), isFalse);

      await commitKey(tester, 'brand-new-key');

      expect(status, 'Store key saved');
      expect(GadgetYaml.fromFile(snapFile.path).getApiKey(), 'brand-new-key');
      // A prepare-device hook was created, executable, canonical.
      final hook = File(hookPath);
      expect(hook.existsSync(), isTrue);
      expect(hook.readAsStringSync(), PrepareDeviceHookService.script);
      const execMask = 0x49; // 0o111
      expect(hook.statSync().mode & execMask, execMask);
    });

    testWidgets('saving a key never overwrites an existing custom hook',
        (tester) async {
      final snapFile = File('${tempDir.path}/snap_custom.yaml');
      snapFile.writeAsStringSync(bareSnapDoc);
      final hookPath = hookService.scriptPathFor(snapFile.path);
      final hook = File(hookPath);
      hook.parent.createSync(recursive: true);
      hook.writeAsStringSync(customHook);
      String? status;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GadgetContent(
            content: gadgetDoc,
            filePath: gadgetFile.path,
            snapFilePath: snapFile.path,
            onContentChanged: (_) {},
            onStatusUpdate: (m) => status = m,
          ),
        ),
      ));

      await commitKey(tester, 'new-key-2');

      expect(status, 'Store key saved');
      expect(GadgetYaml.fromFile(snapFile.path).getApiKey(), 'new-key-2');
      // The custom hook is preserved, NOT replaced by the canonical one.
      expect(hook.readAsStringSync(), customHook);
      expect(hook.readAsStringSync(), isNot(PrepareDeviceHookService.script));
    });
  });
}
