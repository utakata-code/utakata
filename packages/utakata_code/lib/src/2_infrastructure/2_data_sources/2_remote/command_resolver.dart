import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../1_domain/exceptions/domain_exceptions.dart';

/// `which` 等の補助コマンドを実行する関数(テストで差し替える用)。
typedef CommandRunner = Future<ProcessResult> Function(
    String executable, List<String> arguments);

/// 起動方法が決まった外部コマンド(Issue #37)。
///
/// `Process.run(executable, [...prefixArgs, ...args])` で起動する。
/// [overrideEnvVar] が非 null のときは環境変数(`UTAKATA_FLUTTER` 等)で
/// 起動方法が差し替えられており、シェルを介さず argv をそのまま exec する。
class ResolvedCommand {
  final String executable;
  final List<String> prefixArgs;
  final bool runInShell;

  /// 起動方法を差し替えた環境変数名。差し替えていなければ null。
  final String? overrideEnvVar;

  const ResolvedCommand(
    this.executable, {
    this.prefixArgs = const [],
    this.runInShell = false,
    this.overrideEnvVar,
  });

  bool get isOverride => overrideEnvVar != null;

  /// 表示用のコマンド列(エラーメッセージ用)。
  List<String> get argv => [executable, ...prefixArgs];

  Future<ProcessResult> run(List<String> args, {String? workingDirectory}) {
    return Process.run(
      executable,
      [...prefixArgs, ...args],
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
  }
}

/// flutter / git の起動方法を決める(Issue #37)。
///
/// 環境変数 `UTAKATA_FLUTTER` / `UTAKATA_GIT` に「引数の並び」を書くと、
/// その先頭を実行ファイル、残りを前置引数として起動する。例:
/// `UTAKATA_FLUTTER="/system/bin/sh /data/.../flutter/bin/flutter"`
/// (実行権の無い台本をシェル経由で起動する Android 端末向け)。
class CommandResolver {
  static const flutterEnvVar = 'UTAKATA_FLUTTER';
  static const gitEnvVar = 'UTAKATA_GIT';

  final Map<String, String>? _environment;
  final bool? _isWindows;
  final CommandRunner? _runner;

  const CommandResolver({
    Map<String, String>? environment,
    bool? isWindows,
    CommandRunner? runner,
  })  : _environment = environment,
        _isWindows = isWindows,
        _runner = runner;

  Map<String, String> get _env => _environment ?? Platform.environment;
  bool get _windows => _isWindows ?? Platform.isWindows;

  Future<ProcessResult> _runHelper(String executable, List<String> args) {
    final runner = _runner;
    if (runner != null) return runner(executable, args);
    return Process.run(executable, args);
  }

  /// 環境変数 [envVar] の差し替え指定を読む。未設定・空白のみなら null。
  ///
  /// 書式が壊れていれば [InvalidCommandOverrideException]。
  ResolvedCommand? override(String envVar) {
    final value = _env[envVar];
    if (value == null || value.trim().isEmpty) return null;
    final List<String> argv;
    try {
      argv = parseArgv(value);
    } on FormatException catch (e) {
      throw InvalidCommandOverrideException(envVar, value, e.message);
    }
    if (argv.first.isEmpty) {
      throw InvalidCommandOverrideException(
          envVar, value, 'the command (first word) is empty');
    }
    return ResolvedCommand(
      argv.first,
      prefixArgs: argv.skip(1).toList(),
      overrideEnvVar: envVar,
    );
  }

