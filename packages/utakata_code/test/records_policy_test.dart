import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:utakata/src/1_domain/1_entities/config/utakata_config_entity.dart';
import 'package:utakata/src/1_domain/3_usecases/doctor_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/generate_claude_integration_usecase.dart';
import 'package:utakata/src/1_domain/services/actor_resolver.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/filesystem_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_edit_data_source.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/config_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/plan_repository_impl.dart';

/// v1.6.0: records.agent_write による3段階のエージェント書き込み許可。
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('utakata_records_policy_');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  void writeConfig(String body) =>
      File('${dir.path}/utakata.yaml').writeAsStringSync(body);

  GenerateClaudeIntegrationUsecase buildUsecase() =>
      GenerateClaudeIntegrationUsecase(
        writeFile: (path, content) async {
          final file = File(path);
          await file.parent.create(recursive: true);
          await file.writeAsString(content);
        },
        ensureDir: (path) async => Directory(path).create(recursive: true),
        fileExists: (path) => File(path).existsSync(),
        configRepo:
            const ConfigRepositoryImpl(FilesystemDataSource(), YamlDataSource()),
      );

  Future<Map<String, dynamic>> generateSettings() async {
    await buildUsecase().execute(dir.path);
    final raw = File('${dir.path}/.claude/settings.json').readAsStringSync();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  group('設定のパース', () {
    test('既定は none(記録への書き込み不可)', () {
      const config = UtakataConfig();
      expect(config.recordsAgentWrite, 'none');
      expect(config.agentCanAppendRecords, isFalse);
      expect(config.agentCanEditRecords, isFalse);
      expect(config.agentCanReadMessages, isFalse);
    });

    test('append / full と agent_read を読める', () {
      final config = UtakataConfig.fromMap({
        'records': {
          'agent_write': 'append',
          'agent_read': {'messages': true},
        },
      });
      expect(config.recordsAgentWrite, 'append');
      expect(config.agentCanAppendRecords, isTrue);
      expect(config.agentCanEditRecords, isFalse);
      expect(config.agentCanReadMessages, isTrue);
    });

    test('未知の値は安全側(none)に倒す', () {
      final config = UtakataConfig.fromMap({
        'records': {'agent_write': 'anything'},
      });
      expect(config.recordsAgentWrite, 'none');
    });
  });

  group('settings.json の生成', () {
    test('none: 記録・プレビューとも編集不可、CLI の allow なし', () async {
      writeConfig('schema: 1\n');
      final settings = await generateSettings();
      final permissions = settings['permissions'] as Map<String, dynamic>;

      expect(permissions['deny'], contains('Write(doc/records/**)'));
      expect(permissions['deny'], contains('Write(doc/preview/**)'));
      expect(permissions.containsKey('allow'), isFalse);
    });

    test('append: deny は維持しつつ追記 CLI だけ allow する', () async {
      writeConfig('schema: 1\nrecords:\n  agent_write: append\n');
      final settings = await generateSettings();
      final permissions = settings['permissions'] as Map<String, dynamic>;

      // ファイル直接編集は引き続き禁止 = 過去の記録を改変できない
      expect(permissions['deny'], contains('Write(doc/records/**)'));
      expect(permissions['deny'], contains('Edit(doc/records/**)'));
      expect(permissions['allow'], contains('Bash(utakata log add:*)'));
      expect(permissions['allow'], contains('Bash(utakata agree add:*)'));
      expect(permissions['allow'], contains('Bash(utakata message add:*)'));
    });

    test('full: 記録の直接編集を許可(プレビューは生成物なので禁止のまま)', () async {
      writeConfig('schema: 1\nrecords:\n  agent_write: full\n');
      final settings = await generateSettings();
      final permissions = settings['permissions'] as Map<String, dynamic>;

      expect(permissions['deny'], isNot(contains('Write(doc/records/**)')));
      expect(permissions['deny'], contains('Write(doc/preview/**)'));
      expect(permissions['allow'], contains('Bash(utakata log add:*)'));
    });

    test('どのモードでもフックは維持される', () async {
      writeConfig('schema: 1\nrecords:\n  agent_write: append\n');
      final settings = await generateSettings();
      final hooks = settings['hooks'] as Map<String, dynamic>;
      expect(hooks.keys, containsAll(['SessionStart', 'PostToolUse', 'Stop']));
    });
  });

  group('CLAUDE.md の記述がモードと連動する', () {
    Future<String> claudeMd() async {
      await buildUsecase().execute(dir.path);
      return File('${dir.path}/CLAUDE.md').readAsStringSync();
    }

    test('none は読み取り専用と書く', () async {
      writeConfig('schema: 1\n');
      expect(await claudeMd(), contains('読み取り専用'));
    });

    test('append は直接編集禁止・CLI 経由と書く', () async {
      writeConfig('schema: 1\nrecords:\n  agent_write: append\n');
      final content = await claudeMd();
      expect(content, contains('直接編集は禁止'));
      expect(content, contains('utakata message add'));
    });
  });

  group('doctor の診断', () {
    DoctorUsecase buildDoctor() => DoctorUsecase(
          planRepo: const PlanRepositoryImpl(FilesystemDataSource(),
              YamlDataSource(), YamlEditDataSource()),
          configRepo: const ConfigRepositoryImpl(
              FilesystemDataSource(), YamlDataSource()),
          fileExists: (path) => File(path).existsSync(),
          dirExists: (path) => Directory(path).existsSync(),
          readFile: (path) async =>
              File(path).existsSync() ? File(path).readAsString() : null,
          deleteFile: (path) async {},
          deleteDir: (path) async {},
          movePath: (from, to) async {},
          listEntries: (dirPath) => const [],
        );

    test('full は非推奨として報告する', () async {
      writeConfig('schema: 1\nrecords:\n  agent_write: full\n');
      final issues = await buildDoctor().diagnose(dir.path);
      expect(issues.any((i) => i.contains('agent_write: full')), isTrue);
    });

    test('設定と settings.json の乖離を検出する', () async {
      // append に変えたのに settings.json が none のまま(claude init 未実行)
      writeConfig('schema: 1\n');
      await buildUsecase().execute(dir.path);
      writeConfig('schema: 1\nrecords:\n  agent_write: append\n');

      final issues = await buildDoctor().diagnose(dir.path);
      expect(issues.any((i) => i.contains('claude init --only settings')), isTrue);
    });

    test('一致していれば乖離を報告しない', () async {
      writeConfig('schema: 1\nrecords:\n  agent_write: append\n');
      await buildUsecase().execute(dir.path);

      final issues = await buildDoctor().diagnose(dir.path);
      expect(issues.any((i) => i.contains('claude init --only settings')), isFalse);
    });

    test('AI/snapshots/ の残存を案内する', () async {
      writeConfig('schema: 1\n');
      Directory('${dir.path}/AI/snapshots').createSync(recursive: true);

      final issues = await buildDoctor().diagnose(dir.path);
      expect(issues.any((i) => i.contains('AI/snapshots/')), isTrue);
    });
  });

  group('ActorResolver', () {
    test('UTAKATA_ACTOR が最優先', () {
      expect(
          ActorResolver.resolve(
              {'UTAKATA_ACTOR': 'agent:claude', 'USER': 'haruma'}),
          'agent:claude');
    });

    test('未指定なら USER', () {
      expect(ActorResolver.resolve({'USER': 'haruma'}), 'haruma');
    });

    test('空文字は無視して USER に落ちる', () {
      expect(
          ActorResolver.resolve({'UTAKATA_ACTOR': '  ', 'USER': 'haruma'}),
          'haruma');
    });

    test('どちらも無ければ unknown', () {
      expect(ActorResolver.resolve(const {}), 'unknown');
    });

    test('agent: プレフィックスでエージェント判定できる', () {
      expect(ActorResolver.isAgent('agent:claude'), isTrue);
      expect(ActorResolver.isAgent('haruma'), isFalse);
    });
  });
}
