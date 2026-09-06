import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;
import 'package:file_selector/file_selector.dart';
import '../models/gadget_model.dart';
import '../services/snap_service.dart';
import '../services/file_service.dart';
import 'widgets/status_bar.dart';
import 'widgets/channel_list.dart';
import 'widgets/sidebar_header.dart';
import 'widgets/search_section.dart';
import 'widgets/local_snap_loader.dart';
import 'widgets/gadget_content.dart';
import 'widgets/empty_state.dart';

class GadgetEditorScreen extends StatefulWidget {
  const GadgetEditorScreen({super.key});

  @override
  State<GadgetEditorScreen> createState() => _GadgetEditorScreenState();
}

class _GadgetEditorScreenState extends State<GadgetEditorScreen> {
  String? snapName;
  String? gadgetContent;
  Map<String, dynamic>? gadgetData;
  bool isLoading = false;
  String error = '';
  String statusMessage = 'Ready'; // Status bar message
  bool isActionButtonEnabled = false; // Button is inactive by default
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> availableChannels = [];
  Map<String, dynamic>? selectedChannel;
  String? tempDirectoryPath;
  String? appTempDirectory;
  
  // Track if we're in local mode
  bool isLocalMode = false;
  // Store the path of the loaded local snap
  String? loadedLocalSnapPath;
  // Store platform information
  bool isAmd64Platform = true; // Default to amd64

  @override
  void initState() {
    super.initState();
    // Create a temporary directory for our snap files
    _createTempDirectory();
  }

  Future<void> _createTempDirectory() async {
    try {
      // Create a temporary directory in the system's temp directory
      final tempDir = Directory.systemTemp;
      final appDir = Directory('${tempDir.path}/gadget_editor_${DateTime.now().millisecondsSinceEpoch}');
      await appDir.create(recursive: true);
      appTempDirectory = appDir.path;
      tempDirectoryPath = appDir.path;
    } catch (e) {
      // Fallback to current directory if temp creation fails
      tempDirectoryPath = null;
      appTempDirectory = null;
    }
  }