  /// flutter の起動方法を決める。
  ///
  /// 優先順:
  ///   1. 環境変数 UTAKATA_FLUTTER(引数の並び。シェルを介さない)
  ///   2. 環境変数 FLUTTER_PATH(フルパス)
  ///   3. 環境変数 FLUTTER_ROOT → {root}/bin/flutter
  ///   4. which (macOS/Linux) / where (Windows) で PATH 検索
  ///   5. 見つからなければ [FlutterNotFoundException]
  ///
  /// 2〜4 は従来どおり `runInShell: Platform.isWindows` で起動する。
  Future<ResolvedCommand> resolveFlutter() async {
    final overridden = override(flutterEnvVar);
    if (overridden != null) return overridden;

    ResolvedCommand found(String exe) =>
        ResolvedCommand(exe, runInShell: _windows);

    final envPath = _env['FLUTTER_PATH'];
    if (envPath != null && envPath.isNotEmpty && File(envPath).existsSync()) {
      return found(envPath);
    }

    final envRoot = _env['FLUTTER_ROOT'];
    if (envRoot != null && envRoot.isNotEmpty) {
      final candidate =
          p.join(envRoot, 'bin', _windows ? 'flutter.bat' : 'flutter');
      if (File(candidate).existsSync()) return found(candidate);
    }

    final ProcessResult result;
    try {
      result = await _runHelper(_windows ? 'where' : 'which', ['flutter']);
    } on ProcessException {
      // which / where 自体が無い端末(Android 等)
      throw const FlutterNotFoundException();
    }
    if (result.exitCode == 0) {
      final lines = (result.stdout as String)
          .trim()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        if (_windows) {
          return found(lines.firstWhere(
            (l) =>
                l.endsWith('.bat') || l.endsWith('.cmd') || l.endsWith('.exe'),
            orElse: () => lines.first,
          ));
        }
        return found(lines.first);
      }
    }

    throw const FlutterNotFoundException();
  }

  /// git の起動方法を決める。UTAKATA_GIT が無ければ [defaultExecutable] を
  /// 従来どおり `runInShell: true` で起動する。
  ResolvedCommand resolveGit({String defaultExecutable = 'git'}) {
    return override(gitEnvVar) ??
        ResolvedCommand(defaultExecutable, runInShell: true);
  }

  /// 環境変数の値を引数の並びに分ける(POSIX シェルの単語分割の部分集合)。
  ///
  /// - 空白(スペース・タブ・改行)で区切る
  /// - `'...'` の中はそのまま(エスケープなし)
  /// - `"..."` の中では `\"` と `\\` だけがエスケープ。他の `\` は文字どおり
  /// - 引用符の外の `\x` は x そのもの(`\ ` で空白を含むパス)
  /// - 閉じていない引用符・末尾の `\` は [FormatException]
  ///
  /// 変数展開・グロブ・リダイレクト等は行わない。
  static List<String> parseArgv(String value) {
    final args = <String>[];
    final current = StringBuffer();
    var inWord = false;
    var i = 0;
    while (i < value.length) {
      final c = value[i];
      if (c == "'") {
        final end = value.indexOf("'", i + 1);
        if (end < 0) {
          throw const FormatException('unterminated single quote (\')');
        }
        current.write(value.substring(i + 1, end));
        inWord = true;
        i = end + 1;
      } else if (c == '"') {
        i++;
        var closed = false;
        while (i < value.length) {
          final d = value[i];
          if (d == '"') {
            closed = true;
            i++;
            break;
          }
          if (d == r'\' &&
              i + 1 < value.length &&
              (value[i + 1] == '"' || value[i + 1] == r'\')) {
            current.write(value[i + 1]);
            i += 2;
            continue;
          }
          current.write(d);
          i++;
        }
        if (!closed) {
          throw const FormatException('unterminated double quote (")');
        }
        inWord = true;
      } else if (c == r'\') {
        if (i + 1 >= value.length) {
          throw const FormatException('trailing backslash (\\)');
        }
        current.write(value[i + 1]);
        inWord = true;
        i += 2;
      } else if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        if (inWord) {
          args.add(current.toString());
          current.clear();
          inWord = false;
        }
        i++;
      } else {
        current.write(c);
        inWord = true;
        i++;
      }
    }
    if (inWord) args.add(current.toString());
    return args;
  }
}
