import '../1_entities/record/impl_plan_meta.dart';

/// `enforcement.impl_plan: on` のゲート判定(v1.7.0)。
///
/// 「規模のある feature はコードを書く前に実装計画を作る」という運用を、
/// スキャフォールド時点で機械的に担保する。判定は**feature 単位**で行い、
/// 計画の無い feature だけを止める(`apply` は冪等に全 feature を回すため、
/// 1つ欠けただけで全体を失敗させると実用に耐えない)。
abstract final class ImplPlanGate {
  /// [plans] に、archived でない計画が1つでもあれば「計画あり」とみなす。
  /// `done` でも満たす — 細かすぎる要求は運用を殺すため。
  ///
  /// v1.8.0: feature を対象にする種別(`feat` / `fix`)だけを数える。
  /// `refactor:login` のような計画は login feature の「実装計画」ではないので、
  /// それだけでゲートを通してしまわない。
  static Set<String> featuresWithPlan(Iterable<ImplPlanMeta> plans) => {
        for (final plan in plans)
          if (plan.status != ImplPlanStatus.archived && plan.kind.targetsFeature)
            plan.feature,
      };

  /// 計画が無いために止めるべき feature 名(順序は [featureNames] のまま)。
  static List<String> blocked({
    required bool enforced,
    required Iterable<String> featureNames,
    required Set<String> withPlan,
  }) {
    if (!enforced) return const [];
    return [
      for (final name in featureNames)
        if (!withPlan.contains(name)) name,
    ];
  }
}
