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
import 'package:gadget_editor/app/widgets/partition_size_editor.dart';
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

const _multiPartitionYaml = '''
name: pc
volumes:
  pc2004:
    bootloader: grub
    structure:
      - name: system-seed
        size: 1G
        role: system-seed
        type: M
      - name: system-boot
        size: 512M
        role: system-boot
        type: M
''';

// The user's real-world case: a mix with a very small partition (10M) among
// 1.2G and 5G. The 10M tile is far too narrow to show its name, so it must
// degrade to a bare color stripe while the larger partitions keep their labels.
const _stripeYaml = '''
name: pc
volumes:
  pc2004:
    bootloader: grub
    structure:
      - name: boot
        size: 10M
      - name: save
        size: 1200M
      - name: data
        role: system-data
        size: 5G
''';

// A partition with a multi-target content list, to verify the tooltip wraps
// the targets one per line (no single wide comma-joined line).
const _contentYaml = '''
name: pc
volumes:
  pc2004:
    bootloader: grub
    structure:
      - name: data
        role: system-data
        size: 5G
        content:
          - target: EFI/ubuntu/grubx64.efi
          - target: EFI/ubuntu/shimx64.efi
          - target: EFI/ubuntu/bootx64.efi
''';

// One large (1G -> dark blue #1976D2 fill) and one small (512M -> pastel
// #90CAF9 fill) partition, to check that the tile text color is chosen from
// the fill's own luminance: white on the dark fill, dark on the light fill.
const _luminanceYaml = '''
name: pc
volumes:
  pc2004:
    bootloader: grub
    structure:
      - name: large
        size: 1G
      - name: small
        size: 512M
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
    bool dark = false,
  }) async {
    final doc = loadYaml(File(filePath).readAsStringSync());
    final volumes = (doc is YamlMap) ? doc['volumes'] : null;
    await tester.pumpWidget(MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
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

  // The partition pencil is the only 18px edit icon in the tree; the volume-
  // name chip's pencil is 14px. Filter by size to disambiguate.
  Finder partitionPencil() => find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Icons.edit && w.size == 18.0,
      );

  testWidgets('a resizable partition is marked with a dimmed pencil and the whole tile opens the editor',
      (tester) async {
    final file = writeYaml(_multiPartitionYaml);
    final statuses = <String>[];
    await pumpSection(tester, filePath: file.path, statuses: statuses);

    // Exactly one partition (system-seed) is resizable -> exactly one pencil.
    expect(partitionPencil(), findsOneWidget);
    // The pencil is dimmed (not opaque white).
    final pencil = tester.widget<Icon>(partitionPencil());
    expect(pencil.color?.a, lessThan(1.0));

    // Tapping the resizable tile (via its label) opens the size editor.
    await tester.tap(find.text('system-seed'));
    await tester.pumpAndSettle();
    expect(find.byType(PartitionSizeEditor), findsOneWidget);
    expect(find.text('Edit Size for system-seed'), findsOneWidget);

    // Close the dialog again.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(PartitionSizeEditor), findsNothing);
  });

  testWidgets('tapping a non-resizable partition does not open the editor',
      (tester) async {
    final file = writeYaml(_multiPartitionYaml);
    final statuses = <String>[];
    await pumpSection(tester, filePath: file.path, statuses: statuses);

    // system-boot is not resizable: no pencil is shown for it, and tapping it
    // must not open the editor.
    expect(partitionPencil(), findsOneWidget); // only the system-seed one
    await tester.tap(find.text('system-boot'));
    await tester.pumpAndSettle();
    expect(find.byType(PartitionSizeEditor), findsNothing);
  });

  group('partition tile stripe + tooltip', () {
    testWidgets('large partitions keep their name labels', (tester) async {
      final file = writeYaml(_stripeYaml);
      await pumpSection(tester, filePath: file.path, statuses: <String>[]);
      // Both wide partitions are wide enough to show their names.
      expect(find.text('save'), findsOneWidget);
      expect(find.text('data'), findsOneWidget);
    });

    testWidgets('a very small partition degrades to a bare stripe (no name)',
        (tester) async {
      final file = writeYaml(_stripeYaml);
      await pumpSection(tester, filePath: file.path, statuses: <String>[]);
      // The 10M "boot" tile is far too narrow to fit its name -> no label,
      // just a thin colored stripe. The wider partitions still show names.
      expect(find.text('boot'), findsNothing);
      expect(find.text('save'), findsOneWidget);
      expect(find.text('data'), findsOneWidget);
    });

    testWidgets('every partition tile carries a tooltip with its full data',
        (tester) async {
      final file = writeYaml(_stripeYaml);
      await pumpSection(tester, filePath: file.path, statuses: <String>[]);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .join('\n');

      // One tooltip per partition, each carrying the yaml data so the info is
      // available even for the bare-stripe (name-hidden) partitions.
      expect(find.byType(Tooltip), findsNWidgets(3));
      expect(messages, contains('name: boot'));
      expect(messages, contains('name: save'));
      expect(messages, contains('name: data'));
      expect(messages, contains('role: system-data'));
      expect(messages, contains('size: 5.0G'));
    });

    testWidgets('labeled partitions expose a small info icon as the tooltip trigger',
        (tester) async {
      final file = writeYaml(_stripeYaml);
      await pumpSection(tester, filePath: file.path, statuses: <String>[]);

      // Two partitions show their labels (save, data) -> each carries an info
      // icon; the bare-stripe partition (boot) has none.
      expect(find.byIcon(Icons.info_outline), findsNWidgets(2));

      // The info-icon tooltips carry the labeled partitions' data only.
      final iconMessages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .where((t) => t.child is Icon)
          .map((t) => t.message)
          .join('\n');
      expect(iconMessages, contains('name: save'));
      expect(iconMessages, contains('name: data'));
      expect(iconMessages, isNot(contains('name: boot')));
    });

    testWidgets('a bare-stripe partition binds its tooltip to the whole tile (no info icon)',
        (tester) async {
      final file = writeYaml(_stripeYaml);
      await pumpSection(tester, filePath: file.path, statuses: <String>[]);

      // Exactly one partition is a bare stripe (boot) -> its tooltip's child is
      // the tile Container (the whole tile is the trigger), not an Icon.
      final wholeTileTooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .where((t) => t.child is Container)
          .toList();
      expect(wholeTileTooltips, hasLength(1));
      expect(wholeTileTooltips.single.message, contains('name: boot'));
    });

    testWidgets('content list wraps one target per line (no single wide line)',
        (tester) async {
      final file = writeYaml(_contentYaml);
      await pumpSection(tester, filePath: file.path, statuses: <String>[]);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .join('\n');

      // Targets are listed one per line (indented) rather than as a single
      // comma-joined line, so a long content list cannot make the tooltip
      // wider than the app.
      expect(messages, contains('content:\n  - EFI/ubuntu/grubx64.efi'));
      expect(messages, contains('  - EFI/ubuntu/shimx64.efi'));
      expect(messages, contains('  - EFI/ubuntu/bootx64.efi'));
      // No comma-joined single-line content form remains.
      expect(messages, isNot(contains('content: EFI/')));
    });
  });

  group('partition tile text color follows fill luminance', () {
    Color textColorOf(WidgetTester tester, String label) {
      final t = tester.widget<Text>(find.text(label));
      final color = t.style?.color;
      expect(color, isA<Color>());
      return color as Color;
    }

    testWidgets('dark fill gets white text, light fill gets dark text',
        (tester) async {
      final file = writeYaml(_luminanceYaml);
      await pumpSection(tester, filePath: file.path, statuses: <String>[]);

      // 1G partition -> large size -> dark blue #1976D2 fill (luminance
      // ~0.15) -> white text.
      expect(textColorOf(tester, 'large'), Colors.white);
      // 512M partition -> small size -> pastel #90CAF9 fill -> near-black
      // text (dark, but not pure black).
      final smallColor = textColorOf(tester, 'small');
      expect(smallColor, const Color(0xFF1C1C1C));
    });

    testWidgets('switching to the dark theme does not change the text colors',
        (tester) async {
      final file = writeYaml(_luminanceYaml);
      // The text color is keyed off the fill, not the app theme, so a dark
      // theme must produce exactly the same colors as light mode.
      await pumpSection(tester, filePath: file.path, statuses: <String>[],
          dark: true);

      expect(textColorOf(tester, 'large'), Colors.white);
      expect(textColorOf(tester, 'small'), const Color(0xFF1C1C1C));
    });
  });
}
