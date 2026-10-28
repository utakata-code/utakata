import 'dart:io';

import 'package:path/path.dart' as p;

/// git コマンドが見つからないときの例外。
///
/// `runInShell: true` ではシェルが「command not found」で終わるだけで
/// [ProcessException] にならないため、終了コード(127 / Windows の 9009)も
/// この例外に読み替える(Issue #32)。
class GitNotFoundException implements Exception {
  final String detail;

  const GitNotFoundException(this.detail);

  @override
  String toString() => 'git が見つかりません。取得には git が必要です。'
      'vault なら `path:` で手元のフォルダーを指すか、git をインストールしてください'
      '($detail)';
}

/// git コマンドの薄いラッパ(knowledge_repo / vault のフェッチ専用)。
///
/// git はオプトイン機能(`arch get` / `vault get`)を使う場合のみ必要。
/// 不在時は [GitNotFoundException] を投げる。
class GitDataSource {
  /// 呼び出す git の実行ファイル名(テストで「git が無い」状況を作る用)。
  final String executable;

  const GitDataSource({this.executable = 'git'});

  /// シェル経由で「コマンドが見つからない」ときの終了コード
  /// (POSIX sh: 127 / Windows cmd: 9009)。
  static const _commandNotFoundExitCodes = {127, 9009};

  Future<ProcessResult> _run(List<String> args) async {
    final ProcessResult result;
    try {
      result = await Process.run(executable, args, runInShell: true);
    } on ProcessException catch (e) {
      throw GitNotFoundException(e.message);
    }
    if (_commandNotFoundExitCodes.contains(result.exitCode)) {
      throw GitNotFoundException(
          'exit ${result.exitCode}: ${result.stderr.toString().trim()}');
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
      throw Exception('git clone failed (${result.exitCode}): ${result.stderr}');
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
