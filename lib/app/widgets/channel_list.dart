import 'package:flutter/material.dart';
import 'channel_list_item.dart';

/// Orders two channel entries (as produced by [SnapStoreService]) for
/// display.
///
/// Numbered tracks come first, highest number first (26 above 24). Tracks
/// that do not begin with a number (such as the legacy `latest`) are sorted
/// alphabetically after all numbered tracks. Within a track, risks follow the
/// usual snap order (stable, candidate, beta, edge) and then architecture.
int channelDisplayCompare(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aTrack = (a['channel']['track'] as String?) ?? '';
  final bTrack = (b['channel']['track'] as String?) ?? '';

  final aNum = _trackNumber(aTrack);
  final bNum = _trackNumber(bTrack);

  int trackCmp;
  if (aNum != null && bNum != null) {
    // Highest numbered channel first.
    trackCmp = bNum.compareTo(aNum);
  } else if (aNum != null) {
    trackCmp = -1; // a is numbered, b is not -> a first
  } else if (bNum != null) {
    trackCmp = 1; // b is numbered, a is not -> b first
  } else {
    trackCmp = aTrack.compareTo(bTrack);
  }
  if (trackCmp != 0) {
    return trackCmp;
  }

  final aRisk = (a['channel']['risk'] as String?) ?? '';
  final bRisk = (b['channel']['risk'] as String?) ?? '';
  final riskCmp = _riskRank(aRisk).compareTo(_riskRank(bRisk));
  if (riskCmp != 0) {
    return riskCmp;
  }

  final aArch = (a['channel']['architecture'] as String?) ?? '';
  final bArch = (b['channel']['architecture'] as String?) ?? '';
  return aArch.compareTo(bArch);
}

/// Leading integer of a track name ('26' -> 26, '26.04' -> 26, 'latest' -> null).
int? _trackNumber(String track) {
  final match = RegExp(r'^(\d+)').firstMatch(track);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}

int _riskRank(String risk) {
  const order = ['stable', 'candidate', 'beta', 'edge'];
  final i = order.indexOf(risk);
  return i == -1 ? order.length : i;
}

bool _isSameChannel(Map<String, dynamic>? a, Map<String, dynamic>? b) {
  if (a == null || b == null) {
    return false;
  }
  final ca = a['channel'] as Map?;
  final cb = b['channel'] as Map?;
  return ca?['track'] == cb?['track'] &&
      ca?['risk'] == cb?['risk'] &&
      ca?['architecture'] == cb?['architecture'];
}

class ChannelList extends StatelessWidget {
  final List<Map<String, dynamic>> channels;
  final ValueChanged<Map<String, dynamic>> onChannelSelected;
  final bool isDownloading;
  final Map<String, dynamic>? selectedChannel;

  const ChannelList({
    super.key,
    required this.channels,
    required this.onChannelSelected,
    this.isDownloading = false,
    this.selectedChannel,
  });

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const SizedBox.shrink();
    }

    final ordered = List<Map<String, dynamic>>.of(channels)
      ..sort(channelDisplayCompare);

    // The selected channel (if any) always sits at the top; picking another
    // one simply moves the new selection up and the previous one back into
    // its sorted position.
    final selected = selectedChannel;
    final display = <Map<String, dynamic>>[];
    if (selected != null) {
      display.add(selected);
      display.addAll(ordered.where((c) => !_isSameChannel(c, selected)));
    } else {
      display.addAll(ordered);
    }

    final list = ListView.builder(
      itemCount: display.length,
      itemBuilder: (context, index) {
        final channel = display[index];
        return ChannelListItem(
          channel: channel,
          onChannelSelected: onChannelSelected,
          isSelected: _isSameChannel(channel, selected),
        );
      },
    );

    if (!isDownloading) {
      return list;
    }

    // Keep the list visible (dimmed and non-interactive) while a channel is
    // downloading, with a progress indicator on top.
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: Opacity(opacity: 0.5, child: list)),
        const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
