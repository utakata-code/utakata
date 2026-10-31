import 'package:test/test.dart';
import 'package:utakata/src/1_domain/1_entities/dependency_stack_entity.dart';
import 'package:utakata/src/1_domain/1_entities/architecture_definition_entity.dart';
import 'package:utakata/src/1_domain/1_entities/plan/plan_intent.dart';
import 'package:utakata/src/1_domain/2_repositories/architecture_repository.dart';
import 'package:utakata/src/1_domain/2_repositories/plan_repository.dart';
import 'package:utakata/src/1_domain/3_usecases/expand_plan_usecase.dart';

/// Issue #16: `plan expand` は拡張子込みの完全ファイル名を書き出す。
void main() {
  const arch = ArchitectureDefinitionEntity(
    id: 'clean_architecture',
    displayName: 'Clean Architecture',
    layers: [
      LayerDefinitionEntity(name: '1_domain', dirs: ['1_entities', '3_usecases']),
      LayerDefinitionEntity(name: '3_application', dirs: ['1_states']),
      LayerDefinitionEntity(name: 'core', dirs: ['routing']),
    ],
    namingRules: [
      NamingRuleEntity(
        dirPattern: '1_domain/1_entities',
        filePattern: r'^.+_entity\.dart$',
        description: '{name}_entity.dart',
      ),
      NamingRuleEntity(
        dirPattern: '1_domain/3_usecases',
        filePattern: r'^.+_usecase\.dart$',
        description: '{verb}_{name}_usecase.dart',
      ),
      NamingRuleEntity(
        dirPattern: '3_application/1_states',
        filePattern: r'^.+_state\.dart$',
        description: '{feature}_state.dart',
      ),
      NamingRuleEntity(
        dirPattern: 'core/routing',
        filePattern: r'^router\.dart$',
        description: 'router.dart',
      ),
    ],
  );

  ExpandPlanUsecase usecaseFor(PlanIntent plan, _RecordingPlanRepo planRepo) =>
      ExpandPlanUsecase(
        planRepo: planRepo..plan = plan,
        archRepo: _FixedArchRepo(arch),
      );

  test('完全ファイル名(拡張子込み)を書き出す', () async {
    final planRepo = _RecordingPlanRepo();
    final usecase = usecaseFor(
      const PlanIntent(defaultArchitectureId: 'clean_architecture', features: [
        PlanFeatureIntent(
            name: 'todo', permission: 'user', entities: ['todo', 'tag']),
      ]),
      planRepo,
    );

    final results = await usecase.execute('/proj');

    final layers = results.single.layers;
    expect(layers['1_domain/1_entities'], ['tag_entity.dart', 'todo_entity.dart']);
    expect(layers['3_application/1_states'], ['todo_state.dart']);
    // {verb} を含む非決定的な層は書き出さない
    expect(layers.containsKey('1_domain/3_usecases'), isFalse);
    // 固定名の規則も書き出す(決定的なため)
    expect(layers['core/routing'], ['router.dart']);
    expect(planRepo.written['todo'], layers);
  });

  test('既存の layers 宣言は上書きせずスキップする', () async {
    final planRepo = _RecordingPlanRepo();
    final usecase = usecaseFor(
      const PlanIntent(defaultArchitectureId: 'clean_architecture', features: [
        PlanFeatureIntent(
          name: 'todo',
          permission: 'user',
          entities: ['todo'],
          layers: {'1_domain/1_entities': ['custom.dart']},
        ),
      ]),
      planRepo,
    );

    final results = await usecase.execute('/proj');

    expect(results.single.skipped, contains('1_domain/1_entities'));
    expect(results.single.layers.containsKey('1_domain/1_entities'), isFalse);
  });

  test('自由記述(prose)の description は file_pattern を満たさないため書き出さない', () async {
    const proseArch = ArchitectureDefinitionEntity(
      id: 'custom',
      displayName: 'Custom',
      layers: [
        LayerDefinitionEntity(name: '1_domain', dirs: ['helpers']),
      ],
      namingRules: [
        NamingRuleEntity(
          dirPattern: '1_domain/helpers',
          filePattern: r'^.+_helper\.dart$',
          description: '任意のヘルパー名(自由)',
        ),
      ],
    );
    final planRepo = _RecordingPlanRepo()
      ..plan = const PlanIntent(defaultArchitectureId: 'custom', features: [
        PlanFeatureIntent(name: 'todo', permission: 'user', entities: ['todo']),
      ]);
    final usecase = ExpandPlanUsecase(
        planRepo: planRepo, archRepo: _FixedArchRepo(proseArch));

    final results = await usecase.execute('/proj');

    expect(results.single.layers, isEmpty);
    expect(planRepo.written, isEmpty);
  });

  test('複数 feature の編集はまとめて 1 回で書き込む(Issue #28)', () async {
    final planRepo = _RecordingPlanRepo();
    final usecase = usecaseFor(
      const PlanIntent(defaultArchitectureId: 'clean_architecture', features: [
        PlanFeatureIntent(name: 'a', permission: 'user', entities: ['a']),
        PlanFeatureIntent(name: 'b', permission: 'user', entities: ['b']),
      ]),
      planRepo,
    );

    await usecase.execute('/proj');

    expect(planRepo.batchWrites, 1);
    expect(planRepo.written.keys, ['a', 'b']);
  });

  test('dry-run では書き込まない', () async {
    final planRepo = _RecordingPlanRepo();
    final usecase = usecaseFor(
      const PlanIntent(defaultArchitectureId: 'clean_architecture', features: [
        PlanFeatureIntent(name: 'todo', permission: 'user', entities: ['todo']),
      ]),
      planRepo,
    );

    final results = await usecase.execute('/proj', dryRun: true);

    expect(results.single.layers['1_domain/1_entities'], ['todo_entity.dart']);
    expect(planRepo.written, isEmpty);
  });
}

