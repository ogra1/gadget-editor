import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/app/widgets/empty_state.dart';

/// The startup placeholder: a centered, self-contained card with
/// descriptive text pointing at the sidebar's search box and local loader.
///
/// The key regression: it must never overflow, even at the pane size the app
/// computes as its window default (reported as ~350x346 in production), so
/// several sizes are exercised directly.
void main() {
  Widget wrapInPane(Widget child, Size size) => MaterialApp(
        home: Scaffold(
          body: SizedBox(width: size.width, height: size.height, child: child),
        ),
      );

  testWidgets(
      'renders the app mark, title, description, hint and no action buttons',
      (tester) async {
    await tester.pumpWidget(wrapInPane(const EmptyState(), const Size(700, 500)));

    expect(find.text('No gadget snap loaded'), findsOneWidget);
    // Points the user at the sidebar's two entry points.
    expect(find.textContaining('search box in the sidebar'), findsOneWidget);
    expect(find.textContaining('Load Local Snap'), findsOneWidget);
    // Keyboard hint.
    expect(find.textContaining('press Enter'), findsOneWidget);
    // The app mark (not a generic glyph) is shown.
    expect(find.byType(Image), findsOneWidget);
    // No action buttons — the card is descriptive text only.
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('does not overflow at the pane size the app default produces',
      (tester) async {
    // The production overflow report: constraints 350 x 346.
    await tester.pumpWidget(wrapInPane(const EmptyState(), const Size(350, 346)));
    expect(tester.takeException(), isNull);
    expect(find.text('No gadget snap loaded'), findsOneWidget);
  });

  testWidgets('does not overflow in a very small pane', (tester) async {
    await tester.pumpWidget(wrapInPane(const EmptyState(), const Size(300, 180)));
    expect(tester.takeException(), isNull);
    expect(find.text('No gadget snap loaded'), findsOneWidget);
  });

  testWidgets('centers the card in a roomy pane without overflow',
      (tester) async {
    // The default test surface is 800x600, so keep the pane inside it.
    await tester.pumpWidget(wrapInPane(const EmptyState(), const Size(700, 500)));
    expect(tester.takeException(), isNull);

    // The card (FittedBox) is centered in the 700x500 pane, so its center
    // should be at (350, 250).
    final cardCenter = tester.getCenter(find.byType(FittedBox));
    expect(cardCenter.dx, closeTo(350, 2));
    expect(cardCenter.dy, closeTo(250, 2));
  });
}
