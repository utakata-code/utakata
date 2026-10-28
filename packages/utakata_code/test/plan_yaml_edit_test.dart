import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/filesystem_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_edit_data_source.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/plan_repository_impl.dart';
import 'package:yaml/yaml.dart';

/// Issue #28 / #29: plan.yaml への書き込みが yaml_edit の不具合で落ちたり
/// コメントをずらしたりしないこと。
void main() {
  const yamlEdit = YamlEditDataSource();

  group('YamlEditDataSource.appendKeyToBlockMap', () {
    const twoFeatures = 'schema: 1\n'
        'features:\n'
        '  - name: a\n'
        '    permission: user\n'
        '    layers:\n'
        '      1_domain/1_entities:\n'
        '        - a_entity.dart   # comment\n'
        '  - name: b\n'
        '    permission: user\n';

    test('キーがアルファベット順の list 要素にも、前の要素を壊さず末尾に足す', () {
      final updated = yamlEdit.appendKeyToBlockMap(
          twoFeatures,
          ['features', 1],
          'layers',
          {
            '1_domain/1_entities': ['b_entity.dart'],
          });

      expect(
        updated,
        '$twoFeatures'
        '    layers:\n'
        '      1_domain/1_entities:\n'
        '        - b_entity.dart\n',
      );
    });

    test('最後の値が入れ子の block コレクションでも、その最後の行の次に足す', () {
      final updated = yamlEdit.appendKeyToBlockMap(
          twoFeatures, ['features', 0], 'entities', ['a']);

      expect(
        updated,
        'schema: 1\n'
        'features:\n'
        '  - name: a\n'
        '    permission: user\n'
        '    layers:\n'
        '      1_domain/1_entities:\n'
        '        - a_entity.dart   # comment\n'
        '    entities:\n'
        '      - a\n'
        '  - name: b\n'
        '    permission: user\n',
      );
    });

    test('CRLF のファイルでは足した行も CRLF にする', () {
      final crlf = twoFeatures.replaceAll('\n', '\r\n');
      final updated = yamlEdit.appendKeyToBlockMap(
          crlf,
          ['features', 1],
          'layers',
          {
            'x': ['y'],
          });

      expect(updated, '$crlf    layers:\r\n      x:\r\n        - y\r\n');
      expect(updated.replaceAll('\r\n', ''), isNot(contains('\n')));
    });

    test('末尾に改行が無いファイルでも足せ、末尾は改行なしのまま', () {
      final noNewline = twoFeatures.substring(0, twoFeatures.length - 1);
      final updated = yamlEdit.appendKeyToBlockMap(
          noNewline,
          ['features', 1],
          'layers',
          {
            'x': ['y'],
          });

      expect(updated, '$noNewline\n    layers:\n      x:\n        - y');
    });

    test('最後の値が block scalar(|)でも中身を変えずに足す', () {
      const content = 'a:\n'
          '  note: |\n'
          '    hello\n'
          '    world\n'
          '# tail\n'
          'b: 1\n';
      final updated = yamlEdit.appendKeyToBlockMap(content, ['a'], 'z', 1);

      expect(updated,
          'a:\n  note: |\n    hello\n    world\n  z: 1\n# tail\nb: 1\n');
      expect((loadYaml(updated) as Map)['a']['note'], 'hello\nworld\n');
    });

    test('既にあるキーは足さずにエラーにする', () {
      expect(
        () => yamlEdit.appendKeyToBlockMap(
            twoFeatures, ['features', 0], 'name', 'x'),
        throwsA(isA<YamlAppendException>()),
      );
    });

    test('flow 形式のマップは yaml_edit に任せる', () {
      expect(yamlEdit.appendKeyToBlockMap('a: {k: v}\n', ['a'], 'z', 1),
          'a: {k: v, z: 1}\n');
    });
  });

  group('PlanRepositoryImpl', () {
    late Directory tempDir;
    late File planFile;
    const repo =
        PlanRepositoryImpl(FilesystemDataSource(), YamlDataSource(), yamlEdit);

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('utakata_plan_yaml_test_');
      planFile = File(p.join(tempDir.path, 'doc', 'specs', 'plan.yaml'))
        ..createSync(recursive: true);
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('#28: layers の無い feature への plan add が落ちない', () async {
      const original = 'schema: 1\n'
          'features:\n'
          '  - name: a\n'
          '    permission: user\n'
          '    layers:\n'
          '      1_domain/1_entities:\n'
          '        - a_entity.dart   # comment\n'
          '  - name: b\n'
          '    permission: user\n';
      planFile.writeAsStringSync(original);

      final ok = await repo.appendLayerItems(
          tempDir.path, 'b', '1_domain/1_entities', ['b_entity.dart']);

      expect(ok, isTrue);
      expect(
        planFile.readAsStringSync(),
        '$original'
        '    layers:\n'
        '      1_domain/1_entities:\n'
        '        - b_entity.dart\n',
      );
    });

    test('#28: plan expand の書き込みは全 feature 分を 1 回で行い、落ちない', () async {
      const original = 'schema: 1\n'
          'features:\n'
          '  - name: a\n'
          '    permission: user\n'
          '  - name: b\n'
          '    permission: user\n';
      planFile.writeAsStringSync(original);

      final written = await repo.setLayerDeclarationsForFeatures(tempDir.path, {
        'a': {
          '1_domain/1_entities': ['a_entity.dart'],
        },
        'b': {
          '1_domain/1_entities': ['b_entity.dart'],
          '3_application/1_states': ['b_state.dart'],
        },
        'missing': {
          'x': ['y'],
        },
      });

      expect(written, ['a', 'b']);
      final plan = await repo.read(tempDir.path);
      expect(plan!.features[0].layers, {
        '1_domain/1_entities': ['a_entity.dart'],
      });
      expect(plan.features[1].layers, {
        '1_domain/1_entities': ['b_entity.dart'],
        '3_application/1_states': ['b_state.dart'],
      });
    });

    test('#28: 既存の layers へ新しい層を足すときは末尾に足す', () async {
      const original = 'schema: 1\n'
          'features:\n'
          '  - name: a\n'
          '    permission: user\n'
          '    layers:\n'
          '      b_layer:\n'
          '        - x.dart   # keep\n'
          '      c_layer: []\n'
          '  - name: b\n'
          '    permission: user\n';
      planFile.writeAsStringSync(original);

      await repo.appendLayerItems(tempDir.path, 'a', 'a_layer', ['y.dart']);

      expect(
        planFile.readAsStringSync(),
        'schema: 1\n'
        'features:\n'
        '  - name: a\n'
        '    permission: user\n'
        '    layers:\n'
        '      b_layer:\n'
        '        - x.dart   # keep\n'
        '      c_layer: []\n'
        '      a_layer:\n'
        '        - y.dart\n'
        '  - name: b\n'
        '    permission: user\n',
      );
    });

    test('#29: plan add は一覧の途中・最後のコメントを動かさない', () async {
      const original = 'schema: 1\n'
          'features:\n'
          '  - name: a\n'
          '    permission: user\n'
          '    entities: [a]\n'
          '    layers:\n'
          '      1_domain/1_entities:\n'
          '        - a_entity.dart   # c1\n'
          '        - b_entity.dart   # c2\n';
      planFile.writeAsStringSync(original);

      final ok = await repo.appendLayerItems(
          tempDir.path, 'a', '1_domain/1_entities', ['c_entity.dart']);

      expect(ok, isTrue);
      expect(
        planFile.readAsStringSync(),
        '$original'
        '        - c_entity.dart\n',
      );
    });

    test('#29: 既にある項目は足さず、ファイルも書き換えない', () async {
      const original = 'schema: 1\n'
          'features:\n'
          '  - name: a\n'
          '    permission: user\n'
          '    layers:\n'
          '      1_domain/1_entities:\n'
          '        - a_entity.dart   # c1\n';
      planFile.writeAsStringSync(original);

      final ok = await repo.appendLayerItems(tempDir.path, 'a',
          '1_domain/1_entities', ['a_entity.dart', 'a_entity.dart']);

      expect(ok, isTrue);
      expect(planFile.readAsStringSync(), original);
    });

    test('#29: 空リスト宣言の行末コメントも残る', () async {
      const original = 'schema: 1\n'
          'features:\n'
          '  - name: a\n'
          '    permission: user\n'
          '    layers:\n'
          '      x: []   # c\n';
      planFile.writeAsStringSync(original);

      await repo.appendLayerItems(tempDir.path, 'a', 'x', ['r.dart']);

      expect(planFile.readAsStringSync(), contains('x: [r.dart]   # c\n'));
    });

    test('feature が無ければ false を返し、書き換えない', () async {
      const original =
          'schema: 1\nfeatures:\n  - name: a\n    permission: user\n';
      planFile.writeAsStringSync(original);

      final ok =
          await repo.appendLayerItems(tempDir.path, 'zzz', 'x', ['y.dart']);

      expect(ok, isFalse);
      expect(planFile.readAsStringSync(), original);
    });
  });
}
