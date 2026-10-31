import 'dart:io';

import 'package:path/path.dart' as p;

import 'command_resolver.dart';

/// git コマンドが見つからないときの例外。
///
/// `runInShell: true` ではシェルが「command not found」で終わるだけで
/// [ProcessException] にならないため、終了コード(127 / Windows の 9009)も
/// この例外に読み替える(Issue #32)。
///
/// [overrideEnvVar] が非 null のときは `UTAKATA_GIT` で差し替えた起動方法が
/// 失敗しており、案内にその環境変数名を出す(Issue #37)。
class GitNotFoundException implements Exception {
  final String detail;
  final String? overrideEnvVar;

  const GitNotFoundException(this.detail, {this.overrideEnvVar});

  @override
  String toString() {
    final envVar = overrideEnvVar;
    if (envVar != null) {
      return '$envVar で指定した git を起動できません。'
          '$envVar の値を確かめるか、外して既定の git を使ってください'
          '($detail)';
    }
    return 'git が見つかりません。取得には git が必要です。'
        'vault なら `path:` で手元のフォルダーを指すか、git をインストールしてください。'
        '実行権の無い git などは ${CommandResolver.gitEnvVar}="/system/bin/sh /path/to/git" '
        'のように起動方法ごと指定できます'
        '($detail)';
  }
}

/// git コマンドの薄いラッパ(knowledge_repo / vault のフェッチ専用)。
///
/// git はオプトイン機能(`arch get` / `vault get`)を使う場合のみ必要。
/// 不在時は [GitNotFoundException] を投げる。
/// 環境変数 `UTAKATA_GIT` があればその起動方法を使う([CommandResolver.resolveGit])。
class GitDataSource {
  /// 呼び出す git の実行ファイル名(テストで「git が無い」状況を作る用)。
  /// `UTAKATA_GIT` が設定されていればそちらが優先される。
  final String executable;

  final CommandResolver resolver;

  const GitDataSource({
    this.executable = 'git',
    this.resolver = const CommandResolver(),
  });

  /// シェル経由で「コマンドが見つからない」ときの終了コード
  /// (POSIX sh: 127 / Windows cmd: 9009)。
  static const _commandNotFoundExitCodes = {127, 9009};

  Future<ProcessResult> _run(List<String> args) async {
    final command = resolver.resolveGit(defaultExecutable: executable);
    final ProcessResult result;
    try {
      result = await command.run(args);
    } on ProcessException catch (e) {
      throw GitNotFoundException(e.message,
          overrideEnvVar: command.overrideEnvVar);
    }
    if (_commandNotFoundExitCodes.contains(result.exitCode)) {
      throw GitNotFoundException(
          'exit ${result.exitCode}: ${result.stderr.toString().trim()}',
          overrideEnvVar: command.overrideEnvVar);
    }
    return result;
  }

  Future<void> cloneDepth1(String url, String? ref, String targetDir) async {
    final result = await _run([
      'clone',
      '--depth',
      '1',
      if (ref != null && ref.isNotEmpty) ...['--branch', ref],
      url,
      targetDir,
    ]);
    if (result.exitCode != 0) {
      throw Exception(
          'git clone failed (${result.exitCode}): ${result.stderr}');
    }
  }

  /// [targetDir] を取り直す。隣の一時フォルダーへ clone し、成功したときだけ
  /// 旧 [targetDir] を消して差し替える。失敗したら一時フォルダーを片付け、
  /// 旧 [targetDir] はそのまま残す(Issue #32)。
  Future<void> cloneDepth1Replacing(
      String url, String? ref, String targetDir) async {
    final target = Directory(targetDir);
    target.parent.createSync(recursive: true);
    final temp = target.parent.createTempSync('${p.basename(targetDir)}.tmp-');
    try {
      await cloneDepth1(url, ref, temp.path);
    } catch (_) {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
      rethrow;
    }
    if (target.existsSync()) target.deleteSync(recursive: true);
    temp.renameSync(targetDir);
  }

  Future<String> revParseHead(String repoDir) async {
    final result = await _run(['-C', repoDir, 'rev-parse', 'HEAD']);
    if (result.exitCode != 0) {
      throw Exception('git rev-parse failed: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }
}
