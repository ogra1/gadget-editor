import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart'; // YaruColorSchemeExtension (success color)
import 'channel_list.dart';
import 'local_snap_loader.dart';
import 'search_section.dart';
import 'sidebar_header.dart';

/// The fixed left-hand panel: snap search, local-snap loader, and the
/// channel / local-snap info that appears once a snap has been searched or
/// loaded.
///
/// This is a *form* panel, not a list→detail navigation surface, so it is a
/// plain [StatelessWidget] rather than a `YaruMasterDetailPage` (that widget
/// models selectable master tiles with a per-tile detail, which doesn't fit
/// a search box + loader + conditional info list). It takes its data and
/// callbacks from the screen and owns no state.
class GadgetEditorSidebar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchSubmitted;
  final FutureOr<void> Function() onLocalSnapPicked;

  final List<Map<String, dynamic>> availableChannels;
  final Map<String, dynamic>? selectedChannel;
  final bool isDownloading;
  final ValueChanged<Map<String, dynamic>> onChannelSelected;

  final bool isLocalMode;
  final bool hasGadgetData;
  final String? snapName;
  final String? snapVersion;
  final List<String> snapArchitectures;
  final VoidCallback onLocalSnapReload;

  const GadgetEditorSidebar({
    super.key,
    required this.searchController,
    required this.onSearchSubmitted,
    required this.onLocalSnapPicked,
    required this.availableChannels,
    required this.selectedChannel,
    required this.isDownloading,
    required this.onChannelSelected,
    required this.isLocalMode,
    required this.hasGadgetData,
    required this.snapName,
    this.snapVersion,
    required this.snapArchitectures,
    required this.onLocalSnapReload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SidebarHeader(),
          const SizedBox(height: 16),
          SearchSection(
            controller: searchController,
            onSubmitted: onSearchSubmitted,
          ),
          const SizedBox(height: 16),
          LocalSnapLoader(onPressed: onLocalSnapPicked),
          const SizedBox(height: 16),
          if (availableChannels.isNotEmpty)
            _buildAvailableChannels(context)
          else if (isLocalMode && hasGadgetData)
            _buildLocalSnap(context)
          else
            const Expanded(
              child: SizedBox.shrink(), // Sidebar shows nothing but search + loader
            ),
        ],
      ),
    );
  }

  /// Section header shared by the "Available Channels" and "Local Snap"
  /// panels.
  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14),
    );
  }

  Widget _buildAvailableChannels(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Available Channels:'),
          const SizedBox(height: 8),
          Expanded(
            child: ChannelList(
              channels: availableChannels,
              onChannelSelected: onChannelSelected,
              isDownloading: isDownloading,
              selectedChannel: selectedChannel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalSnap(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Local Snap:'),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                // A Card so the ListTile's ink has a Material to paint on.
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Theme.of(context).primaryColor),
                  ),
                  child: ListTile(
                    title: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Theme.of(context).colorScheme.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            snapName ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.normal),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          'Loaded from local file',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.success,
                          ),
                        ),
                        if (snapVersion != null) Text('Version: $snapVersion'),
                        if (snapArchitectures.isNotEmpty)
                          Text(
                            'Architecture: ${snapArchitectures.join(' / ')}',
                          ),
                      ],
                    ),
                    onTap: onLocalSnapReload,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
