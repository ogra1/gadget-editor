import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

class YamlSerializer {
  /// Converts a Map to YAML string using yaml_writer for better reliability
  static String serialize(Map<String, dynamic> data) {
    try {
      // Use yaml_writer for serialization which handles complex structures better
      return YamlWriter().write(data);
    } catch (e) {
      // Fallback to manual serialization if yaml_writer fails
      return _manualSerialize(data);
    }
  }

  /// Manual fallback serialization for complex nested structures
  static String _manualSerialize(Map<String, dynamic> map, {int indent = 0}) {
    final StringBuffer buffer = StringBuffer();
    final indentStr = '  ' * indent;
    
    // Sort keys to ensure consistent output
    final sortedKeys = map.keys.toList()..sort();
    
    for (var key in sortedKeys) {
      final value = map[key];
      
      if (value is Map<String, dynamic>) {
        buffer.write('$indentStr$key:\n');
        buffer.write(_manualSerialize(value, indent: indent + 1));
      } else if (value is List) {
        buffer.write('$indentStr$key:\n');
        for (var item in value) {
          if (item is Map<String, dynamic>) {
            buffer.write('$indentStr  - \n');
            buffer.write(_manualSerialize(item, indent: indent + 2));
          } else {
            buffer.write('$indentStr  - $item\n');
          }
        }
      } else if (value is String && value.contains('\n')) {
        // Handle multiline strings properly
        buffer.write('$indentStr$key: |\n');
        final lines = value.split('\n');
        for (var line in lines) {
          buffer.write('$indentStr    $line\n');
        }
      } else {
        buffer.write('$indentStr$key: $value\n');
      }
    }
    
    return buffer.toString();
  }
}
