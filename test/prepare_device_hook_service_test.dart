import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:gadget_editor/services/prepare_device_hook_service.dart';

void main() {
  late Directory tempDir;
  final service = PrepareDeviceHookService();

  /// A minimal unpacked-snap layout: <temp>/meta/snap.yaml.
  File makeSnapYaml() {
    final meta = Directory('${tempDir.path}/meta');
    meta.createSync(recursive: true);
    final f = File('${meta.path}/snap.yaml');
    f.writeAsStringSync('name: pc\nversion: 1\ntype: gadget\n');
    return f;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pd_hook_test.');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('scriptPathFor', () {
    test('is the hooks/prepare-device sibling of snap.yaml (inside meta/)', () {
      final snap = makeSnapYaml();
      expect(
        service.scriptPathFor(snap.path),
        p.join(tempDir.path, 'meta', 'hooks', 'prepare-device'),
      );
    });
  });

  group('ensureScript (no existing hook)', () {
    test('creates the meta/hooks directory and the script', () {
      final snap = makeSnapYaml();
      final hookPath = service.ensureScript(snap.path);
      final hook = File(hookPath);
      expect(hook.existsSync(), isTrue);
      expect(
          hook.path, p.join(tempDir.path, 'meta', 'hooks', 'prepare-device'));
    });

    test('writes the canonical script verbatim (shebang first; \$ and " kept)',
        () {
      final snap = makeSnapYaml();
      final hook = File(service.ensureScript(snap.path));
      final content = hook.readAsStringSync();
      expect(content, PrepareDeviceHookService.script);
      // The exact lines that would break under interpolation/escaping.
      expect(content.split('\n').first, '#! /bin/sh');
      expect(content, contains(r'$(date -u)'));
      expect(content, contains(r'$SNAP_COMMON'));
      expect(content, contains(r'\"api-key\"'));
      expect(content, contains(r'\"$MODEL_APIKEY\"'));
    });

    test('makes the script executable (owner/group/other x bits)', () {
      final snap = makeSnapYaml();
      final hook = File(service.ensureScript(snap.path));
      // chmod 755 => r-xr-xr-x; assert every execute bit is set. Dart has no
      // octal literal, so the owner/group/other execute mask (0o111 == 73)
      // is written as 0x49.
      const execMask = 0x49;
      expect(hook.statSync().mode & execMask, execMask);
    });
  });

  group('ensureScript (existing hook)', () {
    test('never overwrites an existing hook', () {
      final snap = makeSnapYaml();
      final hookPath = service.scriptPathFor(snap.path);
      const existing = '#!/bin/sh\necho "custom hook"\n';
      final hook = File(hookPath);
      hook.parent.createSync(recursive: true);
      hook.writeAsStringSync(existing);

      final returned = service.ensureScript(snap.path);

      expect(returned, hookPath);
      expect(hook.readAsStringSync(), existing);
      expect(hook.readAsStringSync(), isNot(PrepareDeviceHookService.script));
    });

    test('is idempotent: a second call leaves the file untouched', () {
      final snap = makeSnapYaml();
      final first = service.ensureScript(snap.path);
      final hook = File(first);
      final mtimeBefore = hook.statSync().modified;

      final second = service.ensureScript(snap.path);

      expect(second, first);
      expect(hook.readAsStringSync(), PrepareDeviceHookService.script);
      expect(hook.statSync().modified, mtimeBefore);
    });
  });

  group('exists', () {
    test('is false before creation and true after', () {
      final snap = makeSnapYaml();
      expect(service.exists(snap.path), isFalse);
      service.ensureScript(snap.path);
      expect(service.exists(snap.path), isTrue);
    });
  });
}
