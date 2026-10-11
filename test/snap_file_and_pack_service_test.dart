import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gadget_editor/services/snap_file_service.dart';
import 'package:gadget_editor/services/snap_pack_service.dart';

const String _gadgetYaml = '''
volumes:
  pc:
    bootloader: uboot
    structure:
      - name: /boot
        size: 32M
        type: 83,00
defaults:
  core26:
    CORE20_PC_VERSION: 26
''';

const String _snapYaml = '''
name: pc
version: 26.04
type: gadget
base: core26
confinement: strict
summary: Test gadget
description: A test gadget snap for the file service tests.
apps:
  prepare-device:
    command: commands/prepare-device
''';

/// Builds a minimal but valid unpacked snap directory (the shape produced by
/// `unsquashfs`), returning its path.
Future<String> _makeUnpackedSnap(Directory parent) async {
  final snapDir = await Directory('${parent.path}/unpacked').create();
  await Directory('${snapDir.path}/meta').create();
  await File('${snapDir.path}/meta/gadget.yaml').writeAsString(_gadgetYaml);
  await File('${snapDir.path}/meta/snap.yaml').writeAsString(_snapYaml);
  return snapDir.path;
}

/// Builds a real .snap (squashfs) containing [gadgetYaml]/[snapYaml],
/// returning the file path. Requires squashfs-tools on the host.
Future<String> _makeRealSnap(Directory parent) async {
  final src = await Directory('${parent.path}/src').create();
  await Directory('${src.path}/meta').create();
  await File('${src.path}/meta/gadget.yaml').writeAsString(_gadgetYaml);
  await File('${src.path}/meta/snap.yaml').writeAsString(_snapYaml);
  final snapPath = '${parent.path}/test.snap';
  final result = await Process.run('mksquashfs', [
    src.path,
    snapPath,
    '-noappend',
    '-quiet',
    '-no-progress',
  ]);
  if (result.exitCode != 0) {
    fail('mksquashfs failed: ${result.stderr}');
  }
  return snapPath;
}

/// A snap_pack stand-in that behaves like the real tool for the cases the
/// service cares about: validates its arguments, writes <target>/name.snap
/// and prints "Output file: <path>".
String _fakePackScript(Directory dir) {
  final script = '${dir.path}/fake_snap_pack';
  File(script).writeAsStringSync('''
#!/usr/bin/env bash
[ "\$#" -eq 2 ] || { echo "usage: fake_snap_pack <source> <target>" >&2; exit 2; }
[ -f "\$1/meta/snap.yaml" ] || { echo "meta/snap.yaml missing in \$1" >&2; exit 3; }
[ -d "\$2" ] || { echo "target directory missing: \$2" >&2; exit 4; }
out="\$2/pc_26_amd64.snap"
touch "\$out"
echo "Package name: pc"
echo "Output file: \$out"
exit 0
''');
  Process.runSync('chmod', ['+x', script]);
  return script;
}

