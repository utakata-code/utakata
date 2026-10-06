import 'package:path/path.dart' as p;

import '../../1_domain/1_entities/record/impl_plan_meta.dart';
import '../../1_domain/2_repositories/impl_plan_repository.dart';
import '../../1_domain/services/impl_lane.dart';
import '../1_models/impl_plan_front_matter_model.dart';
import '../2_data_sources/1_local/filesystem_data_source.dart';
import '../2_data_sources/1_local/front_matter_data_source.dart';

/// 実装計画をレーン別ディレクトリ(`doc/impl/<lane>/`)で扱う実装。
///
/// `doc/impl/` 配下を**再帰的に**走査するため、v1.6.x までのフラット配置
/// (`doc/impl/*.md`)や人が年別に整理した `archive/2026/` も見つかる
/// (見つからないと ID 採番から漏れて番号を再利用してしまう)。
/// 正しいレーンへの是正は `utakata impl sync` が行う。
class ImplPlanRepositoryImpl implements ImplPlanRepository {
  final FilesystemDataSource _fs;
  final FrontMatterDataSource _frontMatter;

  const ImplPlanRepositoryImpl(this._fs, this._frontMatter);

  // p.join を通す(リテラルの 'doc/impl' を join に渡すと Windows で
  // 区切り文字が混在し、期待パスと実パスの比較が常に不一致になる)。
  static String get _implDir => p.join('doc', 'impl');

  /// `doc/impl/` 配下の全 .md を走査する。
  ///
  /// 読めなかったファイル(frontmatter の構文エラー・必須項目欠落)は
  /// [ImplScanResult.unreadable] に集める — 黙って捨てると一覧から消えた上に
  /// ID が再利用され、既存の計画が上書きされる。
  Future<ImplScanResult> _scan(String projectDir) async {
    final root = p.join(projectDir, _implDir);
    final found = <String, ImplPlanMeta>{};
    final unreadable = <String>[];
    final idToPaths = <String, List<String>>{};

    for (final relative in _fs.listFilesWithSuffix(root, '.md')) {
      final fullPath = p.join(root, relative);
      final projectRelative = p.join(_implDir, relative);
      final content = await _fs.readFile(fullPath);
      if (content == null) continue;

      ImplPlanMeta? meta;
      try {
        final parsed = _frontMatter.parse(content);
        if (parsed.frontMatter.isEmpty) continue; // frontmatter 無し = 対象外
        meta = ImplPlanFrontMatterModel.fromMap(parsed.frontMatter);
      } catch (_) {
        // YAML 構文エラーも型不正もここで受ける(1件のせいで
        // impl コマンドが全滅しないように)
        unreadable.add(projectRelative);
        continue;
      }

      found[projectRelative] = meta;
      idToPaths.putIfAbsent(meta.id, () => []).add(projectRelative);
    }

    final duplicates = {
      for (final entry in idToPaths.entries)
        if (entry.value.length > 1) entry.key: (entry.value..sort()),
    };
    return ImplScanResult(
        byPath: found, unreadable: unreadable..sort(), duplicates: duplicates);
  }

  String _expectedRelativePath(ImplPlanMeta meta) => p.join(
        _implDir,
        ImplLane.ofMeta(meta).dirName,
        meta.fileName,
      );

  @override
  Future<String> nextId(String projectDir) async {
    final scan = await _scan(projectDir);
    final pattern = RegExp(r'^PLAN-(\d+)$');
    var maxSeq = 0;

    for (final meta in scan.byPath.values) {
      final match = pattern.firstMatch(meta.id);
      if (match == null) continue;
      final seq = int.parse(match.group(1)!);
      if (seq > maxSeq) maxSeq = seq;
    }
    // frontmatter が壊れて読めないファイルも、名前から ID を拾って
    // 採番に含める(読めないからといって番号を再利用しない)。
    final fromName = RegExp(r'PLAN-(\d+)_');
    for (final path in scan.unreadable) {
      final match = fromName.firstMatch(p.basename(path));
      if (match == null) continue;
      final seq = int.parse(match.group(1)!);
      if (seq > maxSeq) maxSeq = seq;
    }
    return 'PLAN-${(maxSeq + 1).toString().padLeft(4, '0')}';
  }

