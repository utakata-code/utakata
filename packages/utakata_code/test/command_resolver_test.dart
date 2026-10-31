@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:utakata/src/1_domain/exceptions/domain_exceptions.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/2_remote/command_resolver.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/2_remote/git_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/2_remote/process_data_source.dart';

/// Issue #37: UTAKATA_FLUTTER / UTAKATA_GIT による起動方法の差し替え。
void main() {
  group('CommandResolver.parseArgv', () {
    List<String> parse(String s) => CommandResolver.parseArgv(s);

    test('空白で区切る(連続・タブ・前後の空白は無視)', () {
      expect(
          parse('  /bin/sh   /a/flutter\tx  '), ['/bin/sh', '/a/flutter', 'x']);
    });

    test('単引用符の中はそのまま(\\ も文字どおり)', () {
      expect(parse(r"sh '/a b/flutter' 'c\d'"), ['sh', '/a b/flutter', r'c\d']);
    });

    test('二重引用符の中は \\" と \\\\ だけがエスケープ', () {
      expect(parse(r'sh "/a b/\"q\"" "x\\y" "c\d"'),
          ['sh', '/a b/"q"', r'x\y', r'c\d']);
    });

    test('引用符の外の \\ は次の1文字をそのまま(空白を含むパス)', () {
      expect(parse(r'/bin/sh /my\ dir/flutter \"'),
          ['/bin/sh', '/my dir/flutter', '"']);
    });

    test('引用符は語の途中でもつながる・空の引用符は空の引数', () {
      expect(parse(r'''a"b c"'d' "" x'''), ['ab cd', '', 'x']);
    });

    test('閉じていない引用符・末尾の \\ はエラー', () {
      expect(() => parse("sh '/a/flutter"), throwsFormatException);
      expect(() => parse('sh "/a/flutter'), throwsFormatException);
      expect(() => parse(r'sh /a/flutter\'), throwsFormatException);
    });
  });

  group('CommandResolver.override', () {
    test('未設定・空白のみは差し替えなし', () {
      expect(const CommandResolver(environment: {}).override('UTAKATA_FLUTTER'),
          isNull);
      expect(
          const CommandResolver(environment: {'UTAKATA_FLUTTER': '  '})
              .override('UTAKATA_FLUTTER'),
          isNull);
    });

    test('先頭が実行ファイル、残りが前置引数。シェルは使わない', () {
      final c = const CommandResolver(environment: {
        'UTAKATA_FLUTTER': '/system/bin/sh "/data/x y/flutter"'
      }).override('UTAKATA_FLUTTER')!;
      expect(c.executable, '/system/bin/sh');
      expect(c.prefixArgs, ['/data/x y/flutter']);
      expect(c.runInShell, isFalse);
      expect(c.overrideEnvVar, 'UTAKATA_FLUTTER');
    });

    test('書式エラーは環境変数名を添えた InvalidCommandOverrideException', () {
      const r = CommandResolver(environment: {'UTAKATA_FLUTTER': "sh '/a"});
      expect(
          () => r.override('UTAKATA_FLUTTER'),
          throwsA(isA<InvalidCommandOverrideException>().having(
              (e) => e.message,
              'message',
              allOf(contains('UTAKATA_FLUTTER'),
                  contains('unterminated single quote')))));
    });

    test('先頭の語が空ならエラー', () {
      const r = CommandResolver(environment: {'UTAKATA_GIT': '"" git'});
      expect(() => r.override('UTAKATA_GIT'),
          throwsA(isA<InvalidCommandOverrideException>()));
    });
  });

  group('resolveFlutter の優先順', () {
    late Directory tmp;
    late String pathExe;
    late String rootDir;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('utakata_cmd_resolver_');
      pathExe = '${tmp.path}/path_flutter';
      File(pathExe).writeAsStringSync('');
      rootDir = '${tmp.path}/root';
      File('$rootDir/bin/flutter').createSync(recursive: true);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<ProcessResult> whichFound(String exe, List<String> args) async =>
        ProcessResult(0, 0, '/usr/which/flutter\n', '');
    Future<ProcessResult> whichMissing(String exe, List<String> args) async =>
        ProcessResult(0, 1, '', '');
    Future<ProcessResult> whichNotInstalled(String exe, List<String> args) =>
        throw ProcessException(exe, args, 'No such file or directory', 2);

    CommandResolver resolver(Map<String, String> env, CommandRunner runner) =>
        CommandResolver(environment: env, isWindows: false, runner: runner);

    test('UTAKATA_FLUTTER が最優先(FLUTTER_PATH / FLUTTER_ROOT より先)', () async {
      final c = await resolver({
        'UTAKATA_FLUTTER': '/bin/sh /x/flutter',
        'FLUTTER_PATH': pathExe,
        'FLUTTER_ROOT': rootDir,
      }, whichFound)
          .resolveFlutter();
      expect(c.argv, ['/bin/sh', '/x/flutter']);
      expect(c.isOverride, isTrue);
    });

    test('次に FLUTTER_PATH(従来どおり)', () async {
      final c = await resolver(
              {'FLUTTER_PATH': pathExe, 'FLUTTER_ROOT': rootDir}, whichFound)
          .resolveFlutter();
      expect(c.argv, [pathExe]);
      expect(c.isOverride, isFalse);
      expect(c.runInShell, isFalse); // runInShell: Platform.isWindows
    });

    test('FLUTTER_PATH が存在しなければ FLUTTER_ROOT', () async {
      final c = await resolver(
              {'FLUTTER_PATH': '${tmp.path}/nope', 'FLUTTER_ROOT': rootDir},
              whichFound)
          .resolveFlutter();
      expect(c.argv, ['$rootDir/bin/flutter']);
    });

    test('どちらも無ければ which', () async {
      final c = await resolver({}, whichFound).resolveFlutter();
      expect(c.argv, ['/usr/which/flutter']);
    });

    test('Windows では where を使い runInShell: true(従来どおり)', () async {
      final c = await CommandResolver(
          environment: {},
          isWindows: true,
          runner: (exe, args) async {
            expect(exe, 'where');
            return ProcessResult(
                0, 0, 'C:\\f\\flutter\r\nC:\\f\\flutter.bat\r\n', '');
          }).resolveFlutter();
      expect(c.argv, ['C:\\f\\flutter.bat']);
      expect(c.runInShell, isTrue);
    });

    test('which で見つからなければ FlutterNotFoundException', () async {
      await expectLater(resolver({}, whichMissing).resolveFlutter(),
          throwsA(isA<FlutterNotFoundException>()));
    });

    test('which 自体が無くても FlutterNotFoundException(生の ProcessException にしない)',
        () async {
      await expectLater(
          resolver({}, whichNotInstalled).resolveFlutter(),
          throwsA(isA<FlutterNotFoundException>().having(
              (e) => e.message, 'message', contains('UTAKATA_FLUTTER'))));
    });
  });

  group('ProcessDataSource: 実行権の無い台本 (chmod 644)', () {
    late Directory tmp;
    late String script;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('utakata_noexec_flutter_');
      script = '${tmp.path}/flutter';
      File(script)
          .writeAsStringSync('#!/bin/sh\necho "fake-flutter args:\$*"\n');
      Process.runSync('chmod', ['644', script]);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('FLUTTER_PATH=<台本> は Permission denied で起動できない(従来の挙動)', () async {
      final ds = ProcessDataSource(
          resolver: CommandResolver(environment: {'FLUTTER_PATH': script}));
      await expectLater(
          ds.flutterVersion(),
          throwsA(isA<ProcessException>().having(
              (e) => e.message, 'message', contains('Permission denied'))));
    });

    test('UTAKATA_FLUTTER="/bin/sh <台本>" なら起動でき、引数が後ろに続く', () async {
      final ds = ProcessDataSource(
          resolver: CommandResolver(
              environment: {'UTAKATA_FLUTTER': '/bin/sh $script'}));
      expect(
          await ds.flutterVersion(), 'fake-flutter args:--version --machine\n');
    });

    test('空白を含むパスも引用符で渡せる', () async {
      final spaced = Directory('${tmp.path}/my sdk')..createSync();
      final s2 = '${spaced.path}/flutter';
      File(script).copySync(s2);
      final ds = ProcessDataSource(
          resolver: CommandResolver(
              environment: {'UTAKATA_FLUTTER': "/bin/sh '$s2'"}));
      expect(
          await ds.flutterVersion(), 'fake-flutter args:--version --machine\n');
    });

    test('差し替えた起動方法が失敗したら環境変数名を添える', () async {
      final ds = ProcessDataSource(
          resolver: CommandResolver(
              environment: {'UTAKATA_FLUTTER': script})); // 実行権なしを直に
      await expectLater(
          ds.flutterVersion(),
          throwsA(isA<CommandOverrideFailedException>().having(
              (e) => e.message,
              'message',
              allOf(contains('UTAKATA_FLUTTER'), contains(script)))));
    });
  });

  group('GitDataSource: UTAKATA_GIT', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('utakata_git_override_');
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('UTAKATA_GIT の argv で git を起動する(実行権の無い台本を sh 経由で)', () async {
      final script = '${tmp.path}/git';
      File(script).writeAsStringSync(
          '#!/bin/sh\n[ "\$3" = rev-parse ] && echo "sha-for-\$2"\n');
      Process.runSync('chmod', ['644', script]);
      final git = GitDataSource(
          executable: 'utakata-no-such-git-cmd',
          resolver:
              CommandResolver(environment: {'UTAKATA_GIT': '/bin/sh $script'}));
      expect(await git.revParseHead('/some/repo'), 'sha-for-/some/repo');
    });

    test('UTAKATA_GIT が起動できなければ案内に UTAKATA_GIT を出す', () async {
      final git = GitDataSource(
          resolver: CommandResolver(
              environment: {'UTAKATA_GIT': '${tmp.path}/no-such-git'}));
      await expectLater(
          git.revParseHead(tmp.path),
          throwsA(isA<GitNotFoundException>().having((e) => e.toString(),
              'toString', contains('UTAKATA_GIT で指定した git を起動できません'))));
    });

    test('UTAKATA_GIT 未設定なら従来どおり。git 不在の案内に UTAKATA_GIT も載る', () async {
      const git = GitDataSource(
          executable: 'utakata-no-such-git-cmd',
          resolver: CommandResolver(environment: {}));
      await expectLater(
          git.revParseHead(tmp.path),
          throwsA(isA<GitNotFoundException>().having(
              (e) => e.toString(),
              'toString',
              allOf(contains('git が見つかりません'), contains('UTAKATA_GIT')))));
    });

    test('UTAKATA_GIT の書式エラーは InvalidCommandOverrideException', () async {
      final git = GitDataSource(
          resolver: CommandResolver(environment: {'UTAKATA_GIT': '"git'}));
      await expectLater(git.revParseHead(tmp.path),
          throwsA(isA<InvalidCommandOverrideException>()));
    });
  });
}
