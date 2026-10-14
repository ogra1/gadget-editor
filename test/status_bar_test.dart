import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/app/widgets/status_bar.dart';

/// The status bar is a fixed-height strip under the editor. Snapd and store
/// error strings can be long and contain newlines; the bar must never let
/// them wrap or overflow — it renders a single ellipsized line and exposes
/// the full text through the tooltip.
void main() {
  // Representative store/download failure: long, and contains a '\n' like
  // the raw snapd output that used to break the layout.
  const longError = 'snap download failed: snapd: network error: '
      'Get "https://store.snapcraft.io/v2/snaps/find?select=name%3Apc": '
      'dial tcp 192.168.1.1:443: i/o timeout\n'
      'The server did not respond within the expected time, please check '
      'your network connection and try again.';

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const SizedBox(height: 120),
            child,
          ],
        ),
      ),
    );
  }

  testWidgets('long multi-line error renders single-line without overflow',
      (tester) async {
    await tester.pumpWidget(wrap(
      const StatusBar(
        message: longError,
        isActionButtonEnabled: false,
      ),
    ));
    await tester.pump();

    // No RenderFlex/overflow exception and the bar keeps its 60px height.
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(StatusBar));
    expect(size.height, 60);
    expect(find.byKey(const ValueKey('status-bar-message')), findsOneWidget);
  });

  testWidgets('tooltip exposes the full error text', (tester) async {
    await tester.pumpWidget(wrap(
      const StatusBar(
        message: longError,
        isActionButtonEnabled: false,
      ),
    ));

    await tester.longPress(find.byKey(const ValueKey('status-bar-message')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The ellipsized bar text plus the tooltip overlay both carry the full
    // string while the tooltip is visible.
    expect(find.text(longError), findsNWidgets(2));
  });

  testWidgets('short message renders as-is', (tester) async {
    await tester.pumpWidget(wrap(
      const StatusBar(
        message: 'Ready',
        isActionButtonEnabled: true,
      ),
    ));
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Pack Snap'), findsOneWidget);
    // A short, single-line message fits, so no tooltip is wired up.
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('pack button honours the enabled flag', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(wrap(
      StatusBar(
        message: 'Ready',
        isActionButtonEnabled: false,
        onActionPressed: () => pressed++,
      ),
    ));
    final button = find.byType(ElevatedButton);
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

    await tester.pumpWidget(wrap(
      StatusBar(
        message: 'Ready',
        isActionButtonEnabled: true,
        onActionPressed: () => pressed++,
      ),
    ));
    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    expect(pressed, 1);
  });

  testWidgets('a short message offers no tooltip', (tester) async {
    await tester.pumpWidget(wrap(
      const StatusBar(
        message: 'Ready',
        isActionButtonEnabled: false,
      ),
    ));
    expect(find.byType(Tooltip), findsNothing);
    // Hovering does not surface a tooltip overlay either.
    await tester.longPress(find.byKey(const ValueKey('status-bar-message')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('a single-line message wider than the bar gets a tooltip',
      (tester) async {
    // No line break, but far too wide to fit the bar -> tooltip required.
    final tooWide = 'x' * 400;
    await tester.pumpWidget(wrap(
      StatusBar(
        message: tooWide,
        isActionButtonEnabled: false,
      ),
    ));
    expect(find.byType(Tooltip), findsOneWidget);
    await tester.longPress(find.byKey(const ValueKey('status-bar-message')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(tooWide), findsNWidgets(2));
  });

  testWidgets(
      'a multi-line message gets a tooltip even when the first '
      'line is short', (tester) async {
    // Only the first line is shown in the bar, so the rest is hidden ->
    // a tooltip is needed regardless of the first line's width.
    const twoLines = 'First line\nsecond line is hidden without a tooltip';
    await tester.pumpWidget(wrap(
      const StatusBar(
        message: twoLines,
        isActionButtonEnabled: false,
      ),
    ));
    expect(find.byType(Tooltip), findsOneWidget);
    await tester.longPress(find.byKey(const ValueKey('status-bar-message')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(twoLines), findsNWidgets(2));
  });
}
