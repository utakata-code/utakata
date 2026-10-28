// 既知バグの回帰テスト。
//
// v0.6.0 では旧 diff/validate の実装を直接動かして2件のバグ
// (①validate の direct 未補償、②非決定的命名ディレクトリの extra 誤検知)
// を実証した。v0.7.0 で正準構造モデル(StructureChecker)へ載せ替えた後は、
// 同じシナリオを新 CheckUsecase で実行し、両方とも解消されていることを
// 回帰テストとして固定する。
import 'package:test/test.dart';
import 'package:utakata/src/1_domain/1_entities/dependency_stack_entity.dart';
import 'package:utakata/src/1_domain/1_entities/architecture_definition_entity.dart';
import 'package:utakata/src/1_domain/1_entities/plan/plan_intent.dart';
import 'package:utakata/src/1_domain/1_entities/structure/structure_node.dart';
import 'package:utakata/src/1_domain/1_entities/structure/structure_snapshot.dart';
import 'package:utakata/src/1_domain/2_repositories/architecture_repository.dart';
import 'package:utakata/src/1_domain/2_repositories/plan_repository.dart';
import 'package:utakata/src/1_domain/2_repositories/structure_repository.dart';
import 'package:utakata/src/1_domain/3_usecases/check_usecase.dart';
import 'package:utakata/src/1_domain/messages/ja_messages.dart';

class _FakePlanRepository implements PlanRepository {
  final PlanIntent plan;
  _FakePlanRepository(this.plan);

  @override
  Future<PlanIntent?> read(String projectDir) async => plan;

  @override
  Future<void> write(String projectDir, PlanIntent plan) async {}

  @override
  Future<void> adoptFeature(String projectDir, PlanFeatureIntent feature) async {}

  @override
  Future<bool> setLayerDeclarations(String projectDir, String featureName,
          Map<String, List<String>> declarations) async =>
      false;

  @override
  Future<List<String>> setLayerDeclarationsForFeatures(String projectDir,
          Map<String, Map<String, List<String>>> declarationsByFeature) async =>
      const [];

  @override
  Future<bool> appendLayerItems(String projectDir, String featureName,
          String layerPath, List<String> items) async =>
      false;

  @override
  Future<bool> removeLayerItem(String projectDir, String featureName,
          String layerPath, String item) async =>
      false;
}

class _FakeStructureRepository implements StructureRepository {
  final StructureDirNode root;
  _FakeStructureRepository(this.root);

  @override
  Future<StructureSnapshot> scan(String projectDir) async =>
      StructureSnapshot(root: root, scannedAt: DateTime(2026, 1, 1));
}

class _FakeArchitectureRepository implements ArchitectureRepository {
  @override
  Future<DependencyStack> getDependencyStack(String architectureId) async =>
      DependencyStack.empty;

  final ArchitectureDefinitionEntity definition;
  _FakeArchitectureRepository(this.definition);

  @override
  Future<ArchitectureDefinitionEntity> getById(String architectureId) async => definition;

  @override
  Future<List<ArchitectureDefinitionEntity>> getAll() async => [definition];

  @override
  Future<String> getRawDefinition(String architectureId) async => '';
}

