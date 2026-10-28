import 'dart:convert';

import '../1_entities/config/utakata_config_entity.dart';
import '../2_repositories/config_repository.dart';

/// `claude init --only` で選べる生成対象。
///
/// [cliName] はコマンドラインで指定する名前(`--only skills` 等)。
enum ClaudeIntegrationTarget {
  /// `.claude/skills/utakata-*/SKILL.md`
  skills('skills'),

  /// `.claude/agents/*.md`
  agents('agents'),

  /// `.mcp.json`(`mcpServers.utakata` だけを追加・置換する)
  mcp('mcp'),

  /// `.claude/settings.json`(ファイルごと上書き)
  settings('settings'),

  /// `CLAUDE.md`(ファイルごと上書き)
  claudeMd('claude-md');

  final String cliName;
  const ClaudeIntegrationTarget(this.cliName);

  static ClaudeIntegrationTarget? fromCliName(String name) {
    for (final target in values) {
      if (target.cliName == name) return target;
    }
    return null;
  }
}

/// [GenerateClaudeIntegrationUsecase.execute] の結果。
class ClaudeIntegrationResult {
  /// 書き込んだ相対パス。
  final List<String> written;

  /// JSON として読めなかったため書き込まなかった相対パス(現状 `.mcp.json` のみ)。
  final List<String> invalidJson;

  const ClaudeIntegrationResult({
    required this.written,
    this.invalidJson = const [],
  });
}

/// `create` 時に `.claude/` と `.mcp.json` を生成するユースケース(仕様書 §11)。
///
/// フックは「速い検査ほど早いフックに」の原則で構成する:
/// PreToolUse はパス判定のみ(utakata を起動しない)、PostToolUse は
/// 単一ファイル粒度の check、Stop はブロックしない警告のみ。
///
/// v1.0.0(S1)から `CLAUDE.md` も生成する。`utakata.yaml` に `team:` が
/// 定義されていれば「登場人物と役割」節を含め、AI が誰の決定に従うべきかを
/// セッション冒頭から把握できるようにする。既存の CLAUDE.md は上書きしない。
///
/// `.mcp.json` は利用者が他の MCP サーバーを足していることがあるため、
/// 上書きする場面でもファイルごとは置き換えず、`mcpServers.utakata` だけを
/// 追加・置換する(#30)。JSON として読めないときは書かずに結果で知らせる。
class GenerateClaudeIntegrationUsecase {
  final Future<void> Function(String path, String content) _writeFile;
  final Future<void> Function(String path) _ensureDir;
  final bool Function(String path)? _fileExists;
  final Future<String?> Function(String path)? _readFile;
  final ConfigRepository? _configRepo;

  const GenerateClaudeIntegrationUsecase({
    required Future<void> Function(String path, String content) writeFile,
    required Future<void> Function(String path) ensureDir,
    bool Function(String path)? fileExists,
    Future<String?> Function(String path)? readFile,
    ConfigRepository? configRepo,
  })  : _writeFile = writeFile,
        _ensureDir = ensureDir,
        _fileExists = fileExists,
        _readFile = readFile,
        _configRepo = configRepo;

