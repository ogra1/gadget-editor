// Widget tests for the "Extras (unknown keys)" section in [GadgetContent].
//
// The Extras section must appear whenever the document has keys the editor has
// no dedicated section for. It is NOT gated on architecture (that rule was
// arbitrary) and is labelled "Extras (unknown keys)" so the user understands
// what they are looking at.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/app/widgets/gadget_content.dart';

const _yamlWithExtras = '''
volumes:
  pc:
    bootloader: grub
    structure:
      - name: system-seed
        size: 1G
        role: system-seed
        type: M
defaults:
  core26:
    FOO: bar
custom_key: hello
another_unknown: 42
''';

const _yamlNoExtras = '''
volumes:
  pc:
    bootloader: grub
    structure:
      - name: system-seed
        size: 1G
        role: system-seed
        type: M
defaults:
  core26:
    FOO: bar
''';

void main() {
  Future<void> pumpContent(WidgetTester tester, String content) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GadgetContent(
          content: content,
          onStatusUpdate: (m) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows "Extras (unknown keys)" when unknown keys are present',
      (tester) async {
    await pumpContent(tester, _yamlWithExtras);
    expect(find.text('Extras (unknown keys)'), findsOneWidget);
    // The unknown keys themselves are visible in the section body.
    expect(find.textContaining('custom_key'), findsOneWidget);
    expect(find.textContaining('another_unknown'), findsOneWidget);
  });

  testWidgets('hides the Extras section when there are no unknown keys',
      (tester) async {
    await pumpContent(tester, _yamlNoExtras);
    expect(find.text('Extras (unknown keys)'), findsNothing);
    // The known sections are still there.
    expect(find.text('Volumes'), findsOneWidget);
    expect(find.text('Defaults'), findsOneWidget);
  });
}
