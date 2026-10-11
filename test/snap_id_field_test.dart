import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/app/widgets/snap_id_field.dart';
import 'package:gadget_editor/services/snap_lookup_service.dart';
import 'package:gadget_editor/services/snap_store_service.dart';

const kId = 'hJmReLmgXSUj4SF7WhyTVRV6IzUa4QUZ';
const kUrl = 'https://api.snapcraft.io/v2/snaps/info/htop';

/// In-memory store client for the resolver.
class FakeStoreHttp implements SnapStoreHttpClient {
  FakeStoreHttp(this.routes);

  final Map<String, (int, List<int>)> routes;

  @override
  Future<({int statusCode, List<int> bytes})> get(
      String url, Map<String, String> headers) async {
    final route = routes[url] ?? (400, <int>[]);
    return (statusCode: route.$1, bytes: route.$2);
  }
}

Map<String, dynamic> _info(String name, String id,
        {String? publisher, String? validation}) =>
    {
      'name': name,
      'snap-id': id,
      'snap': {
        if (publisher != null)
          'publisher': {
            'display-name': publisher,
            if (validation != null) 'validation': validation,
          },
      },
    };

/// A lookup service whose result is deferred through an injectable future,
/// used to exercise the in-flight await path of [SnapIdFieldState].
class _DeferredLookupService extends SnapLookupService {
  _DeferredLookupService(this._fn) : super(httpClient: _NoopHttp());

  final Future<SnapLookup?> Function() _fn;

  @override
  Future<SnapLookup?> lookup(String name) => _fn();
}

class _NoopHttp implements SnapStoreHttpClient {
  @override
  Future<({int statusCode, List<int> bytes})> get(
          String url, Map<String, String> headers) async =>
      (statusCode: 200, bytes: <int>[]);
}

void main() {
  /// Pumps a [SnapIdField] backed by [lookupService] inside a form.
  Widget wrap(SnapLookupService lookupService,
      {TextEditingController? controller}) {
    return MaterialApp(
      home: Scaffold(
        body: Form(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 420,
              child: SnapIdField(
                controller: controller ?? TextEditingController(),
                lookupService: lookupService,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).controller.text;

  testWidgets('resolves a typed snap name to its snap ID in place',
      (tester) async {
    final service = SnapLookupService(
        httpClient: FakeStoreHttp({
      kUrl: (
        200,
        utf8.encode(jsonEncode(_info('htop', kId,
            publisher: 'Maximiliano Bertacchini', validation: 'starred')))
      ),
    }));
    final controller = TextEditingController();
    await tester.pumpWidget(wrap(service, controller: controller));
    addTearDown(controller.dispose);

    await tester.enterText(find.byType(SnapIdField), 'htop');
    // Debounce has not elapsed yet: nothing happens.
    expect(fieldText(tester), 'htop');
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    // The lookup is in flight (the fake resolves on the next microtask).
    await tester.pump();

    expect(fieldText(tester), kId,
        reason: 'the name must be replaced by the resolved snap ID');
    // Resolved indicator: a check icon, and no more spinner.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Tooltip metadata carries the publisher info.
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('htop'));
    expect(tooltip.message, contains('Maximiliano Bertacchini'));
  });

  testWidgets(
      'keeps unresolvable text as-is with a not-found indicator (manual ID fallback)',
      (tester) async {
    final service = SnapLookupService(
        httpClient: FakeStoreHttp({
      kUrl: (400, <int>[]),
    }));
    await tester.pumpWidget(wrap(service));

    await tester.enterText(find.byType(SnapIdField), 'private-build');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // The raw text is preserved: it is the manual snap-ID fallback.
    expect(fieldText(tester), 'private-build');
    expect(find.byIcon(Icons.link_off), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('never looks up 32-character IDs or the system nick',
      (tester) async {
    final service = SnapLookupService(httpClient: FakeStoreHttp({}));
    await tester.pumpWidget(wrap(service));

    // A pasted 32-char ID: no lookup, no indicator.
    await tester.enterText(find.byType(SnapIdField), kId);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(fieldText(tester), kId);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byIcon(Icons.link_off), findsNothing);

    // "system": same.
    await tester.enterText(find.byType(SnapIdField), 'system');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(fieldText(tester), 'system');
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('resolves text set programmatically via resolveForSave',
      (tester) async {
    final service = SnapLookupService(
        httpClient: FakeStoreHttp({
      kUrl: (200, utf8.encode(jsonEncode(_info('htop', kId)))),
    }));
    final controller = TextEditingController();
    final key = GlobalKey<SnapIdFieldState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SnapIdField(
          key: key,
          controller: controller,
          lookupService: service,
        ),
      ),
    ));
    addTearDown(controller.dispose);

    // No typing: set the text directly (e.g. a prefilled form) and save.
    controller.text = 'htop';
    final saved = await key.currentState!.resolveForSave();
    expect(saved, kId,
        reason: 'resolveForSave must resolve before the value is persisted');
    expect(fieldText(tester), kId);
  });

  testWidgets('waits for an in-flight lookup in resolveForSave',
      (tester) async {
    // The lookup future stays pending until explicitly completed, so the
    // in-flight state is real: resolveForSave must not return before it.
    final completer = Completer<SnapLookup?>();
    final service = _DeferredLookupService(() => completer.future);

    final controller = TextEditingController();
    final key = GlobalKey<SnapIdFieldState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SnapIdField(
          key: key,
          controller: controller,
          lookupService: service,
        ),
      ),
    ));
    addTearDown(controller.dispose);

    await tester.enterText(find.byType(SnapIdField), 'htop');
    await tester.pump(const Duration(milliseconds: 300)); // lookup in flight

    // Kick off resolveForSave without awaiting it: it must block on the
    // in-flight lookup, so the field still shows the typed name.
    final saved = key.currentState!.resolveForSave();
    expect(fieldText(tester), 'htop');

    // Complete the deferred lookup in the fake zone, then drive the microtask
    // chain so both _maybeResolve and resolveForSave resume. Completing from
    // here (rather than via runAsync) keeps the continuations in the same
    // zone, avoiding a fake/real-zone deadlock.
    completer.complete(const SnapLookup(name: 'htop', snapId: kId));
    await tester.pump();
    await tester.pump();

    expect(await saved, kId,
        reason: 'must await the in-flight lookup, not return the name');
    expect(fieldText(tester), kId);
  });

  testWidgets('clearing the field resets resolution state', (tester) async {
    final service = SnapLookupService(
        httpClient: FakeStoreHttp({
      kUrl: (200, utf8.encode(jsonEncode(_info('htop', kId)))),
    }));
    await tester.pumpWidget(wrap(service));

    await tester.enterText(find.byType(SnapIdField), 'htop');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.enterText(find.byType(SnapIdField), '');
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });
}
