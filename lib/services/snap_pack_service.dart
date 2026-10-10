import 'dart:io';
import 'package:path/path.dart' as path;

/// Result of a successful snap pack.
class SnapPackResult {
  SnapPackResult({required this.targetDirectory, this.snapFileName});

  /// Directory the .snap file was written into.
  final String targetDirectory;

  /// Name of the produced .snap file, when the tool printed it.
  final String? snapFileName;
}

/// Exception thrown when the snap pack step fails.
class SnapPackException implements Exception {
  SnapPackException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Invokes the `snap_pack` helper to repack an unpacked snap directory into
/// a fresh .snap file.
///
/// The path to the tool can be injected; by default it is derived from the
/// `SNAP` environment variable (`$SNAP/bin/snap_pack`).
class SnapPackService {
  SnapPackService({String? snapPackPath})
      : _snapPackPath = snapPackPath ?? _defaultSnapPackPath();

  static String? _defaultSnapPackPath() {
    final snapVar = Platform.environment['SNAP'];
    if (snapVar == null || snapVar.isEmpty) {
      return null;
    }
    return path.join(snapVar, 'bin', 'snap_pack');
  }

  final String? _snapPackPath;

  /// Packs the unpacked snap whose `meta/gadget.yaml` is at
  /// [gadgetYamlPath] into [targetDirectory].
  ///
  /// Callers pass the `meta/gadget.yaml` file path (as produced by
  /// [SnapFileService]); this service derives the snap root directory —
  /// the directory that *contains* `meta/` — because that is the layout
  /// `snap_pack` expects.
  Future<SnapPackResult> packSnap(
      String gadgetYamlPath, String targetDirectory) async {
    final snapPackPath = _snapPackPath;
    if (snapPackPath == null || !await File(snapPackPath).exists()) {
      throw SnapPackException(
          'snap_pack tool not found at ${snapPackPath ?? '(SNAP env not set)'}');
    }

    if (path.basename(gadgetYamlPath) != 'gadget.yaml' ||
        !await File(gadgetYamlPath).exists()) {
      throw SnapPackException(
          'gadget.yaml not found at $gadgetYamlPath '
          '(expected the unpacked snap\'s meta/gadget.yaml)');
    }

    // snap_pack expects the directory that *contains* meta/:
    // <root>/meta/gadget.yaml -> <root>
    final sourceDir = path.dirname(path.dirname(gadgetYamlPath));

    final process = await Process.run(
      snapPackPath,
      [sourceDir, targetDirectory],
      runInShell: true,
    );
    if (process.exitCode != 0) {
      // The real snap_pack tool prints its errors to stdout; include both
      // streams so the user actually sees why the pack failed.
      final stdoutText = process.stdout.toString().trim();
      final stderrText = process.stderr.toString().trim();
      final detail =
          [stdoutText, stderrText].where((t) => t.isNotEmpty).join(' | ');
      throw SnapPackException(
          'Error packing snap: ${detail.isEmpty ? 'unknown error' : detail}');
    }

    // Extract the snap file name from the tool output (if available).
    String? snapFileName;
    for (final line in process.stdout.toString().split('\n')) {
      if (line.contains('.snap')) {
        final parts = line.split('/');
        if (parts.isNotEmpty) {
          snapFileName = parts.last.trim();
          break;
        }
      }
    }

    return SnapPackResult(
        targetDirectory: targetDirectory, snapFileName: snapFileName);
  }
}
