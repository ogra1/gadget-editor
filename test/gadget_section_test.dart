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

    testWidgets('[$mode] Defaults empty state: icon chip + dashed zone + Add button',
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
      expect(find.byKey(const ValueKey('gadget-section-dashed-zone')), findsOneWidget);
      // The drop-zone button supersedes the header + in the empty state.
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('[$mode] Connections + Boot Options empty states differ per section',
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

    testWidgets('[$mode] populated Defaults keeps the header, drops the empty state',
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
      expect(find.byKey(const ValueKey('gadget-section-dashed-zone')), findsNothing);
      // With data present the header + is the only add affordance, so it
      // must remain.
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  }
}