  /// [skipExisting] が true の場合、既に存在するファイルには一切触れない
  /// (`claude init` の既定 = 欠けているものだけ補修する安全モード)。
  /// false(create の既定・`claude init --force`)は CLAUDE.md 以外を上書きする。
  /// [forceClaudeMd] は既存 CLAUDE.md も上書きする(`claude init --force` 専用)。
  ///
  /// [only] を指定すると、その対象だけを書く。選んだ対象は既存でも上書きする
  /// (`claude init --only skills` 等。claude-md を選べば CLAUDE.md も上書き)。
  /// このとき [skipExisting] と [forceClaudeMd] は無視する。
  ///
  /// 上書きするモードでも、既存の `.mcp.json` は `mcpServers.utakata` だけを
  /// 追加・置換して他のエントリを残す。
  Future<ClaudeIntegrationResult> execute(
    String projectDir, {
    bool skipExisting = false,
    bool forceClaudeMd = false,
    Set<ClaudeIntegrationTarget>? only,
  }) async {
    bool includes(ClaudeIntegrationTarget target) =>
        only == null || only.contains(target);
    if (only != null) {
      skipExisting = false;
      forceClaudeMd = only.contains(ClaudeIntegrationTarget.claudeMd);
    }

    if (includes(ClaudeIntegrationTarget.skills)) {
      await _ensureDir('$projectDir/.claude/skills/utakata-structure');
      await _ensureDir('$projectDir/.claude/skills/utakata-client-context');
      await _ensureDir('$projectDir/.claude/skills/utakata-impl-flow');
      await _ensureDir('$projectDir/.claude/skills/utakata-client-explainer');
    }
    if (includes(ClaudeIntegrationTarget.agents)) {
      await _ensureDir('$projectDir/.claude/agents');
    }

    final written = <String>[];
    final invalidJson = <String>[];
    final fileExists = _fileExists;
    bool exists(String path) => fileExists != null && fileExists(path);

    Future<void> write(String relativePath, String content) async {
      final path = '$projectDir/$relativePath';
      if (skipExisting && exists(path)) return;
      await _writeFile(path, content);
      written.add(relativePath);
    }

    // 記録への書き込みポリシー(records.agent_write)を settings.json と
    // CLAUDE.md の両方に反映する(v1.6.0)。
    final config = await _configRepo?.read(projectDir);

    if (includes(ClaudeIntegrationTarget.mcp)) {
      const relativePath = '.mcp.json';
      final path = '$projectDir/$relativePath';
      if (!(skipExisting && exists(path))) {
        final existing = exists(path) ? await _readFile?.call(path) : null;
        final merged = existing == null ? _mcpJson() : _mergeMcpJson(existing);
        if (merged == null) {
          invalidJson.add(relativePath);
        } else if (merged != existing) {
          await _writeFile(path, merged);
          written.add(relativePath);
        }
      }
    }
    if (includes(ClaudeIntegrationTarget.settings)) {
      await write('.claude/settings.json', _settingsJson(config));
    }
    if (includes(ClaudeIntegrationTarget.skills)) {
      await write(
          '.claude/skills/utakata-structure/SKILL.md', _structureSkill());
      await write('.claude/skills/utakata-client-context/SKILL.md',
          _clientContextSkill(config));
      await write(
          '.claude/skills/utakata-impl-flow/SKILL.md', _implFlowSkill());
      await write('.claude/skills/utakata-client-explainer/SKILL.md',
          _clientExplainerSkill());
    }
    if (includes(ClaudeIntegrationTarget.agents)) {
      await write(
          '.claude/agents/structure-auditor.md', _structureAuditorAgent());
    }

    if (includes(ClaudeIntegrationTarget.claudeMd)) {
      final claudeMdPath = '$projectDir/CLAUDE.md';
      if (forceClaudeMd || !exists(claudeMdPath)) {
        await _writeFile(claudeMdPath, _claudeMd(config));
        written.add('CLAUDE.md');
      }
    }
    return ClaudeIntegrationResult(written: written, invalidJson: invalidJson);
  }

  /// utakata の MCP サーバー定義(`.mcp.json` の `mcpServers.utakata`)。
  static const Map<String, Object> _utakataMcpServer = {
    'command': 'utakata',
    'args': ['mcp'],
  };

