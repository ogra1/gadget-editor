import 'dart:io';
import 'package:yaml/yaml.dart';
// Removed unused import: import 'package:path/path.dart' as path;

class FileService {
  static Future<Map<String, dynamic>?> loadLocalGadgetSnap(String filePath) async {
    try {
      // Check if file exists
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }
      
      // Extract snap using Process - use temp directory for consistency
      final extractPath = '${filePath}_extracted';
      
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
        return null;
      }
      
      // Find gadget.yaml
      final gadgetPath = '$extractPath/meta/gadget.yaml';
      final gadgetFile = File(gadgetPath);
      if (!await gadgetFile.exists()) {
        return null;
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
        return null;
      }
      
      return parsedData;
    } catch (e) {
      return null;
    }
  }
}
