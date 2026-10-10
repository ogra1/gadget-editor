import 'package:flutter/material.dart';

class ChannelListItem extends StatelessWidget {
  final Map<String, dynamic> channel;
  final ValueChanged<Map<String, dynamic>> onChannelSelected;
  final bool isSelected;

  const ChannelListItem({
    super.key,
    required this.channel,
    required this.onChannelSelected,
    this.isSelected = false,
  });

  String get _trackRiskDisplay {
    final channelInfo = channel['channel'] as Map<String, dynamic>;
    final track = channelInfo['track'] as String?;
    final risk = channelInfo['risk'] as String?;
    return '${track ?? 'unknown'}/${risk ?? 'unknown'}';
  }

  @override
  Widget build(BuildContext context) {
    final channelInfo = channel['channel'] as Map<String, dynamic>;
    final version = channel['version'] as String?;
    final revision = channel['revision'] as int?;
    final architecture = channelInfo['architecture'] as String?;

    final title = Row(
      children: [
        if (isSelected)
          const Icon(
            Icons.check_circle,
            size: 16,
            color: Colors.green,
          ),
        if (isSelected) const SizedBox(width: 8),
        Expanded(child: Text(_trackRiskDisplay)),
      ],
    );

    final subtitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Version: $version'),
        Text('Architecture: $architecture'),
        Text('Revision: $revision'),
        if (isSelected) ...[
          const SizedBox(height: 4),
          const Text(
            'Currently Selected',
            style: TextStyle(
              fontSize: 12,
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );

    if (isSelected) {
      // A Card (Material) rather than a bare Container: ListTile paints its
      // ink on the nearest Material ancestor, which a DecoratedBox would hide.
      return Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Theme.of(context).primaryColor),
        ),
        child: ListTile(
          title: title,
          subtitle: subtitle,
          // Already selected; nothing to do.
          onTap: () {},
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: title,
        subtitle: subtitle,
        trailing: const Icon(Icons.download_for_offline),
        onTap: () => onChannelSelected(channel),
      ),
    );
  }
}
