import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../1_domain/1_entities/config/utakata_config_entity.dart';
import '../../1_domain/2_repositories/config_repository.dart';
import '../../1_domain/2_repositories/vault_repository.dart';
import '../2_data_sources/2_remote/git_data_source.dart';

/// [VaultRepository] の実装。
///
/// Vault の解決順:
///   1. プロジェクトの `utakata.yaml` の `vault:`
///   2. `~/.utakata/config.yaml` の `vault:`(全案件共通。通常はこちら)
///   3. 未設定 → null(vault 機能はオフ)
///
/// `path` の解決規則(Issue #18):
///   - 絶対パス・`~` 始まりはそのまま(`~` はホーム展開)
///   - 相対パスは**書かれた設定ファイルの場所**から解決する:
///     プロジェクトの `utakata.yaml` ならプロジェクトルート、
///     `~/.utakata/config.yaml` なら `~/.utakata/`
///     (以前は実行時のカレントディレクトリ基準だったため、どのプロジェクト
///     から実行するかで挙動が変わっていた)
///
/// 参照先の解決順:
///   1. `path`(手元のクローン)が存在すればそれを使う — 自分で書き足す
///      個人資産なので、編集が即座に反映されるこちらを優先する
///   2. `url` のフェッチ済みキャッシュ(`~/.utakata/cache/vault/<hash>/`)
class VaultRepositoryImpl implements VaultRepository {
  final ConfigRepository _configRepo;
  final GitDataSource _git;
  final String _homeDir;

  const VaultRepositoryImpl(this._configRepo, this._git, this._homeDir);

  /// ルート直下にある「Vault 自体の説明ファイル」(一覧に出さない)。
  ///
  /// ネストした `README.md`(例: `Google/GCP/README.md` の共通前提知識)は
  /// 実体のあるエントリなので**除外しない**。
  static const _rootOnlyExcludedNames = {'README.md', 'CLAUDE.md'};

  /// Vault 参照と、相対 `path` を解決する基準ディレクトリの組を返す。
  Future<(VaultRef, String)?> _resolveRef(String projectDir) async {
    final fromProject = (await _configRepo.read(projectDir))?.vault;
    if (fromProject != null && !fromProject.isEmpty) {
      return (fromProject, projectDir);
    }
    final fromGlobal = (await _configRepo.readGlobal())?.vault;
    if (fromGlobal != null && !fromGlobal.isEmpty) {
      return (fromGlobal, p.join(_homeDir, '.utakata'));
    }
    return null;
  }

  String _expandHome(String path) =>
      path.startsWith('~') ? p.join(_homeDir, path.substring(1).replaceFirst(RegExp(r'^[/\\]'), '')) : path;

  /// `path` 設定値を絶対パスへ解決する。相対パスは [baseDir]
  /// (その設定が書かれたファイルの場所)基準。
  String _resolvePath(String rawPath, String baseDir) {
    final expanded = _expandHome(rawPath);
    if (p.isAbsolute(expanded)) return p.normalize(expanded);
    return p.normalize(p.join(baseDir, expanded));
  }

  String _cacheDirFor(String url) {
    // 依存を増やさないため FNV-1a 64bit をディレクトリ名の分離のみに使う。
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(url)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    final key = hash.toRadixString(16).padLeft(16, '0').substring(0, 12);
    return p.join(_homeDir, '.utakata', 'cache', 'vault', key);
  }

  @override
  Future<String?> resolveRoot(String projectDir) async {
    final resolved = await _resolveRef(projectDir);
    if (resolved == null) return null;
    final (ref, baseDir) = resolved;

    final localPath = ref.path;
    if (localPath != null && localPath.isNotEmpty) {
      final dir = _resolvePath(localPath, baseDir);
      if (Directory(dir).existsSync()) return dir;
    }

    final url = ref.url;
    if (url != null && url.isNotEmpty) {
      final cached = p.join(_cacheDirFor(url), 'repo');
      if (Directory(cached).existsSync()) return cached;
    }

    return null;
  }

  /// `url` の Vault を取得(または再取得)してキャッシュに置く。
  /// 取得したパスを返す。`url` 未設定なら null。
  Future<String?> fetch(String projectDir) async {
    final resolved = await _resolveRef(projectDir);
    final ref = resolved?.$1;
    final url = ref?.url;
    if (url == null || url.isEmpty) return null;

    // 一時フォルダーに取ってから差し替える。失敗しても前回の取得結果は残る
    // (Issue #32)。
    final repoDir = p.join(_cacheDirFor(url), 'repo');
    await _git.cloneDepth1Replacing(url, ref?.ref, repoDir);
    return repoDir;
  }

  @override
  Future<List<VaultEntry>> list(String projectDir) async {
    final root = await resolveRoot(projectDir);
    if (root == null) return const [];

    final entries = <VaultEntry>[];
    for (final entity in Directory(root).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final relative = p.relative(entity.path, from: root);
      final segments = p.split(relative);
      if (segments.any((s) => s.startsWith('.'))) continue;
      // `_template.md` のような雛形はどの階層でも除外する
      if (p.basename(relative).startsWith('_')) continue;
      if (segments.length == 1 && _rootOnlyExcludedNames.contains(segments.first)) {
        continue;
      }

      entries.add(VaultEntry(
        id: relative.substring(0, relative.length - '.md'.length),
        title: _titleOf(entity),
      ));
    }
    entries.sort((a, b) => a.id.compareTo(b.id));
    return entries;
  }

  String _titleOf(File file) {
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('# ')) return line.substring(2).trim();
    }
    return p.basenameWithoutExtension(file.path);
  }

  @override
  Future<String?> read(String projectDir, String entryId) async {
    final root = await resolveRoot(projectDir);
    if (root == null) return null;

    final normalized = entryId.endsWith('.md') ? entryId : '$entryId.md';
    // Vault の外に出るパスは拒否する
    final target = p.normalize(p.join(root, normalized));
    if (!p.isWithin(root, target)) return null;

    final file = File(target);
    return file.existsSync() ? file.readAsString() : null;
  }
}
