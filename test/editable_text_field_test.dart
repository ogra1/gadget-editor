import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/app/widgets/editable_text_field.dart';

Future<void> _pump(
  WidgetTester tester, {
  String text = 'pc',
  required Function(String) onSave,
  bool enabled = true,
  String? label,
  Function(EditableTextFieldState)? onStateCreated,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 200,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Mirror the real call sites: a Flexible in a bounded Row,
              // so the chip sizes to its content and wraps when constrained.
              Flexible(
                child: EditableTextField(
                  text: text,
                  onSave: onSave,
                  enabled: enabled,
                  label: label,
                  onStateCreated: onStateCreated,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('resting state is a compact chip, not a text field',
      (tester) async {
    await _pump(tester, onSave: (_) {});

    expect(find.text('pc'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.edit), findsOneWidget);
    // The chip hugs its content - far narrower than the row it sits in.
    final chipSize = tester.getSize(find.byType(GestureDetector));
    expect(chipSize.width, lessThan(120));
    expect(chipSize.width, greaterThan(0));
  });

  testWidgets('long name wraps instead of clipping', (tester) async {
    const longName =
        'a-very-long-gadget-snap-name-that-would-clip-at-two-hundred-pixels';
    await _pump(tester, text: longName, onSave: (_) {});

    // Full value is present (possibly on multiple lines) ...
    expect(find.text(longName), findsOneWidget);
    // ... and the chip is no shorter than the previous test's short chip,
    // i.e. it grew (and wrapped) to accommodate the name.
    final chipSize = tester.getSize(find.byType(GestureDetector));
    expect(chipSize.width, greaterThan(120));
  });

  testWidgets('tap expands in place to an outlined text field',
      (tester) async {
    await _pump(tester, onSave: (_) {});
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    final field =
        tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.isDense, isTrue);
    expect(field.decoration?.border, isA<OutlineInputBorder>());
  });

  testWidgets('check commits the edited value and collapses back',
      (tester) async {
    String? saved;
    await _pump(tester, onSave: (v) => saved = v);
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'pc-amd64');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(saved, 'pc-amd64');
    expect(find.text('pc-amd64'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Enter commits the edited value exactly once', (tester) async {
    // Regression: on desktop Enter fires both onSubmitted and
    // onEditingComplete - saving twice would make a volume rename fail on
    // the second pass ("No volume named '<old>'").
    final saved = <String>[];
    await _pump(tester, onSave: (v) => saved.add(v));
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'pc-26');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(saved, ['pc-26']);
    expect(find.text('pc-26'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('label renders as a caption above the chip at rest',
      (tester) async {
    await _pump(tester, onSave: (_) {}, label: 'Image Name');

    expect(find.text('Image Name'), findsOneWidget);
    final caption = tester.getTopLeft(find.text('Image Name'));
    final chip = tester.getTopLeft(find.text('pc'));
    expect(caption.dy, lessThan(chip.dy));
  });

  testWidgets('label becomes the floating label while editing',
      (tester) async {
    await _pump(tester, onSave: (_) {}, label: 'Image Name');
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.labelText, 'Image Name');
  });

  testWidgets('no caption is shown without a label', (tester) async {
    await _pump(tester, onSave: (_) {});

    expect(find.text('Image Name'), findsNothing);
  });

  testWidgets('X cancels and restores the original value', (tester) async {
    String? saved;
    await _pump(tester, onSave: (v) => saved = v);
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'changed');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(saved, isNull);
    expect(find.text('pc'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('disabled field does not open an editor', (tester) async {
    await _pump(tester, onSave: (_) {}, enabled: false);

    expect(find.byIcon(Icons.edit), findsNothing);
    await tester.tap(find.text('pc'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('rejected save flips back to the original text',
      (tester) async {
    // Mirrors the snap-name flow: onSave validates and, on failure, calls
    // resetToOriginal() synchronously.
    EditableTextFieldState? stateRef;
    String? rejected;
    await _pump(
      tester,
      onSave: (v) {
        rejected = v;
        stateRef?.resetToOriginal();
      },
      onStateCreated: (s) => stateRef = s,
    );
    expect(stateRef, isNotNull);

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pcA');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(rejected, 'pcA');
    // Field collapsed back to the chip showing the original name.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('pc'), findsOneWidget);
    expect(find.text('pcA'), findsNothing);
  });

  testWidgets('successful round trip updates the original value',
      (tester) async {
    EditableTextFieldState? stateRef;
    await _pump(
      tester,
      onSave: (_) {},
      onStateCreated: (s) => stateRef = s,
    );

    // Commit a valid edit.
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pc-26');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(find.text('pc-26'), findsOneWidget);

    // Parent round-trips the accepted value (what the screen does after a
    // successful save).
    await _pump(
      tester,
      text: 'pc-26',
      onSave: (_) {},
      onStateCreated: (s) => stateRef = s,
    );
    await tester.pumpAndSettle();

    // A later rejected edit must revert to the *new* original.
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bad name');
    stateRef!.resetToOriginal();
    await tester.pumpAndSettle();
    expect(find.text('pc-26'), findsOneWidget);
    expect(find.text('bad name'), findsNothing);
  });
}
