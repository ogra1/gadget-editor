import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'dart:math' as math;
import 'package:gadget_editor/app/widgets/editable_text_field.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:io';
import 'package:gadget_editor/app/widgets/partition_size_editor.dart';

class GadgetVolumesSection extends StatefulWidget {
  final dynamic volumes;
  final VoidCallback? onEdit;
  final bool showEditButton;
  final String? filePath;
  final VoidCallback? refreshCallback;
  final Function(String)? onStatusUpdate;

  const GadgetVolumesSection({
    super.key,
    required this.volumes,
    this.onEdit,
    this.showEditButton = true,
    this.filePath,
    this.refreshCallback,
    this.onStatusUpdate,
  });

  @override
  State<GadgetVolumesSection> createState() => _GadgetVolumesSectionState();
}

class _GadgetVolumesSectionState extends State<GadgetVolumesSection> {
  @override
  Widget build(BuildContext context) {
    if (widget.volumes == null || (widget.volumes is YamlMap && widget.volumes.isEmpty)) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Volumes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text('No volumes defined.'),
          ],
        ),
      );
    }

    if (widget.volumes is YamlMap) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Volumes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...widget.volumes.entries.map((entry) {
                final volumeName = entry.key;
                final volumeData = entry.value;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storage, size: 20, color: Colors.grey),
                        const SizedBox(width: 8),
                        SizedBox(
                          //width: MediaQuery.of(context).size.width * 0.14,
                          width: 200,
                          child: EditableTextField(
                            text: volumeName,
                            onSave: (newName) {
                              // Update the volume name in the YAML file
                              if (widget.filePath != null) {
                                _updateVolumeNameInFile(widget.filePath!, volumeName, newName);
                              }
                            },
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (volumeData['structure'] != null && volumeData['structure'] is List) 
                      _buildPartitionVisualization(context, volumeData['structure'], volumeName) 
                    else if (volumeData['structure'] == null) 
                      const Text('No structure field found') 
                    else 
                      const Text('Structure is not a list'),
                    const SizedBox(height: 16),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Volumes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text('No volumes defined. Click the edit icon to add volumes.'),
        ],
      ),
    );
  }

  // Function to update volume name in the YAML file
  void _updateVolumeNameInFile(String filePath, String oldName, String newName) {
    try {
      // Read the existing file content
      final file = File(filePath);
      final content = file.readAsStringSync();

      // Parse the YAML content
      final yaml = loadYaml(content);

      // Check if it's a YamlMap and has volumes
      if (yaml is YamlMap && yaml.containsKey('volumes')) {
        final volumes = yaml['volumes'];

        // Create a new volumes map with updated volume name
        final newVolumes = <String, dynamic>{};

        // Iterate through existing volumes and update the name
        if (volumes is YamlMap) {
          for (var entry in volumes.entries) {
            if (entry.key == oldName) {
              newVolumes[newName] = entry.value;
            } else {
              newVolumes[entry.key] = entry.value;
            }
          }
        } else if (volumes is Map<String, dynamic>) {
          for (var entry in volumes.entries) {
            if (entry.key == oldName) {
              newVolumes[newName] = entry.value;
            } else {
              newVolumes[entry.key] = entry.value;
            }
          }
        }

        // Create a new YamlEditor instance to update the file
        final editor = YamlEditor(content);

        // Update the volumes section in the editor
        editor.update(['volumes'], newVolumes);

        // Write back to file
        file.writeAsStringSync(editor.toString());
        widget.onStatusUpdate!('Volume name updated successfully');
        if (widget.refreshCallback != null) {
          widget.refreshCallback!();
        }
      }

    } catch (e) {
      // Handle error appropriately in your app
      print('Error updating volume name: $e');
    }
  }

  Widget _buildPartitionVisualization(BuildContext context, List structure, String volumeName) {
    if (structure.isEmpty) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Text('No partitions to display'),
        ),
      );
    }
    // Parse all sizes to calculate total size
    double totalSize = 0;
    List<Map<String, dynamic>> parsedStructures = [];

    for (var item in structure) {
      final sizeStr = item['size'];
      if (sizeStr != null) {
        double sizeValue = _parseSize(sizeStr);
        parsedStructures.add({
          'name': item['name'] ?? 'Unnamed',
          'size': sizeValue,
          'role': item['role'],
          'type': item['type'],
        });
        totalSize += sizeValue;
      }
    }

    if (totalSize <= 0) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Text('No valid partition sizes'),
        ),
      );
    }
    // Create proportional visualization
    return SizedBox(
      height: 80,
      child: Row(
        children: [
          for (var item in parsedStructures) 
            Expanded(
              flex: (item['size']! / totalSize * 1000).toInt() > 0 ? (item['size']! / totalSize * 1000).toInt() : 1,
              child: Container(
                height: 78,
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: _getPartitionColor(item['role'], item['size']!),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300, width: 0.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          // Text content centered
                          Center(
                            child: Text(
                              item['name'] ?? 'Unnamed',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Edit icon for system-seed and system-data partitions
                          if (item['role'] == 'system-seed' || item['role'] == 'system-data')
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () {
                                  // Show the partition size editor dialog
                                  showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return PartitionSizeEditor(
                                        partitionName: item['name'] ?? 'Unnamed',
                                        currentSize: _formatSize(item['size']),
                                        filePath: widget.filePath,
                                        volumeName: volumeName,
                                        onSave: (newSize) {
                                          // The dialog handles saving, so we just close it
                                          if (widget.refreshCallback != null) {
                                            widget.refreshCallback!();
                                          }
                                          Navigator.of(context).pop();
                                        },
                                        onCancel: () {
                                          Navigator.of(context).pop();
                                        },
                                        onStatusUpdate: (message) {
                                          if (widget.onStatusUpdate != null) {
                                            widget.onStatusUpdate!(message);
                                          } else if (widget.refreshCallback != null) {
                                            // Fallback to refresh if no status update callback
                                            widget.refreshCallback!();
                                          }
                                        },
                                        onPartitionChanged: () {
                                          // Trigger refresh when partition is changed
                                          if (widget.refreshCallback != null) {
                                            widget.refreshCallback!();
                                          }
                                        },
                                      );
                                    },
                                  );
                                },
                                child: Icon(
                                  Icons.edit,
                                  size: 18, // Larger size
                                  color: Colors.white, // White color for better visibility
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      _formatSize(item['size']),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _parseSize(dynamic size) {
    if (size == null) return 0;

    // Convert to string first if it's not already
    String sizeStr = size.toString();

    if (sizeStr.endsWith('M')) {
      return (double.tryParse(sizeStr.substring(0, sizeStr.length - 1)) ?? 0) * 1024 * 1024;
    } else if (sizeStr.endsWith('G')) {
      return (double.tryParse(sizeStr.substring(0, sizeStr.length - 1)) ?? 0) * 1024 * 1024 * 1024;
    } else if (sizeStr.endsWith('K')) {
      return (double.tryParse(sizeStr.substring(0, sizeStr.length - 1)) ?? 0) * 1024;
    } else {
      // For sizes without units (like 440), treat as bytes
      return double.tryParse(sizeStr) ?? 0;
    }
  }

  String _formatSize(double sizeInBytes) {
    if (sizeInBytes >= 1024 * 1024 * 1024) {
      return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
    } else if (sizeInBytes >= 1024 * 1024) {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)}M';
    } else if (sizeInBytes >= 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)}K';
    } else {
      return '${sizeInBytes.toStringAsFixed(0)}B';
    }
  }

  Color _getPartitionColor(String? role, double sizeInBytes) {
    // Define pastel colors for each role
    Map<String, Color> roleColors = {
      'system-seed': const Color(0xFF81C784), // Light green (pastel)
      'system-boot': const Color(0xFF64B5F6), // Light blue (pastel)
      'system-save': const Color(0xFFBA68C8), // Light purple (pastel)
      'system-data': const Color(0xFFB39DDB), // Light purple (pastel)
    };
    // If we have a role, use the role-based color and adjust intensity based on size
    if (role != null && roleColors.containsKey(role)) {
      Color baseColor = roleColors[role]!;

      // Adjust intensity based on size (larger partitions = darker colors for better contrast)
      double intensity = _calculateIntensity(sizeInBytes);

      // Return the color with adjusted brightness
      return _adjustColorBrightness(baseColor, intensity);
    }

    // For partitions without roles, use a size-based color gradient
    return _getSizeBasedColor(sizeInBytes);
  }

  double _calculateIntensity(double sizeInBytes) {
    // Define reasonable size ranges to map to intensity
    const double smallThreshold = 1024 * 1024; // 1MB
    const double mediumThreshold = 1024 * 1024 * 1024; // 1GB

    if (sizeInBytes < smallThreshold) {
      return 0.8; // Light color for small partitions
    } else if (sizeInBytes < mediumThreshold) {
      return 0.6; // Medium color for medium partitions
    } else {
      return 0.4; // Darker color for large partitions
    }
  }

  Color _adjustColorBrightness(Color color, double intensity) {
    // Create a simple brightness adjustment by modifying RGB values directly
    int red = (color.red * intensity).round().clamp(0, 255);
    int green = (color.green * intensity).round().clamp(0, 255);
    int blue = (color.blue * intensity).round().clamp(0, 255);

    return Color.fromARGB(color.alpha, red, green, blue);
  }

  Color _getSizeBasedColor(double sizeInBytes) {
    // Create a color gradient based on size using simple thresholds
    const double smallThreshold = 1024 * 1024; // 1MB
    const double mediumThreshold = 1024 * 1024 * 1024; // 1GB

    if (sizeInBytes < smallThreshold) {
      // Very small partitions - light blue (pastel)
      return const Color(0xFF90CAF9); // Light blue
    } else if (sizeInBytes < mediumThreshold) {
      // Medium partitions - medium blue (pastel)
      return const Color(0xFF64B5F6); // Blue
    } else {
      // Large partitions - dark blue (but still pastel-like)
      return const Color(0xFF1976D2); // Darker blue
    }
  }
}
