import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/app/widgets/gadget_section.dart';
import 'package:yaru/yaru.dart';
import 'package:yaml/yaml.dart';

/// Structural tests for the restyled [GadgetSection]: each section renders a
/// tinted icon-chip header, and the empty state shows the dashed drop-zone
/// with an "Add …" button. Pumps under the real Yaru theme (light + dark), so
/// any layout overflow in the new header/empty state surfaces as a failure.
void main() {
  Future<void> pumpSection(
    WidgetTester tester,
    GadgetSection section, {
    bool dark = false,
  }) async {
    final mode = dark ? ThemeMode.dark : ThemeMode.light;
    // Mirror lib/main.dart exactly: YaruTheme + builder supplying the
    // resolved light/dark Material themes.
    await tester.pumpWidget(YaruTheme(
      data: YaruThemeData(variant: YaruVariant.orange, themeMode: mode),
      builder: (context, yaru, child) => MaterialApp(
        theme: yaru.theme,
        darkTheme: yaru.darkTheme,
        themeMode: mode,
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: section),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final dark in const [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets(
        '[$mode] Defaults empty state: icon chip + dashed zone + Add button',
        (tester) async {
      await pumpSection(
        tester,
        GadgetSection(title: 'Defaults', data: null, onEdit: () {}),
        dark: dark,
      );

      expect(find.byType(Icon), findsWidgets); // chip icon (+ button icon)
      expect(find.text('Defaults'), findsOneWidget);
      expect(
        find.text('No defaults yet. Add snap configuration entries.'),
        findsOneWidget,
      );
      expect(find.text('Add Defaults'), findsOneWidget);
      expect(find.byKey(const ValueKey('gadget-section-dashed-zone')),
          findsOneWidget);
      // The drop-zone button supersedes the header Add button in the
      // empty state.
      expect(find.text('Add'), findsNothing);
    });

    testWidgets(
        '[$mode] Connections + Boot Options empty states differ per section',
        (tester) async {
      await pumpSection(
        tester,
        GadgetSection(title: 'Connections', data: null, onEdit: () {}),
        dark: dark,
      );
      expect(find.text('Add Connections'), findsOneWidget);
      expect(
        find.text('No connections yet. Define snap plug/slot connections.'),
        findsOneWidget,
      );

      await pumpSection(
        tester,
        GadgetSection(title: 'Boot Options', data: null, onEdit: () {}),
        dark: dark,
      );
      expect(find.text('Add Boot Options'), findsOneWidget);
      expect(
        find.text('No boot options yet. Add kernel commandline options.'),
        findsOneWidget,
      );
    });

    testWidgets(
        '[$mode] populated Defaults keeps the header, drops the empty state',
        (tester) async {
      final data = loadYaml(
        '''
        system:
          ubuntu-autostart-services:
            - /etc/init.d/udisks2
        ''',
      );
      await pumpSection(
        tester,
        GadgetSection(title: 'Defaults', data: data, onEdit: () {}),
        dark: dark,
      );
      expect(find.text('Defaults'), findsOneWidget);
      expect(find.textContaining('ubuntu-autostart-services'), findsOneWidget);
      expect(find.text('Add Defaults'), findsNothing);
      expect(find.byKey(const ValueKey('gadget-section-dashed-zone')),
          findsNothing);
      // With data present the compact header "Add" text button is the only
      // add affordance, so it must remain.
      expect(find.text('Add'), findsOneWidget);
    });
  }

  // ---------------------------------------------------------------------
  // Per-setting trash icons in the Defaults tree
  // ---------------------------------------------------------------------
  group('Defaults per-setting delete', () {
    // A real YamlMap (the app hands the section parsed YAML, not text):
    // the tree renderer only kicks in for YamlMap data. Direct children of
    // the snap ID's value are the deletable "settings"; deeper nodes are
    // part of a setting's value and are not individually deletable.
    final data = loadYaml('''
core20:
  a: 1
  b: 2
  nested:
    c: 3
  list:
    - x
    - y
''');

    testWidgets('offers a trash icon per direct child of the snap ID',
        (tester) async {
      final callbacks = <List<Object?>>[];
      await pumpSection(
        tester,
        GadgetSection(
          title: 'Defaults',
          data: data,
          onEdit: () {},
          onDelete: (d, i) {},
          onDeleteEntry: (d, path) => callbacks.add(path as List<Object?>),
        ),
      );
      // Direct children of core20: a, b, nested, list = 4 settings. This
      // count also proves the list items (x, y) and the nested key 'c'
      // (both grandchildren) got no icon of their own.
      expect(find.byTooltip('Delete setting'), findsNWidgets(4));
      expect(find.text('c:'), findsOneWidget);
      expect(find.text('x'), findsOneWidget);
    });

    testWidgets('tap + confirm deletes exactly that setting via the callback',
        (tester) async {
      final callbacks = <List<Object?>>[];
      await pumpSection(
        tester,
        GadgetSection(
          title: 'Defaults',
          data: data,
          onEdit: () {},
          onDelete: (d, i) {},
          onDeleteEntry: (d, path) => callbacks.add(path as List<Object?>),
        ),
      );
      // 'b' is the second direct child: the second delete icon.
      await tester.tap(find.byTooltip('Delete setting').at(1));
      await tester.pumpAndSettle();
      expect(find.text('Delete Default'), findsOneWidget);
      expect(find.text('Are you sure you want to delete "b under core20"?'),
          findsOneWidget);
      // Cancel keeps everything.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(callbacks, isEmpty);
      expect(find.byTooltip('Delete setting'), findsNWidgets(4));

      // Now confirm the deletion.
      await tester.tap(find.byTooltip('Delete setting').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(callbacks, [
        ['core20', 'b'],
      ]);
    });

    testWidgets('deleting the whole "list" setting removes its items too',
        (tester) async {
      final callbacks = <List<Object?>>[];
      await pumpSection(
        tester,
        GadgetSection(
          title: 'Defaults',
          data: data,
          onEdit: () {},
          onDelete: (d, i) {},
          onDeleteEntry: (d, path) => callbacks.add(path as List<Object?>),
        ),
      );
      // 'list' is the 4th direct child (index 3): deleting it takes the
      // whole key (and its items) in one go.
      await tester.tap(find.byTooltip('Delete setting').at(3));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure you want to delete "list under core20"?'),
          findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(callbacks, [
        ['core20', 'list'],
      ]);
    });

    testWidgets('a flat list of settings deletes items by index',
        (tester) async {
      final flat = loadYaml('core20:\n  - x\n  - y\n');
      final callbacks = <List<Object?>>[];
      await pumpSection(
        tester,
        GadgetSection(
          title: 'Defaults',
          data: flat,
          onEdit: () {},
          onDelete: (d, i) {},
          onDeleteEntry: (d, path) => callbacks.add(path as List<Object?>),
        ),
      );
      expect(find.byTooltip('Delete setting'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Delete setting').at(1));
      await tester.pumpAndSettle();
      expect(
          find.text('Are you sure you want to delete "item 1 under core20"?'),
          findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(callbacks, [
        ['core20', 1],
      ]);
    });

    testWidgets('without onDeleteEntry the tree stays static', (tester) async {
      await pumpSection(
        tester,
        GadgetSection(title: 'Defaults', data: data, onEdit: () {}),
      );
      expect(find.byTooltip('Delete setting'), findsNothing);
    });

    testWidgets('the Defaults card itself has no trash icon', (tester) async {
      await pumpSection(
        tester,
        GadgetSection(
          title: 'Defaults',
          data: data,
          onEdit: () {},
          onDelete: (d, i) {},
          onDeleteEntry: (d, path) {},
        ),
      );
      // Only the per-setting trash icons remain (4 settings in [data]).
      expect(find.byTooltip('Delete setting'), findsNWidgets(4));
      // The whole-card delete icon was removed.
      expect(find.byTooltip('Delete default'), findsNothing);
    });
  });
}
