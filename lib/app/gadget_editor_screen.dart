import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:file_selector/file_selector.dart';
import 'package:flutter_window_close/flutter_window_close.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'widgets/status_bar.dart';
import 'widgets/gadget_sidebar.dart';
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
  // Services are injected so the screen can be widget-tested with real
  // (or faked) backends. main.dart constructs the production instances.
  final SnapStoreService storeService;
  final SnapFileService fileService;
  final SnapPackService packService;

  const GadgetEditorScreen({
    super.key,
    required this.storeService,
    required this.fileService,
    required this.packService,
  });

  @override
  State<GadgetEditorScreen> createState() => GadgetEditorScreenState();
}

// Public (not underscore-prefixed) so widget tests can drive the loaded state
// (e.g. call loadLocalGadgetSnap) and assert on the fields directly.
class GadgetEditorScreenState extends State<GadgetEditorScreen> {
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

  // Reference to the version EditableTextField for reset functionality
  EditableTextFieldState? _snapVersionFieldState;


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
          await widget.storeService.searchGadgetChannels(snapName);

      setState(() {
        availableChannels = channels;
        statusMessage = 'Found ${availableChannels.length} available channels';
      });
    } catch (e) {
      final message = _serviceErrorMessage(e);
      setState(() {
        error = message;
        statusMessage = 'Error: $error';
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
          await widget.fileService.extractSnap(filePath, extractPath);

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
        final extracted = await widget.fileService.readExtracted(extractPath);
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
      final snapFile = await widget.storeService.downloadSnapFile(channel, path.dirname(filePath));
      final extracted =
          await widget.fileService.extractSnap(snapFile.path, extractPath);

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
        final extracted = await widget.fileService.readExtracted(extractPath);
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
  // Synchronous on purpose (like GadgetYaml.save()): the metadata files are tiny, and sync I/O keeps the save deterministic under widget tests (no pending async tasks to settle).
  void _saveSnapNameToFile(String newName) {
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
      final content = file.readAsStringSync();

      // Use yaml_edit to update just the name key, preserving the rest of the
      // file (including formatting and any unknown keys).
      final yamlEditor = YamlEditor(content);
      yamlEditor.update(['name'], newName);
      final newYamlString = yamlEditor.toString();

      file.writeAsStringSync(newYamlString);

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
  //  Save an edited snap version into meta/snap.yaml (inserting the key if
  //  it is absent). Mirrors [_saveSnapNameToFile].
  void _saveSnapVersionToFile(String newVersion) {
    final snapPath = snapFilePath;
    if (snapPath == null) {
      setState(() {
        statusMessage = 'Error: No snap.yaml file path available';
      });
      return;
    }

    final trimmed = newVersion.trim();
    if (trimmed.isEmpty || trimmed.contains('\n') || trimmed.contains('\r')) {
      setState(() {
        statusMessage = 'Invalid version: must be a non-empty single line';
      });
      _snapVersionFieldState?.resetToOriginal();
      return;
    }

    try {
      final file = File(snapPath);
      final content = file.readAsStringSync();

      // Use yaml_edit to update just the version key, preserving the rest of
      // the file (including formatting and any unknown keys). yaml_edit
      // inserts the key at the end when it is absent.
      final yamlEditor = YamlEditor(content);
      yamlEditor.update(['version'], trimmed);
      final newYamlString = yamlEditor.toString();

      file.writeAsStringSync(newYamlString);

      setState(() {
        snapVersion = trimmed;
        statusMessage = 'Version saved successfully';
      });
    } catch (e) {
      setState(() {
        statusMessage = 'Error saving version: $e';
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

      final result = await widget.packService.packSnap(gadgetYamlPath, directory);

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
          // Main content area: fixed sidebar + editor pane.
          Expanded(
            child: Row(
              children: [
                GadgetEditorSidebar(
                  searchController: _searchController,
                  onSearchSubmitted: (value) {
                    if (value.isNotEmpty) {
                      // Only set snapName from the actual snap.yaml content when downloading
                      fetchSnapChannels(value);
                    }
                  },
                  onLocalSnapPicked: () async {
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
                  availableChannels: availableChannels,
                  selectedChannel: selectedChannel,
                  isDownloading: isDownloading,
                  onChannelSelected: downloadSelectedChannel,
                  isLocalMode: isLocalMode,
                  hasGadgetData: gadgetData != null,
                  snapName: snapName,
                  snapVersion: snapVersion,
                  snapArchitectures: snapArchitectures,
                  onLocalSnapReload: reloadLocalSnap,
                ),
                // The editor pane takes the remaining width (the sidebar is a
                // fixed 300px). Without Expanded the pane would get an
                // unbounded width and the header row's Flexible children
                // would overflow.
                Expanded(child: _buildMainContent(context)),
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

  /// The right-hand editor pane: the snap header row (name, version,
  /// architecture) followed by the gadget content, or a placeholder when
  /// nothing is loaded.
  Widget _buildMainContent(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (gadgetData != null)
            _buildHeaderRow(context)
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
                snapFilePath: snapFilePath,
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
    );
  }

  /// The editable snap header row: name, version, and architecture badge.
  Widget _buildHeaderRow(BuildContext context) {
    return Row(
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
            // Key so widget tests can target the name
            // field specifically (there are two such
            // fields in the header).
            key: const ValueKey('snap-name-field'),
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
        // Editable snap version (between name and arch).
        const SizedBox(width: 16),
        Text(
          'Version:',
          style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 130,
          child: EditableTextField(
            key: const ValueKey('snap-version-field'),
            text: snapVersion ?? '',
            onSave: (newVersion) {
              _saveSnapVersionToFile(newVersion);
            },
            style: const TextStyle(fontSize: 16),
            onStateCreated: (state) {
              _snapVersionFieldState = state;
            },
          ),
        ),
        // Which architecture the loaded snap targets.
        if (snapArchitectures.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: ArchBadge(architectures: snapArchitectures),
          ),
      ],
    );
  }
}