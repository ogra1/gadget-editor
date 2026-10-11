import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import 'package:path/path.dart' as path;
import 'package:file_selector/file_selector.dart';
import 'package:flutter_window_close/flutter_window_close.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'widgets/status_bar.dart';
import 'widgets/channel_list.dart';
import 'widgets/sidebar_header.dart';
import 'widgets/search_section.dart';
import 'widgets/local_snap_loader.dart';
import 'widgets/gadget_content.dart';
import 'widgets/empty_state.dart';
import 'widgets/editable_text_field.dart';
import '../services/snap_store_service.dart';
import '../services/snap_file_service.dart';
import '../services/snap_pack_service.dart';
import '../app/widgets/arch_badge.dart';
import 'utils/snap_name_validator.dart';

// Global variable to store the temp directory path
Directory? globalTempDirectory;

void _cleanUpAndExit() {
  if (globalTempDirectory != null && globalTempDirectory!.existsSync()) {
    try {
      // Synchronously erase the custom folder and its contents
      globalTempDirectory!.deleteSync(recursive: true);
    } catch (e) {
      stderr.writeln('Failed to purge temporary directory: $e');
    }
  }
  exit(0);
}

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
  bool isDownloading = false;
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
  // Architectures of the loaded gadget snap, taken from meta/snap.yaml
  // (the single source of truth for both store-downloaded and local snaps).
  List<String> snapArchitectures = const [];
  // Version of the loaded gadget snap from meta/snap.yaml (null when snap.yaml
  // has no version field).
  String? snapVersion;
  // Store the file path for saving changes
  String? gadgetFilePath;
  // Store the snap.yaml file path for saving snap name
  String? snapFilePath;

  // Keep track of original snap name for reset functionality
  
  // Reference to the EditableTextField for reset functionality
  EditableTextFieldState? _snapNameFieldState;

  // Services backing the store, file and pack operations.
  final SnapStoreService _storeService = SnapStoreService();
  final SnapFileService _fileService = SnapFileService();
  final SnapPackService _packService = SnapPackService();

  @override
  void initState() {
    super.initState();
    // Create a temporary directory for our snap files
    _createTempDirectory();

    // Register native signal intercepts for Linux termination events
    ProcessSignal.sigint.watch().listen((_) => _cleanUpAndExit());
    ProcessSignal.sigterm.watch().listen((_) => _cleanUpAndExit());

    // Register window close handler for GTK events
    FlutterWindowClose.setWindowShouldCloseHandler(() async {
      _cleanUpAndExit();
      return true;
    });
  }

  @override
  void dispose() {
    // Clean up temporary files when the widget is disposed
    _cleanupTempFiles();
    super.dispose();
  }

  Future<void> _createTempDirectory() async {
    try {
      // Create a temporary directory in the system's temp directory
      final tempDir = Directory.systemTemp;
      final appDir = Directory('${tempDir.path}/gadget_editor_${DateTime.now().millisecondsSinceEpoch}');
      await appDir.create(recursive: true);
      globalTempDirectory = appDir;
      appTempDirectory = appDir.path;
      tempDirectoryPath = appDir.path;
      debugPrint('created tempdir: $appDir.path');
    } catch (e) {
      // If temp directory creation fails, we still want to track that we tried
      // But we won't set tempDirectoryPath to null to avoid cleanup issues
      // Instead, we'll just not set the temp directory path
      appTempDirectory = null;
      tempDirectoryPath = null;
      globalTempDirectory = null;
    }
  }

  Future<void> _cleanupTempFiles() async {
    try {
      // Check if we have a valid temp directory path
      Directory? tempDir;

      // Use the global temp directory if available
      if (globalTempDirectory != null) {
        tempDir = globalTempDirectory;
      } else if (appTempDirectory != null) {
        // Explicitly check for null to avoid the promotion issue
        tempDir = Directory(appTempDirectory!);
      } else if (tempDirectoryPath != null) {
        // Explicitly check for null to avoid the promotion issue
        tempDir = Directory(tempDirectoryPath!);
      }

      debugPrint('in cleanup function: $tempDir');

      // If we have a path, try to delete it
      if (tempDir != null && await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }

      // Also try to clean up any old gadget_editor directories that might exist
      // This is a fallback cleanup for any leftover directories
      final tempDirPath = Directory.systemTemp;
      final entries = await tempDirPath.list().toList();

      for (var entry in entries) {
        if (entry is Directory && entry.path.contains('/gadget_editor_')) {
          try {
            await entry.delete(recursive: true);
          } catch (e) {
            // Ignore cleanup errors as they're not critical
          }
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
      final channels =
          await _storeService.searchGadgetChannels(snapName);

      setState(() {
        availableChannels = channels;
        statusMessage = 'Found ${availableChannels.length} available channels';
      });
    } catch (e) {
      final message = _serviceErrorMessage(e);
      setState(() {
        error = message;
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
      final fileName = path.basename(filePath);
      final extractPath = '${tempDirectoryPath!}/${fileName}_extracted';
      final extracted =
          await _fileService.extractSnap(filePath, extractPath);

      // Extract snap name from filename (everything before first underscore)
      // if snap.yaml doesn't have it
      String snapNameFromFileName = fileName;
      final underscoreIndex = fileName.indexOf('_');
      if (underscoreIndex != -1) {
        snapNameFromFileName = fileName.substring(0, underscoreIndex);
      }

      setState(() {
        // Only set snapName from the actual snap.yaml file content
        snapName = extracted.snapNameFromYaml.isNotEmpty
            ? extracted.snapNameFromYaml
            : snapNameFromFileName;
        gadgetContent = extracted.content;
        gadgetData = extracted.data;
        snapArchitectures = extracted.architectures;
        snapVersion = extracted.version.isEmpty ? null : extracted.version;
        loadedLocalSnapPath = filePath; // Store the original path
        gadgetFilePath = extracted.gadgetPath; // meta/gadget.yaml
        snapFilePath = extracted.snapPath; // meta/snap.yaml
        availableChannels = []; // Clear remote channels
        statusMessage = 'Local gadget snap loaded successfully';
      });
    } catch (e) {
      final message = _serviceErrorMessage(e);
      setState(() {
        error = message;
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
      isDownloading = true;
      error = '';
      isLocalMode = false; // Switch to remote mode
      statusMessage = 'Downloading selected channel...';
      isActionButtonEnabled = true; // Enable button when remote snap is loaded
    });

    try {
      final downloadUrl = channel['download']['url'];
      if (downloadUrl == null) {
        throw StoreException('No download URL found in selected channel');
      }

      final channelInfo = channel['channel'] as Map<String, dynamic>;
      final track = channelInfo['track'] as String?;
      final risk = channelInfo['risk'] as String?;

      // Determine where the snap file lives: in the temp directory if
      // available, otherwise the current directory.
      final fileName = path.basename(downloadUrl.toString());
      final filePath =
          tempDirectoryPath != null ? '$tempDirectoryPath/$fileName' : fileName;

      // Extraction directory keyed by track/risk (cache location).
      final extractPath = SnapFileService.extractPathFor(
        filePath,
        track: track,
        risk: risk,
      );

      // If we already extracted this channel, read directly from the cache.
      if (await Directory(extractPath).exists()) {
        final extracted = await _fileService.readExtracted(extractPath);
        setState(() {
          snapName = extracted.snapNameFromYaml.isNotEmpty
              ? extracted.snapNameFromYaml
              : snapName;
          gadgetContent = extracted.content;
          gadgetData = extracted.data;
          selectedChannel = channel;
          snapArchitectures = extracted.architectures;
          snapVersion = extracted.version.isEmpty ? null : extracted.version;
          gadgetFilePath = extracted.gadgetPath;
          snapFilePath = extracted.snapPath;
          statusMessage = 'Gadget parsed successfully (cached)';
        });
        return;
      }

      // Download + extract.
      final snapFile = await _storeService.downloadSnapFile(channel, path.dirname(filePath));
      final extracted =
          await _fileService.extractSnap(snapFile.path, extractPath);

      setState(() {
        snapName = extracted.snapNameFromYaml.isNotEmpty
            ? extracted.snapNameFromYaml
            : snapName;
        gadgetContent = extracted.content;
        gadgetData = extracted.data;
        selectedChannel = channel;
        snapArchitectures = extracted.architectures;
        snapVersion = extracted.version.isEmpty ? null : extracted.version;
        gadgetFilePath = extracted.gadgetPath;
        snapFilePath = extracted.snapPath;
        statusMessage = 'Gadget parsed successfully';
      });
    } catch (e) {
      final message = _serviceErrorMessage(e);
      setState(() {
        error = message;
        statusMessage = 'Error: $error';
        isActionButtonEnabled = false; // Disable button on error
      });
    } finally {
      setState(() {
        isDownloading = false;
      });
    }
  }
  //  Function to reload local snap from cache
  Future<void> reloadLocalSnap() async {
    final localPath = loadedLocalSnapPath;
    if (localPath == null) {
      return;
    }

    setState(() {
      isLoading = true;
      error = '';
      statusMessage = 'Reloading local snap...';
    });

    try {
      // Determine the extraction path that would have been used
      final fileName = path.basename(localPath);
      final extractPath = '${tempDirectoryPath!}/${fileName}_extracted';

      // Check if the directory already exists (cached version)
      if (await Directory(extractPath).exists()) {
        final extracted = await _fileService.readExtracted(extractPath);
        setState(() {
          snapName = extracted.snapNameFromYaml.isNotEmpty
              ? extracted.snapNameFromYaml
              : 'Local Snap';
          gadgetContent = extracted.content;
          gadgetData = extracted.data;
          snapArchitectures = extracted.architectures;
          snapVersion = extracted.version.isEmpty ? null : extracted.version;
          statusMessage = 'Local snap reloaded successfully (cached)';
        });
        return;
      }

      // If no cached directory exists, fall back to normal extraction
      await loadLocalGadgetSnap(localPath);
    } catch (e) {
      final message = _serviceErrorMessage(e);
      setState(() {
        error = message;
        statusMessage = 'Error: $error';
        isActionButtonEnabled = false; // Disable button on error
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }
  //  Function to save the edited snap name to the file with validation
  Future<void> _saveSnapNameToFile(String newName) async {
    final snapPath = snapFilePath;
    if (snapPath == null) {
      setState(() {
        statusMessage = 'Error: No snap.yaml file path available';
      });
      return;
    }

    // Validate the snap name
    final validationResult = SnapNameValidator.validate(newName);
    if (!validationResult.isValid) {
      setState(() {
        statusMessage = 'Invalid snap name: ${validationResult.errorMessage}';
      });

      // Reset the text field to original value when validation fails
      _snapNameFieldState?.resetToOriginal();
      return;
    }

    try {
      final file = File(snapPath);
      final content = await file.readAsString();

      // Use yaml_edit to update just the name key, preserving the rest of the
      // file (including formatting and any unknown keys).
      final yamlEditor = YamlEditor(content);
      yamlEditor.update(['name'], newName);
      final newYamlString = yamlEditor.toString();

      await file.writeAsString(newYamlString);

      setState(() {
        snapName = newName;
        statusMessage = 'Snap name saved successfully';
      });
    } catch (e) {
      setState(() {
        statusMessage = 'Error saving snap name: $e';
      });
    }
  }
  //  New function to pack a snap package
  Future<void> _packSnap() async {
    final gadgetYamlPath = gadgetFilePath;
    if (gadgetYamlPath == null) {
      setState(() {
        statusMessage = 'No gadget file loaded. Please load a snap first.';
      });
      return;
    }

    try {
      setState(() {
        statusMessage = 'Select directory to save packed snap...';
      });

      // Show directory selection dialog to let user choose where to save the packed snap
      final directory = await getDirectoryPath();

      if (directory == null) {
        setState(() {
          statusMessage = 'Pack snap cancelled by user.';
        });
        return;
      }

      setState(() {
        statusMessage = 'Packing snap...';
      });

      final result = await _packService.packSnap(gadgetYamlPath, directory);

      setState(() {
        statusMessage = result.snapFileName != null
            ? 'Snap packed successfully to ${result.targetDirectory}/${result.snapFileName}'
            : 'Snap packed successfully to ${result.targetDirectory}';
      });
    } catch (e) {
      final message = _serviceErrorMessage(e);
      setState(() {
        statusMessage = 'Error packing snap: $message';
      });
    }
  }
  /// / Extracts a user-facing message from a service failure. The service
  /// exceptions all carry one; anything else is stringified.
  String _serviceErrorMessage(Object e) {
    switch (e) {
      case StoreException():
        return e.message;
      case SnapFileException():
        return e.message;
      case SnapPackException():
        return e.message;
      default:
        return e.toString();
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
                            // Only set snapName from the actual snap.yaml content when downloading
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
                      if (availableChannels.isNotEmpty)
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
                                  isDownloading: isDownloading,
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
                                    // Show local snap info (a Card so the
                                    // ListTile's ink has a Material to paint on).
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
                                            if (snapVersion != null)
                                              Text('Version: $snapVersion'),
                                            if (snapArchitectures.isNotEmpty)
                                              Text(
                                                'Architecture: ${snapArchitectures.join(' / ')}',
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
                          Row(
                            children: [
                              // Caption with bold font and same size as name
                              SizedBox(
                                width: 100,
                                child: Text(
                                  'Snap Name:',
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16, // Same size as name
                                  ),
                                ),
                              ),
                              Flexible(
                                child: EditableTextField(
                                  text: snapName ?? 'Unknown',
                                  onSave: (newName) {
                                    // Save to file when the user clicks save
                                    _saveSnapNameToFile(newName);
                                  },
                                  style: const TextStyle(fontSize: 16),
                                  onStateCreated: (state) {
                                    // Capture the state reference for later use
                                    _snapNameFieldState = state;
                                  },
                                ),
                              ),
                              // Which architecture the loaded snap targets.
                              if (snapArchitectures.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: ArchBadge(
                                      architectures: snapArchitectures),
                                ),
                            ],
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
                              filePath: gadgetFilePath,
                              onContentChanged: (newContent) {
                                // When content changes, update the state
                                setState(() {
                                  gadgetContent = newContent;
                                });
                              },
                              onStatusUpdate: (message) {
                                setState(() {
                                  statusMessage = message;
                                });
                              },
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
            onActionPressed: _packSnap,
          ),
        ],
      ),
    );
  }
}