  @override
  Future<void> create(String projectDir, ImplPlanMeta meta, String body) async {
    final relative = _expectedRelativePath(meta);
    final path = p.join(projectDir, relative);
    // 既存ファイルを黙って上書きしない(ID が何らかの理由で重複した場合に
    // 他人の計画本文を消さないため)。
    if (_fs.entityExists(path)) {
      throw StateError('implementation plan file already exists: $relative');
    }
    final content = _frontMatter.render(ImplPlanFrontMatterModel.toMap(meta), body);
    await _fs.writeFile(path, content);
  }

  @override
  Future<List<ImplPlanMeta>> listAll(String projectDir) async {
    final scan = await _scan(projectDir);
    return scan.byPath.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  @override
  Future<ImplScanResult> scanAll(String projectDir) => _scan(projectDir);

  @override
  Future<ImplPlanMeta?> findById(String projectDir, String id) async {
    final scan = await _scan(projectDir);
    for (final meta in scan.byPath.values) {
      if (meta.id == id) return meta;
    }
    return null;
  }

  @override
  Future<String?> update(String projectDir, ImplPlanMeta meta) async {
    final scan = await _scan(projectDir);
    final matches = [
      for (final entry in scan.byPath.entries)
        if (entry.value.id == meta.id) entry.key,
    ]..sort();
    if (matches.isEmpty) {
      throw StateError('Implementation plan "${meta.id}" not found');
    }
    if (matches.length > 1) {
      // どれを更新すべきか決められない。黙って一方を選ぶと、もう一方が
      // 移動先で上書きされて消える。
      throw StateError('Implementation plan "${meta.id}" exists in multiple '
          'files (${matches.join(", ")}). Remove the duplicate first.');
    }

    final currentRelative = matches.first;
    final currentPath = p.join(projectDir, currentRelative);
    final content = await _fs.readFile(currentPath);
    if (content == null) {
      throw StateError('Implementation plan "${meta.id}" is unreadable');
    }
    // 本文には触れず frontmatter だけ差し替える
    final parsed = _frontMatter.parse(content);
    final updated =
        _frontMatter.render(ImplPlanFrontMatterModel.toMap(meta), parsed.body);
    await _fs.writeFile(currentPath, updated);

    final expectedRelative = _expectedRelativePath(meta);
    if (p.equals(expectedRelative, currentRelative)) return null;
    await _fs.movePath(currentPath, p.join(projectDir, expectedRelative));
    return expectedRelative;
  }

  @override
  Future<Map<String, ({String actual, String expected})>> detectMisplaced(
      String projectDir) async {
    final scan = await _scan(projectDir);
    final result = <String, ({String actual, String expected})>{};
    for (final entry in scan.byPath.entries) {
      // 重複 ID は移動すると片方が消えるので是正対象にしない(doctor が別途報告)
      if (scan.duplicates.containsKey(entry.value.id)) continue;
      final expected = _expectedRelativePath(entry.value);
      if (!p.equals(entry.key, expected)) {
        result[entry.value.id] = (actual: entry.key, expected: expected);
      }
    }
    return result;
  }

  @override
  Future<ImplSyncResult> sync(String projectDir, {bool dryRun = false}) async {
    final misplaced = await detectMisplaced(projectDir);
    final moved = <String>[];
    final blocked = <String, String>{};

    for (final entry in misplaced.entries) {
      final destination = p.join(projectDir, entry.value.expected);
      if (_fs.entityExists(destination)) {
        // 移動先が埋まっている = 上書きすると相手が消える。人に判断させる。
        blocked[entry.key] = entry.value.expected;
        continue;
      }
      if (!dryRun) {
        await _fs.movePath(p.join(projectDir, entry.value.actual), destination);
      }
      moved.add(entry.key);
    }
    moved.sort();
    return ImplSyncResult(moved: moved, blocked: blocked);
  }
}