void main() {
  final msg = JaMessages();

  group('回帰: direct パーミッションの feature が正しく検証される(旧バグ解消)', () {
    // 旧 validate_usecase は 'direct' パーミッションの補償展開を行わず、
    // plan と実構造が完全一致していても missing/extra を誤検知していた
    // (known_bugs_test.dart の v0.6.0 版で実証済み)。
    // 正準モデルは ExpectedStructureBuilder が direct を最初からフラットな
    // トップレベルとして構築するため、この種の食い違いが構造的に発生しない。
    test('direct feature が実構造と一致していれば check はクリーン', () async {
      final arch = const ArchitectureDefinitionEntity(
        id: 'clean_architecture',
        displayName: 'Clean Architecture',
        layers: [LayerDefinitionEntity(name: '1_domain', dirs: ['1_entities'])],
        namingRules: [],
        guides: [],
        dependencies: {},
        devDependencies: {},
        coreModules: [],
      );

      final plan = PlanIntent(
        defaultArchitectureId: 'clean_architecture',
        features: [
          const PlanFeatureIntent(name: 'auth', permission: 'direct'),
        ],
      );

      final snapshot = StructureDirNode({
        'auth': StructureDirNode({
          '1_domain': StructureDirNode({
            '1_entities': StructureDirNode.empty,
          }),
        }),
      });

      final usecase = CheckUsecase(
        planRepo: _FakePlanRepository(plan),
        archRepo: _FakeArchitectureRepository(arch),
        structureRepo: _FakeStructureRepository(snapshot),
        msg: msg,
      );

      final report = await usecase.execute('/tmp/fake');

      expect(report.isClean, isTrue,
          reason: 'direct feature は正準モデルでは常にトップレベル展開されるため一致するはず');
    });
  });

  group('回帰: 命名が非決定的なディレクトリの実ファイルが extra 誤検知されない(旧バグ解消)', () {
    // 旧 diff/validate は plan 側に __files__ が宣言されていない
    // ディレクトリ(usecases 等、ファイル名が非決定的)の実ファイルを
    // 常に extra として誤検知していた。正準モデルは allowRules 方式により、
    // 命名規則に合致するファイルは列挙不要で valid とみなす。
    test('naming rule に合致するファイルは required files が空でも extra にならない',
        () async {
      final arch = const ArchitectureDefinitionEntity(
        id: 'clean_architecture',
        displayName: 'Clean Architecture',
        layers: [LayerDefinitionEntity(name: '1_domain', dirs: ['3_usecases'])],
        namingRules: [
          NamingRuleEntity(
            dirPattern: '1_domain/3_usecases',
            filePattern: r'^.+_usecase\.dart$',
            description: '{verb}_{name}_usecase.dart',
          ),
        ],
        guides: [],
        dependencies: {},
        devDependencies: {},
        coreModules: [],
      );

      final plan = PlanIntent(
        defaultArchitectureId: 'clean_architecture',
        features: [
          const PlanFeatureIntent(name: 'memo', permission: 'user', entities: ['memo']),
        ],
      );

      final snapshot = StructureDirNode({
        'user': StructureDirNode({
          'memo': StructureDirNode({
            '1_domain': StructureDirNode({
              '3_usecases': StructureDirNode({
                'create_memo_usecase.dart': const StructureFileNode(FileKind.source),
                'delete_memo_usecase.dart': const StructureFileNode(FileKind.source),
              }),
            }),
          }),
        }),
      });

      final usecase = CheckUsecase(
        planRepo: _FakePlanRepository(plan),
        archRepo: _FakeArchitectureRepository(arch),
        structureRepo: _FakeStructureRepository(snapshot),
        msg: msg,
      );

      final report = await usecase.execute('/tmp/fake');

      expect(report.extraPaths, isEmpty,
          reason: '命名規則に合致する実装ファイルは非決定的ディレクトリでも正当とみなされるはず');
      expect(report.isClean, isTrue);
    });

    test('naming rule に合致しないファイルは naming violation として検出される', () async {
      final arch = const ArchitectureDefinitionEntity(
        id: 'clean_architecture',
        displayName: 'Clean Architecture',
        layers: [LayerDefinitionEntity(name: '1_domain', dirs: ['3_usecases'])],
        namingRules: [
          NamingRuleEntity(
            dirPattern: '1_domain/3_usecases',
            filePattern: r'^.+_usecase\.dart$',
            description: '{verb}_{name}_usecase.dart',
          ),
        ],
        guides: [],
        dependencies: {},
        devDependencies: {},
        coreModules: [],
      );

      final plan = PlanIntent(
        defaultArchitectureId: 'clean_architecture',
        features: [
          const PlanFeatureIntent(name: 'memo', permission: 'user', entities: ['memo']),
        ],
      );

      final snapshot = StructureDirNode({
        'user': StructureDirNode({
          'memo': StructureDirNode({
            '1_domain': StructureDirNode({
              '3_usecases': StructureDirNode({
                'memo_helper.dart': const StructureFileNode(FileKind.source),
              }),
            }),
          }),
        }),
      });

      final usecase = CheckUsecase(
        planRepo: _FakePlanRepository(plan),
        archRepo: _FakeArchitectureRepository(arch),
        structureRepo: _FakeStructureRepository(snapshot),
        msg: msg,
      );

      final report = await usecase.execute('/tmp/fake');

      expect(report.namingViolations, hasLength(1));
      expect(report.namingViolations.first.filePath,
          'user/memo/1_domain/3_usecases/memo_helper.dart');
    });
  });

  group('回帰: exceptions/ サブディレクトリが専用の命名規則で検証される(旧バグ解消)', () {
    // 旧 validate_usecase は `dirPath.contains('/exceptions')` の場合に
    // 検証を丸ごとスキップしていた。これにより 1_domain/exceptions に
    // 定義された専用ルールも適用されなくなっていた。
    // NameRuleMatcher はパスセグメント末尾一致で最も具体的な規則を選ぶため、
    // スキップなしで正しく検証できる。
    test('1_domain/exceptions は親(存在しない)ではなく自身の規則で検証される', () async {
      final arch = const ArchitectureDefinitionEntity(
        id: 'clean_architecture',
        displayName: 'Clean Architecture',
        layers: [LayerDefinitionEntity(name: '1_domain', dirs: ['exceptions'])],
        namingRules: [
          NamingRuleEntity(
            dirPattern: '1_domain/exceptions',
            filePattern: r'^.+_exceptions?\.dart$|^domain_exceptions\.dart$',
            description: '{name}_exceptions.dart or domain_exceptions.dart',
          ),
        ],
        guides: [],
        dependencies: {},
        devDependencies: {},
        coreModules: [],
      );

      final plan = PlanIntent(
        defaultArchitectureId: 'clean_architecture',
        features: [
          const PlanFeatureIntent(name: 'memo', permission: 'user', entities: ['memo']),
        ],
      );

      final snapshot = StructureDirNode({
        'user': StructureDirNode({
          'memo': StructureDirNode({
            '1_domain': StructureDirNode({
              'exceptions': StructureDirNode({
                'memo_exceptions.dart': const StructureFileNode(FileKind.source),
              }),
            }),
          }),
        }),
      });

      final usecase = CheckUsecase(
        planRepo: _FakePlanRepository(plan),
        archRepo: _FakeArchitectureRepository(arch),
        structureRepo: _FakeStructureRepository(snapshot),
        msg: msg,
      );

      final report = await usecase.execute('/tmp/fake');

      expect(report.isClean, isTrue,
          reason: 'memo_exceptions.dart は 1_domain/exceptions 専用ルールに合致するはず');
    });
  });
}
