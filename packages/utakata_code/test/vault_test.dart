import 'dart:io';

import 'package:test/test.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/filesystem_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/2_remote/git_data_source.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/config_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/vault_repository_impl.dart';

void main() {
  late Directory tempDir;
  late String homeDir;
  late String projectDir;
  late String vaultDir;
  late VaultRepositoryImpl repo;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('utakata_vault_test_');
    homeDir = '${tempDir.path}/home';
    projectDir = '${tempDir.path}/proj';
    vaultDir = '${tempDir.path}/vault';

    Directory('$homeDir/.utakata').createSync(recursive: true);
    Directory(projectDir).createSync(recursive: true);
    Directory('$vaultDir/Google/GCP').createSync(recursive: true);

    // ルート直下の説明ファイル(一覧に出ない)
    File('$vaultDir/README.md').writeAsStringSync('# vault index\n');
    File('$vaultDir/CLAUDE.md').writeAsStringSync('# agent rules\n');
    File('$vaultDir/_template.md').writeAsStringSync('# <サービス名>\n');
    // 実エントリ
    File('$vaultDir/Google/GCP/Firebase.md').writeAsStringSync('# Firebase\n\n## 概要\n');
    // ネストした README は共通前提の実体なので一覧に出る
    File('$vaultDir/Google/GCP/README.md')
        .writeAsStringSync('# Google Cloud Platform (GCP)\n');

    final configRepo =
        ConfigRepositoryImpl(const FilesystemDataSource(), const YamlDataSource(),
            homeDir: homeDir);
    repo = VaultRepositoryImpl(configRepo, const GitDataSource(), homeDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  void writeGlobalConfig(String body) =>
      File('$homeDir/.utakata/config.yaml').writeAsStringSync(body);
  void writeProjectConfig(String body) =>
      File('$projectDir/utakata.yaml').writeAsStringSync(body);

  test('未設定なら root は null・一覧は空', () async {
    expect(await repo.resolveRoot(projectDir), isNull);
    expect(await repo.list(projectDir), isEmpty);
  });

  test('~/.utakata/config.yaml の vault.path から解決する', () async {
    writeGlobalConfig('vault:\n  path: "$vaultDir"\n');
    expect(await repo.resolveRoot(projectDir), vaultDir);
  });

  test('プロジェクトの utakata.yaml がグローバル設定より優先される', () async {
    final other = '${tempDir.path}/other_vault';
    Directory(other).createSync();
    writeGlobalConfig('vault:\n  path: "$vaultDir"\n');
    writeProjectConfig('schema: 1\nvault:\n  path: "$other"\n');
    expect(await repo.resolveRoot(projectDir), other);
  });

  test('一覧: ルート直下の README/CLAUDE/_template は除外、ネスト README は含む', () async {
    writeGlobalConfig('vault:\n  path: "$vaultDir"\n');
    final ids = (await repo.list(projectDir)).map((e) => e.id).toList();
    expect(ids, ['Google/GCP/Firebase', 'Google/GCP/README']);
  });

  test('一覧は見出し(# )をタイトルとして拾う', () async {
    writeGlobalConfig('vault:\n  path: "$vaultDir"\n');
    final entries = await repo.list(projectDir);
    expect(entries.first.title, 'Firebase');
    expect(entries.last.title, 'Google Cloud Platform (GCP)');
  });

  test('read: 拡張子ありなしどちらでも読める', () async {
    writeGlobalConfig('vault:\n  path: "$vaultDir"\n');
    expect(await repo.read(projectDir, 'Google/GCP/Firebase'), contains('# Firebase'));
    expect(await repo.read(projectDir, 'Google/GCP/Firebase.md'), contains('# Firebase'));
  });

  test('read: Vault の外へのパス脱出を拒否する', () async {
    File('${tempDir.path}/secret.md').writeAsStringSync('secret');
    writeGlobalConfig('vault:\n  path: "$vaultDir"\n');
    expect(await repo.read(projectDir, '../secret'), isNull);
  });

  test('path が存在しなければ解決しない(url 未設定時)', () async {
    writeGlobalConfig('vault:\n  path: "${tempDir.path}/does_not_exist"\n');
    expect(await repo.resolveRoot(projectDir), isNull);
  });

  test('プロジェクトの path が空文字なら未設定としてグローバルへフォールバックする', () async {
    writeGlobalConfig('vault:\n  path: "$vaultDir"\n');
    writeProjectConfig('schema: 1\nvault:\n  path: ""\n');
    expect(await repo.resolveRoot(projectDir), vaultDir);
  });

  group('相対パスの解決 (Issue #18)', () {
    test('utakata.yaml の相対 path はプロジェクトルート基準', () async {
      Directory('$projectDir/knowledge/vault').createSync(recursive: true);
      writeProjectConfig('schema: 1\nvault:\n  path: knowledge/vault\n');
      expect(await repo.resolveRoot(projectDir), '$projectDir/knowledge/vault');
    });

    test('utakata.yaml の ../ 相対 path もプロジェクトルート基準', () async {
      writeProjectConfig('schema: 1\nvault:\n  path: ../vault\n');
      expect(await repo.resolveRoot(projectDir), vaultDir);
    });

    test('グローバル設定の相対 path は ~/.utakata/ 基準', () async {
      Directory('$homeDir/.utakata/vault').createSync(recursive: true);
      writeGlobalConfig('vault:\n  path: vault\n');
      expect(await repo.resolveRoot(projectDir), '$homeDir/.utakata/vault');
    });

    test('~ 始まりの path はホーム展開される', () async {
      Directory('$homeDir/my_vault').createSync(recursive: true);
      writeGlobalConfig('vault:\n  path: "~/my_vault"\n');
      expect(await repo.resolveRoot(projectDir), '$homeDir/my_vault');
    });

    test('絶対 path は設定の場所に関係なくそのまま使う', () async {
      writeProjectConfig('schema: 1\nvault:\n  path: "$vaultDir"\n');
      expect(await repo.resolveRoot(projectDir), vaultDir);
    });
  });

  group('vault get の失敗で前回の取得結果を消さない (Issue #32)', () {
    const url = 'https://example.invalid/vault.git';
    late _FakeGit git;
    late VaultRepositoryImpl fetchRepo;

    setUp(() {
      git = _FakeGit();
      final configRepo = ConfigRepositoryImpl(
          const FilesystemDataSource(), const YamlDataSource(),
          homeDir: homeDir);
      fetchRepo = VaultRepositoryImpl(configRepo, git, homeDir);
      writeGlobalConfig('vault:\n  url: "$url"\n');
    });

    List<String> siblingsOf(String dir) => Directory(dir)
        .parent
        .listSync()
        .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .toList();

    test('成功すると取り直した内容に差し替わる', () async {
      git.content = '# Old\n';
      final first = await fetchRepo.fetch(projectDir);
      git.content = '# New\n';
      final second = await fetchRepo.fetch(projectDir);

      expect(second, first);
      expect(await fetchRepo.read(projectDir, 'Entry'), '# New\n');
      expect(siblingsOf(second!), ['repo']);
    });

    test('取得に失敗しても前回のキャッシュが残り、一時フォルダーも残らない', () async {
      git.content = '# Old\n';
      final path = await fetchRepo.fetch(projectDir);

      git.fail = true;
      await expectLater(fetchRepo.fetch(projectDir), throwsException);

      expect(await fetchRepo.resolveRoot(projectDir), path);
      expect((await fetchRepo.list(projectDir)).map((e) => e.id), ['Entry']);
      expect(await fetchRepo.read(projectDir, 'Entry'), '# Old\n');
      expect(siblingsOf(path!), ['repo']);
    });

    test('git が無くても前回のキャッシュは残る', () async {
      git.content = '# Old\n';
      final path = await fetchRepo.fetch(projectDir);

      final noGitRepo = VaultRepositoryImpl(
          ConfigRepositoryImpl(
              const FilesystemDataSource(), const YamlDataSource(),
              homeDir: homeDir),
          const GitDataSource(executable: 'utakata-no-such-git-cmd'),
          homeDir);
      await expectLater(
          noGitRepo.fetch(projectDir), throwsA(isA<GitNotFoundException>()));

      expect(await fetchRepo.read(projectDir, 'Entry'), '# Old\n');
      expect(siblingsOf(path!), ['repo']);
    });
  });

  group('git が見つからないときの案内 (Issue #32)', () {
    test('clone は GitNotFoundException になり、path: と git の導入を案内する',
        () async {
      const git = GitDataSource(executable: 'utakata-no-such-git-cmd');
      final target = '${tempDir.path}/clone_target';
      Object? error;
      try {
        await git.cloneDepth1('https://example.invalid/x.git', null, target);
      } catch (e) {
        error = e;
      }
      expect(error, isA<GitNotFoundException>());
      final message = error.toString();
      expect(message, contains('git が見つかりません'));
      expect(message, contains('path:'));
      expect(message, contains('git をインストール'));
    });

    test('rev-parse も GitNotFoundException になる', () async {
      const git = GitDataSource(executable: 'utakata-no-such-git-cmd');
      await expectLater(
          git.revParseHead(tempDir.path), throwsA(isA<GitNotFoundException>()));
    });
  });
}

/// clone の代わりに `Entry.md` を書くだけの git(ネットワーク・git 不要)。
class _FakeGit extends GitDataSource {
  String content = '';
  bool fail = false;

  _FakeGit();

  @override
  Future<void> cloneDepth1(String url, String? ref, String targetDir) async {
    // 実際の git と同じく、途中まで書いてから失敗するケースを再現する
    Directory(targetDir).createSync(recursive: true);
    File('$targetDir/Entry.md').writeAsStringSync(fail ? '# Broken\n' : content);
    if (fail) throw Exception('git clone failed (128): network unreachable');
  }
}