/// A snap_pack stand-in that always fails with a stderr message.
String _failingPackScript(Directory dir) {
  final script = '${dir.path}/failing_snap_pack';
  File(script).writeAsStringSync(
      '#!/usr/bin/env bash\necho "boom: cannot create squashfs" >&2\nexit 1\n');
  Process.runSync('chmod', ['+x', script]);
  return script;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('snap_file_test_');
  });

  tearDown(() async {
    if (await Directory(tmp.path).exists()) {
      await Directory(tmp.path).delete(recursive: true);
    }
  });

  group('SnapFileService.extractSnap', () {
    test('extracts a real snap and parses metadata', () async {
      final snap = await _makeRealSnap(tmp);
      final service = SnapFileService();

      final extracted =
          await service.extractSnap(snap, '${tmp.path}/out');

      expect(extracted.extractPath, '${tmp.path}/out');
      expect(extracted.gadgetPath, '${tmp.path}/out/meta/gadget.yaml');
      expect(extracted.snapPath, '${tmp.path}/out/meta/snap.yaml');
      expect(extracted.snapNameFromYaml, 'pc');
      expect(extracted.data['volumes'], isA<Map>());
      expect(extracted.data['volumes']['pc']['bootloader'], 'uboot');
      expect(extracted.content, contains('bootloader: uboot'));
      expect(await File('${tmp.path}/out/meta/gadget.yaml').exists(), isTrue);
    });

    test('throws when the snap file is missing', () async {
      final service = SnapFileService();
      expect(
        () => service.extractSnap('${tmp.path}/nope.snap', '${tmp.path}/out'),
        throwsA(isA<SnapFileException>()
            .having((e) => e.message, 'message', contains('File not found'))),
      );
    });

    test('throws a helpful error for an unextractable file', () async {
      final bogus = File('${tmp.path}/bogus.snap');
      await bogus.writeAsString('this is not a squashfs image');
      final service = SnapFileService();
      expect(
        () => service.extractSnap(bogus.path, '${tmp.path}/out'),
        throwsA(isA<SnapFileException>()
            .having((e) => e.message, 'message', contains('extraction failed'))),
      );
    });
  });

  group('SnapFileService.readExtracted', () {
    test('reads cached metadata including the snap name', () async {
      final snapDir = await _makeUnpackedSnap(tmp);
      final service = SnapFileService();

      final extracted = await service.readExtracted(snapDir);

      expect(extracted.snapNameFromYaml, 'pc');
      expect(extracted.data['defaults']['core26']['CORE20_PC_VERSION'], 26);
      expect(extracted.gadgetPath, '$snapDir/meta/gadget.yaml');
    });

    test('tolerates a missing snap.yaml (falls back to empty name)', () async {
      final snapDir = await _makeUnpackedSnap(tmp);
      await File('$snapDir/meta/snap.yaml').delete();
      final service = SnapFileService();

      final extracted = await service.readExtracted(snapDir);

      expect(extracted.snapNameFromYaml, '');
      expect(extracted.snapPath, isNull);
      expect(extracted.data['volumes'], isA<Map>());
    });

    test('throws when gadget.yaml is missing', () async {
      final emptyDir = await Directory('${tmp.path}/empty').create();
      final service = SnapFileService();
      expect(
        () => service.readExtracted(emptyDir.path),
        throwsA(isA<SnapFileException>()
            .having((e) => e.message, 'message', contains('gadget.yaml'))),
      );
    });
  });

  group('SnapFileService.extractPathFor', () {
    test('keys the path by track and risk when available', () {
      expect(
        SnapFileService.extractPathFor('/tmp/a.snap',
            track: '26', risk: 'stable'),
        '/tmp/a.snap_extracted_26_stable',
      );
    });

    test('falls back to the plain suffix without track/risk', () {
      expect(SnapFileService.extractPathFor('/tmp/a.snap'),
          '/tmp/a.snap_extracted');
    });
  });

  group('ExtractedGadget.architectures (meta/snap.yaml)', () {
    /// Writes an unpacked snap dir whose snap.yaml carries [archYaml].
    Future<String> unpackedWithArch(Directory parent, String archYaml) async {
      final snapDir = await Directory('${parent.path}/unpacked').create();
      await Directory('${snapDir.path}/meta').create();
      await File('${snapDir.path}/meta/gadget.yaml').writeAsString(_gadgetYaml);
      await File('${snapDir.path}/meta/snap.yaml')
          .writeAsString('name: pc\n$archYaml\n');
      return snapDir.path;
    }

    test('parses the list form of architectures', () async {
      final dir = await Directory.systemTemp.createTemp('arch_test.');
      final snapDir =
          await unpackedWithArch(dir, 'architectures: [amd64, arm64]');
      final extracted = await SnapFileService().readExtracted(snapDir);
      expect(extracted.architectures, ['amd64', 'arm64']);
    });

    test('parses the block form of architectures', () async {
      final dir = await Directory.systemTemp.createTemp('arch_test.');
      final snapDir = await unpackedWithArch(
          dir, 'architectures:\n  - amd64\n  - arm64');
      final extracted = await SnapFileService().readExtracted(snapDir);
      expect(extracted.architectures, ['amd64', 'arm64']);
    });

    test('parses the all-architecture wildcard', () async {
      final dir = await Directory.systemTemp.createTemp('arch_test.');
      final snapDir = await unpackedWithArch(dir, 'architectures: all');
      final extracted = await SnapFileService().readExtracted(snapDir);
      expect(extracted.architectures, ['all']);
    });

    test('is empty when the field is missing', () async {
      final dir = await Directory.systemTemp.createTemp('arch_test.');
      final snapDir = await unpackedWithArch(dir, 'version: 1.0');
      final extracted = await SnapFileService().readExtracted(snapDir);
      expect(extracted.architectures, isEmpty);
    });

    test('extractSnap surfaces architectures from a real snap file', () async {
      final dir = await Directory.systemTemp.createTemp('arch_test.');
      final snapPath = await _makeRealSnap(dir);
      final extracted =
          await SnapFileService().extractSnap(snapPath, '${dir.path}/out');
      // _snapYaml carries no architectures field, so the list must be empty
      // while the name is still surfaced.
      expect(extracted.architectures, isEmpty);
      expect(extracted.snapNameFromYaml, 'pc');
    });
  });

  group('SnapPackService.packSnap', () {
    test('packs an unpacked snap directory into the target', () async {
      final snapDir = await _makeUnpackedSnap(tmp);
      final target = await Directory('${tmp.path}/out').create();
      final service = SnapPackService(snapPackPath: _fakePackScript(tmp));

      final result =
          await service.packSnap('$snapDir/meta/gadget.yaml', target.path);

      expect(result.targetDirectory, target.path);
      expect(result.snapFileName, 'pc_26_amd64.snap');
      expect(await File('${target.path}/pc_26_amd64.snap').exists(), isTrue);
    });

    test('throws SnapPackException when the tool is missing', () async {
      final snapDir = await _makeUnpackedSnap(tmp);
      final service = SnapPackService(snapPackPath: '${tmp.path}/absent');
      expect(
        () => service.packSnap('$snapDir/meta/gadget.yaml', tmp.path),
        throwsA(isA<SnapPackException>()
            .having((e) => e.message, 'message', contains('not found'))),
      );
    });

    test('throws SnapPackException with stderr when the tool fails', () async {
      final snapDir = await _makeUnpackedSnap(tmp);
      final target = await Directory('${tmp.path}/out').create();
      final service =
          SnapPackService(snapPackPath: _failingPackScript(tmp));
      expect(
        () => service.packSnap('$snapDir/meta/gadget.yaml', target.path),
        throwsA(isA<SnapPackException>()
            .having((e) => e.message, 'message', contains('boom'))),
      );
    });
    test('passes the snap ROOT directory (not meta/) to the tool', () async {
      final snapDir = await _makeUnpackedSnap(tmp);
      final seen = await File('${tmp.path}/seen_args').create();
      final script = '${tmp.path}/recording_pack';
      final scriptPath = seen.path;
      File(script).writeAsStringSync(
          '#!/usr/bin/env bash\necho "\$1" > "$scriptPath"\necho "Output file: /x/pc_26_amd64.snap"\nexit 0\n');
      Process.runSync('chmod', ['+x', script]);
      final target = await Directory('${tmp.path}/out').create();

      await SnapPackService(snapPackPath: script)
          .packSnap('$snapDir/meta/gadget.yaml', target.path);

      // Regression: the tool must receive <root>, the directory that
      // contains meta/ — not meta/ itself (double dirname of the file).
      expect(await seen.readAsString(), '$snapDir\n');
    });

    test("reports the tool's stdout message when the tool fails there",
        () async {
      final snapDir = await _makeUnpackedSnap(tmp);
      // Like the real snap_pack: prints the error to stdout, exits 1.
      final script = '${tmp.path}/stdout_failing_pack';
      File(script).writeAsStringSync(
          '#!/usr/bin/env bash\necho "Error creating snap package: Required meta/snap.yaml file not found in snap directory"\nexit 1\n');
      Process.runSync('chmod', ['+x', script]);
      final target = await Directory('${tmp.path}/out').create();
      final service = SnapPackService(snapPackPath: script);

      SnapPackException? err;
      try {
        await service.packSnap('$snapDir/meta/gadget.yaml', target.path);
      } on SnapPackException catch (e) {
        err = e;
      }
      // Regression: stderr-only error messages produced a bare
      // "Error packing snap" in the UI because the real tool writes to
      // stdout.
      expect(err, isNotNull);
      expect(err!.message, contains('Required meta/snap.yaml file not found'));
    });

    test('rejects a path that is not a meta/gadget.yaml file', () async {
      final snapDir = await _makeUnpackedSnap(tmp);
      final target = await Directory('${tmp.path}/out').create();
      final service = SnapPackService(snapPackPath: _fakePackScript(tmp));

      // Handing the meta/ directory (the old bug) must fail clearly
      // instead of packing the wrong root.
      SnapPackException? err;
      try {
        await service.packSnap('$snapDir/meta', target.path);
      } on SnapPackException catch (e) {
        err = e;
      }
      expect(err, isNotNull);
      expect(err!.message, contains('gadget.yaml not found'));

      SnapPackException? missing;
      try {
        await service.packSnap('$snapDir/meta/nope.yaml', target.path);
      } on SnapPackException catch (e) {
        missing = e;
      }
      expect(missing, isNotNull);
      expect(missing!.message, contains('gadget.yaml not found'));
    });
  });
}
