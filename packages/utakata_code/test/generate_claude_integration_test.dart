import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:utakata/src/1_domain/3_usecases/generate_claude_integration_usecase.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/filesystem_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_data_source.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/config_repository_impl.dart';

GenerateClaudeIntegrationUsecase _buildUsecase() => GenerateClaudeIntegrationUsecase(
      writeFile: (path, content) async {
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsString(content);
      },
      ensureDir: (path) async => Directory(path).create(recursive: true),
      fileExists: (path) => File(path).existsSync(),
      readFile: (path) async {
        final file = File(path);
        return file.existsSync() ? file.readAsString() : null;
      },
      configRepo: const ConfigRepositoryImpl(FilesystemDataSource(), YamlDataSource()),
    );

void main() {
  test('writes .mcp.json, .claude/settings.json, skills, and an agent', () async {
    final dir = Directory.systemTemp.createTempSync('claude_integration_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    final usecase = _buildUsecase();

    await usecase.execute(dir.path);

    expect(File('${dir.path}/.mcp.json').existsSync(), isTrue);
    expect(File('${dir.path}/.claude/settings.json').existsSync(), isTrue);
    expect(
      File('${dir.path}/.claude/skills/utakata-structure/SKILL.md').existsSync(),
      isTrue,
    );
    expect(
      File('${dir.path}/.claude/skills/utakata-client-context/SKILL.md').existsSync(),
      isTrue,
    );
    expect(
      File('${dir.path}/.claude/skills/utakata-impl-flow/SKILL.md').existsSync(),
      isTrue,
    );
    expect(
      File('${dir.path}/.claude/skills/utakata-client-explainer/SKILL.md')
          .existsSync(),
      isTrue,
    );
    expect(File('${dir.path}/.claude/agents/structure-auditor.md').existsSync(), isTrue);

    final settings = jsonDecode(await File('${dir.path}/.claude/settings.json').readAsString())
        as Map<String, dynamic>;
    expect(settings['permissions']['deny'], contains('Edit(doc/records/**)'));
    expect(settings['hooks'], contains('SessionStart'));
    expect(settings['hooks'], contains('PostToolUse'));
    expect(settings['hooks'], contains('Stop'));

    final mcp = jsonDecode(await File('${dir.path}/.mcp.json').readAsString())
        as Map<String, dynamic>;
    expect(mcp['mcpServers']['utakata']['command'], 'utakata');
  });

  test('writes CLAUDE.md with a team section when utakata.yaml defines team', () async {
    final dir = Directory.systemTemp.createTempSync('claude_integration_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    File('${dir.path}/utakata.yaml').writeAsStringSync('''
schema: 1
team:
  client: "山田さん(要件の決定権者)"
  developer: "私(最終レビュー)"
  ai_agents:
    - id: feature-builder
      role: "実装担当"
''');

    await _buildUsecase().execute(dir.path);

    final claudeMd = File('${dir.path}/CLAUDE.md').readAsStringSync();
    expect(claudeMd, contains('登場人物と役割'));
    expect(claudeMd, contains('山田さん'));
    expect(claudeMd, contains('feature-builder'));
    expect(claudeMd, contains('doc/records/'));
  });

  test('skipExisting repairs only missing files; force regenerates all', () async {
    final dir = Directory.systemTemp.createTempSync('claude_integration_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    await _buildUsecase().execute(dir.path);

    // ユーザーがスキルを編集し、agent を削除したとする
    final skillPath = '${dir.path}/.claude/skills/utakata-structure/SKILL.md';
    File(skillPath).writeAsStringSync('edited by human');
    File('${dir.path}/.claude/agents/structure-auditor.md').deleteSync();

    // 既定(claude init): 欠けた agent だけ書き、編集済みスキルは保護
    final repaired = await _buildUsecase().execute(dir.path, skipExisting: true);
    expect(repaired.written, ['.claude/agents/structure-auditor.md']);
    expect(File(skillPath).readAsStringSync(), 'edited by human');

    // --force: CLAUDE.md 含め全て再生成
    final forced = await _buildUsecase()
        .execute(dir.path, skipExisting: false, forceClaudeMd: true);
    expect(forced.written, contains('CLAUDE.md'));
    expect(File(skillPath).readAsStringSync(), isNot('edited by human'));
  });

  group('.mcp.json は utakata のエントリだけを追加・置換する(#30)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('claude_integration_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    String mcpPath() => '${dir.path}/.mcp.json';
    Map<String, dynamic> readMcp() =>
        jsonDecode(File(mcpPath()).readAsStringSync()) as Map<String, dynamic>;

    const otherServers = '''
{
  "mcpServers": {
    "mobile-ide": {"type": "http", "url": "http://127.0.0.1:8765/mcp"}
  },
  "extra": true
}
''';

    test('--force でも他のサーバーとトップレベルのキーを残す', () async {
      File(mcpPath()).writeAsStringSync(otherServers);

      final result = await _buildUsecase()
          .execute(dir.path, skipExisting: false, forceClaudeMd: true);

      expect(result.written, contains('.mcp.json'));
      expect(result.invalidJson, isEmpty);
      final mcp = readMcp();
      expect(mcp['extra'], isTrue);
      expect(mcp['mcpServers']['mobile-ide']['url'], 'http://127.0.0.1:8765/mcp');
      expect(mcp['mcpServers']['utakata'], {
        'command': 'utakata',
        'args': ['mcp'],
      });
    });

    test('古い utakata エントリは置換する', () async {
      File(mcpPath()).writeAsStringSync(
          '{"mcpServers":{"utakata":{"command":"old"},"x":{"command":"x"}}}');

      await _buildUsecase().execute(dir.path);

      final servers = readMcp()['mcpServers'] as Map<String, dynamic>;
      expect(servers['utakata']['command'], 'utakata');
      expect(servers['x'], {'command': 'x'});
    });

    test('mcpServers が無ければ追加する', () async {
      File(mcpPath()).writeAsStringSync('{"other": 1}');

      await _buildUsecase().execute(dir.path);

      final mcp = readMcp();
      expect(mcp['other'], 1);
      expect(mcp['mcpServers']['utakata']['command'], 'utakata');
    });

    test('既に同じ定義があればファイルに触れない', () async {
      const original =
          '{"mcpServers": {"utakata": {"command": "utakata", "args": ["mcp"]}}}';
      File(mcpPath()).writeAsStringSync(original);

      final result = await _buildUsecase()
          .execute(dir.path, skipExisting: false, forceClaudeMd: true);

      expect(result.written, isNot(contains('.mcp.json')));
      expect(File(mcpPath()).readAsStringSync(), original);
    });

    test('既定(claude init)は既存の .mcp.json に触れない(1.8.0 と同じ)', () async {
      File(mcpPath()).writeAsStringSync(otherServers);

      final result = await _buildUsecase().execute(dir.path, skipExisting: true);

      expect(result.written, isNot(contains('.mcp.json')));
      expect(File(mcpPath()).readAsStringSync(), otherServers);
    });

    test('JSON として読めなければ書かずに知らせ、他のファイルは書く', () async {
      const broken = '{"mcpServers": {';
      File(mcpPath()).writeAsStringSync(broken);

      final result = await _buildUsecase()
          .execute(dir.path, skipExisting: false, forceClaudeMd: true);

      expect(result.invalidJson, ['.mcp.json']);
      expect(result.written, isNot(contains('.mcp.json')));
      expect(result.written, contains('.claude/settings.json'));
      expect(File(mcpPath()).readAsStringSync(), broken);
    });

    test('mcpServers がオブジェクトでなければ書かない', () async {
      const odd = '{"mcpServers": []}';
      File(mcpPath()).writeAsStringSync(odd);

      final result = await _buildUsecase().execute(dir.path);

      expect(result.invalidJson, ['.mcp.json']);
      expect(File(mcpPath()).readAsStringSync(), odd);
    });
  });

  group('only: 選んだ対象だけを上書きで再生成する(#30)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('claude_integration_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('skills だけを再生成し、settings.json・CLAUDE.md・.mcp.json・agents に触れない',
        () async {
      await _buildUsecase().execute(dir.path);

      final skillPath = '${dir.path}/.claude/skills/utakata-impl-flow/SKILL.md';
      final settingsPath = '${dir.path}/.claude/settings.json';
      final claudeMdPath = '${dir.path}/CLAUDE.md';
      final mcpPath = '${dir.path}/.mcp.json';
      final agentPath = '${dir.path}/.claude/agents/structure-auditor.md';
      File(skillPath).writeAsStringSync('stale skill');
      File(settingsPath).writeAsStringSync('{"hooks": {"mine": []}}');
      File(claudeMdPath).writeAsStringSync('human notes');
      File(mcpPath).writeAsStringSync('{"mcpServers": {}}');
      File(agentPath).deleteSync();

      final result = await _buildUsecase().execute(dir.path,
          only: {ClaudeIntegrationTarget.skills});

      expect(result.written, [
        '.claude/skills/utakata-structure/SKILL.md',
        '.claude/skills/utakata-client-context/SKILL.md',
        '.claude/skills/utakata-impl-flow/SKILL.md',
        '.claude/skills/utakata-client-explainer/SKILL.md',
      ]);
      expect(File(skillPath).readAsStringSync(), contains('impl note'));
      expect(File(settingsPath).readAsStringSync(), '{"hooks": {"mine": []}}');
      expect(File(claudeMdPath).readAsStringSync(), 'human notes');
      expect(File(mcpPath).readAsStringSync(), '{"mcpServers": {}}');
      expect(File(agentPath).existsSync(), isFalse);
    });

    test('skipExisting を指定しても only の対象は上書きする', () async {
      await _buildUsecase().execute(dir.path);
      final claudeMdPath = '${dir.path}/CLAUDE.md';
      File(claudeMdPath).writeAsStringSync('human notes');

      final result = await _buildUsecase().execute(dir.path,
          skipExisting: true,
          only: {ClaudeIntegrationTarget.claudeMd, ClaudeIntegrationTarget.agents});

      expect(result.written,
          ['.claude/agents/structure-auditor.md', 'CLAUDE.md']);
      expect(File(claudeMdPath).readAsStringSync(), contains('utakata CLI'));
    });

    test('mcp を選ぶと utakata のエントリだけを追加する', () async {
      final mcpPath = '${dir.path}/.mcp.json';
      File(mcpPath).writeAsStringSync('{"mcpServers": {"a": {"command": "a"}}}');

      final result = await _buildUsecase()
          .execute(dir.path, only: {ClaudeIntegrationTarget.mcp});

      expect(result.written, ['.mcp.json']);
      final servers = (jsonDecode(File(mcpPath).readAsStringSync())
          as Map<String, dynamic>)['mcpServers'] as Map<String, dynamic>;
      expect(servers.keys, containsAll(['a', 'utakata']));
      expect(Directory('${dir.path}/.claude').existsSync(), isFalse);
    });

    test('CLI 名と対象が対応する', () {
      expect(
        ClaudeIntegrationTarget.values.map((t) => t.cliName),
        ['skills', 'agents', 'mcp', 'settings', 'claude-md'],
      );
      expect(ClaudeIntegrationTarget.fromCliName('claude-md'),
          ClaudeIntegrationTarget.claudeMd);
      expect(ClaudeIntegrationTarget.fromCliName('nope'), isNull);
    });
  });

  test('writes a generic CLAUDE.md without utakata.yaml, and never overwrites', () async {
    final dir = Directory.systemTemp.createTempSync('claude_integration_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    await _buildUsecase().execute(dir.path);
    final claudeMd = File('${dir.path}/CLAUDE.md').readAsStringSync();
    expect(claudeMd, contains('utakata CLI'));
    expect(claudeMd, isNot(contains('登場人物と役割')));

    // 既存 CLAUDE.md は上書きしない
    File('${dir.path}/CLAUDE.md').writeAsStringSync('user content');
    await _buildUsecase().execute(dir.path);
    expect(File('${dir.path}/CLAUDE.md').readAsStringSync(), 'user content');
  });
}
