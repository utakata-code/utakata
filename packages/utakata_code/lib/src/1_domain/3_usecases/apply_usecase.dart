import 'package:path/path.dart' as p;

import '../1_entities/feature_spec_entity.dart';
import '../2_repositories/architecture_repository.dart';
import '../2_repositories/plan_repository.dart';
import 'add_feature_usecase.dart';
import 'create_required_files_usecase.dart';
import 'generate_core_usecase.dart';

/// `utakata apply` — plan.yaml から未生成の feature/core を作成するユースケース。
///
/// 旧 `feature init`(InitFeaturesUsecase)+ `core`(GenerateCoreUsecase)を
/// 統合する。check と同じ「plan.yaml の意図」を入力にするため、
/// 生成すべき内容が check の期待値と食い違うことがなくなる
/// (旧 `feature init` が plan_architecture.yaml の `__files__` を無視する
/// バグのクラスを構造的に解消する)。
///
/// ディレクトリに加えて、check が必須と判定するファイル
/// ([CreateRequiredFilesUsecase])を**空ファイルとして生成**する
/// (Issue #19)。命名だけでなく「ファイルの存在自体」を plan.yaml から
/// 決定論的にコントロールできる。既存ファイルは一切上書きしない。
class ApplyUsecase {
  final PlanRepository _planRepo;
  final ArchitectureRepository _archRepo;
  final AddFeatureUsecase _addFeatureUsecase;
  final GenerateCoreUsecase _generateCoreUsecase;

  final bool Function(String path) _fileExists;
  final Future<void> Function(String path, String content) _writeFile;

  /// `enforcement.impl_plan: on` のゲート(v1.7.0)。
  /// 「実装計画のある feature 名」を返す。**null を返せばゲートしない**
  /// (未注入も同じ)。設定が off のときは null を返す実装を注入する。
  final Future<Set<String>?> Function(String projectDir)? _featuresWithPlan;

  const ApplyUsecase({
    required PlanRepository planRepo,
    required ArchitectureRepository archRepo,
    required AddFeatureUsecase addFeatureUsecase,
    required GenerateCoreUsecase generateCoreUsecase,
    required bool Function(String path) fileExists,
    required Future<void> Function(String path, String content) writeFile,
    Future<Set<String>?> Function(String projectDir)? featuresWithPlan,
  })  : _planRepo = planRepo,
        _archRepo = archRepo,
        _addFeatureUsecase = addFeatureUsecase,
        _generateCoreUsecase = generateCoreUsecase,
        _fileExists = fileExists,
        _writeFile = writeFile,
        _featuresWithPlan = featuresWithPlan;

  /// [scope]: 'all' | 'feature' | 'core'
  Future<ApplyResult> execute(
    String projectDir, {
    String scope = 'all',
    bool dryRun = false,
  }) async {
    final plan = await _planRepo.read(projectDir);

    final features = <FeatureSpecEntity>[];
    final blocked = <String>[];
    final blockedPaths = <String>[];
    var createdFiles = const <String>[];
    if ((scope == 'all' || scope == 'feature') && plan != null) {
      // 実装計画ゲート(enforcement.impl_plan)。**新規に作る feature だけ**を
      // 対象にする — 既にディスクにあるものは「これから実装を始める」わけでは
      // ないため。
      final withPlan = await _featuresWithPlan?.call(projectDir);

      for (final feature in plan.features) {
        final spec = FeatureSpecEntity(
          featureName: feature.name,
          entityName: feature.entities.isNotEmpty ? feature.entities.first : feature.name,
          permission: feature.permission,
          architectureId: feature.architectureId ?? plan.defaultArchitectureId,
          // plan.yaml で不要と宣言された層は生成しない(Issue #12)
          optedOutLayers: {
            for (final entry in feature.layers.entries)
              if (entry.value.isEmpty) entry.key,
          },
        );

        final alreadyScaffolded =
            _fileExists(p.join(projectDir, spec.relativePath));
        if (withPlan != null &&
            !alreadyScaffolded &&
            !withPlan.contains(feature.name)) {
          blocked.add(feature.name);
          blockedPaths.add(spec.relativePath);
          continue;
        }

        features.add(spec);
        if (!dryRun) {
          await _addFeatureUsecase.execute(projectDir, spec);
        }
      }

      // 必須ファイルの生成は feature add と共有する(Issue #34)
      createdFiles = await CreateRequiredFilesUsecase(
        archRepo: _archRepo,
        fileExists: _fileExists,
        writeFile: _writeFile,
      ).execute(projectDir, plan,
          dryRun: dryRun, skipPathPrefixes: blockedPaths);
    }

    var coreModulePaths = const <String>[];
    if ((scope == 'all' || scope == 'core') && plan != null && !dryRun) {
      coreModulePaths =
          await _generateCoreUsecase.execute(projectDir, plan.defaultArchitectureId);
    }

    return ApplyResult(
      features: features,
      coreModulePaths: coreModulePaths,
      createdFiles: createdFiles,
      blockedFeatures: blocked,
    );
  }
}

class ApplyResult {
  final List<FeatureSpecEntity> features;
  final List<String> coreModulePaths;

  /// 今回生成した(dry-run 時は生成予定の)必須ファイルのプロジェクト相対パス。
  final List<String> createdFiles;

  /// 実装計画が無いため生成しなかった feature 名(enforcement.impl_plan)。
  final List<String> blockedFeatures;

  const ApplyResult({
    required this.features,
    required this.coreModulePaths,
    this.createdFiles = const [],
    this.blockedFeatures = const [],
  });
}
