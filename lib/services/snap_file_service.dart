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

  /// Whether [channel] (a store channel map) targets the amd64
  /// architecture.
  static bool isAmd64Arch(Map<String, dynamic> channel) {
    final channelInfo = channel['channel'];
    final architecture =
        channelInfo is Map ? channelInfo['architecture'] : null;
    return architecture?.toString().toLowerCase() == 'amd64';
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
    final snapData = loadYaml(await File(metaSnapPath).readAsString());
    if (snapData is YamlMap && snapData.containsKey('name')) {
      snapNameFromYaml = snapData['name'] as String;
    }

    return ExtractedGadget(
      extractPath: extractPath,
      gadgetPath: gadgetPath,
      snapPath: metaSnapPath,
      content: content,
      data: data,
      snapNameFromYaml: snapNameFromYaml,
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
    final metaSnapPath = '$extractPath/meta/snap.yaml';
    if (await File(metaSnapPath).exists()) {
      snapPath = metaSnapPath;
      final snapData = loadYaml(await File(metaSnapPath).readAsString());
      if (snapData is YamlMap && snapData.containsKey('name')) {
        snapNameFromYaml = snapData['name'] as String;
      }
    }

    return ExtractedGadget(
      extractPath: extractPath,
      gadgetPath: gadgetPath,
      snapPath: snapPath,
      content: content,
      data: data,
      snapNameFromYaml: snapNameFromYaml,
    );
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
