import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/app/widgets/channel_list.dart';
import 'package:yaru/yaru.dart';

Map<String, dynamic> _channel(
    String track, String risk, String arch, int revision) {
  return {
    'channel': {'track': track, 'risk': risk, 'architecture': arch},
    'version': track,
    'revision': revision,
    'download': {'url': 'https://example.com/$track-$risk-$arch.snap'},
  };
}

void main() {
  group('channelDisplayCompare', () {
    test('numbers highest to lowest, non-numbered tracks last', () {
      final a = _channel('24', 'stable', 'amd64', 1);
      final b = _channel('26', 'stable', 'amd64', 2);
      final c = _channel('latest', 'stable', 'amd64', 3);
      expect(channelDisplayCompare(b, a), lessThan(0)); // 26 above 24
      expect(channelDisplayCompare(a, c), lessThan(0)); // 24 above latest
      expect(channelDisplayCompare(b, c), lessThan(0)); // 26 above latest
    });

    test('leading number of dotted tracks counts', () {
      final a = _channel('26.04', 'stable', 'amd64', 1);
      final b = _channel('26', 'stable', 'amd64', 2);
      expect(channelDisplayCompare(a, b), 0); // same leading number
    });

    test('risk order: stable, candidate, beta, edge', () {
      final risks = ['edge', 'beta', 'candidate', 'stable']
          .map((r) => _channel('26', r, 'amd64', 1));
      final sorted = risks.toList()..sort(channelDisplayCompare);
      expect(sorted.map((c) => (c['channel'] as Map)['risk']),
          ['stable', 'candidate', 'beta', 'edge']);
    });

    test('architecture is the final tiebreaker', () {
      final a = _channel('26', 'stable', 'arm64', 1);
      final b = _channel('26', 'stable', 'amd64', 2);
      expect(channelDisplayCompare(b, a), lessThan(0));
    });
  });

  group('ChannelList', () {
    final channels = [
      _channel('latest', 'stable', 'amd64', 50),
      _channel('26', 'stable', 'arm64', 20),
      _channel('26', 'stable', 'amd64', 10),
      _channel('24', 'stable', 'amd64', 5),
    ];

    Future<void> pumpList(WidgetTester tester,
        {Map<String, dynamic>? selected, bool downloading = false}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: ChannelList(
              channels: channels,
              onChannelSelected: (c) {},
              selectedChannel: selected,
              isDownloading: downloading,
            ),
          ),
        ),
      ));
    }

    testWidgets('renders sorted: numbered desc, latest last', (tester) async {
      await pumpList(tester);
      // 26/stable (amd64 before arm64 by arch tiebreak) then 24, then latest.
      final amd64 = tester.getCenter(find.text('26/stable').at(0));
      final t24 = tester.getCenter(find.text('24/stable'));
      final latest = tester.getCenter(find.text('latest/stable'));
      expect(amd64.dy, lessThan(t24.dy));
      expect(t24.dy, lessThan(latest.dy));
    });

    testWidgets('selected channel moves to the top', (tester) async {
      final selected = channels[3]; // 24/stable - would normally sort below 26
      await pumpList(tester, selected: selected);

      expect(find.text('Currently Selected'), findsOneWidget);
      final top = tester.getCenter(find.text('24/stable'));
      final t26 = tester.getCenter(find.text('26/stable').at(0));
      expect(top.dy, lessThan(t26.dy));
    });

    testWidgets('keeps list visible and dimmed while downloading',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: ChannelList(
              channels: channels,
              onChannelSelected: (c) => tapped = true,
              isDownloading: true,
            ),
          ),
        ),
      ));

      // List still visible ...
      expect(find.text('26/stable'), findsNWidgets(2));
      expect(find.text('24/stable'), findsOneWidget);
      // ... with a progress indicator on top ...
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // ... and no longer interactive. The list is wrapped in an
      // IgnorePointer (see ChannelList), so this tap is *expected* to miss
      // its hit test — warnIfMissed: false suppresses the (misleading)
      // "would not hit test" warning; the assertion below is the real check.
      await tester.tap(
        find.byIcon(Icons.download_for_offline).first,
        warnIfMissed: false,
      );
      await tester.pump();
      expect(tapped, isFalse);
    });
  });

  group('theming', () {
    final selectedChannels = [
      _channel('26', 'stable', 'amd64', 10),
    ];

    Future<void> pumpSelected(WidgetTester tester, {ThemeData? theme}) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: ChannelList(
              channels: selectedChannels,
              onChannelSelected: (c) {},
              selectedChannel: selectedChannels[0],
              isDownloading: false,
            ),
          ),
        ),
      ));
    }

    testWidgets(
        'selected label and check use the theme success color, not raw green',
        (tester) async {
      await pumpSelected(tester);

      final ctx = tester.element(find.text('Currently Selected'));
      final success = Theme.of(ctx).colorScheme.success;

      final label = tester.widget<Text>(find.text('Currently Selected'));
      expect(label.style?.color, success);
      expect(label.style?.color, isNot(Colors.green));

      final check = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      expect(check.color, success);
      expect(check.color, isNot(Colors.green));
    });
  });
}
