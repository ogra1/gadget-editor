import 'dart:io';
import 'package:yaml/yaml.dart';

/// Result of extracting (or reading) a gadget snap: the unpacked directory
/// plus the parsed metadata the UI needs.
class ExtractedGadget {
  ExtractedGadget({
    required this.extractPath,
    required this.gadgetPath,
    required this.content,
    required this.data,
    this.snapPath,
    this.snapNameFromYaml = '',
    this.architectures = const [],
    this.version = '',
  });

  /// Directory containing the `meta/` of the unpacked snap.
  final String extractPath;

  /// Absolute path of `meta/gadget.yaml`.
  final String gadgetPath;

  /// Absolute path of `meta/snap.yaml`, if present.
  final String? snapPath;

  /// Raw text of `meta/gadget.yaml`.
  final String content;

  /// Parsed `meta/gadget.yaml` as a plain map.
  final Map<String, dynamic> data;

  /// The `name` from `meta/snap.yaml` (empty when missing).
  final String snapNameFromYaml;

  /// The `architectures` from `meta/snap.yaml`: the single source of truth
  /// for which architectures this snap targets (`all` means any). Empty when
  /// `meta/snap.yaml` is absent or the field is missing.
  final List<String> architectures;

  /// The `version` from `meta/snap.yaml` (empty when the field is missing).
  final String version;
}

/// Exception thrown when a snap cannot be extracted or its metadata cannot
/// be read.
class SnapFileException implements Exception {
  SnapFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Extracts snap files (squashfs) and reads their `meta/gadget.yaml` /
/// `meta/snap.yaml` metadata.
class SnapFileService {
  /// Deterministic extraction directory for a snap file, keyed by track/risk
  /// so different channels of the same snap never clobber each other.
  static String extractPathFor(
    String snapFilePath, {
    String? track,
    String? risk,
  }) {
    if (track != null && risk != null) {
      return '${snapFilePath}_extracted_${track}_$risk';
    }
    return '${snapFilePath}_extracted';
  }


  /// Unpacks the snap at [snapPath] into [extractPath] (replacing any
  /// previous extraction) and returns the parsed metadata.
  Future<ExtractedGadget> extractSnap(String snapPath, String extractPath) async {
    final snap = File(snapPath);
    if (!await snap.exists()) {
      throw SnapFileException('File not found: $snapPath');
    }

    // Remove an existing extraction first (fixes the overwrite issue).
    final extractDir = Directory(extractPath);
    if (await extractDir.exists()) {
      await extractDir.delete(recursive: true);
    }

    final process = await Process.run(
      'unsquashfs',
      ['-d', extractPath, snapPath],
      runInShell: true,
    );
    if (process.exitCode != 0) {
      throw SnapFileException('Snap extraction failed: ${process.stderr}');
    }

    final gadgetPath = '$extractPath/meta/gadget.yaml';
    if (!await File(gadgetPath).exists()) {
      throw SnapFileException('gadget.yaml not found in snap');
    }

    final metaSnapPath = '$extractPath/meta/snap.yaml';
    if (!await File(metaSnapPath).exists()) {
      throw SnapFileException('snap.yaml not found in snap');
    }

    final content = await File(gadgetPath).readAsString();
    final data = _parseYaml(content);

    String snapNameFromYaml = '';
    final List<String> architectures = [];
    String version = '';
    final snapData = loadYaml(await File(metaSnapPath).readAsString());
    if (snapData is YamlMap) {
      if (snapData.containsKey('name')) {
        snapNameFromYaml = snapData['name'] as String;
      }
      if (snapData.containsKey('version')) {
        version = snapData['version'].toString();
      }
      architectures.addAll(_parseArchitectures(snapData));
    }

    return ExtractedGadget(
      extractPath: extractPath,
      gadgetPath: gadgetPath,
      snapPath: metaSnapPath,
      content: content,
      data: data,
      snapNameFromYaml: snapNameFromYaml,
      architectures: architectures,
      version: version,
    );
  }

  /// Reads the metadata of an already-extracted directory [extractPath]
  /// (the cache path). A missing `meta/snap.yaml` is tolerated here, unlike
  /// in [extractSnap].
  Future<ExtractedGadget> readExtracted(String extractPath) async {
    final gadgetPath = '$extractPath/meta/gadget.yaml';
    if (!await File(gadgetPath).exists()) {
      throw SnapFileException('gadget.yaml not found in $extractPath');
    }

    final content = await File(gadgetPath).readAsString();
    final data = _parseYaml(content);

    String? snapPath;
    String snapNameFromYaml = '';
    final List<String> architectures = [];
    String version = '';
    final metaSnapPath = '$extractPath/meta/snap.yaml';
    if (await File(metaSnapPath).exists()) {
      snapPath = metaSnapPath;
      final snapData = loadYaml(await File(metaSnapPath).readAsString());
      if (snapData is YamlMap) {
        if (snapData.containsKey('name')) {
          snapNameFromYaml = snapData['name'] as String;
        }
        if (snapData.containsKey('version')) {
          version = snapData['version'].toString();
        }
        architectures.addAll(_parseArchitectures(snapData));
      }
    }

    return ExtractedGadget(
      extractPath: extractPath,
      gadgetPath: gadgetPath,
      snapPath: snapPath,
      content: content,
      data: data,
      snapNameFromYaml: snapNameFromYaml,
      architectures: architectures,
      version: version,
    );
  }

  /// Reads the mandatory `architectures` field of a parsed `meta/snap.yaml`
  /// map, tolerating the list form (`architectures: [amd64, arm64]`, block
  /// and flow) as well as the all-architecture wildcard
  /// (`architectures: all`).
  static List<String> _parseArchitectures(Map snapData) {
    final raw = snapData['architectures'];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    if (raw is String && raw.isNotEmpty) {
      return [raw];
    }
    return const [];
  }

  static Map<String, dynamic> _parseYaml(String content) {
    final data = loadYaml(content);
    if (data is YamlMap) {
      return data.cast<String, dynamic>();
    }
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw SnapFileException('Unsupported YAML data type: ${data.runtimeType}');
  }
}
