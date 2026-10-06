import '../1_entities/record/impl_plan_meta.dart';

/// feature 実装計画書(`doc/impl/<lane>/PLAN-*.md`)の読み書きを行う
/// リポジトリのインターフェース。frontmatter のみ機械管理する(仕様書 §8)。
///
/// v1.7.0 からファイルは状態に応じた**レーン**(サブディレクトリ)に置かれる。
/// 正は frontmatter であり、配置はそこから導出される([ImplLane])。
abstract interface class ImplPlanRepository {
  /// 次の `PLAN-NNNN`。**archive も含む全レーン**の最大連番 + 1
  /// (archive を無視すると、アーカイブ後に ID を再利用してしまう)。
  Future<String> nextId(String projectDir);

  /// [body] は §1〜§8 のテンプレート本文(Markdown)。
  Future<void> create(String projectDir, ImplPlanMeta meta, String body);

  /// 全レーンの計画を返す(archive を含む)。
  Future<List<ImplPlanMeta>> listAll(String projectDir);

  Future<ImplPlanMeta?> findById(String projectDir, String id);

  /// frontmatter を更新し、**続けて正しいレーンへ移動する**。
  /// 移動が起きた場合は移動先の相対パスを返す(起きなければ null)。
  ///
  /// [logEntry] を渡すと、本文の記録領域([ImplPlanBody.marker] より下)に
  /// 1 件追記する(v1.8.0)。計画部分には触れない。
  Future<String?> update(String projectDir, ImplPlanMeta meta,
      {String? logEntry});

  /// 本文(frontmatter を除いた Markdown)をそのまま返す(v1.8.0)。
  /// 凍結後の変更検知と `note` の追記位置の判定に使う。
  Future<String> readBody(String projectDir, String id);

  /// 走査の生結果(読めなかったファイル・重複 ID を含む)。
  Future<ImplScanResult> scanAll(String projectDir);

  /// frontmatter とファイル配置の乖離を検出する。
  /// 返り値は「ID → (現在の相対パス, あるべき相対パス)」。
  Future<Map<String, ({String actual, String expected})>> detectMisplaced(
      String projectDir);

  /// [detectMisplaced] の結果に従ってファイルを移動する。
  Future<ImplSyncResult> sync(String projectDir, {bool dryRun = false});
}

/// `doc/impl/` 走査の結果。
final class ImplScanResult {
  /// プロジェクト相対パス → メタ
  final Map<String, ImplPlanMeta> byPath;

  /// frontmatter が読めなかったファイル(相対パス)。
  /// 一覧から消えるだけでなく ID 再利用の温床になるので、必ず報告する。
  final List<String> unreadable;

  /// 同じ ID を持つファイルが複数ある場合の「ID → パス一覧」。
  final Map<String, List<String>> duplicates;

  const ImplScanResult({
    this.byPath = const {},
    this.unreadable = const [],
    this.duplicates = const {},
  });

  bool get isHealthy => unreadable.isEmpty && duplicates.isEmpty;
}

/// `impl sync` の結果。
final class ImplSyncResult {
  /// 移動した(dry-run なら移動予定の)計画 ID。
  final List<String> moved;

  /// 移動先が既に埋まっていて移動できなかった「ID → 移動先」。
  /// 上書きすると相手の本文が消えるため、人の判断に委ねる。
  final Map<String, String> blocked;

  const ImplSyncResult({this.moved = const [], this.blocked = const {}});
}
