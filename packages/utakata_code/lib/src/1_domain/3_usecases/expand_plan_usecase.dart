import '../1_entities/architecture_definition_entity.dart';
import '../1_entities/plan/plan_intent.dart';
import '../2_repositories/architecture_repository.dart';
import '../2_repositories/plan_repository.dart';
import '../services/expected_structure_builder.dart';
import '../services/name_rule_matcher.dart';
import 'architecture_definition_entity_resolver.dart';

/// 1 feature 分の展開結果(表示用)。
class ExpandedFeature {
  final String name;

  /// 層パス → 導出された項目リスト
  final Map<String, List<String>> layers;

  /// 既に `layers` 宣言があり、上書きを避けてスキップした層パス
  final List<String> skipped;

  const ExpandedFeature({
    required this.name,
    required this.layers,
    this.skipped = const [],
  });
}

/// `utakata plan expand` — 自動導出されている層構成を plan.yaml に
/// 明示的に書き出す(Issue #12)。
///
/// 「自動生成を基準としつつ、手動での増減も可能にする」ための起点。
/// 書き出したあとは各層のリストを人間/AI が編集でき、`check`/`apply` は
/// その宣言に従う(宣言のない層は従来どおり entities から導出)。
///
/// 書き出す項目は**拡張子込みの完全ファイル名**(Issue #16。例:
/// `todo_entity.dart`)。plan.yaml 上で「見たまま」になり編集しやすく、
/// check/apply([ExpectedStructureBuilder])と同一の導出を共有するため
/// 食い違いも起きない(`.dart` で終わる項目はリテラル扱いされる)。
///
/// 命名が非決定的な層(`{verb}` を含む usecases 等)は、導出だけでは
/// ファイル名を決められないため**書き出さない**。それらは
/// `utakata plan add <feature> <layer> <item>` で明示的に追加する。
class ExpandPlanUsecase {
  final PlanRepository _planRepo;
  final ArchitectureRepository _archRepo;

  const ExpandPlanUsecase({
    required PlanRepository planRepo,
    required ArchitectureRepository archRepo,
  })  : _planRepo = planRepo,
        _archRepo = archRepo;

  /// [dryRun] が true の場合は書き込まず、結果だけを返す。
  Future<List<ExpandedFeature>> execute(
    String projectDir, {
    bool dryRun = false,
    String? onlyFeature,
  }) async {
    final plan = await _planRepo.read(projectDir);
    if (plan == null) return const [];

    final architectures = await resolveArchitectures(plan, _archRepo);
    final results = <ExpandedFeature>[];
    final toWrite = <String, Map<String, List<String>>>{};

    for (final feature in plan.features) {
      if (onlyFeature != null && feature.name != onlyFeature) continue;
      final archId = feature.architectureId ?? plan.defaultArchitectureId;
      final arch = architectures[archId];
      if (arch == null) continue;

      final derived = <String, List<String>>{};
      final skipped = <String>[];
      for (final layerPath in _leafLayerPaths(arch)) {
        // 既に宣言済みの層は人間の編集結果なので上書きしない
        if (feature.declarationFor(layerPath) != null) {
          skipped.add(layerPath);
          continue;
        }
        final items = _deriveItems(arch, layerPath, feature);
        if (items == null) continue; // 非決定的な層は書き出さない
        derived[layerPath] = items;
      }

      if (derived.isNotEmpty) toWrite[feature.name] = derived;

      results.add(ExpandedFeature(
        name: feature.name,
        layers: derived,
        skipped: skipped,
      ));
    }

    // 全 feature 分をまとめて 1 回で書く(途中で失敗しても plan.yaml を
    // 一部だけ書き換えた状態で残さない。Issue #28)
    if (!dryRun && toWrite.isNotEmpty) {
      await _planRepo.setLayerDeclarationsForFeatures(projectDir, toWrite);
    }

    return results;
  }

  /// アーキテクチャ定義の末端ディレクトリ(ファイルを置く階層)のパス一覧。
  static List<String> _leafLayerPaths(ArchitectureDefinitionEntity arch) => [
        for (final layer in arch.layers)
          for (final dir in layer.dirs) '${layer.name}/$dir',
      ];

  /// その層に置くべき完全ファイル名(拡張子込み)を導出する(Issue #16)。
  /// 命名が非決定的(`{verb}` / 選択肢あり)な層では null を返す。
  static List<String>? _deriveItems(
    ArchitectureDefinitionEntity arch,
    String layerPath,
    PlanFeatureIntent feature,
  ) {
    final rule = NameRuleMatcher.findFor(layerPath, arch.namingRules);
    if (rule == null) return null;

    final names = ExpectedStructureBuilder.resolveFileNames(rule, feature);
    if (names.isEmpty) return null;
    return names.toList()..sort();
  }
}
