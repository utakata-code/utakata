import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../1_domain/exceptions/domain_exceptions.dart';
import 'command_resolver.dart';

/// 外部プロセス実行を担うデータソース
///
/// flutter create / flutter analyze 等を呼び出す。
/// flutter の起動方法は [CommandResolver] が**初回使用時に**遅延解決し、以降は
/// キャッシュする(plan/check/status --brief 等 flutter を使わないコマンドの
/// 起動を妨げない)。優先順は [CommandResolver.resolveFlutter] を参照。
class ProcessDataSource {
  final CommandResolver resolver;

  const ProcessDataSource({this.resolver = const CommandResolver()});

  /// 解決済みの flutter 起動方法(resolver ごとに初回アクセス時に解決・キャッシュ)
  static final _cache = Expando<ResolvedCommand>('flutter');

  Future<ResolvedCommand> get _flutter async {
    return _cache[resolver] ??= await resolver.resolveFlutter();
  }

  /// flutter を [args] で起動する。
  ///
  /// UTAKATA_FLUTTER で差し替えた起動方法が失敗したときは、環境変数名を
  /// 添えた [CommandOverrideFailedException] にする。
  Future<ProcessResult> _runFlutter(List<String> args,
      {String? workingDirectory}) async {
    final command = await _flutter;
    try {
      return await command.run(args, workingDirectory: workingDirectory);
    } on ProcessException catch (e) {
      final envVar = command.overrideEnvVar;
      if (envVar == null) rethrow;
      throw CommandOverrideFailedException(envVar, command.argv, e.message);
    }
  }

  /// flutter create を実行する
  ///
  /// 成功時は true を返す
  Future<bool> flutterCreate({
    required String appName,
    required String projectName,
    required String org,
    required String platforms,
    required String description,
    String? workingDir,
  }) async {
    final result = await _runFlutter(
      [
        'create',
        '--empty',
        '--project-name=$projectName',
        '--org=$org',
        '--description=$description',
        '--platforms=$platforms',
        appName,
      ],
      workingDirectory: workingDir,
    );

    stdout.write(result.stdout);
    if (result.exitCode != 0) {
      stderr.write(result.stderr);
      return false;
    }
    return true;
  }

  /// build_runner を実行する
  ///
  /// 成功時は true を返す
  Future<bool> flutterPubRunBuildRunner({
    required String appName,
    String? workingDir,
  }) async {
    final targetDir = workingDir ?? p.join(Directory.current.path, appName);

    // 依存関係を解決するために flutter pub get を実行
    final getResult = await _runFlutter(
      ['pub', 'get'],
      workingDirectory: targetDir,
    );
    stdout.write(getResult.stdout);
    if (getResult.exitCode != 0) {
      stderr.write(getResult.stderr);
      return false;
    }

    final result = await _runFlutter(
      [
        'pub',
        'run',
        'build_runner',
        'build',
        '--delete-conflicting-outputs',
      ],
      workingDirectory: targetDir,
    );

    stdout.write(result.stdout);
    if (result.exitCode != 0) {
      stderr.write(result.stderr);
      return false;
    }
    return true;
  }

  /// flutter analyze を実行してその出力を返す
  Future<String> flutterAnalyze(String projectDir) async {
    // build/ 配下(SourcePackages 等)のノイズを避けるため lib/ と test/ のみを対象にする。
    // test/ が存在しないプロジェクトでは lib/ のみを渡す。
    final targets = <String>['lib'];
    if (Directory(p.join(projectDir, 'test')).existsSync()) {
      targets.add('test');
    }
    final result = await _runFlutter(
      ['analyze', ...targets],
      workingDirectory: projectDir,
    );
    return result.stdout as String;
  }

  /// flutter --version を実行してバージョン文字列を返す
  Future<String> flutterVersion() async {
    final result = await _runFlutter(
      ['--version', '--machine'],
    );
    return result.stdout as String;
  }
}