  /// 既存の `.mcp.json` に `mcpServers.utakata` だけを追加・置換する。
  ///
  /// 既に同じ定義があれば [existing] をそのまま返す(書式を崩さない)。
  /// JSON として読めない・構造が想定外(ルートや `mcpServers` が
  /// オブジェクトでない)なら null を返し、呼び出し側は書き込まない。
  String? _mergeMcpJson(String existing) {
    final Object? decoded;
    try {
      decoded = jsonDecode(existing);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final servers = decoded['mcpServers'] ?? <String, dynamic>{};
    if (servers is! Map<String, dynamic>) return null;

    final current = servers['utakata'];
    if (current is Map &&
        jsonEncode(current) == jsonEncode(_utakataMcpServer)) {
      return existing;
    }
    servers['utakata'] = _utakataMcpServer;
    decoded['mcpServers'] = servers;
    return '${const JsonEncoder.withIndent('  ').convert(decoded)}\n';
  }

  /// `records.agent_write` に応じた CLAUDE.md の記述(settings.json と連動)。
  String _recordsPolicyLine(UtakataConfig? config) {
    switch (config?.recordsAgentWrite ?? 'none') {
      case 'append':
        return '**直接編集は禁止**。追記は `utakata log add` / '
            '`utakata agree add` / `utakata message add` 経由でのみ行う'
            '(既存の記録の書き換え・削除は不可)。';
      case 'full':
        return '編集が許可されています(`records.agent_write: full`)。'
            'ただし送受信原文(`messages/`)は一次証跡なので書き換えないこと。';
      default:
        return '**読み取り専用**。書き込みは人間が `utakata log add` / '
            '`utakata agree add` で行う。';
    }
  }

  String _claudeMd(UtakataConfig? config) {
    final buffer = StringBuffer()
      ..writeln('# utakata プロジェクト')
      ..writeln()
      ..writeln('このプロジェクトは utakata CLI(仕様駆動開発)で管理されています。')
      ..writeln()
      ..writeln('## まず読むもの')
      ..writeln()
      ..writeln('- `doc/summary.md` — 案件整理サマリー(合意の台帳。ビジネス上の決定事項)')
      ..writeln('- `doc/specs/plan.yaml` — feature の意図レベル計画')
      ..writeln('- `doc/records/` — お客様との会話ログ・合意・送受信原文。'
          '${_recordsPolicyLine(config)}')
      ..writeln('- `utakata.yaml` — プロジェクトのマスター設定')
      ..writeln()
      ..writeln('設定ファイルの書き方は `utakata doc show plan` / '
          '`utakata doc show config` で確認できる(推測で書かないこと)。');

    final team = config?.team;
    if (team != null && !team.isEmpty) {
      buffer
        ..writeln()
        ..writeln('## 登場人物と役割')
        ..writeln();
      if (team.client != null) buffer.writeln('- **お客様**: ${team.client}');
      if (team.developer != null) buffer.writeln('- **開発者**: ${team.developer}');
      for (final agent in team.aiAgents) {
        buffer.writeln('- **AI (${agent.id})**: ${agent.role}');
      }
      buffer
        ..writeln()
        ..writeln('仕様に関わる判断はお客様・開発者に確認し、AI が独断で決定しないこと。');
    }

    buffer
      ..writeln()
      ..writeln('## 構造ルール')
      ..writeln()
      ..writeln('- 実装前に `utakata check --json` で構造違反を確認する')
      ..writeln('- feature 追加は `utakata plan adopt` → `utakata apply --scope feature`')
      ..writeln('- ファイルを手動作成せず、utakata CLI で構造を拡張する')
      ..writeln('- コミット前に `utakata check` を実行する');

    return buffer.toString();
  }

  String _mcpJson() => '''
{
  "mcpServers": {
    "utakata": {
      "command": "utakata",
      "args": ["mcp"]
    }
  }
}
''';

  /// `.claude/settings.json` を `records.agent_write` に応じて組み立てる。
  ///
  /// - `none`(既定): 記録もプレビューも編集不可(従来どおり)
  /// - `append`: **deny はそのまま**。代わりに追記系 CLI の実行だけ allow する
  ///   → エージェントは CLI を通してしか書けず、ID 採番・スキーマ検証を
  ///     必ず通り、過去の記録を改変・削除できない
  /// - `full`: `doc/records/**` の deny を外す(プレビューは生成物なので
  ///   引き続き deny)
  String _settingsJson(UtakataConfig? config) {
    final mode = config?.recordsAgentWrite ?? 'none';

    final deny = <String>[
      if (mode != 'full') ...[
        'Edit(doc/records/**)',
        'Write(doc/records/**)',
      ],
      'Edit(doc/preview/**)',
      'Write(doc/preview/**)',
    ];

    // 追記系 CLI(append / full 共通)。ファイル直接編集の代替経路になる。
    final allow = <String>[
      if (mode != 'none') ...[
        'Bash(utakata log add:*)',
        'Bash(utakata agree add:*)',
        'Bash(utakata message add:*)',
      ],
    ];

    String jsonArray(List<String> items) =>
        items.map((e) => '      "$e"').join(',\n');

    final permissions = StringBuffer()
      ..writeln('  "permissions": {')
      ..writeln('    "deny": [')
      ..writeln(jsonArray(deny))
      ..write('    ]');
    if (allow.isNotEmpty) {
      permissions
        ..writeln(',')
        ..writeln('    "allow": [')
        ..writeln(jsonArray(allow))
        ..write('    ]');
    }
    permissions
      ..writeln()
      ..write('  },');

    // エージェントが記録を追記できるモードでは、記録者を環境変数で名乗らせる。
    // コマンド前置き(`UTAKATA_ACTOR=… utakata log add`)にすると allow の
    // パターンに一致しなくなるため、settings.json の env で渡す。
    final env = mode == 'none'
        ? ''
        : '  "env": {\n    "UTAKATA_ACTOR": "agent:claude"\n  },\n';

    return '''
{
${permissions.toString()}
$env  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "utakata status --brief" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "utakata check --json" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "utakata status --brief --write-report" }
        ]
      }
    ]
  }
}
''';
  }

  String _structureSkill() => '''
---
name: utakata-structure
description: |
  utakata プロジェクトの構造ワークフロー(計画→生成→検証)。
  feature の追加・実装開始・構造やレイヤーの確認・命名/構造エラーの修正・
  コミット前チェックのとき、コードやディレクトリを手で作る前に必ず使用。
---

# utakata 構造ワークフロー

このプロジェクトの `lib/` 構造は utakata CLI が管理する。
**レイヤーディレクトリやファイルを手動で作らず、必ず以下のフローに従う。**

## 基本フロー(計画 → 生成 → 検証)

1. **計画**: feature は `doc/specs/plan.yaml` に宣言する(name / permission /
   entities)。CLI でやるなら `utakata feature add <name> --entity <e> --permission user`
   (`--template <id>` で feature プリセットも適用できる)
2. **生成**: `utakata apply --scope feature` — plan.yaml が宣言していて `lib/` に
   無いものだけを生成する(`--dry-run` で事前確認可)
3. **検証**: `utakata check --json` — 不足・余分・命名規則違反を1回で報告する。
   **コミット前に必ず `utakata check` を実行する**

## 層ごとの過不足を調整したいとき

- feature を宣言しても全層が必須になるわけではない。`plan.yaml` の `layers:` で
  必要な層だけを宣言できる(空リスト `[]` = その層は不要)
- `utakata plan expand` — 自動導出されている構成を plan.yaml に書き出す
- `utakata plan add <feature> <layer> <item>` / `plan remove ...` — 1項目ずつ増減

## すでに書いたコードが plan に無いとき

- `utakata plan adopt` — `lib/features/` にあるが plan.yaml に無い feature を
  検出して追記する(書式保持)。plan.yaml を手で書き換えるより先にこれを使う

## エラー・違反を直すとき

- 命名/構造違反や lint エラーが出たファイルは
  `utakata guide for <file> --json` で**該当レイヤーのガイドを取得してから**直す
- レイヤーの役割・依存方向は `utakata arch show <arch_id>` で確認する
- ガイド一覧は `utakata guide list`、個別表示は `utakata guide show <layer_path>`

## 設定ファイルの書き方が分からないとき

- `utakata doc show plan` — plan.yaml(features / entities / layers)の書き方
- `utakata doc show config` — utakata.yaml の書き方
- MCP なら `doc_get` ツール(topic: plan | config)
- **推測で YAML を書かず、必ずこれで書式を確認する**

## 設定の優先順位

- マスター設定は `utakata.yaml`(`project.architecture` は plan.yaml より優先)。
  内容は MCP の `config_get`、または直接読んで確認する
- MCP ツール(`check_run`・`structure_get`・`plan_get`・`guide_for_file` 等)が
  使えない場合は同名機能を Bash の `utakata` コマンドで代替する
''';

  String _clientContextSkill(UtakataConfig? config) => '''
---
name: utakata-client-context
description: |
  お客様との会話・合意・過去セッションを参照して要件の根拠を確認するスキル。
  「この要件の出典は？」「お客様と何を合意した？」「誰の決定に従う？」
  「仕様の背景は？」のとき、および doc/records/ に触れる前に必ず使用。
---

# utakata クライアントコンテキストスキル

`doc/records/` はこの案件の**ビジネス上の正史**(お客様との会話・合意・過去セッション)。

## 参照方法(すべて読み取り専用)

- 会話ログ: `utakata log show [--thread <トピック>] [--tag <タグ>] [--date <日付>]`
- 合意: `utakata agree list [--unreflected]` — ID・ステータス・タイトル・金額付き。
  出典 MSG ID は `doc/records/agreements.jsonl` の記録と `utakata summary` が
  再生成する `doc/summary.md` の「参照:」行で確認する。
  未反映(--unreflected)の合意は実装に落ちていない決定事項なので特に注意する
- 誰の決定に従うか: MCP `config_get`(または `utakata.yaml` の `team:`)。
  仕様の変更・解釈は team に定義された決定権者に確認し、AI が独断で決めない
- 過去の開発セッション記録: `doc/records/sessions/`(人間が取り込んだもの)
- 人間向けプレビューは `doc/preview/` にあるが、正本は常に `doc/records/` の JSONL

${_skillRecordsSection(config)}
- `doc/summary.md` の合意台帳区間(`<!-- utakata:begin agreements -->`)は
  `utakata summary` が再生成する。マーカー内は手で編集しない
''';

  /// SKILL.md の「記録への書き込み」節。`records.agent_write` と連動させる
  /// (settings.json の許可と食い違う説明を配らないため)。
  String _skillRecordsSection(UtakataConfig? config) {
    switch (config?.recordsAgentWrite ?? 'none') {
      case 'append':
        return '''
## 記録の追記: CLI 経由のみ(直接編集は禁止)

- `doc/records/**` と `doc/preview/**` への Edit/Write は deny 設定で拒否される
- 追記は次のコマンドで行える(既存の記録の書き換え・削除はできない):
  - 会話の記録: `utakata log add "..." -s client|developer`
  - 送受信原文: `utakata message add -d inbound|outbound "..."`
  - 合意の記録: `utakata agree add --title "..." --kind client_agreement`
- 記録者は環境変数 `UTAKATA_ACTOR`(既定で `agent:claude`)として残るため、
  人間の記録と区別できる。**事実だけを記録し、要約や解釈を混ぜない**
- 判断を伴う記録(合意の確定など)は、実行前に人間に確認する''';
      case 'full':
        return '''
## 記録の編集: 許可されている(`records.agent_write: full`)

- `doc/records/**` は編集できるが、**送受信原文(`messages/`)は一次証跡**なので
  書き換えない。追記は CLI(`utakata log add` / `message add` / `agree add`)を使う
- `doc/preview/**` は生成物なので編集しない(`... render` で再生成する)
- 判断を伴う記録(合意の確定など)は、実行前に人間に確認する''';
      default:
        return '''
## 絶対ルール: AI は記録に書き込まない

- `doc/records/**` と `doc/preview/**` への Edit/Write は deny 設定で拒否される
- 記録が必要になったら、人間に次のコマンドの実行を**提案**する:
  - 会話の記録: `utakata log add "..." -s client|developer`
  - 送受信原文: `utakata message add -d inbound|outbound "..."`
  - 合意の記録: `utakata agree add --title "..." --kind client_agreement`
  - セッションの取り込み: `utakata log import claude-session --last`''';
    }
  }

  String _implFlowSkill() => '''
---
name: utakata-impl-flow
description: |
  実装計画(impl plan)のライフサイクル管理。feature の実装を開始する・
  実装方針を検討する・進捗を記録する・実装を完了する・テストを進める・
  リファクタリングや文書整理の計画を立てる・「どの計画が進行中？」のときに使用。
---

# utakata 実装計画フロー

規模のある変更は、コードを書く前に実装計画を作る
(`utakata.yaml` の `enforcement.impl_plan: "on"` で feature の計画を必須化できる)。

## 状態は2軸

- `status`(実装): `todo` → `in_progress` → `review` → `done`
- `test`(検証): `todo` → `in_progress` → `review` → `done`(不要なら `not_required`)

計画ファイルは状態に応じて `doc/impl/<レーン>/` を移動する
(`1_todo` / `2_in_progress` / `3_review` / `4_test_todo` /
`5_test_in_progress` / `6_test_review` / `7_done` / `archive`)。
**正は frontmatter** であり、配置はそこから導出される。

## 計画書は「計画」と「実施記録」の2領域

本文はマーカー行 `<!-- utakata:log -->` で分かれている。

- **上 = 計画**。`utakata impl start` した時点で**凍結**される。
  以後、書き換えると状態遷移が止まる
- **下 = 実施記録**。追記のみ。**ファイルを直接編集せず**
  `utakata impl note <PLAN-id> "本文"` で追記する(日時と記録者が付く)

実装中の技術選定の理由・試行錯誤・途中の判断・追試の結果は、すべて
**記録として `impl note` で残す**。計画部分には書かない。

## 手順

1. **着手前**: `utakata impl new [kind:]<target> [--agreement <AGR-id>] [--spec <path>]`
   — `kind` は `feat` / `fix` / `refactor` / `docs` / `chore` / `test`。
   省略時は `feat`(feature の計画。`doc/impl/1_todo/PLAN-NNNN_<feature>.md`)。
   feature に紐づかない作業は `refactor:doc_layout` のように種別を付ける
   (`PLAN-NNNN_refactor_doc_layout.md`)
2. **計画を書く**: `todo` の間は計画部分を自由に編集してよい
3. **実装開始**: `utakata impl start <PLAN-id>` — ここで計画部分が凍結される
4. **実装中**: `utakata impl note <PLAN-id> "..."` で記録を追記する
5. **自分のレビュー**: `utakata impl review <PLAN-id>`
6. **実装完了**: `utakata impl done <PLAN-id>`
7. **検証**: `utakata impl test start|review|done <PLAN-id>`
   — テストが不要な変更なら `utakata impl test skip <PLAN-id> --reason "..."`
8. **アーカイブ**: 参照しなくなったら `utakata impl archive <PLAN-id>`
9. **状況確認**: `utakata impl list` / `utakata impl board`

## 凍結後に計画を変えたくなったら

- **小さな修正(誤字・補足)**: 計画部分を直したうえで
  `utakata impl revise <PLAN-id> --reason "理由"` で改訂として受理する。
  `revisions` が +1 され、理由が記録に残る。受理するまで状態遷移は止まる
- **設計方針やスコープが変わる**: 凍結した計画書に上書きせず、
  `utakata impl new <target> --supersedes <旧PLAN-id>` で新しい計画書を切る。
  旧計画は `utakata impl archive` する(ボードに「置き換え」が表示される)

## 注意

- **逆行してよい**。テストが落ちたら `utakata impl start` で実装へ戻す
  (検証軸は実装が `done` になるまで進められない)
- frontmatter(`id` / `status` / `plan_digest` 等)は機械管理。手で編集しない。
  書き換えてしまった / ファイルを手で動かした場合は `utakata impl sync`
- 「凍結後に書き換えられています」と出たら、意図した変更なら `revise`、
  そうでなければ計画部分を元に戻す。記録は `impl note` へ
- ボード(`doc/preview/impl_board.md`)は状態変更のたびに自動再生成される
- 実装が仕様やお客様の合意に関わる場合は、着手前に utakata-client-context
  スキルの手順で根拠を確認する
''';

  String _clientExplainerSkill() => """
---
name: utakata-client-explainer
description: |
  お客様向けの説明文(アカウント取得のお願い・技術スタックの概要説明・
  料金や審査の案内)を作成するスキル。
  「Apple Developer の取得手順を説明して」「Firebase の料金をお客様に説明したい」
  「必要なアカウントを案内する文面を作って」のときに使用。
---

# お客様向け説明文の作成

外部サービス(Apple / Google / LINE 等)の取得手順・料金・審査要否は
**Vault に蓄積された検証済みナレッジ**を根拠にする。記憶だけで書かない。

## 手順

1. `utakata vault list` — 使えるエントリを確認する(MCP なら `vault_list`)
2. `utakata vault show <id>` — 該当サービスの本文を読む(MCP なら `vault_get`)
3. 読んだ内容をもとに、**その案件のお客様に合わせて**説明文を書く

## Vault の読み方

各エントリは次の構成になっている:

- **概要** — 非エンジニアにも通じる説明。ここを土台にする
- **アカウント取得手順** — 手順・料金・審査有無・所要日数
- **深掘り調査・検証済みの主張** — `確認した現在日時` と公式 URL 付きの検証記録。
  **料金・審査基準・仕様はここを必ず確認する**
- **参考リンク** — 補助情報

## 守ること

- **検証日時を確認する**: Vault の記述には `確認した現在日時` がある。日付が古く、
  料金や仕様など変わりやすい内容なら、その旨を添えるか人間に再確認を促す
- **Vault に無いことを断定しない**: 根拠が無い項目は「確認します」と書くか、
  人間に調査を依頼する。推測で料金や審査要否を書かない
- **Vault に書き込まない**: 知識の追記は人間が Vault リポジトリ側で行う
- **送信も人間が行う**: 生成した文面は下書き。送った後の記録は人間が
  `utakata log add "..." -s developer` (下書き段階なら `--draft`)で行う
- 合意事項(金額・仕様)が生じたら `utakata agree add` の実行を人間に提案する
""";

  String _structureAuditorAgent() => '''
---
name: structure-auditor
description: utakata check の結果を読み、構造・命名違反の修復を提案するエージェント
tools: Bash, Read, Edit
---

`utakata check --json` を実行し、missing/extra/namingViolations を解析して
修復方針を提案する。違反ファイルは `utakata guide for <file> --json` で該当
レイヤーのガイドを取得してから直す。命名規則違反は該当ファイルをリネームし、
missing は `utakata apply` で生成できるか確認する。plan.yaml 自体の変更は
`utakata plan adopt` の提案に留め、実行は人間の確認を経てから行う。
''';
}
