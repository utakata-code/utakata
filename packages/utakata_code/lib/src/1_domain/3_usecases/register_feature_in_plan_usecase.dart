import '../1_entities/plan/plan_intent.dart';
import '../2_repositories/plan_repository.dart';
import 'create_required_files_usecase.dart';

/// `feature add` で作った feature を plan.yaml に載せ、その feature の
/// 必須ファイルを作るユースケース(Issue #34)。
///
/// `feature add` の直後に `check` が通るようにするためのもの。plan.yaml に
/// 同じ名前の feature が既にあれば追記はせず、plan.yaml 側の宣言をもとに
/// 必須ファイルだけを作る。
class RegisterFeatureInPlanUsecase {
  final PlanRepository _planRepo;
  final CreateRequiredFilesUsecase _requiredFiles;

  const RegisterFeatureInPlanUsecase({
    required PlanRepository planRepo,
    required CreateRequiredFilesUsecase requiredFiles,
  })  : _planRepo = planRepo,
        _requiredFiles = requiredFiles;

  /// [createPlanIfMissing] が false なら、plan.yaml が無いプロジェクトでは
  /// 何もしない(plan.yaml を新しく作らない。旧来のプロジェクトとの互換)。
  Future<RegisterFeatureResult> execute(
    String projectDir,
    PlanFeatureIntent feature, {
    bool createPlanIfMissing = false,
  }) async {
    final adopt = await _planRepo.adoptFeature(projectDir, feature,
        createIfMissing: createPlanIfMissing);
    if (adopt == AdoptFeatureResult.noPlan) {
      return const RegisterFeatureResult(AdoptFeatureResult.noPlan);
    }

    final plan = await _planRepo.read(projectDir);
    if (plan == null) return RegisterFeatureResult(adopt);
    final created =
        await _requiredFiles.executeForFeature(projectDir, plan, feature.name);
    return RegisterFeatureResult(adopt, createdFiles: created);
  }
}

class RegisterFeatureResult {
  final AdoptFeatureResult adopt;

  /// 今回生成した必須ファイルのプロジェクト相対パス。
  final List<String> createdFiles;

  const RegisterFeatureResult(this.adopt, {this.createdFiles = const []});
}
