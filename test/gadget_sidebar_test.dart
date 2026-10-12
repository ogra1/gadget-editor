import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/app/widgets/gadget_sidebar.dart';
import 'package:gadget_editor/app/widgets/channel_list.dart';
import 'package:gadget_editor/app/widgets/local_snap_loader.dart';
import 'package:gadget_editor/app/widgets/search_section.dart';

/// The sidebar is a stateless form panel: it must render the search box +
/// local loader plus exactly one of (available channels / local snap info /
/// nothing) depending on the state passed in by the screen.
void main() {
  GadgetEditorSidebar sidebar({
    List<Map<String, dynamic>> availableChannels = const [],
    Map<String, dynamic>? selectedChannel,
    bool isDownloading = false,
    ValueChanged<Map<String, dynamic>>? onChannelSelected,
    bool isLocalMode = false,
    bool hasGadgetData = false,
    String? snapName,
    String? snapVersion,
    List<String> snapArchitectures = const [],
    VoidCallback? onLocalSnapReload,
    void Function(String)? onSearchSubmitted,
    FutureOr<void> Function()? onLocalSnapPicked,
  }) {
    return GadgetEditorSidebar(
      searchController: TextEditingController(),
      onSearchSubmitted: onSearchSubmitted ?? (v) {},
      onLocalSnapPicked: onLocalSnapPicked ?? () {},
      availableChannels: availableChannels,
      selectedChannel: selectedChannel,
      isDownloading: isDownloading,
      onChannelSelected: onChannelSelected ?? (c) {},
      isLocalMode: isLocalMode,
      hasGadgetData: hasGadgetData,
      snapName: snapName,
      snapVersion: snapVersion,
      snapArchitectures: snapArchitectures,
      onLocalSnapReload: onLocalSnapReload ?? () {},
    );
  }

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('always shows search + local loader; empty when no data',
      (tester) async {
    await tester.pumpWidget(wrap(sidebar()));
    expect(find.byType(SearchSection), findsOneWidget);
    expect(find.byType(LocalSnapLoader), findsOneWidget);
    expect(find.text('Available Channels:'), findsNothing);
    expect(find.text('Local Snap:'), findsNothing);
    expect(find.byType(ChannelList), findsNothing);
  });

  testWidgets('shows the channel list when channels are available',
      (tester) async {
    await tester.pumpWidget(wrap(sidebar(
      availableChannels: [
        {'channel': {'track': '26', 'risk': 'stable', 'architecture': 'amd64'}},
      ],
    )));
    expect(find.text('Available Channels:'), findsOneWidget);
    expect(find.byType(ChannelList), findsOneWidget);
    expect(find.text('Local Snap:'), findsNothing);
  });

  testWidgets(
      'shows the local snap card in local mode (channels take precedence)',
      (tester) async {
    await tester.pumpWidget(wrap(sidebar(
      isLocalMode: true,
      hasGadgetData: true,
      snapName: 'pc',
      snapVersion: '26.04',
      snapArchitectures: ['amd64', 'arm64'],
    )));
    expect(find.text('Local Snap:'), findsOneWidget);
    expect(find.text('Loaded from local file'), findsOneWidget);
    expect(find.text('Version: 26.04'), findsOneWidget);
    expect(find.text('Architecture: amd64 / arm64'), findsOneWidget);

    // Channels win over the local-snap card when both are present.
    await tester.pumpWidget(wrap(sidebar(
      isLocalMode: true,
      hasGadgetData: true,
      snapName: 'pc',
      availableChannels: [
        {'channel': {'track': '26', 'risk': 'stable', 'architecture': 'amd64'}},
      ],
    )));
    expect(find.text('Available Channels:'), findsOneWidget);
    expect(find.text('Local Snap:'), findsNothing);
  });

  testWidgets('tapping the local snap card triggers a reload', (tester) async {
    var reloaded = 0;
    await tester.pumpWidget(wrap(sidebar(
      isLocalMode: true,
      hasGadgetData: true,
      snapName: 'pc',
      onLocalSnapReload: () => reloaded++,
    )));
    await tester.tap(find.text('Loaded from local file'));
    await tester.pump();
    expect(reloaded, 1);
  });

  testWidgets('search submission and local pick callbacks are wired',
      (tester) async {
    String? searched;
    var picked = 0;
    await tester.pumpWidget(wrap(sidebar(
      onSearchSubmitted: (v) => searched = v,
      onLocalSnapPicked: () async => picked++,
    )));
    await tester.enterText(
        find.byType(TextField).first, 'pc');
    await tester.tap(find.byType(LocalSnapLoader));
    await tester.pump();
    expect(picked, 1);
    // Submit the search field.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(searched, 'pc');
  });
}
