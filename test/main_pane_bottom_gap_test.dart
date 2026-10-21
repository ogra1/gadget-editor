import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/app/gadget_editor_screen.dart';
import 'package:gadget_editor/app/widgets/api_key_section.dart';
import 'package:gadget_editor/app/widgets/channel_list.dart';
import 'package:gadget_editor/app/widgets/channel_list_item.dart';
import 'package:gadget_editor/app/widgets/gadget_content.dart';
import 'package:gadget_editor/app/widgets/gadget_section.dart';
import 'package:gadget_editor/app/widgets/gadget_volumes.dart';
import 'package:gadget_editor/services/snap_file_service.dart';
import 'package:gadget_editor/services/snap_pack_service.dart';
import 'package:gadget_editor/services/snap_store_service.dart';

// ignore_for_file: deprecated_member_use

/// Regression: the editor pane and the sidebar must run right up to the
/// footer — no dead vertical band below the last section card / channel item.
///
/// Before the fix, the main pane stacked an outer 16px + a scroll 16px (32px)
/// below the last card, and the sidebar had a 16px band below the channel
/// list (and the local-snap card). These tests seed a loaded state, scroll to
/// the bottom, and assert the last content widget is flush with the pane/list
/// bottom (i.e. the footer).
void main() {
  setUp(() {
    final window = TestWidgetsFlutterBinding.instance.window;
    // A modest window so a small-but-real gadget overflows and scrolls.
    window.physicalSizeTestValue = const Size(1000, 620);
    window.devicePixelRatioTestValue = 1.0;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.window.clearAllTestValues();
  });

  testWidgets('last editor section card is flush with the footer',
      (tester) async {
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
    // ignore: invalid_use_of_protected_member
    state.setState(() {
      state.snapName = 'pc';
      state.gadgetData = <String, dynamic>{
        'volumes': <String, dynamic>{
          'pc': <String, dynamic>{
            'structure': <String, dynamic>{
              'label': 'mnt',
              'type': '83',
              'size': 1073741824,
              'offset': '+',
            },
            'filesystem': 'ext4',
            'image': 'image/img.xfs.img',
          }
        },
        'defaults': <String, dynamic>{
          'core20': <String, dynamic>{
            'core': <String, dynamic>{'kernel_command_line': 'console=ttyS0'}
          }
        },
      };
      state.gadgetContent = 'volumes:\n  pc: {}\n';
      state.snapArchitectures = const ['amd64'];
      state.isActionButtonEnabled = true;
    });
    await tester.pump();

    expect(find.byType(GadgetContent), findsOneWidget);
    final scroll = find.byType(SingleChildScrollView).first;
    await tester.drag(scroll, const Offset(0, -2000));
    await tester.pumpAndSettle();

    final scrollRect = tester.getRect(scroll);
    double lastBottom = 0;
    for (final f in [
      find.byType(GadgetSection),
      find.byType(ApiKeySection),
      find.byType(GadgetVolumesSection),
    ]) {
      for (final el in f.evaluate()) {
        lastBottom =
            math.max(lastBottom, tester.getBottomLeft(find.byWidget(el.widget)).dy);
      }
    }
    expect(lastBottom, greaterThan(0));
    expect(
      scrollRect.bottom - lastBottom,
      lessThanOrEqualTo(3),
      reason: 'no vertical dead band below the last section card '
          '(was 32px before the fix)',
    );
  });

  testWidgets('last channel-list card is flush with the footer (sidebar)',
      (tester) async {
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
    // Seed a store search that returned several channels (so the list
    // overflows the sidebar and scrolls).
    // ignore: invalid_use_of_protected_member
    state.setState(() {
      state.availableChannels = List.generate(
        24,
        (i) => <String, dynamic>{
          'channel': <String, dynamic>{
            'track': '26',
            'risk': ['stable', 'candidate', 'beta', 'edge'][i % 4],
            'architecture': i.isEven ? 'amd64' : 'arm64',
          },
          'download': <String, dynamic>{
            'url': 'https://example.com/$i.snap',
            'size': 1000 + i,
          },
        },
      );
      state.snapArchitectures = const ['amd64'];
    });
    await tester.pump();

    expect(find.byType(ChannelList), findsOneWidget);
    // The channel list is a ListView; find its scrollable and drag down.
    final listView = find.byType(ListView).first;
    await tester.drag(listView, const Offset(0, -4000));
    await tester.pumpAndSettle();

    final listRect = tester.getRect(find.byType(ChannelList));
    // The last channel card (a Card inside a ChannelListItem). Use the
    // ChannelListItem widget's bottom as the measure.
    double lastBottom = 0;
    for (final el in find.byType(ChannelListItem).evaluate()) {
      lastBottom =
          math.max(lastBottom, tester.getBottomLeft(find.byWidget(el.widget)).dy);
    }
    expect(lastBottom, greaterThan(0));
    // The last card's bottom margin is 4px (matching inter-card spacing), so
    // at most ~6px of space below it — NOT the old 16px band.
    expect(
      listRect.bottom - lastBottom,
      lessThanOrEqualTo(6),
      reason: 'no vertical dead band below the last channel card '
          '(was 16px before the fix)',
    );
  });
}
