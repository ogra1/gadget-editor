import 'package:flutter/material.dart';

class ChannelList extends StatelessWidget {
  final List<Map<String, dynamic>> channels;
  final Function(Map<String, dynamic>) onChannelSelected;
  final bool isLoading;
  final String error;
  final Map<String, dynamic>? selectedChannel;

  const ChannelList({
    super.key,
    required this.channels,
    required this.onChannelSelected,
    required this.isLoading,
    required this.error,
    this.selectedChannel,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Remove the error display from here - it should only appear in status bar
    if (channels.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        final channelInfo = channel['channel'] as Map<String, dynamic>;
        final version = channel['version'] as String?;
        final revision = channel['revision'] as int?;
        final risk = channelInfo['risk'] as String?;
        final architecture = channelInfo['architecture'] as String?;
        final track = channelInfo['track'] as String?;
          
        // Format track/risk display  
        String trackRiskDisplay = '${track ?? 'unknown'}/${risk ?? 'unknown'}';
          
        // Check if this channel is selected  
        bool isSelected = false;
        if (selectedChannel != null) {
          isSelected = selectedChannel?['channel']?['track'] == track &&  
                      selectedChannel?['channel']?['risk'] == risk;  
        }
          
        if (isSelected) {
          // Show selected channel with special styling  
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              border: Border.all(color: Theme.of(context).primaryColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              title: Row(
                children: [  
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trackRiskDisplay,
                      style: const TextStyle(fontWeight: FontWeight.normal),
                    ),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [  
                  Text('Version: $version'),
                  Text('Architecture: $architecture'),
                  Text('Revision: $revision'),
                  const SizedBox(height: 4), // Added spacing  
                  const Text(
                    'Currently Selected',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              onTap: () {
                // Already selected, do nothing  
              },
            ),
          );
        } else {
          // Regular channel  
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              title: Text(trackRiskDisplay),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [  
                  Text('Version: $version'),
                  Text('Architecture: $architecture'),
                  Text('Revision: $revision'),
                ],
              ),
              trailing: const Icon(Icons.download_for_offline),
              onTap: () {
                onChannelSelected(channel);
              },
            ),
          );
        }  
      },
    );
  }
}
