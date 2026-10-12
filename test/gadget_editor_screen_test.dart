import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/app/gadget_editor_screen.dart';
import 'package:gadget_editor/services/snap_file_service.dart';
import 'package:gadget_editor/services/snap_pack_service.dart';
import 'package:gadget_editor/services/snap_store_service.dart';

// Resizing the test surface from setUp (outside a testWidgets body) requires
// the pre-multi-window `window.*TestValue` API, which is deprecated. Suppress
// the resulting info across this file.
// ignore_for_file: deprecated_member_use

/// Widget tests for the editable snap **name** and **version** fields in the
/// header row, verifying each edit round-trips to the on-disk `meta/snap.yaml`.
///
/// The screen's State is public on purpose: these tests seed a "local snap
/// already loaded" state directly (pointing the fields at a real temp file)
/// rather than driving the full `unsquashfs` extraction path, which performs
/// real async I/O that doesn't settle under a `testWidgets` fake-async zone.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gadget_screen_test.');
    // The app is a desktop layout (300px sidebar + main area); the default
    // 800x600 test surface is too narrow and the header row overflows. Use a
    // realistic window size so the layout matches production. Done via the
    // binding (not a WidgetTester) so it applies to every test in the group.
    // The non-tester-scoped resize API is deprecated ahead of multi-window
    // support but is still the only way to size the surface in setUp.
    final window = TestWidgetsFlutterBinding.instance.window;
    window.physicalSizeTestValue = const Size(1440, 900);
    window.devicePixelRatioTestValue = 1.0;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.window.clearAllTestValues();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeSnapYaml(String content) {
    final f = File('${tempDir.path}/snap.yaml');
    f.writeAsStringSync(content);
    return f;
  }

  // Pump the screen with a loaded-snap state whose editable fields point at
  // [snapYamlPath]. Returns the (public) State for assertions.
  Future<GadgetEditorScreenState> pumpLoaded(
    WidgetTester tester, {
    required String snapName,
    required File snapYaml,
    String? version,
    List<String> architectures = const ['amd64'],
  }) async {
    final key = GlobalKey<GadgetEditorScreenState>();
    await tester.pumpWidget(MaterialApp(
      home: GadgetEditorScreen(
        key: key,
        storeService: SnapStoreService(),
        fileService: SnapFileService(),
        packService: SnapPackService(),
      ),
    ));
    await tester.pump();

    final state = key.currentState!;
    // Seed the loaded-snap fields directly. Calling setState from outside the
    // State is normally off-limits; this is an intentional test-only seed.
    // ignore: invalid_use_of_protected_member
    state.setState(() {
      state.snapName = snapName;
      state.gadgetData = <String, dynamic>{'volumes': <String, dynamic>{} };
      state.gadgetContent = 'volumes: {}\n';
      state.snapVersion = version;
      state.snapArchitectures = architectures;
      state.snapFilePath = snapYaml.path;
      state.gadgetFilePath = snapYaml.path;
      state.statusMessage = 'Local gadget snap loaded successfully';
      state.isActionButtonEnabled = true;
    });
    await tester.pump();
    return state;
  }

  // Expand the keyed EditableTextField into its editor and assert it opened.
  Future<void> openEditor(WidgetTester tester, ValueKey key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
      findsOneWidget,
      reason: 'editing mode should expand a TextField for $key',
    );
  }

  Finder editorField(ValueKey key) =>
      find.descendant(of: find.byKey(key), matching: find.byType(TextField));

  Finder checkButton(ValueKey key) =>
      find.descendant(of: find.byKey(key), matching: find.byIcon(Icons.check));

  const nameKey = ValueKey('snap-name-field');
  const versionKey = ValueKey('snap-version-field');

  testWidgets('editing the snap name persists to meta/snap.yaml',
      (tester) async {
    final snap = writeSnapYaml('name: pc\nversion: "1.0"\nconfinement: strict\n');

    await pumpLoaded(tester, snapName: 'pc', snapYaml: snap, version: '1.0');
    expect(find.text('pc'), findsWidgets); // header chip + sidebar

    await openEditor(tester, nameKey);
    await tester.enterText(editorField(nameKey), 'pc2');
    await tester.pump();
    await tester.tap(checkButton(nameKey));
    await tester.pumpAndSettle();

    expect(snap.readAsStringSync(), contains('name: pc2'));
    expect(snap.readAsStringSync(), isNot(contains('name: pc\n')));
    expect(find.text('Snap name saved successfully'), findsOneWidget);
  });

  testWidgets('editing the snap version persists to meta/snap.yaml',
      (tester) async {
    final snap = writeSnapYaml('name: pc\nversion: "1.0"\nconfinement: strict\n');

    await pumpLoaded(tester, snapName: 'pc', snapYaml: snap, version: '1.0');

    await openEditor(tester, versionKey);
    await tester.enterText(editorField(versionKey), '2.5.0');
    await tester.pump();
    await tester.tap(checkButton(versionKey));
    await tester.pumpAndSettle();

    // yaml_edit writes the scalar unquoted (2.5.0 is not a bare number).
    expect(snap.readAsStringSync(), contains('version: 2.5.0'));
    expect(snap.readAsStringSync(), isNot(contains('1.0')));
    expect(find.text('Version saved successfully'), findsOneWidget);
  });

  testWidgets('setting a version on a snap that has none inserts the key',
      (tester) async {
    // No `version:` line in the source snap.
    final snap = writeSnapYaml('name: pc\nconfinement: strict\n');

    await pumpLoaded(tester, snapName: 'pc', snapYaml: snap, version: null);
    expect(find.byKey(versionKey), findsOneWidget); // empty chip at rest

    await openEditor(tester, versionKey);
    await tester.enterText(editorField(versionKey), '9.9.9');
    await tester.pump();
    await tester.tap(checkButton(versionKey));
    await tester.pumpAndSettle();

    expect(snap.readAsStringSync(), contains('version: 9.9.9'));
    expect(find.text('Version saved successfully'), findsOneWidget);
  });

  testWidgets('saving an empty version is rejected and snaps back',
      (tester) async {
    final snap = writeSnapYaml('name: pc\nversion: "1.0"\nconfinement: strict\n');

    await pumpLoaded(tester, snapName: 'pc', snapYaml: snap, version: '1.0');

    await openEditor(tester, versionKey);
    await tester.enterText(editorField(versionKey), '   ');
    await tester.pump();
    await tester.tap(checkButton(versionKey));
    await tester.pumpAndSettle();

    // Rejected: the file is untouched and the field reverts to "1.0".
    expect(snap.readAsStringSync(), contains('version: "1.0"'));
    expect(snap.readAsStringSync(), isNot(contains('version: ""')));
    expect(find.textContaining('Invalid version'), findsOneWidget);
    expect(find.text('1.0'), findsWidgets);
  });
}