class _RecordingPlanRepo implements PlanRepository {
  PlanIntent? plan;
  final written = <String, Map<String, List<String>>>{};

  @override
  Future<PlanIntent?> read(String projectDir) async => plan;

  @override
  Future<bool> setLayerDeclarations(
    String projectDir,
    String featureName,
    Map<String, List<String>> declarations,
  ) async {
    written[featureName] = declarations;
    return true;
  }

  /// 1 回の呼び出しでまとめて書かれたか(Issue #28)を確かめるための回数
  int batchWrites = 0;

  @override
  Future<List<String>> setLayerDeclarationsForFeatures(
    String projectDir,
    Map<String, Map<String, List<String>>> declarationsByFeature,
  ) async {
    batchWrites++;
    written.addAll(declarationsByFeature);
    return declarationsByFeature.keys.toList();
  }

  @override
  Future<bool> appendLayerItems(String projectDir, String featureName,
          String layerPath, List<String> items) =>
      throw UnimplementedError();

  @override
  Future<void> write(String projectDir, PlanIntent plan) =>
      throw UnimplementedError();

  @override
  Future<AdoptFeatureResult> adoptFeature(
          String projectDir, PlanFeatureIntent feature,
          {bool createIfMissing = true}) =>
      throw UnimplementedError();

  @override
  Future<bool> removeLayerItem(String projectDir, String featureName,
          String layerPath, String item) =>
      throw UnimplementedError();
}

class _FixedArchRepo implements ArchitectureRepository {
  @override
  Future<DependencyStack> getDependencyStack(String architectureId) async =>
      DependencyStack.empty;

  final ArchitectureDefinitionEntity arch;
  _FixedArchRepo(this.arch);

  @override
  Future<ArchitectureDefinitionEntity> getById(String architectureId) async =>
      arch;

  @override
  Future<List<ArchitectureDefinitionEntity>> getAll() async => [arch];

  @override
  Future<String> getRawDefinition(String architectureId) =>
      throw UnimplementedError();
}
