import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;
import 'package:file_selector/file_selector.dart';
import 'package:flutter_window_close/flutter_window_close.dart';
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
import 'widgets/editable_text_field.dart'; // Import the new widget';
import 'package:yaml_edit/yaml_edit.dart'; // Import yaml_edit package
import 'utils/snap_name_validator.dart'; // Import the validation utility

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
  // Store the file path for saving changes
  String? gadgetFilePath;
  // Store the snap.yaml file path for saving snap name
  String? snapFilePath;

  // Editing state for snap name
  bool _isEditingSnapName = false;
  final TextEditingController _snapNameController = TextEditingController();

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
      print('created tempdir: $appDir.path'); 
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

      print('in cleanup function: $tempDir'); 

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

      // Find snap.yaml
      final snapPath = '$extractPath/meta/snap.yaml';
      final snapFileForReading = File(snapPath);
      if (!await snapFileForReading.exists()) {
        throw Exception('snap.yaml not found in snap');
      }

      // Read and parse gadget.yaml
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

      // Read snap.yaml to get the actual snap name
      final snapContent = await snapFileForReading.readAsString();
      final snapData = loadYaml(snapContent);
      String snapNameFromSnapYaml = '';
      if (snapData is YamlMap && snapData.containsKey('name')) {
        snapNameFromSnapYaml = snapData['name'] as String;
      }

      // Extract snap name from filename (everything before first underscore) if snap.yaml doesn't have it
      String snapNameFromFileName = fileName;
      final underscoreIndex = fileName.indexOf('_');
      if (underscoreIndex != -1) {
        snapNameFromFileName = fileName.substring(0, underscoreIndex);
      }

      setState(() {
        // Only set snapName from the actual snap.yaml file content
        this.snapName = snapNameFromSnapYaml.isNotEmpty ? snapNameFromSnapYaml : snapNameFromFileName;
        this.gadgetContent = content;
        this.gadgetData = parsedData;
        this.isAmd64Platform = false; // Local snaps are typically not amd64
        loadedLocalSnapPath = filePath; // Store the original path
        gadgetFilePath = gadgetPath; // Store the gadget.yaml file path
        snapFilePath = snapPath; // Store the snap.yaml file path
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
      final fileName = path.basename(channel['download']['url']);
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

            // Extract snap name from snap.yaml if available
            final snapPath = '$uniqueExtractPath/meta/snap.yaml';
            final snapFileForReading = File(snapPath);
            String snapNameFromSnapYaml = '';
            if (await snapFileForReading.exists()) {
              final snapContent = await snapFileForReading.readAsString();
              final snapData = loadYaml(snapContent);
              if (snapData is YamlMap && snapData.containsKey('name')) {
                snapNameFromSnapYaml = snapData['name'] as String;
              }
            }

            // Extract architecture information from the channel
            final architecture = channelInfo['architecture'] as String?;
            // Determine if it's amd64 platform
            bool isAmd64 = architecture?.toLowerCase() == 'amd64';

            setState(() {
              // Only set snapName from the actual snap.yaml file content
              this.snapName = snapNameFromSnapYaml.isNotEmpty ? snapNameFromSnapYaml : snapName;
              this.gadgetContent = content;
              this.gadgetData = parsedData;
              this.selectedChannel = channel;
              this.isAmd64Platform = isAmd64; // Store the platform info
              this.gadgetFilePath = gadgetPath; // Store the gadget.yaml file path
              this.snapFilePath = snapPath; // Store the snap.yaml file path
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

        // Extract snap using Process - make directory name based on filename
        final channelInfo = channel['channel'] as Map<String, dynamic>;
        final track = channelInfo['track'] as String?;
        final risk = channelInfo['risk'] as String?;
        String uniqueExtractPath;

        if (track != null && risk != null) {
          // Create unique directory name based on filename and track/risk
          final baseFileName = path.basename(filePath);
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

        // Find snap.yaml
        final snapPath = '$uniqueExtractPath/meta/snap.yaml';
        final snapFileForReading = File(snapPath);
        if (!await snapFileForReading.exists()) {
          throw Exception('snap.yaml not found in snap');
        }

        // Read snap.yaml to get the actual snap name
        final snapContent = await snapFileForReading.readAsString();
        final snapData = loadYaml(snapContent);
        String snapNameFromSnapYaml = '';
        if (snapData is YamlMap && snapData.containsKey('name')) {
          snapNameFromSnapYaml = snapData['name'] as String;
        }

        // Extract architecture information from the channel
        final architecture = channelInfo['architecture'] as String?;
        // Determine if it's amd64 platform
        bool isAmd64 = architecture?.toLowerCase() == 'amd64';

        setState(() {
          // Only set snapName from the actual snap.yaml file content
          this.snapName = snapNameFromSnapYaml.isNotEmpty ? snapNameFromSnapYaml : snapName;
          this.gadgetContent = content;
          this.gadgetData = parsedData;
          this.selectedChannel = channel;
          this.isAmd64Platform = isAmd64; // Store the platform info
          this.gadgetFilePath = gadgetPath; // Store the gadget.yaml file path
          this.snapFilePath = snapPath; // Store the snap.yaml file path
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

            // Read snap.yaml to get the actual snap name
            final snapPath = '$extractPath/meta/snap.yaml';
            final snapFileForReading = File(snapPath);
            String snapNameFromSnapYaml = '';
            if (await snapFileForReading.exists()) {
              final snapContent = await snapFileForReading.readAsString();
              final snapData = loadYaml(snapContent);
              if (snapData is YamlMap && snapData.containsKey('name')) {
                snapNameFromSnapYaml = snapData['name'] as String;
              }
            }

            setState(() {
              // Only set snapName from the actual snap.yaml file content
              this.snapName = snapNameFromSnapYaml.isNotEmpty ? snapNameFromSnapYaml : 'Local Snap';
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

  // Function to save the edited snap name to the file with validation
  Future<void> _saveSnapNameToFile(String newName) async {
    if (snapFilePath == null) {
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
      return;
    }

    try {
      // Read the existing snap.yaml content
      final file = File(snapFilePath!);
      final content = await file.readAsString();

      // Parse the existing YAML
      final yaml = loadYaml(content);

      // Convert YamlMap to Map<String, dynamic> properly to avoid type errors
      Map<String, dynamic> yamlMap;
      if (yaml is YamlMap) {
        // Properly convert YamlMap to Map<String, dynamic>
        yamlMap = {};
        for (var key in yaml.keys) {
          yamlMap[key.toString()] = yaml[key];
        }
      } else if (yaml is Map<String, dynamic>) {
        yamlMap = yaml;
      } else {
        yamlMap = {};
      }

      // Update the snap name in the YAML structure
      yamlMap['name'] = newName;

      // Use yaml_edit to serialize without adding unnecessary quotes
      final yamlEditor = YamlEditor(content);
      yamlEditor.update(['name'], newName);
      final newYamlString = yamlEditor.toString();

      // Write back to file
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

  // New function to pack a snap package
  Future<void> _packSnap() async {
    // Check if we have a gadget file loaded
	String? snapVar = Platform.environment['SNAP'];

    if (gadgetFilePath == null) {
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

      // Get the directory that contains the gadget.yaml file
      final gadgetDir = path.dirname(gadgetFilePath!);
      
      // The snap_pack tool expects a directory containing meta/ 
      // The gadgetDir points to meta/ directory, so we need to get the parent
      final parentDir = path.dirname(gadgetDir);
      
      // Check if snap_pack exists in bin/
      final snapPackPath = '${snapVar}/bin/snap_pack';
      
      // Check if the snap_pack tool exists
      final snapPackFile = File(snapPackPath);
      if (!await snapPackFile.exists()) {
        setState(() {
          statusMessage = 'Error: snap_pack tool not found at $snapPackPath';
        });
        return;
      }

      // Run the snap_pack command
      final process = await Process.run(
        snapPackPath,
        [parentDir, directory],
        runInShell: true,
      );
      
      if (process.exitCode != 0) {
        setState(() {
          statusMessage = 'Error packing snap: ${process.stderr}';
        });
        return;
      }
      
      // Extract the snap file name from the output (if available)
      String? snapFileName;
      final outputLines = process.stdout.toString().split('\n');
      for (var line in outputLines) {
        if (line.contains('.snap')) {
          final parts = line.split('/');
          if (parts.isNotEmpty) {
            snapFileName = parts.last.trim();
            break;
          }
        }
      }
      
      setState(() {
        statusMessage = snapFileName != null 
            ? 'Snap packed successfully to $directory/$snapFileName'
            : 'Snap packed successfully to $directory';
      });
      
    } catch (e) {
      setState(() {
        statusMessage = 'Error packing snap: $e';
      });
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
                              SizedBox(
                                //width: MediaQuery.of(context).size.width * 0.14, // 20% of available width
                                width: 200,
                                child: EditableTextField(
                                  text: snapName ?? 'Unknown',
                                  onSave: (newName) {
                                    // Save to file when the user clicks save
                                    _saveSnapNameToFile(newName);
                                  },
                                  style: const TextStyle(fontSize: 16),
                                ),
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
                              isAmd64: isAmd64Platform,
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
