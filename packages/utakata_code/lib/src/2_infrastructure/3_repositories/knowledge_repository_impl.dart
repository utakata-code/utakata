import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../1_domain/1_entities/config/knowledge_lock.dart';
import '../../1_domain/1_entities/config/utakata_config_entity.dart';
import '../../1_domain/2_repositories/knowledge_repository.dart';
import '../2_data_sources/1_local/yaml_data_source.dart';
import '../2_data_sources/2_remote/git_data_source.dart';

/// [KnowledgeRepository] の実装。
///
/// キャッシュ配置: `~/.utakata/cache/knowledge/<urlハッシュ12桁>/`
///   - `repo/`                — 直近 clone(使い捨て)
///   - `materialized-<sha>/`  — 同梱テンプレートと同じ
///     `architectures/<id>/...` 形式へ変換したツリー(解決はここを見る)
class KnowledgeRepositoryImpl implements KnowledgeRepository {
  final GitDataSource _git;
  final YamlDataSource _yaml;
  final String _homeDir;

  const KnowledgeRepositoryImpl(this._git, this._yaml, this._homeDir);

  static const _lockFileName = 'utakata.lock';

  String _cacheRoot(String url) {
    // 依存を増やさないため FNV-1a 64bit をハッシュに使う(セキュリティ目的ではなく
    // キャッシュディレクトリ名の分離のみが目的)。
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(url)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    final key = hash.toRadixString(16).padLeft(16, '0').substring(0, 12);
    return p.join(_homeDir, '.utakata', 'cache', 'knowledge', key);
  }

  @override
  Future<KnowledgeLock?> readLock(String projectDir) async {
    final file = File(p.join(projectDir, _lockFileName));
    if (!file.existsSync()) return null;
    final doc = _yaml.parse(await file.readAsString(), source: file.path);
    return KnowledgeLock.fromMap(doc);
  }

  @override
  Future<String?> materializedRoot(String projectDir) async {
    final lock = await readLock(projectDir);
    if (lock == null) return null;
    final dir = p.join(_cacheRoot(lock.url), 'materialized-${lock.sha}');
    return Directory(dir).existsSync() ? dir : null;
  }

  @override
  Future<String?> ensureDefaultAvailable({bool autoFetch = true}) async {
    const url = KnowledgeRepository.defaultUrl;
    const ref = KnowledgeRepository.defaultRef;
    final cacheRoot = _cacheRoot(url);

    // タグ→SHA のマーカー。存在すれば追加のネットワークアクセスなしで解決する。
    final markerFile = File(p.join(cacheRoot, 'default-$ref.sha'));
    if (markerFile.existsSync()) {
      final sha = markerFile.readAsStringSync().trim();
      final materialized = Directory(p.join(cacheRoot, 'materialized-$sha'));
      if (materialized.existsSync()) return materialized.path;
    }

    if (!autoFetch) return null;

    stderr.writeln('📥 公式ナレッジ(utakata_arch_lib @ $ref)を取得しています…');
    try {
      final repoDir = Directory(p.join(cacheRoot, 'repo'));
      // 一時フォルダーに取ってから差し替える(失敗時は前回の repo/ を残す。Issue #32)
      await _git.cloneDepth1Replacing(url, ref, repoDir.path);
      final sha = await _git.revParseHead(repoDir.path);

      final materialized = Directory(p.join(cacheRoot, 'materialized-$sha'));
      if (!materialized.existsSync()) {
        _materialize(Directory(p.join(repoDir.path, 'arches')), materialized);
      }
      markerFile.writeAsStringSync('$sha\n');
      return materialized.path;
    } catch (e) {
      stderr.writeln('⚠️  取得できませんでした(オフライン?): $e');
      stderr.writeln('   構造コマンド(create/apply/check 等)は影響を受けません。'
          'ガイドの参照にはネットワークと git が必要です。');
      return null;
    }
  }

  @override
  Future<KnowledgeFetchResult> fetch(
    String projectDir,
    KnowledgeRepoRef repoRef, {
    bool update = false,
  }) async {
    final existingLock = await readLock(projectDir);

    if (!update && existingLock != null && existingLock.url == repoRef.url) {
      final cached = await materializedRoot(projectDir);
      if (cached != null) {
        return KnowledgeFetchResult(lock: existingLock, refetched: false);
      }
    }

    final cacheRoot = _cacheRoot(repoRef.url);
    final repoDir = Directory(p.join(cacheRoot, 'repo'));
    // 一時フォルダーに取ってから差し替える(失敗時は前回の repo/ を残す。Issue #32)
    await _git.cloneDepth1Replacing(repoRef.url, repoRef.ref, repoDir.path);
    final sha = await _git.revParseHead(repoDir.path);

    final materialized = Directory(p.join(cacheRoot, 'materialized-$sha'));
    if (!materialized.existsSync()) {
      _materialize(Directory(p.join(repoDir.path, 'arches')), materialized);
    }

    final lock = KnowledgeLock(
      url: repoRef.url,
      ref: repoRef.ref ?? '',
      sha: sha,
      fetchedAt: DateTime.now().toUtc().toIso8601String(),
    );
    File(p.join(projectDir, _lockFileName)).writeAsStringSync(lock.toYaml());

    return KnowledgeFetchResult(
      lock: lock,
      previousSha: existingLock?.sha == sha ? null : existingLock?.sha,
      refetched: true,
    );
  }

  /// arch_lib の `arches/<id>/` を同梱テンプレートと同じ
  /// `architectures/<id>/` 形式へ変換する(tool/sync_arch_lib.dart と同じ規則)。
  void _materialize(Directory archesDir, Directory target) {
    if (!archesDir.existsSync()) {
      throw Exception('取得したリポジトリに arches/ がありません'
          '(utakata_arch_lib 互換構造ではありません): ${archesDir.path}');
    }
    for (final entry in archesDir.listSync().whereType<Directory>()) {
      final id = p.basename(entry.path);
      if (id.startsWith('_') || id.startsWith('.')) continue;
      final archTarget = Directory(p.join(target.path, 'architectures', id));
      for (final entity in entry.listSync(recursive: true)) {
        final relative = p.relative(entity.path, from: entry.path);
        if (p.split(relative).any((s) => s.startsWith('.git'))) continue;
        final targetPath = p.join(archTarget.path, relative);
        if (entity is Directory) {
          Directory(targetPath).createSync(recursive: true);
        } else if (entity is File) {
          File(targetPath).parent.createSync(recursive: true);
          if (relative == 'arch_definition.yaml') {
            final content = entity.readAsStringSync().replaceAll(
                  RegExp(r'detail_content_path:\s*"(?!architectures/)'),
                  'detail_content_path: "architectures/$id/',
                );
            File(targetPath).writeAsStringSync(content);
          } else {
            entity.copySync(targetPath);
          }
        }
      }
    }
  }
}
