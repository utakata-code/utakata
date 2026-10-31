import 'package:test/test.dart';
import 'package:utakata/src/1_domain/1_entities/dependency_stack_entity.dart';
import 'package:utakata/src/1_domain/1_entities/architecture_definition_entity.dart';
import 'package:utakata/src/1_domain/1_entities/plan/plan_intent.dart';
import 'package:utakata/src/1_domain/1_entities/template_file_entity.dart';
import 'package:utakata/src/1_domain/2_repositories/architecture_repository.dart';
import 'package:utakata/src/1_domain/2_repositories/plan_repository.dart';
import 'package:utakata/src/1_domain/2_repositories/template_repository.dart';
import 'package:utakata/src/1_domain/3_usecases/add_feature_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/apply_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/generate_core_usecase.dart';
import 'package:utakata/src/1_domain/messages/ja_messages.dart';

/// Issue #19: `utakata apply` は必須ファイルを空ファイルとして生成する。
void main() {
  const arch = ArchitectureDefinitionEntity(
    id: 'clean_architecture',
    displayName: 'Clean Architecture',
    layers: [
      LayerDefinitionEntity(name: '1_domain', dirs: ['1_entities', '3_usecases']),
      LayerDefinitionEntity(name: '4_presentation', dirs: ['2_pages']),
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
        dirPattern: '4_presentation/2_pages',
        filePattern: r'^.+_page\.dart$',
        description: '{feature}_page.dart',
      ),
    ],
  );

  late Set<String> existingFiles;
  late Map<String, String> writtenFiles;
  late _FakePlanRepo planRepo;
  late ApplyUsecase usecase;

  setUp(() {
    existingFiles = {};
    writtenFiles = {};
    planRepo = _FakePlanRepo();
    final archRepo = _FixedArchRepo(arch);
    usecase = ApplyUsecase(
      planRepo: planRepo,
      archRepo: archRepo,
      addFeatureUsecase: AddFeatureUsecase(
        archRepo: archRepo,
        templateRepo: _EmptyTemplateRepo(),
        msg: const JaMessages(),
        writeFile: (path, content) async => writtenFiles[path] = content,
        ensureDir: (path) async {},
      ),
      generateCoreUsecase: GenerateCoreUsecase(
        archRepo: archRepo,
        ensureDir: (path) async {},
        readFile: (path) async => null,
      ),
      fileExists: (path) => existingFiles.contains(path),
      writeFile: (path, content) async => writtenFiles[path] = content,
    );
  });

  PlanIntent planWith(PlanFeatureIntent feature) => PlanIntent(
      defaultArchitectureId: 'clean_architecture', features: [feature]);

  test('決定的な必須ファイルを空ファイルとして生成する', () async {
    planRepo.plan = planWith(const PlanFeatureIntent(
        name: 'todo', permission: 'user', entities: ['todo']));

    final result = await usecase.execute('/proj', scope: 'feature');

    expect(
        result.createdFiles,
        containsAll([
          'lib/features/user/todo/1_domain/1_entities/todo_entity.dart',
          'lib/features/user/todo/4_presentation/2_pages/todo_page.dart',
        ]));
    // 非決定的な層({verb})のファイルは生成しない
    expect(result.createdFiles.where((f) => f.contains('3_usecases')), isEmpty);
    // 実際に空文字で書かれている
    expect(
        writtenFiles[
            '/proj/lib/features/user/todo/1_domain/1_entities/todo_entity.dart'],
        '');
  });

  test('layers 宣言で明示した項目は非決定的な層でも生成する', () async {
    planRepo.plan = planWith(const PlanFeatureIntent(
      name: 'todo',
      permission: 'user',
      entities: ['todo'],
      layers: {'1_domain/3_usecases': ['get_todo_usecase.dart']},
    ));

    final result = await usecase.execute('/proj', scope: 'feature');

    expect(result.createdFiles,
        contains('lib/features/user/todo/1_domain/3_usecases/get_todo_usecase.dart'));
  });

  test('既存ファイルは上書きせずスキップする', () async {
    existingFiles.add('/proj/lib/features/user/todo/1_domain/1_entities/todo_entity.dart');
    planRepo.plan = planWith(const PlanFeatureIntent(
        name: 'todo', permission: 'user', entities: ['todo']));

    final result = await usecase.execute('/proj', scope: 'feature');

    expect(result.createdFiles,
        isNot(contains('lib/features/user/todo/1_domain/1_entities/todo_entity.dart')));
    expect(
        writtenFiles.containsKey(
            '/proj/lib/features/user/todo/1_domain/1_entities/todo_entity.dart'),
        isFalse);
  });

  test('空リスト宣言(不要な層)のファイルは生成しない', () async {
    planRepo.plan = planWith(const PlanFeatureIntent(
      name: 'todo',
      permission: 'user',
      entities: ['todo'],
      layers: {'4_presentation': []},
    ));

    final result = await usecase.execute('/proj', scope: 'feature');

    expect(result.createdFiles.where((f) => f.contains('4_presentation')), isEmpty);
  });

  test('パス区切りを含む layers 項目は無視する(check と解釈が食い違うため)', () async {
    planRepo.plan = planWith(const PlanFeatureIntent(
      name: 'todo',
      permission: 'user',
      entities: ['todo'],
      layers: {'1_domain/1_entities': ['config/todo_settings.dart']},
    ));

    final result = await usecase.execute('/proj', scope: 'feature');

    expect(result.createdFiles.where((f) => f.contains('config/')), isEmpty);
  });

  test('dry-run では書き込まず、生成予定のみ返す', () async {
    planRepo.plan = planWith(const PlanFeatureIntent(
        name: 'todo', permission: 'user', entities: ['todo']));

    final result = await usecase.execute('/proj', scope: 'feature', dryRun: true);

    expect(result.createdFiles, isNotEmpty);
    expect(writtenFiles, isEmpty);
  });
}

class _FakePlanRepo implements PlanRepository {
  PlanIntent? plan;

  @override
  Future<PlanIntent?> read(String projectDir) async => plan;

  @override
  Future<void> write(String projectDir, PlanIntent plan) =>
      throw UnimplementedError();

  @override
  Future<AdoptFeatureResult> adoptFeature(
          String projectDir, PlanFeatureIntent feature,
          {bool createIfMissing = true}) =>
      throw UnimplementedError();

  @override
  Future<bool> setLayerDeclarations(String projectDir, String featureName,
          Map<String, List<String>> declarations) =>
      throw UnimplementedError();

  @override
  Future<List<String>> setLayerDeclarationsForFeatures(String projectDir,
          Map<String, Map<String, List<String>>> declarationsByFeature) =>
      throw UnimplementedError();

  @override
  Future<bool> appendLayerItems(String projectDir, String featureName,
          String layerPath, List<String> items) =>
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

class _EmptyTemplateRepo implements TemplateRepository {
  @override
  Future<List<TemplateFileEntity>> getFeatureTemplates(
          String architectureId) async =>
      const [];

  @override
  Future<List<TemplateFileEntity>> getProjectTemplates(
          String architectureId) async =>
      const [];
}
