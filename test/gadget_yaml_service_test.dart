import 'dart:io';

import 'package:gadget_editor/services/gadget_yaml_service.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:test/test.dart';

// A realistic gadget.yaml fixture exercising every section the service
// mutates: name, defaults, connections, kernel-cmdline and volumes.
const fixture = '''
name: pc
defaults:
  core20:
    refresh-motivation: timely
  core22:
    # keep this one
    hold: true
connections:
  - interface: serial
    plug: modem
    slots:
      - modem0
kernel-cmdline:
  allow:
    - console=ttyS0
    - debug
  append:
    - loglevel=4
volumes:
  pc:
    structure:
      - name: mbr
        size: 2M
      - name: root
        size: 10G
''';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gadget_yaml_test.');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeTemp(String name, String content) {
    final file = File('${tempDir.path}/$name');
    file.writeAsStringSync(content);
    return file;
  }

  group('construction', () {
    test('fromContent parses a valid document', () {
      final gadget = GadgetYaml.fromContent(fixture);
      expect(gadget.isFileBacked, isFalse);
      expect(gadget.filePath, isNull);
      expect(gadget.toYaml(), fixture);
    });

    test('fromContent rejects invalid YAML', () {
      expect(
        () => GadgetYaml.fromContent('a: [unclosed'),
        throwsA(isA<GadgetYamlException>()),
      );
    });

    test('fromFile produces a file-backed instance', () {
      final file = writeTemp('gadget.yaml', fixture);
      final gadget = GadgetYaml.fromFile(file.path);
      expect(gadget.isFileBacked, isTrue);
      expect(gadget.filePath, file.path);
      expect(gadget.toYaml(), fixture);
    });

    test('fromFile rejects a missing file', () {
      expect(
        () => GadgetYaml.fromFile('${tempDir.path}/nope.yaml'),
        throwsA(isA<GadgetYamlException>()),
      );
    });

    test('fromFile rejects an invalid YAML file', () {
      final file = writeTemp('bad.yaml', 'a: [unclosed');
      expect(
        () => GadgetYaml.fromFile(file.path),
        throwsA(isA<GadgetYamlException>()),
      );
    });
  });

  group('setSnapName', () {
    test('replaces only the name value, preserving the rest', () {
      final gadget = GadgetYaml.fromContent(fixture);
      gadget.setSnapName('pc-custom');
      expect(
        gadget.toYaml(),
        fixture.replaceFirst('name: pc\n', 'name: pc-custom\n'),
      );
    });

    test('adds the name key when absent', () {
      final gadget = GadgetYaml.fromContent('defaults:\n  core22:\n    hold: true\n');
      gadget.setSnapName('pc');
      final out = gadget.toYaml();
      expect(out, contains('name: pc'));
      expect(out, contains('defaults:'));
    });
  });

  group('removeDefault', () {
    test('removes one entry and prunes the emptied section', () {
      final gadget = GadgetYaml.fromContent('defaults:\n  core20:\n    x: 1\n');
      gadget.removeDefault('core20');
      expect(gadget.toYaml(), '');
    });

    test('removes one entry, keeps the siblings and their comments', () {
      final gadget = GadgetYaml.fromContent(fixture);
      gadget.removeDefault('core20');
      expect(
        gadget.toYaml(),
        '''
name: pc
defaults:
  core22:
    # keep this one
    hold: true
connections:
  - interface: serial
    plug: modem
    slots:
      - modem0
kernel-cmdline:
  allow:
    - console=ttyS0
    - debug
  append:
    - loglevel=4
volumes:
  pc:
    structure:
      - name: mbr
        size: 2M
      - name: root
        size: 10G
''',
      );
    });

    test('throws when defaults is missing', () {
      final gadget = GadgetYaml.fromContent('name: pc\n');
      expect(() => gadget.removeDefault('core20'),
          throwsA(isA<GadgetYamlException>()));
    });

    test('throws when the key is missing', () {
      final gadget = GadgetYaml.fromContent('defaults:\n  core20:\n    x: 1\n');
      expect(() => gadget.removeDefault('core22'),
          throwsA(isA<GadgetYamlException>()));
    });

    test('a failed removal leaves the document untouched', () {
      final gadget = GadgetYaml.fromContent('defaults:\n  core20:\n    x: 1\n');
      expect(() => gadget.removeDefault('nope'),
          throwsA(isA<GadgetYamlException>()));
      expect(gadget.toYaml(), 'defaults:\n  core20:\n    x: 1\n');
    });
  });

  group('setDefault', () {
    test('creates the defaults section and dot-separated nesting on demand', () {
      final gadget = GadgetYaml.fromContent('name: pc\n');
      gadget.setDefault('core20', 'foo.bar.baz', 'x');
      expect(gadget.valueAt(const ['defaults', 'core20', 'foo', 'bar', 'baz']), 'x');
      // A missing top-level section is appended at the end of the document,
      // never re-sorted above the existing keys.
      expect(gadget.toYaml(),
          'name: pc\ndefaults:\n  core20:\n    foo:\n      bar:\n        baz: x\n');
    });

    test('appends a new top-level section after the last section, preserving order', () {
      // name is alphabetically after defaults; the section must still land
      // at the end (the bug this guards: yaml_edit would sort it to the top).
      final gadget = GadgetYaml.fromContent('name: pc\nvolumes:\n  pc:\n    size: 1G\n');
      gadget.setDefault('core20', 'foo', 'bar');
      expect(gadget.toYaml(),
          'name: pc\nvolumes:\n  pc:\n    size: 1G\ndefaults:\n  core20:\n    foo: bar\n');
    });

    test('appends a new key at the end of a nested map too', () {
      final gadget = GadgetYaml.fromContent('volumes:\n  pc:\n    size: 1G\n    structure:\n      - name: root\n        size: 5G\n');
      gadget.update(['volumes', 'pc', 'image'], 'image.raw');
      expect(gadget.toYaml(),
          'volumes:\n  pc:\n    size: 1G\n    structure:\n      - name: root\n        size: 5G\n    image: image.raw\n');
    });

    test('replaces a null-valued key in place without reordering', () {
      final gadget = GadgetYaml.fromContent('a: 1\ndefaults:\nb: 2\n');
      gadget.setDefault('core20', 'x', 'y');
      // defaults keeps its middle position; only its value appears.
      expect(gadget.toYaml(),
          'a: 1\ndefaults:\n  core20:\n    x: y\nb: 2\n');
    });

    test('appends a new section when the last entry has a trailing comment', () {
      final gadget = GadgetYaml.fromContent('name: pc\nvolumes: # disks\n  pc:\n    size: 1G\n');
      gadget.setDefault('core20', 'x', 'y');
      expect(gadget.toYaml(),
          'name: pc\nvolumes: # disks\n  pc:\n    size: 1G\ndefaults:\n  core20:\n    x: y\n');
    });

    test('updates an existing leaf without touching siblings', () {
      final gadget = GadgetYaml.fromContent(fixture);
      gadget.setDefault('core20', 'refresh-motivation', 'eager');
      expect(gadget.valueAt(const ['defaults', 'core20', 'refresh-motivation']), 'eager');
      expect(gadget.valueAt(const ['defaults', 'core22', 'hold']), true);
      expect(gadget.toYaml(),
          fixture.replaceFirst('refresh-motivation: timely', 'refresh-motivation: eager'));
    });

    test('adds a nested key under an existing snap, keeping sibling keys', () {
      final gadget = GadgetYaml.fromContent(fixture);
      gadget.setDefault('core22', 'nested.new', 42);
      expect(gadget.valueAt(const ['defaults', 'core22', 'nested', 'new']), 42);
      expect(gadget.valueAt(const ['defaults', 'core22', 'hold']), true);
      expect(gadget.toYaml(),
          fixture.replaceFirst('    hold: true\n', '    hold: true\n    nested:\n      new: 42\n'));
    });

    test('stores a literal multiline scalar in block style', () {
      final gadget = GadgetYaml.fromContent('defaults:\n  core20:\n    a: 1\n');
      gadget.setDefault('core20', 'multi',
          wrapAsYamlNode('line1\nline2', scalarStyle: ScalarStyle.LITERAL));
      expect(gadget.toYaml().contains('multi: |'), isTrue);
      expect(gadget.valueAt(const ['defaults', 'core20', 'multi']), 'line1\nline2');
    });

    test('replaces a scalar when the key path extends it', () {
      final gadget = GadgetYaml.fromContent(fixture);
      gadget.setDefault('core20', 'refresh-motivation.detail', 'x');
      expect(gadget.valueAt(const ['defaults', 'core20', 'refresh-motivation', 'detail']), 'x');
    });

    test('rejects an empty snap ID or empty dot-separated key part', () {
      final gadget = GadgetYaml.fromContent('name: pc\n');
      expect(() => gadget.setDefault('', 'a', 'b'),
          throwsA(isA<GadgetYamlException>()));
      expect(() => gadget.setDefault('core20', 'a..b', 'c'),
          throwsA(isA<GadgetYamlException>()));
    });
  });

  group('removeConnection', () {
    test('removes an entry by index, keeps the rest', () {
      final gadget = GadgetYaml.fromContent('''
connections:
  - interface: serial
    plug: modem
  - interface: usb
    plug: modem1
''');
      gadget.removeConnection(0);
      final out = gadget.toYaml();
      expect(out, contains('interface: usb'));
      expect(out, isNot(contains('interface: serial')));
      expect(out, isNot(contains('plug: modem\n')));
      expect(gadget.valueAt(const ['connections', 0, 'plug']), 'modem1');
    });

    test('prunes the emptied connections section', () {
      final gadget = GadgetYaml.fromContent('connections:\n  - interface: serial\n');
      gadget.removeConnection(0);
      final out = gadget.toYaml();
      expect(out, isNot(contains('connections')));
    });

    test('throws on out-of-bounds index', () {
      final gadget = GadgetYaml.fromContent('connections:\n  - interface: serial\n');
      expect(() => gadget.removeConnection(5),
          throwsA(isA<GadgetYamlException>()));
      expect(() => gadget.removeConnection(-1),
          throwsA(isA<GadgetYamlException>()));
    });

    test('throws when connections is missing', () {
      final gadget = GadgetYaml.fromContent('name: pc\n');
      expect(() => gadget.removeConnection(0),
          throwsA(isA<GadgetYamlException>()));
    });
  });

  group('addConnection', () {
    test('creates the missing section at the end of the document', () {
      final gadget = GadgetYaml.fromContent('name: pc\nvolumes:\n  pc:\n    size: 1G\n');
      gadget.addConnection({'interface': 'serial'});
      expect(gadget.toYaml(),
          'name: pc\nvolumes:\n  pc:\n    size: 1G\nconnections:\n  - interface: serial\n');
    });

    test('appends to an existing list, preserving existing entries', () {
      final gadget = GadgetYaml.fromContent('''
connections:
  - interface: serial
    plug: modem
''');
      gadget.addConnection(const {
        'interface': 'usb',
        'plug': 'modem1',
        'slots': ['modem2'],
      });
      final out = gadget.toYaml();
      expect(out, contains('interface: serial'));
      expect(out, contains('interface: usb'));
      expect(
          out.indexOf('interface: serial') < out.indexOf('interface: usb'),
          isTrue);
      expect(gadget.valueAt(const ['connections', 1, 'plug']), 'modem1');
      final slots = gadget.valueAt(const ['connections', 1, 'slots']);
      expect(slots, ['modem2']);
    });

    test('creates the connections section on demand', () {
      final gadget = GadgetYaml.fromContent('name: pc\n');
      gadget.addConnection(const {'interface': 'serial', 'plug': 'modem'});
      final out = gadget.toYaml();
      expect(out, contains('connections:'));
      expect(out, contains('interface: serial'));
      expect(gadget.valueAt(const ['connections', 0, 'interface']), 'serial');
    });
  });

  group('removeKernelCmdlineItem', () {
    test('removes an item, keeps non-empty sibling sections', () {
      final gadget = GadgetYaml.fromContent(fixture);
      final levels = gadget.removeKernelCmdlineItem('allow', 0);
      expect(levels, 1);
      final out = gadget.toYaml();
      expect(out, isNot(contains('console=ttyS0')));
      expect(out, contains('debug'));
      expect(out, contains('loglevel=4'));
      expect(out, contains('kernel-cmdline:'));
      expect(out, contains('append:'));
    });

    test('prunes an emptied sub-section but keeps kernel-cmdline', () {
      final gadget = GadgetYaml.fromContent(fixture);
      final levels = gadget.removeKernelCmdlineItem('append', 0);
      expect(levels, 2);
      final out = gadget.toYaml();
      expect(out, isNot(contains('loglevel=4')));
      expect(out, isNot(contains('append:')));
      expect(out, contains('allow:'));
      expect(out, contains('kernel-cmdline:'));
    });

    test('prunes the whole kernel-cmdline section when fully empty', () {
      final gadget = GadgetYaml.fromContent('kernel-cmdline:\n  allow:\n    - x\n');
      final levels = gadget.removeKernelCmdlineItem('allow', 0);
      expect(levels, 3);
      expect(gadget.toYaml(), '');
    });

    test('throws on invalid section names', () {
      final gadget = GadgetYaml.fromContent(fixture);
      expect(() => gadget.removeKernelCmdlineItem('bogus', 0),
          throwsA(isA<GadgetYamlException>()));
    });

    test('throws when the section or index is missing', () {
      final gadget = GadgetYaml.fromContent('name: pc\n');
      expect(() => gadget.removeKernelCmdlineItem('allow', 0),
          throwsA(isA<GadgetYamlException>()));
      expect(() => gadget.removeKernelCmdlineItem('allow', 99),
          throwsA(isA<GadgetYamlException>()));
    });
  });

  group('addKernelCmdlineItem', () {
    test('appends to an existing sub-section', () {
      final gadget = GadgetYaml.fromContent(fixture);
      gadget.addKernelCmdlineItem('append', 'quiet');
      final out = gadget.toYaml();
      expect(out, contains('loglevel=4'));
      expect(out, contains('quiet'));
      expect(gadget.valueAt(const ['kernel-cmdline', 'append', 1]), 'quiet');
    });

    test('creates the section on demand', () {
      final gadget = GadgetYaml.fromContent('name: pc\n');
      gadget.addKernelCmdlineItem('allow', 'console=ttyS0');
      final out = gadget.toYaml();
      expect(out, contains('kernel-cmdline:'));
      expect(out, contains('console=ttyS0'));
      expect(gadget.valueAt(const ['kernel-cmdline', 'allow', 0]), 'console=ttyS0');
    });

    test('appends a missing sub-section at the end of the section', () {
      final gadget = GadgetYaml.fromContent(
          'kernel-cmdline:\n  allow:\n    - console=ttyS0\n');
      gadget.addKernelCmdlineItem('remove', 'debug');
      expect(gadget.toYaml(),
          'kernel-cmdline:\n  allow:\n    - console=ttyS0\n  remove:\n    - debug\n');
    });

    test('throws on invalid section names', () {
      final gadget = GadgetYaml.fromContent('name: pc\n');
      expect(() => gadget.addKernelCmdlineItem('bogus', 'x'),
          throwsA(isA<GadgetYamlException>()));
    });
  });

  group('updatePartitionSize', () {
    test('updates only the size field, preserving everything else', () {
      final gadget = GadgetYaml.fromContent(fixture);
      gadget.updatePartitionSize('pc', 'root', '20G');
      expect(
        gadget.toYaml(),
        fixture.replaceFirst('size: 10G', 'size: 20G'),
      );
    });

    test('finds the partition by name, not position', () {
      final gadget = GadgetYaml.fromContent(fixture);
      gadget.updatePartitionSize('pc', 'mbr', '4M');
      final out = gadget.toYaml();
      expect(out, contains('size: 4M'));
      expect(out, contains('size: 10G'));
    });

    test('throws for unknown volume, partition or structure', () {
      final gadget = GadgetYaml.fromContent(fixture);
      expect(
          () => gadget.updatePartitionSize('nope', 'root', '1G'),
          throwsA(isA<GadgetYamlException>()));
      expect(
          () => gadget.updatePartitionSize('pc', 'nope', '1G'),
          throwsA(isA<GadgetYamlException>()));

      final noStructure = GadgetYaml.fromContent('volumes:\n  pc:\n    foo: 1\n');
      expect(
          () => noStructure.updatePartitionSize('pc', 'root', '1G'),
          throwsA(isA<GadgetYamlException>()));
    });
  });

  group('renameVolume', () {
    test('renames the key, preserving the volume content verbatim', () {
      final gadget = GadgetYaml.fromContent(fixture);
      gadget.renameVolume('pc', 'pc-custom');
      expect(
        gadget.toYaml(),
        fixture.replaceFirst('volumes:\n  pc:', 'volumes:\n  pc-custom:'),
      );
    });

    test('rename succeeds even when the key line carries a comment', () {
      // Note: yaml_edit does not carry the old key's inline comment over to
      // the new key; the rename itself must still work.
      final gadget = GadgetYaml.fromContent('volumes:\n  pc: # default disk\n    foo: 1\n');
      gadget.renameVolume('pc', 'pc2');
      expect(gadget.has(const ['volumes', 'pc2', 'foo']), isTrue);
      expect(gadget.valueAt(const ['volumes', 'pc2', 'foo']), 1);
      expect(gadget.has(const ['volumes', 'pc']), isFalse);
    });

    test('throws when the source volume is missing', () {
      final gadget = GadgetYaml.fromContent(fixture);
      expect(() => gadget.renameVolume('nope', 'pc2'),
          throwsA(isA<GadgetYamlException>()));
    });

    test('throws when the target name is taken', () {
      final gadget = GadgetYaml.fromContent(
          'volumes:\n  a:\n    x: 1\n  b:\n    y: 2\n');
      expect(() => gadget.renameVolume('a', 'b'),
          throwsA(isA<GadgetYamlException>()));
    });

    test('same-name rename is a no-op', () {
      final gadget = GadgetYaml.fromContent(fixture);
      gadget.renameVolume('pc', 'pc');
      expect(gadget.toYaml(), fixture);
    });
  });

  group('renameVolume', () {
    test('appends the renamed volume at the end, preserving other order', () {
      // 'zeta' sorts after 'pc', and 'alpha' would sort before 'pc': in a
      // sorted-insertion world the file would be reordered either way.
      final gadget = GadgetYaml.fromContent(
          'name: pc\nvolumes:\n  alpha:\n    size: 1G\n  pc:\n    size: 2G\n');
      gadget.renameVolume('pc', 'zeta');
      expect(gadget.toYaml(),
          'name: pc\nvolumes:\n  alpha:\n    size: 1G\n  zeta:\n    size: 2G\n');
    });
  });

  group('pass-throughs', () {
    test('update creates intermediate maps', () {
      final gadget = GadgetYaml.fromContent('name: pc\n');
      gadget.update(const ['defaults', 'core22', 'hold'], true);
      expect(gadget.valueAt(const ['defaults', 'core22', 'hold']), true);
      expect(gadget.toYaml(),
          'name: pc\ndefaults:\n  core22:\n    hold: true\n');
    });

    test('update appends a missing top-level key at the end', () {
      final gadget = GadgetYaml.fromContent('name: pc\n');
      gadget.update(const ['connections'], []);
      // A bare empty list renders as flow `[]` inline: still one line.
      expect(gadget.toYaml(), 'name: pc\nconnections: []\n');
    });

    test('update replaces a null-valued key in place without duplicating it', () {
      final gadget = GadgetYaml.fromContent('a: 1\ndefaults:\nb: 2\n');
      gadget.update(const ['defaults'], {'x': 'y'});
      expect(gadget.toYaml(), 'a: 1\ndefaults:\n  x: y\nb: 2\n');
    });

    test('remove throws on a missing path and leaves the document intact', () {
      final gadget = GadgetYaml.fromContent('name: pc\n');
      expect(() => gadget.remove(const ['defaults', 'core20']),
          throwsA(isA<GadgetYamlException>()));
      expect(gadget.toYaml(), 'name: pc\n');
    });

    test('insertIntoList splices at a position', () {
      final gadget = GadgetYaml.fromContent('kernel-cmdline:\n  allow:\n    - a\n    - b\n');
      gadget.insertIntoList(const ['kernel-cmdline', 'allow'], 1, 'z');
      expect(
          gadget.valueAt(const ['kernel-cmdline', 'allow']), ['a', 'z', 'b']);
    });

    test('appendToList appends', () {
      final gadget = GadgetYaml.fromContent('kernel-cmdline:\n  allow:\n    - a\n');
      gadget.appendToList(const ['kernel-cmdline', 'allow'], 'b');
      expect(
          gadget.valueAt(const ['kernel-cmdline', 'allow']), ['a', 'b']);
    });

    test('appendToList requires the list to exist', () {
      final gadget = GadgetYaml.fromContent('name: pc\n');
      expect(() => gadget.appendToList(const ['connections'], 'x'),
          throwsA(isA<GadgetYamlException>()));
      expect(gadget.toYaml(), 'name: pc\n');
    });

    test('mutate runs a guarded batch on existing nodes', () {
      final gadget = GadgetYaml.fromContent(fixture);
      gadget.mutate((editor) {
        editor.update(const ['name'], 'pc2');
        editor.update(const ['defaults', 'core22', 'hold'], false);
      });
      expect(gadget.valueAt(const ['name']), 'pc2');
      expect(gadget.valueAt(const ['defaults', 'core22', 'hold']), false);
    });
  });

  group('inspection', () {
    test('has / valueAt / nodeAt report existence', () {
      final gadget = GadgetYaml.fromContent(fixture);
      expect(gadget.has(const ['name']), isTrue);
      expect(gadget.has(const ['defaults', 'core20']), isTrue);
      expect(gadget.has(const ['defaults', 'core99']), isFalse);
      expect(gadget.valueAt(const ['name']), 'pc');
      expect(gadget.valueAt(const ['defaults', 'core99']), isNull);
      expect(gadget.nodeAt(const ['name']), isNotNull);
      expect(gadget.nodeAt(const ['defaults', 'core99']), isNull);
    });

    test('toMap returns plain Dart collections', () {
      final gadget = GadgetYaml.fromContent(fixture);
      final map = gadget.toMap();
      expect(map['name'], 'pc');
      expect(map['defaults'], isA<Map<String, dynamic>>());
      expect(map['defaults']['core22'], {'hold': true});
      expect(map['connections'], isA<List>());
      expect(map['connections'][0], isA<Map<String, dynamic>>());
      expect(map['connections'][0]['slots'], ['modem0']);
      expect(map['kernel-cmdline']['allow'], ['console=ttyS0', 'debug']);
      expect(map['volumes']['pc']['structure'][1], {
        'name': 'root',
        'size': '10G',
      });
    });
  });

  group('fallback rule (string-backed vs file-backed)', () {
    test('string-backed mutations never touch the filesystem', () {
      final gadget = GadgetYaml.fromContent(fixture);
      gadget.setSnapName('pc-x');
      gadget.removeDefault('core20');
      gadget.save(); // must be a no-op
      expect(gadget.isFileBacked, isFalse);
      expect(gadget.toYaml(),
          fixture.replaceFirst('name: pc\n', 'name: pc-x\n').replaceAll(
              '  core20:\n    refresh-motivation: timely\n', ''));
    });

    test('file-backed save persists to disk and re-reads the file', () {
      final file = writeTemp('gadget.yaml', fixture);
      final gadget = GadgetYaml.fromFile(file.path);
      gadget.setSnapName('pc-saved');
      gadget.removeDefault('core20');

      // Not persisted yet.
      expect(file.readAsStringSync(), fixture);

      gadget.save();
      expect(file.readAsStringSync(), gadget.toYaml());
      expect(file.readAsStringSync(), isNot(contains('core20')));
      expect(file.readAsStringSync(), contains('name: pc-saved'));
    });

    test('reload discards unsaved in-memory mutations', () {
      final file = writeTemp('gadget.yaml', fixture);
      final gadget = GadgetYaml.fromFile(file.path);
      gadget.setSnapName('pc-dirty');
      expect(gadget.toYaml(), contains('name: pc-dirty'));
      gadget.reload();
      expect(gadget.toYaml(), fixture);
    });

    test('reload picks up external file changes', () {
      final file = writeTemp('gadget.yaml', fixture);
      final gadget = GadgetYaml.fromFile(file.path);
      file.writeAsStringSync('name: pc-external\n');
      gadget.reload();
      expect(gadget.valueAt(const ['name']), 'pc-external');
    });

    test('file-backed and string-backed behave identically for edits', () {
      final file = writeTemp('gadget.yaml', fixture);
      final fromFile = GadgetYaml.fromFile(file.path);
      final fromString = GadgetYaml.fromContent(fixture);
      for (final gadget in [fromFile, fromString]) {
        gadget.setSnapName('pc-twin');
        gadget.removeDefault('core20');
        gadget.removeConnection(0);
        gadget.removeKernelCmdlineItem('append', 0);
        gadget.updatePartitionSize('pc', 'root', '20G');
        gadget.renameVolume('pc', 'pc2');
      }
      expect(fromFile.toYaml(), fromString.toYaml());
    });

    test('save returns the persisted text', () {
      final file = writeTemp('gadget.yaml', fixture);
      final gadget = GadgetYaml.fromFile(file.path);
      gadget.setSnapName('pc-ret');
      final returned = gadget.save();
      expect(returned, gadget.toYaml());
    });
  });

  group('getApiKey / setApiKey', () {
    const keyDoc = '''
name: pc
version: 26-0.1
base: core26
hooks:
  prepare-device:
    environment:
      MODEL_APIKEY: ''
''';

    test('getApiKey returns null when the hook/key is absent', () {
      final g = GadgetYaml.fromContent('name: pc\nversion: 1\n');
      expect(g.getApiKey(), isNull);
    });

    test('getApiKey returns an empty string for an empty key', () {
      final g = GadgetYaml.fromContent(keyDoc);
      expect(g.getApiKey(), '');
    });

    test('getApiKey returns the configured value', () {
      final g = GadgetYaml.fromContent(keyDoc.replaceAll("''", "'abc123'"));
      expect(g.getApiKey(), 'abc123');
    });

    test('setApiKey sets an existing key in place (no reorder)', () {
      final g = GadgetYaml.fromContent(keyDoc);
      g.setApiKey('secret-value');
      expect(g.getApiKey(), 'secret-value');
      // The value is written in place; the key keeps its position and the
      // document order is preserved (name still first, hooks still present).
      expect(g.toYaml(), contains('MODEL_APIKEY: secret-value'));
      expect(g.toYaml().indexOf('name: pc'), 0);
    });

    test('setApiKey creates the hooks/prepare-device/environment nesting', () {
      final g = GadgetYaml.fromContent('name: pc\nversion: 1\n');
      g.setApiKey('k1');
      expect(g.getApiKey(), 'k1');
      final m = g.toMap();
      expect(
        m['hooks']['prepare-device']['environment']['MODEL_APIKEY'],
        'k1',
      );
    });

    test('setApiKey overwrites a previously set value', () {
      final g = GadgetYaml.fromContent(keyDoc);
      g.setApiKey('first');
      g.setApiKey('second');
      expect(g.getApiKey(), 'second');
    });

    test('setApiKey persists an empty string (clearing the key)', () {
      final g = GadgetYaml.fromContent(keyDoc.replaceAll("''", "'abc'"));
      g.setApiKey('');
      expect(g.getApiKey(), '');
    });

    test('file-backed setApiKey persists to disk on save', () {
      final file = writeTemp('gadget.yaml', keyDoc);
      final g = GadgetYaml.fromFile(file.path);
      g.setApiKey('disk-value');
      g.save();
      expect(g.getApiKey(), 'disk-value');
      // A fresh read from disk sees the value too.
      expect(GadgetYaml.fromFile(file.path).getApiKey(), 'disk-value');
    });
  });
}
