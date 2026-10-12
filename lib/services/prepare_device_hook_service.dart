import 'dart:io';

import 'package:path/path.dart' as p;

/// Thrown when the prepare-device hook script cannot be created.
class PrepareDeviceHookException implements Exception {
  PrepareDeviceHookException(this.message);

  final String message;

  @override
  String toString() => 'PrepareDeviceHookException: $message';
}

/// Manages the `meta/hooks/prepare-device` hook script of an unpacked gadget
/// snap.
///
/// The hook is what actually consumes the store API key: on first boot of an
/// Ubuntu Core system snapd runs it and injects `MODEL_APIKEY` from
/// `snap.yaml`'s `hooks.prepare-device.environment`. The script itself is
/// **static** — it reads the key from its environment, so the key value is
/// never written into the script.
///
/// [ensureScript] is idempotent and never clobbers: an existing
/// `prepare-device` hook is left exactly as-is.
class PrepareDeviceHookService {
  /// The canonical prepare-device hook script.
  ///
  /// Written as a raw string so the `\"` and `$` sequences survive verbatim.
  /// The first line must remain the shebang.
  static const String script = r'''#! /bin/sh
set -eu

if [ -z "$MODEL_APIKEY" ] ; then
    exit 0
fi

exec >> $SNAP_COMMON/prepare-device-hook.log 2>&1

# If you are forking and building your own gadget:
# implement your preferred way of generating a serial number for this device here
snapctl set registration.proposed-serial="\"$(date -u)\""
snapctl set device-service.url="https://serial-vault-partners.canonical.com/v1/"
snapctl set device-service.headers="{\"api-key\": \"$MODEL_APIKEY\"}"
''';

  /// Path of the `prepare-device` hook for the snap whose `meta/snap.yaml` is
  /// [snapYamlPath]: `<dir of snapYamlPath>/hooks/prepare-device`.
  String scriptPathFor(String snapYamlPath) {
    final metaDir = p.dirname(snapYamlPath); // .../meta
    return p.join(metaDir, 'hooks', 'prepare-device');
  }

  /// Whether a prepare-device hook already exists for [snapYamlPath].
  bool exists(String snapYamlPath) =>
      File(scriptPathFor(snapYamlPath)).existsSync();

  /// Ensures an executable `prepare-device` hook exists for the unpacked snap
  /// whose `meta/snap.yaml` is [snapYamlPath].
  ///
  /// - If a hook already exists it is returned **untouched** (never
  ///   overwritten).
  /// - Otherwise [script] is written and `chmod 755` is applied.
  ///
  /// Returns the absolute path of the hook. Throws
  /// [PrepareDeviceHookException] if the directory cannot be created or the
  /// file cannot be made executable.
  String ensureScript(String snapYamlPath) {
    final scriptPath = scriptPathFor(snapYamlPath);
    final file = File(scriptPath);

    // Never overwrite an existing hook.
    if (file.existsSync()) {
      return scriptPath;
    }

    final dir = file.parent;
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (e) {
        throw PrepareDeviceHookException('cannot create ${dir.path}: $e');
      }
    }

    try {
      file.writeAsStringSync(script);
    } catch (e) {
      throw PrepareDeviceHookException('cannot write $scriptPath: $e');
    }

    _makeExecutable(file);
    return scriptPath;
  }

  /// Sets the owner execute bit on [file] via `chmod`. `dart:io` has no
  /// portable "chmod" API, and this codebase already shells out to the snap
  /// tooling, so `chmod 755` is the consistent choice.
  void _makeExecutable(File file) {
    final result = Process.runSync('chmod', ['755', file.path]);
    if (result.exitCode != 0) {
      throw PrepareDeviceHookException(
          'chmod failed for ${file.path}: ${result.stderr}');
    }
  }
}