  Future<void> _cleanupTempFiles() async {
    try {
      if (appTempDirectory != null) {
        final tempDir = Directory(appTempDirectory!);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    } catch (e) {
      // Ignore cleanup errors as they're not critical
    }
  }

  Future<void> fetchSnapChannels(String snapName) async {
    setState(() {
      isLoading = true;
      error = '';
      availableChannels = [];
      selectedChannel = null;
      statusMessage = 'Searching for gadget snaps...';
    });
      
    try {
      // Get the snap info from Snap Store API to get channel information
      final snapInfoUrl = 'https://api.snapcraft.io/v2/snaps/info/$snapName';
        
      final request = await HttpClient().getUrl(Uri.parse(snapInfoUrl));
      // Add all required headers from your curl example
      request.headers.set('Snap-Device-Series', '16');
      request.headers.set('X-Ubuntu-Series', '16');
      request.headers.set('X-Ubuntu-Release', '20.04');
      request.headers.set('Accept', 'application/json');
        
      final response = await request.close();
        
      if (response.statusCode == 200) {
        final data = await response.transform(utf8.decoder).join();
        final snapInfo = jsonDecode(data);
          
        // Extract the channel map
        final channelMap = snapInfo['channel-map'] as List<dynamic>? ?? [];
          
        if (channelMap.isEmpty) {
          throw Exception('No channel map found in API response');
        }
          
        // Filter for gadget type snaps only AND Ubuntu Core tracks (full numbers, not 24.04, 26.04)
        final gadgetChannels = channelMap
            .where((channel) => channel['type'] == 'gadget')
            .where((channel) => channel['channel']['track'] != null)
            .where((channel) => !channel['channel']['track'].toString().contains('.'))
            .toList();
          
        // Group channels by track/risk and select the one with highest revision
        final uniqueChannels = <Map<String, dynamic>>[];
        final channelGroups = <String, List<Map<String, dynamic>>>{};
          
        for (var channel in gadgetChannels) {
          final track = channel['channel']['track'] as String?;
          final risk = channel['channel']['risk'] as String?;
          final key = '${track}/${risk}';
            
          if (!channelGroups.containsKey(key)) {
            channelGroups[key] = [];
          }
          channelGroups[key]!.add(channel);
        }
          
        // For each group, select the channel with the highest revision
        for (var group in channelGroups.values) {
          Map<String, dynamic>? maxRevisionChannel;
          int maxRevision = -1;
            
          for (var channel in group) {
            final revision = channel['revision'] as int?;
            if (revision != null && revision > maxRevision) {
              maxRevision = revision;
              maxRevisionChannel = channel;
            }
          }
            
          if (maxRevisionChannel != null) {
            uniqueChannels.add(maxRevisionChannel);
          }
        }
          
        setState(() {
          availableChannels = uniqueChannels.map((channel) {
            return {
              'channel': channel['channel'],
              'download': channel['download'],
              'revision': channel['revision'],
              'version': channel['version'],
            };
          }).toList();
          statusMessage = 'Found ${availableChannels.length} available channels';
        });
      } else {
        // Get the response body for better error details
        final errorBody = await response.transform(utf8.decoder).join();
        throw Exception('Snap not found: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      setState(() {
	    error = e.toString();
        // Remove the Exception: prefix if present
        if (error.startsWith('Exception: ')) {
          error = error.substring(11); // Remove "Exception: "
        }
        statusMessage = '\n$error';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> loadLocalGadgetSnap(String filePath) async {
    setState(() {
      isLoading = true;
      error = '';
      selectedChannel = null;
      isLocalMode = true; // Switch to local mode
      statusMessage = 'Loading local gadget snap...';
      isActionButtonEnabled = true; // Enable button when local snap is loaded
    });
      
    try {
      // Check if file exists
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }
        
      // Extract snap using Process - use temp directory for consistency
      final fileName = path.basename(filePath);
      final extractPath = '${tempDirectoryPath!}/${fileName}_extracted';
        
      // Remove existing directory if it exists (this fixes the overwrite issue)
      final extractDir = Directory(extractPath);
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
        
      final extractProcess = await Process.run(
        'unsquashfs',
        ['-d', extractPath, filePath],
        runInShell: true,
      );
        
      if (extractProcess.exitCode != 0) {
        throw Exception('Snap extraction failed: ${extractProcess.stderr}');
      }
        
      // Find gadget.yaml
      final gadgetPath = '$extractPath/meta/gadget.yaml';
      final gadgetFile = File(gadgetPath);
      if (!await gadgetFile.exists()) {
        throw Exception('gadget.yaml not found in snap');
      }
        
      // Read and parse
      final content = await gadgetFile.readAsString();
      final data = loadYaml(content); // This returns YamlMap, not Map<String, dynamic>
        
      // Convert YamlMap to Map<String, dynamic> properly
      Map<String, dynamic> parsedData;
      if (data is YamlMap) {
        parsedData = data.cast<String, dynamic>();
      } else if (data is Map<String, dynamic>) {
        parsedData = data;
      } else {
        throw Exception('Unsupported YAML data type: ${data.runtimeType}');
      }
        
      // Extract snap name from filename (everything before first underscore)
      String snapNameFromFileName = fileName;
      final underscoreIndex = fileName.indexOf('_');
      if (underscoreIndex != -1) {
        snapNameFromFileName = fileName.substring(0, underscoreIndex);
      }
        
      setState(() {
        this.snapName = snapNameFromFileName;
        this.gadgetContent = content;
        this.gadgetData = parsedData;
        this.isAmd64Platform = false; // Local snaps are typically not amd64
        loadedLocalSnapPath = filePath; // Store the original path
        availableChannels = []; // Clear remote channels
        statusMessage = 'Local gadget snap loaded successfully';
      });
        
    } catch (e) {
      setState(() {
        error = e.toString();
        statusMessage = 'Error loading local snap: $error';
        isActionButtonEnabled = false; // Disable button on error
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> downloadSelectedChannel(Map<String, dynamic> channel) async {
    setState(() {
      isLoading = true;
      error = '';
      isLocalMode = false; // Switch to remote mode
      statusMessage = 'Downloading selected channel...';
      isActionButtonEnabled = true; // Enable button when remote snap is loaded
    });
      
    try {
      final downloadUrl = channel['download']['url'];
        
      if (downloadUrl == null) {
        throw Exception('No download URL found in selected channel');
      }
        
      // Determine the file path - use temp directory if available, otherwise current directory
      final fileName = '$snapName.snap';
      String filePath;
      if (tempDirectoryPath != null) {
        filePath = '$tempDirectoryPath/$fileName';
      } else {
        filePath = fileName;
      }
        
      // Check if we already have a cached version (check if the extracted directory exists)
      final channelInfo = channel['channel'] as Map<String, dynamic>;
      final track = channelInfo['track'] as String?;
      final risk = channelInfo['risk'] as String?;
        
      // Try to locate the existing extracted directory if it's already been extracted
      if (track != null && risk != null) {
        final uniqueExtractPath = '${filePath}_extracted_${track}_${risk}';
        final extractDir = Directory(uniqueExtractPath);
          
        // If the directory exists, read directly from it
        if (await extractDir.exists()) {
          final gadgetPath = '$uniqueExtractPath/meta/gadget.yaml';
          final file = File(gadgetPath);
          if (await file.exists()) {
            final content = await file.readAsString();
            final data = loadYaml(content);
              
            Map<String, dynamic> parsedData;
            if (data is YamlMap) {
              parsedData = data.cast<String, dynamic>();
            } else if (data is Map<String, dynamic>) {
              parsedData = data;
            } else {
              throw Exception('Unsupported YAML data type: ${data.runtimeType}');
            }
              
            // Extract architecture information from the channel
            final architecture = channelInfo['architecture'] as String?;
            // Determine if it's amd64 platform
            bool isAmd64 = architecture?.toLowerCase() == 'amd64';
              
            setState(() {
              this.snapName = snapName;
              this.gadgetContent = content;
              this.gadgetData = parsedData;
              this.selectedChannel = channel;
              this.isAmd64Platform = isAmd64; // Store the platform info
            });
              
            setState(() {
              statusMessage = 'Gadget parsed successfully (cached)';
            });
            return;
          }
        }
      }
        
      // Download the snap file directly from the API
      final downloadRequest = await HttpClient().getUrl(Uri.parse(downloadUrl));
      // Add the same headers for download request
      downloadRequest.headers.set('Snap-Device-Series', '16');
      downloadRequest.headers.set('X-Ubuntu-Series', '16');
      downloadRequest.headers.set('X-Ubuntu-Release', '20.04');
      downloadRequest.headers.set('Accept', 'application/octet-stream');
        
      final downloadResponse = await downloadRequest.close();
        
      if (downloadResponse.statusCode == 200) {
        // Save the snap file
        final snapFile = File(filePath);
        await snapFile.openWrite().addStream(downloadResponse);
          
        // Extract snap using Process - make directory name unique with track/risk
        final channelInfo = channel['channel'] as Map<String, dynamic>;
        final track = channelInfo['track'] as String?;
        final risk = channelInfo['risk'] as String?;
        String uniqueExtractPath;
          
        if (track != null && risk != null) {
          // Create unique directory name with track and risk
          uniqueExtractPath = '${filePath}_extracted_${track}_${risk}';
        } else {
          // Fallback to original naming
          uniqueExtractPath = '${filePath}_extracted';
        }
          
        // Remove existing directory if it exists (this fixes the overwrite issue)
        final extractDir = Directory(uniqueExtractPath);
        if (await extractDir.exists()) {
          await extractDir.delete(recursive: true);
        }
          
        final extractProcess = await Process.run(
          'unsquashfs',
          ['-d', uniqueExtractPath, filePath],
          runInShell: true,
        );

        if (extractProcess.exitCode != 0) {
          throw Exception('Snap extraction failed: ${extractProcess.stderr}');
        }
          
        // Find gadget.yaml
        final gadgetPath = '$uniqueExtractPath/meta/gadget.yaml';
        final file = File(gadgetPath);
        if (!await file.exists()) {
          throw Exception('gadget.yaml not found in snap');
        }
          
        // Read and parse
        final content = await file.readAsString();
        final data = loadYaml(content); // This returns YamlMap, not Map<String, dynamic>
          
        // Convert YamlMap to Map<String, dynamic> properly
        Map<String, dynamic> parsedData;
        if (data is YamlMap) {
          parsedData = data.cast<String, dynamic>();
        } else if (data is Map<String, dynamic>) {
          parsedData = data;
        } else {
          throw Exception('Unsupported YAML data type: ${data.runtimeType}');
        }
          
        // Extract architecture information from the channel
        final architecture = channelInfo['architecture'] as String?;
        // Determine if it's amd64 platform
        bool isAmd64 = architecture?.toLowerCase() == 'amd64';
          
        setState(() {
          this.snapName = snapName;
          this.gadgetContent = content;
          this.gadgetData = parsedData;
          this.selectedChannel = channel;
          this.isAmd64Platform = isAmd64; // Store the platform info
        });
          
        setState(() {
          statusMessage = 'Gadget parsed successfully';
        });
      } else {
        throw Exception('Failed to download snap: ${downloadResponse.statusCode}');
      }
    } catch (e) {
      setState(() {
        error = e.toString();
        statusMessage = 'Error: $error';
        isActionButtonEnabled = false; // Disable button on error
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Function to reload local snap from cache
  Future<void> reloadLocalSnap() async {
    if (loadedLocalSnapPath != null) {
      setState(() {
        isLoading = true;
        error = '';
        statusMessage = 'Reloading local snap...';
      });
        
      try {
        // Determine the extraction path that would have been used
        final fileName = path.basename(loadedLocalSnapPath!);
        final extractPath = '${tempDirectoryPath!}/${fileName}_extracted';
          
        // Check if the directory already exists (cached version)
        final extractDir = Directory(extractPath);
        if (await extractDir.exists()) {
          // Load directly from cached directory
          final gadgetPath = '$extractPath/meta/gadget.yaml';
          final gadgetFile = File(gadgetPath);
          if (await gadgetFile.exists()) {
            final content = await gadgetFile.readAsString();
            final data = loadYaml(content);
              
            Map<String, dynamic> parsedData;
            if (data is YamlMap) {
              parsedData = data.cast<String, dynamic>();
            } else if (data is Map<String, dynamic>) {
              parsedData = data;
            } else {
              throw Exception('Unsupported YAML data type: ${data.runtimeType}');
            }
              
            setState(() {
              this.snapName = 'Local Snap: ${path.basename(loadedLocalSnapPath!)}';
              this.gadgetContent = content;
              this.gadgetData = parsedData;
            });
              
            setState(() {
              statusMessage = 'Local snap reloaded successfully (cached)';
            });
            return;
          }
        }
          
        // If no cached directory exists, fall back to normal extraction
        await loadLocalGadgetSnap(loadedLocalSnapPath!);
          
      } catch (e) {
        setState(() {
          error = e.toString();
          statusMessage = 'Error: $error';
          isActionButtonEnabled = false; // Disable button on error
        });
      } finally {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gadget Editor'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? Colors.white,
        elevation: 0,
        toolbarHeight: 40,
      ),
      body: Column(
        children: [
          // Main content area with sidebar and main content
          Expanded(
            child: Row(
              children: [
                // Left sidebar with snap input and channels
                Container(
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
                        controller: _searchController,
                        onSubmitted: (value) {
                          if (value.isNotEmpty) {
                            snapName = value;
                            fetchSnapChannels(value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      LocalSnapLoader(
                        onPressed: () async {
                          try {
                            // Use file_selector for cross-platform file picking
                            final file = await openFile();
                            if (file != null) {
                              loadLocalGadgetSnap(file.path);
                            }
                          } catch (e) {
                            setState(() {
                              error = 'Failed to select file: $e';
                              statusMessage = 'Error: Failed to select file';
                              isActionButtonEnabled = false; // Disable button on error
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      if (isLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (availableChannels.isNotEmpty)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Available Channels:',
                                style: TextStyle(
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ChannelList(
                                  channels: availableChannels,
                                  onChannelSelected: downloadSelectedChannel,
                                  isLoading: isLoading,
                                  error: error,
                                  selectedChannel: selectedChannel,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (isLocalMode && gadgetData != null)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Local Snap:',
                                style: TextStyle(
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView(
                                  children: [
                                    // Show local snap info
                                    Container(
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
                                            const Text(
                                              'Loaded from local file',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green,
                                              ),
                                            ),
                                          ],
                                        ),
                                        onTap: () {
                                          // Reload the local snap when clicked
                                          reloadLocalSnap();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        const Expanded(
                          child: SizedBox.shrink(), // Sidebar shows nothing but search and button
                        ),
                    ],
                  ),
                ),
                // Main content area
                Expanded(
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (gadgetData != null)
                          Text(
                            'Snap: $snapName',
                            style: Theme.of(context).textTheme.headlineSmall,
                          )
                        else
                          const Text(
                            'Gadget Editor',
                            style: TextStyle(
                              fontSize: 24,
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (gadgetData != null)
                          Expanded(
                            child: GadgetContent(
                              content: gadgetContent,
                              isAmd64: isAmd64Platform,
                            ),
                          )
                        else
                          const Expanded(
                            child: EmptyState(),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Status bar at the bottom
          StatusBar(
            message: statusMessage,
            isActionButtonEnabled: isActionButtonEnabled,
            onActionPressed: () {
              setState(() {
                statusMessage = 'Action button clicked!';
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Clean up temporary files when the widget is disposed
    _cleanupTempFiles();
    super.dispose();
  }
}
