import '../1_entities/feature_spec_entity.dart';
import '../1_entities/plan/plan_intent.dart';
import '../2_repositories/feature_template_repository.dart';
import '../messages/cli_messages.dart';
import 'add_feature_usecase.dart';
import 'register_feature_in_plan_usecase.dart';

/// `utakata feature add <name> --template <id>` — feature プリセットの適用
/// (仕様書 §10)。
///
/// 構造の生成(AddFeatureUsecase)と plan.yaml への意図追記
/// (PlanRepository.adoptFeature)、その feature の必須ファイルの生成を
/// 1回の呼び出しでまとめて行う(適用直後から check がクリーンになるように
/// するため)。plan.yaml に同じ名前の feature が既にあれば追記しない
/// (Issue #34)。
class ApplyFeatureTemplateUsecase {
  final FeatureTemplateRepository _templateRepo;
  final AddFeatureUsecase _addFeatureUsecase;
  final RegisterFeatureInPlanUsecase _registerUsecase;
  final CliMessages _msg;

  const ApplyFeatureTemplateUsecase({
    required FeatureTemplateRepository templateRepo,
    required AddFeatureUsecase addFeatureUsecase,
    required RegisterFeatureInPlanUsecase registerUsecase,
    required CliMessages msg,
  })  : _templateRepo = templateRepo,
        _addFeatureUsecase = addFeatureUsecase,
        _registerUsecase = registerUsecase,
        _msg = msg;

  Future<(FeatureSpecEntity, RegisterFeatureResult)> execute(
    String projectDir,
    String featureName,
    String templateId, {
    String architectureId = 'clean_architecture',
  }) async {
    final manifest = await _templateRepo.resolve(projectDir, templateId);
    if (manifest == null) {
      throw Exception(_msg.templateNotFound(templateId));
    }

    final entityName = manifest.entities.isNotEmpty ? manifest.entities.first : featureName;
    final spec = FeatureSpecEntity(
      featureName: featureName,
      entityName: entityName,
      permission: manifest.permission,
      architectureId: architectureId,
    );

    await _addFeatureUsecase.execute(projectDir, spec);
    // テンプレート適用は従来どおり plan.yaml が無ければ作る
    final registration = await _registerUsecase.execute(
      projectDir,
      PlanFeatureIntent(
        name: featureName,
        permission: manifest.permission,
        entities: manifest.entities.isNotEmpty ? manifest.entities : [featureName],
        architectureId: architectureId,
      ),
      createPlanIfMissing: true,
    );

    return (spec, registration);
  }
}
