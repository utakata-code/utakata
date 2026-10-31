import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:utakata/src/1_domain/1_entities/architecture_definition_entity.dart';
import 'package:utakata/src/1_domain/1_entities/dependency_stack_entity.dart';
import 'package:utakata/src/1_domain/1_entities/plan/plan_intent.dart';
import 'package:utakata/src/1_domain/2_repositories/architecture_repository.dart';
import 'package:utakata/src/1_domain/2_repositories/plan_repository.dart';
import 'package:utakata/src/1_domain/3_usecases/create_required_files_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/register_feature_in_plan_usecase.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/filesystem_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_edit_data_source.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/plan_repository_impl.dart';
import 'package:yaml/yaml.dart';

/// Issue #34: テンプレート無しの `feature add` でも plan.yaml に登録し、
/// 必須ファイルを作る。plan.yaml が無ければ今までどおり何もしない。
void main() {
  const yamlEdit = YamlEditDataSource();

  // `doc init` が作る plan.yaml と同じ形(`features: []` の後ろにコメント例)
  const docInitPlan = 'schema: 1\n'
      '\n'
      '# comment\n'
      'features: []\n'
      '# features:\n'
      '#   - name: todo\n'
      '#     permission: user\n';

  group('YamlEditDataSource.appendToBlockList', () {
    const item = {
      'name': 'counter',
      'permission': 'user',
      'entities': ['counter'],
    };

    test('features: [] は flow 形式にせず block 形式のリストにする', () {
      final updated =
          yamlEdit.appendToBlockList(docInitPlan, ['features'], item);

      expect(
        updated,
        'schema: 1\n'
        '\n'
        '# comment\n'
        'features:\n'
        '  - name: counter\n'
        '    permission: user\n'
        '    entities:\n'
        '      - counter\n'
        '# features:\n'
        '#   - name: todo\n'
        '#     permission: user\n',
      );
      expect(updated, isNot(contains('[{')));
    });

    test('block 形式のリストには、後ろのコメント行より前(最後の要素の次)に足す',
        () {
      final first =
          yamlEdit.appendToBlockList(docInitPlan, ['features'], item);
      final updated = yamlEdit.appendToBlockList(first, ['features'], {
        'name': 'todo',
        'permission': 'admin',
      });

      expect(
        updated,
        contains('      - counter\n'
            '  - name: todo\n'
            '    permission: admin\n'
            '# features:\n'),
      );
      final features = (loadYaml(updated) as Map)['features'] as List;
      expect(features.map((f) => f['name']), ['counter', 'todo']);
    });

    test('値なし(features:)も block 形式のリストにする', () {
      final updated = yamlEdit.appendToBlockList(
          'schema: 1\nfeatures:\nother: 1\n', ['features'], {'name': 'a'});

      expect(updated, 'schema: 1\nfeatures:\n  - name: a\nother: 1\n');
    });

    test('キーが無ければ末尾に block 形式で足す', () {
      final updated = yamlEdit
          .appendToBlockList('schema: 1\n', ['features'], {'name': 'a'});

      expect(updated, 'schema: 1\nfeatures:\n  - name: a\n');
    });

    test('中身のある flow 形式のリストは利用者の書式のまま足す', () {
      final updated = yamlEdit.appendToBlockList(
          'features: [{name: a}]\n', ['features'], {'name': 'b'});

      final features = (loadYaml(updated) as Map)['features'] as List;
      expect(features.map((f) => f['name']), ['a', 'b']);
    });

    test('字下げなしの block リスト(- が行頭)にも同じ字下げで足す', () {
      final updated = yamlEdit.appendToBlockList(
          'features:\n- name: a\n  permission: user\n# tail\n',
          ['features'],
          {'name': 'b'});

      expect(updated,
          'features:\n- name: a\n  permission: user\n- name: b\n# tail\n');
    });
  });

  group('PlanRepositoryImpl.adoptFeature', () {
    late Directory tempDir;
    late File planFile;
    const repo =
        PlanRepositoryImpl(FilesystemDataSource(), YamlDataSource(), yamlEdit);

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('utakata_adopt_test_');
      planFile = File(p.join(tempDir.path, 'doc', 'specs', 'plan.yaml'));
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('同じ名前の feature は足さず、ファイルも書き換えない', () async {
      planFile
        ..createSync(recursive: true)
        ..writeAsStringSync(
            'schema: 1\nfeatures:\n  - name: counter\n    permission: admin\n');
      final before = planFile.readAsStringSync();

      final result = await repo.adoptFeature(tempDir.path,
          const PlanFeatureIntent(name: 'counter', permission: 'user'));

      expect(result, AdoptFeatureResult.alreadyPlanned);
      expect(planFile.readAsStringSync(), before);
    });

    test('createIfMissing: false なら plan.yaml を作らない', () async {
      final result = await repo.adoptFeature(
          tempDir.path, const PlanFeatureIntent(name: 'a', permission: 'user'),
          createIfMissing: false);

      expect(result, AdoptFeatureResult.noPlan);
      expect(planFile.existsSync(), isFalse);
    });

    test('既定(plan adopt / --template)は従来どおり plan.yaml を作る', () async {
      final result = await repo.adoptFeature(
          tempDir.path, const PlanFeatureIntent(name: 'a', permission: 'user'));

      expect(result, AdoptFeatureResult.added);
      expect(planFile.existsSync(), isTrue);
    });
  });

  group('RegisterFeatureInPlanUsecase', () {
    const arch = ArchitectureDefinitionEntity(
      id: 'clean_architecture',
      displayName: 'Clean Architecture',
      layers: [
        LayerDefinitionEntity(name: '1_domain', dirs: ['1_entities']),
        LayerDefinitionEntity(name: '4_presentation', dirs: ['2_pages']),
      ],
      namingRules: [
        NamingRuleEntity(
          dirPattern: '1_domain/1_entities',
          filePattern: r'^.+_entity\.dart$',
          description: '{name}_entity.dart',
        ),
        NamingRuleEntity(
          dirPattern: '4_presentation/2_pages',
          filePattern: r'^.+_page\.dart$',
          description: '{feature}_page.dart',
        ),
      ],
    );

    late Directory tempDir;
    late File planFile;
    late RegisterFeatureInPlanUsecase usecase;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('utakata_register_test_');
      planFile = File(p.join(tempDir.path, 'doc', 'specs', 'plan.yaml'));
      usecase = RegisterFeatureInPlanUsecase(
        planRepo: const PlanRepositoryImpl(
            FilesystemDataSource(), YamlDataSource(), yamlEdit),
        requiredFiles: CreateRequiredFilesUsecase(
          archRepo: _FixedArchRepo(arch),
          fileExists: (path) => FileSystemEntity.typeSync(path) !=
              FileSystemEntityType.notFound,
          writeFile: (path, content) async {
            File(path)
              ..createSync(recursive: true)
              ..writeAsStringSync(content);
          },
        ),
      );
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    bool exists(String relative) =>
        File(p.join(tempDir.path, relative)).existsSync();

    test('plan.yaml があれば登録し、その feature の必須ファイルだけを作る', () async {
      planFile
        ..createSync(recursive: true)
        ..writeAsStringSync('schema: 1\n'
            'features:\n'
            '  - name: other\n'
            '    permission: user\n');

      final result = await usecase.execute(
        tempDir.path,
        const PlanFeatureIntent(
            name: 'counter', permission: 'user', entities: ['counter']),
      );

      expect(result.adopt, AdoptFeatureResult.added);
      expect(result.createdFiles, [
        'lib/features/user/counter/1_domain/1_entities/counter_entity.dart',
        'lib/features/user/counter/4_presentation/2_pages/counter_page.dart',
      ]);
      expect(
          exists(
              'lib/features/user/counter/1_domain/1_entities/counter_entity.dart'),
          isTrue);
      // 他の feature のファイルは作らない(apply の仕事)
      expect(exists('lib/features/user/other'), isFalse);

      final features = (loadYaml(planFile.readAsStringSync()) as Map)['features']
          as List;
      expect(features.last['name'], 'counter');
      // --arch を明示していなければ architecture は書かない
      expect((features.last as Map).containsKey('architecture'), isFalse);
    });

    test('plan.yaml が無ければ何もしない(plan.yaml を作らない)', () async {
      final result = await usecase.execute(tempDir.path,
          const PlanFeatureIntent(name: 'counter', permission: 'user'));

      expect(result.adopt, AdoptFeatureResult.noPlan);
      expect(result.createdFiles, isEmpty);
      expect(planFile.existsSync(), isFalse);
      expect(exists('lib'), isFalse);
    });

    test('同じ名前が既にあれば足さず、plan.yaml 側の宣言でファイルを作る', () async {
      const original = 'schema: 1\n'
          'features:\n'
          '  - name: counter\n'
          '    permission: user\n'
          '    entities: [tally]\n';
      planFile
        ..createSync(recursive: true)
        ..writeAsStringSync(original);

      final result = await usecase.execute(
        tempDir.path,
        const PlanFeatureIntent(
            name: 'counter', permission: 'user', entities: ['counter']),
      );

      expect(result.adopt, AdoptFeatureResult.alreadyPlanned);
      expect(planFile.readAsStringSync(), original);
      expect(result.createdFiles,
          contains('lib/features/user/counter/1_domain/1_entities/tally_entity.dart'));
    });

    test('既存ファイルは上書きしない', () async {
      planFile
        ..createSync(recursive: true)
        ..writeAsStringSync(docInitPlan);
      final entity = File(p.join(tempDir.path,
          'lib/features/user/counter/1_domain/1_entities/counter_entity.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('class Counter {}\n');

      final result = await usecase.execute(
        tempDir.path,
        const PlanFeatureIntent(
            name: 'counter', permission: 'user', entities: ['counter']),
      );

      expect(result.createdFiles, [
        'lib/features/user/counter/4_presentation/2_pages/counter_page.dart',
      ]);
      expect(entity.readAsStringSync(), 'class Counter {}\n');
      expect(planFile.readAsStringSync(), contains('features:\n  - name: counter\n'));
    });
  });
}

class _FixedArchRepo implements ArchitectureRepository {
  final ArchitectureDefinitionEntity arch;
  _FixedArchRepo(this.arch);

  @override
  Future<DependencyStack> getDependencyStack(String architectureId) async =>
      DependencyStack.empty;

  @override
  Future<ArchitectureDefinitionEntity> getById(String architectureId) async =>
      arch;

  @override
  Future<List<ArchitectureDefinitionEntity>> getAll() async => [arch];

  @override
  Future<String> getRawDefinition(String architectureId) =>
      throw UnimplementedError();
}
