import '../1_entities/plan/plan_intent.dart';

/// 意図レベル計画(`doc/specs/plan.yaml`)の読み書きを行うリポジトリのインターフェース。
///
/// 生成された具象ツリー(旧 plan_architecture.yaml)は扱わない(仕様書 §6)。
abstract interface class PlanRepository {
  /// `doc/specs/plan.yaml` を読む。存在しなければ、旧
  /// `AI/specs/feature_request.yaml` を読み取り専用でフォールバック解釈する
  /// (v0.7 後方互換。ファイルへの書き戻しは行わない)。
  /// どちらも存在しない場合は null を返す。
  Future<PlanIntent?> read(String projectDir);

  /// plan.yaml が存在しなければ新規作成し、意図レベルで書き込む。
  Future<void> write(String projectDir, PlanIntent plan);

  /// feature を、コメント・書式を保持したまま plan.yaml の `features:` 配列へ
  /// 外科的に追記する(`plan adopt` / `feature add`)。
  ///
  /// - 同じ名前の feature が既にあれば何も書かず
  ///   [AdoptFeatureResult.alreadyPlanned] を返す(Issue #34)
  /// - plan.yaml が無いとき、[createIfMissing] が true なら新しく作り、
  ///   false なら何も書かず [AdoptFeatureResult.noPlan] を返す
  /// - `features: []` へは block 形式で書く(flow 形式 `[{...}]` にしない)
  Future<AdoptFeatureResult> adoptFeature(
    String projectDir,
    PlanFeatureIntent feature, {
    bool createIfMissing = true,
  });

  /// [featureName] の `layers` に層宣言をマージして書き込む(Issue #12)。
  /// コメント・書式は保持される。feature が見つからなければ false を返す。
  Future<bool> setLayerDeclarations(
    String projectDir,
    String featureName,
    Map<String, List<String>> declarations,
  );

  /// 複数 feature の `layers` へ層宣言をまとめてマージし、plan.yaml へは
  /// 1 回だけ書き込む(`plan expand`。Issue #28)。途中で失敗した場合は何も
  /// 書かない。plan.yaml に見つかった(書き込んだ)feature 名を返す。
  Future<List<String>> setLayerDeclarationsForFeatures(
    String projectDir,
    Map<String, Map<String, List<String>>> declarationsByFeature,
  );

  /// [layerPath] の宣言へ、まだ無い [items] だけを末尾に追記する(`plan add`。
  /// Issue #29)。既存の項目・コメント・並びは変えない。層の宣言が無ければ
  /// 作る。feature が見つからなければ false を返す。
  Future<bool> appendLayerItems(
    String projectDir,
    String featureName,
    String layerPath,
    List<String> items,
  );

  /// [layerPath] の宣言から [item] を1件削除する。
  /// feature・層宣言・項目のいずれかが無ければ false を返す。
  Future<bool> removeLayerItem(
    String projectDir,
    String featureName,
    String layerPath,
    String item,
  );
}

/// [PlanRepository.adoptFeature] の結果。
enum AdoptFeatureResult {
  /// plan.yaml に追記した(plan.yaml を新しく作った場合も含む)
  added,

  /// 同じ名前の feature が既にあるため追記しなかった
  alreadyPlanned,

  /// plan.yaml が無く、作らない指定だったため何もしなかった
  noPlan,
}
