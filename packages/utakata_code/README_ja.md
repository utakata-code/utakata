# utakata

**utakata** は **[utakata code](https://github.com/utakata-code)** が開発する Dart CLI ツールです。
**お客様・開発者・AI エージェント**が**仕様駆動開発**によって Flutter アプリを共同構築するために設計されています。

> English documentation: [README.md](README.md)

[![pub.dev](https://img.shields.io/pub/v/utakata.svg)](https://pub.dev/packages/utakata)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

---

## 特徴

- 🤖 **Claude Code ネイティブ**: `create` が `.mcp.json` + `.claude/`(フック・スキル・エージェント)+ プロジェクト `CLAUDE.md` を生成。`utakata mcp` はステートレスな読み取り専用 MCP サーバーを提供し、AI が構造・計画・会話ログ・合意・設定を「書き込まずに」参照できます。記録への書き込みをどこまで許すかは3段階(`records.agent_write: none | append | full`)で選べます。
- 🧭 **マスター設定(`utakata.yaml`)**: アーキテクチャ、`team`(お客様・開発者・AI の役割と決定権)、`.claude/skills/` に同期する `skills`、任意のリモート `knowledge_repo`(`utakata arch get` でコミット SHA を `utakata.lock` に固定)を1ファイルで宣言。未指定なら全て同梱・完全オフラインで動作します。
- 🏗️ **マルチアーキテクチャ対応**: **Clean Architecture (4層)** と **MVVM (3層)** を標準搭載。`utakata arch eject <id>` でローカルに書き出してカスタマイズ可能。
- 🔍 **1回の check で全て検証**: `utakata check` が「不足ファイル」「余分なファイル」「命名規則違反」を1回の走査で報告します。違反箇所には GUIDE の抜粋も添えられ、直し方がその場でわかります。
- 📋 **意図レベルの計画**: `doc/specs/plan.yaml` に feature(名前・権限・entity)を宣言するだけ。`utakata apply` が不足分だけ — 層ディレクトリに加えて必須ファイル(空ファイル)も — を生成し、ファイルの存在自体を plan で管理できます。`utakata plan adopt` は plan.yaml に載っていない実装済みコードを検出し、書式を保ったまま追記します。
- 🔗 **import の決定論的監査**: `utakata imports` が「ファイル配置」だけでなく「依存の向き」を検証します — `arch_definition.yaml` の層間依存グラフ(`import_rules`)と、外部パッケージの**配置宣言**(`dependencies/core_stack.yaml` にバージョンと使ってよい層を1箇所で宣言。宣言外のパッケージは論じない)に基づく監査です。
- 🎚️ **層ごとの粒度指定**: feature を宣言しても「全層が必須」にはなりません。必要な層だけを `layers:` に書き、使わない層は空リスト(`[]`)で除外し、命名が自由な層でもファイルを明示できます。`utakata plan expand` で自動導出の結果を書き出してから編集できます。
- 📚 **ナレッジはリポジトリにもパッケージにも置かない**: ガイドは [utakata_arch_lib](https://github.com/utakata-code/utakata_arch_lib) で一元管理し、参照時にオンデマンド取得します(バージョン固定タグ・`~/.utakata/` にキャッシュ)。パッケージには機械可読な定義だけを同梱するため `create`/`apply`/`check` は完全オフラインで動作。プロジェクトにはアプリ本体 + `doc/` + 設定だけが残り、`apply` がディレクトリごとに GUIDE.md を撒くこともなくなりました(参照は `guide for <file>`)。
- 🗂️ **クライアント説明用ナレッジ Vault**: `vault:` に自分のナレッジリポジトリを指定すると、生成される `utakata-client-explainer` スキルがそれを根拠にお客様向けの説明文を書きます(料金や審査要否を記憶で書かず、各エントリの検証日時を確認する)。
- 💬 **お客様との会話の記録**: `utakata log` が要約した会話を、`utakata message` が実際に送受信した**原文**を無加工で残します。`utakata agree` は合意をトラッキング。すべて JSONL・追記専用で、AI にどこまで書かせるかは `records.agent_write` で決められます(`append` なら CLI 経由の追記だけ許可され、過去の記録は改変できません)。
- 📝 **実装計画とサマリー**: `utakata impl` が feature ごとの計画を**2軸**(実装: `todo → in_progress → review → done` / 検証: 同様の4段階と `not_required`)で管理します。進行に応じて計画ファイルがレーンのディレクトリ(`doc/impl/2_in_progress/`・`4_test_todo/` 等)を移動し、`doc/preview/impl_board.md` にボードが再生成されます。`enforcement.impl_plan: on` にすると、計画の無い feature のスキャフォールドを止められます。`utakata summary` は案件整理サマリーの合意ログ区間を自動再生成します。
- 🌐 **多言語対応**: CLI メッセージは日本語・英語に対応しています。

---

## インストール

```sh
dart pub global activate utakata
```

`$HOME/.pub-cache/bin` を `PATH` に追加してください。

---

## クイックスタート

```sh
# (任意)アプリがまだ存在しない段階(契約前フェーズ)で doc/ ワークスペースを先行作成
utakata doc init

# Flutter プロジェクトを新規作成(.mcp.json + .claude/ も同時生成)
utakata create my_app --org com.example

# doc/specs/plan.yaml に feature を宣言してから生成
utakata apply --scope feature

# 構造・命名規則・必須ファイルを1回で検証
utakata check
```

`doc/specs/plan.yaml`:

```yaml
schema: 1
project:
  architecture: clean_architecture
features:
  - name: todo
    permission: user
    entities: [todo]
```

旧 `AI/` ベースのレイアウトを使っている既存プロジェクトは `utakata doctor --migrate` で移行できます(既定は dry-run)。

---

## 組み込みアーキテクチャ

```sh
utakata arch list         # 利用可能なアーキテクチャ一覧
utakata arch show mvvm    # レイヤー構造と命名規則を表示
```

| アーキテクチャ | レイヤー数 | 説明 |
|---|---|---|
| `clean_architecture` | 4 | Domain → Infrastructure → Application → Presentation |
| `mvvm` | 3 | Model → ViewModel → View |

`plan.yaml` で feature 単位のアーキテクチャ上書きも可能です:

```yaml
features:
  - name: todo
    permission: user
    entities: [todo]
    architecture: clean_architecture   # プロジェクト既定を上書き
```

---

## コマンドリファレンス

### プロジェクトセットアップ

| コマンド | 説明 |
|---|---|
| `utakata doc init` | Flutter プロジェクト本体より先に `doc/` ワークスペース(specs/records/preview/impl/knowledge/archive)+ `utakata.yaml` を作成する |
| `utakata doc show <config\|plan\|imports\|records\|impl>` / `utakata doc list` | `utakata.yaml` / `doc/specs/plan.yaml` / `import_rules` / 記録の扱いのリファレンスを表示する(インストール済みバージョンに対応。MCP の `doc_get` でも取得可能) |
| `utakata create <name> [--org] [--platforms] [--arch] [--mcp ...]` | 選択したアーキテクチャで Flutter プロジェクトを新規作成し、`.mcp.json` + `.claude/` も生成する。`claude init` と同じ `--mcp` / `--mcp-url` / `--mcp-header` / `--mcp-name` を受け付ける([MCP の行き先](#mcp-の行き先)) |
| `utakata doctor [--migrate]` | プロジェクトを診断する。`--migrate` は旧 `AI/` ベースのレイアウト(または独自運用の `doc/`)を現行レイアウトへ移行する |

### 構造

| コマンド | 説明 |
|---|---|
| `utakata feature add <name> [--entity] [--permission] [--template <id>]` | feature を1つスキャフォールドする。`--template` は feature プリセット(プロジェクトまたは `~/.utakata/feature_templates/` から解決する `manifest.yaml`)を適用し、同じ操作で `plan.yaml` にも登録する |
| `utakata apply [--scope all\|feature\|core] [--dry-run]` | `plan.yaml` が宣言していて `lib/` に無いものを生成する |
| `utakata plan adopt [-y]` | `lib/features/` にあるが `plan.yaml` に無い feature を検出し追記する(既存のコメント・書式は保持) |
| `utakata plan expand [--dry-run] [--feature <name>]` | 自動導出されている層ごとのファイル構成を `plan.yaml` に書き出す(以後は手で増減できる) |
| `utakata plan add <feature> <layer> <item...>` / `remove <feature> <layer> <item>` | 層の項目を1件追加・削除する(AI エージェント/スクリプト向け。書式は保持) |
| `utakata check [--json] [--file <path>]` | 不足ファイル・余分なファイル・命名規則違反を1回の走査で報告する |
| `utakata imports [--json] [--arch <id>]` | import の健全性を監査する(層間依存グラフ `import_rules` + パッケージ配置宣言 `dependencies/*.yaml`。違反があれば exit 1) |
| `utakata status [--brief] [--write-report]` | Flutter バージョン + lint + check サマリー。`--brief` は flutter 呼び出しを一切行わない(Claude Code フック用) |
| `utakata arch list\|show\|eject\|export` | アーキテクチャ定義の確認、またはローカルへの書き出し(カスタマイズ開始) |
| `utakata arch get [--update]` | `utakata.yaml` の `knowledge_repo`(オプトイン)をフェッチしてコミット SHA を `utakata.lock` に固定する |

### お客様・記録系(追記専用。AI に許す範囲は `records.agent_write` で設定)

| コマンド | 説明 |
|---|---|
| `utakata log add "..." -s client\|developer\|system\|third_party [--at] [--thread] [--tag] [--reply-to] [--draft]` | 会話を1件追記する(`doc/records/log/YYYY-MM.jsonl`) |
| `utakata log show [--date] [--thread] [--tag]` / `utakata log render` | 会話の検索 / `doc/preview/` 配下の Markdown プレビュー再生成 |
| `utakata log import claude-session [--list\|--last\|--session <id>] [--full] [-y]` | Claude Code セッション生ログを人間の操作で `doc/records/sessions/` に取り込む(既定は user/assistant テキストのみ・秘密情報は `[REDACTED]`・確認プロンプト付き) |
| `utakata message add -d inbound\|outbound [-c <経路>] [--at] [--from\|--to] [--subject] [--thread] [--external-id] "..."` | 送受信原文を無加工で記録する(`doc/records/messages/YYYY-MM.jsonl`) |
| `utakata message import --format jsonl\|md [--file <path>] [--channel] [--dry-run]` | 既存のやり取りを一括取り込みする(`external_id` か本文一致で重複スキップ) |
| `utakata message list\|show\|render\|link` | 一覧 / 全文表示 / `doc/preview/messages/` の再生成 / 要約ログ・合意への紐付け |
| `utakata agree add --title "..." --kind client_agreement\|internal_decision\|tentative [--amount] [--from <msg id>]` | 合意を記録する(`doc/records/agreements.jsonl`・追記専用) |
| `utakata agree status <id> <status>` / `correct <id>` / `reflect <id> --plan\|--spec` / `list [--unreflected]` | 合意の状態更新・訂正(supersede)・反映記録・未反映合意の一覧 |
| `utakata impl new [kind:]<target> [--agreement] [--spec] [--message] [--basis] [--backlog] [--supersedes]` | 実装計画を作成する(`doc/impl/1_todo/PLAN-NNNN_{feature}.md`)。`kind` は `feat`(既定)/`fix`/`refactor`/`docs`/`chore`/`test`。`--supersedes` で旧計画を置き換える |
| `utakata impl note <id> "本文"` / `revise <id> --reason` | 実施記録を追記(stdin 可)/ 凍結後に書き換えた計画を改訂として受理 |
| `utakata impl start\|review\|done\|archive <id>` | 実装軸を進める。ファイルは対応するレーンへ移動する |
| `utakata impl test start\|review\|done\|todo\|skip <id>` | 検証軸を進める(実装が `done` になってから。`skip --reason` はテスト不要の明示) |
| `utakata impl list [--status] [--test] [--lane] [--json]` / `board` / `sync [--dry-run]` | 一覧 / レーン別ボード表示(`doc/preview/impl_board.md` を再生成)/ frontmatter に合わせた再配置 |
| `utakata summary` | `doc/summary.md` の合意ログ区間を再生成する(手書き部分はそのまま) |

### ナレッジ

| コマンド | 説明 |
|---|---|
| `utakata guide list\|show\|eject [--arch]` | レイヤーのガイドを閲覧、またはローカルへ書き出してカスタマイズを開始する |
| `utakata guide for <file> [--json]` | `lib/features/` 配下のファイルパスから該当レイヤーのガイドを決定論的に解決する(lint エラー修正のコンテキスト供給用) |

### AI 統合

| コマンド | 説明 |
|---|---|
| `utakata mcp` | ステートレス・読み取り専用の MCP サーバーを stdio で起動する(`structure_get`・`check_run`・`plan_get`・`log_query`・`agreements_query`・`guide_get`・`guide_for_file`・`config_get`・`doc_get`・`vault_list`・`vault_get`、および `records.agent_read.messages` 有効時のみ `message_query`) |
| `utakata vault list\|show\|get` | クライアント説明用の実務ナレッジ Vault を参照する(`vault:` で設定。通常は `~/.utakata/config.yaml`) |
| `utakata skills sync [--force]` | `utakata.yaml` の `skills` リストをアーキテクチャ同梱 SKILL から `.claude/skills/` に同期する(managed マーカー保護: 人間の作ったファイルは絶対に上書きしない) |
| `utakata claude init [--only <対象>] [--force] [--mcp ...]` | 既存プロジェクトに Claude Code 統合(`.claude/` + `.mcp.json` + `CLAUDE.md`)を後付け・補修する。既定は欠けているファイルのみ生成。`--only skills` のように対象(`skills` / `agents` / `mcp` / `settings` / `claude-md`、複数可)を選ぶとそれだけを上書きで再生成。`--force` は全再生成で、`settings.json` と `CLAUDE.md` はファイルごと上書きされる。`.mcp.json` はどのモードでも `mcpServers.utakata`(または `--mcp-name` のキー)だけを追加・置換し、他のサーバーは残す。そのエントリの行き先は `--mcp` / `--mcp-url` / `--mcp-header` / `--mcp-name` で選ぶ([MCP の行き先](#mcp-の行き先)) |

`diff` は `check` への永続的なエイリアスとして残ります。`scan`・`validate`・`feature init`・`core`・`arch create` は削除・改名されました。詳細は [CHANGELOG.md](CHANGELOG.md) を参照してください。

---

## AI エージェントへの案内

`utakata create` は `.mcp.json` と `.claude/settings.json` を生成し、以下のフックを設定します:

- **SessionStart** → `utakata status --brief`(プロジェクト状態の要約。flutter 呼び出しなし)
- **PostToolUse**(Edit/Write) → `utakata check --json`(編集直後のファイルへの即時フィードバック)
- **Stop** → `utakata status --brief --write-report`
- **deny ルール**: `doc/records/**` と `doc/preview/**` への `Edit`/`Write` を拒否 — 会話ログ・合意の書き込み経路は人間専用であり、ドキュメント上の約束ではなくホスト側で技術的に強制されます

ファイルを手動で作成せず、`utakata` CLI でプロジェクト構造を拡張してください。コミット前に `utakata check` を実行することを推奨します。

### MCP の行き先

既定の `.mcp.json` は `utakata mcp` を stdio で起動します。MCP を別の場所が出している(HTTP で MCP を出す IDE など)とき、または MCP クライアントから見て `utakata` が `PATH` に無いときは、`claude init` / `create` のフラグで行き先を選べます。

| オプション | 意味 |
|---|---|
| `--mcp=stdio\|http\|none` | `stdio`(既定)= `{"command": "utakata", "args": ["mcp"]}`。`http` = `{"type": "http", "url": ..., "headers": {...}}`。`none` = `.mcp.json` に一切触れない(`--only mcp` も何もしない) |
| `--mcp-url <url>` | `http` の URL(必須)。`--mcp-url` だけを指定したときは `--mcp=http` とみなす。そのまま書くので、`${VAR}` は Claude Code が環境変数で展開する |
| `--mcp-header 'Name: value'` | `http` のヘッダー(複数可)。最初の `:` で分けて前後の空白を除く。指定が無ければ `headers` は書かない |
| `--mcp-name <name>` | `mcpServers` で utakata が追加・置換するキー(既定 `utakata`)。他のサーバーは残す |

矛盾する組み合わせ(URL の無い `--mcp=http`、`stdio` / `none` と `--mcp-url` / `--mcp-header`、`none` と `--mcp-name`、`:` の無いヘッダー)は何も書かずに終了コード 64 で終わります。

```bash
# IDE が HTTP で出す MCP を指す。${...} は Claude Code が展開する
utakata claude init --only mcp \
  --mcp-url '${MIDE_MCP_URL}' \
  --mcp-header 'Authorization: Bearer ${MIDE_MCP_TOKEN}' \
  --mcp-name mobile-ide
```

```json
{
  "mcpServers": {
    "mobile-ide": {
      "type": "http",
      "url": "${MIDE_MCP_URL}",
      "headers": { "Authorization": "Bearer ${MIDE_MCP_TOKEN}" }
    }
  }
}
```

これらのフラグが変えるのは `.mcp.json` だけです。`.claude/settings.json` のフックとスキルは引き続き `utakata` CLI を呼びます(utakata の MCP は読み取り専用で、`impl new` / `log add` / `apply` などの書き込みには CLI が要るため)。`http` / `none` にしても、フックから `utakata` を呼べるようにしておいてください。選んだ行き先はどこにも保存しないため、後で `.mcp.json` を再生成するとき(`--force` / `--only mcp`)は同じフラグを付け直してください(付けないと既定の stdio の `mcpServers.utakata` が足されます)。

---

## アーキテクチャ

`utakata` 自体も Clean Architecture で実装されています:

```
packages/utakata_code/lib/src/
├── 0_templates/       # アーキテクチャテンプレート (clean_architecture, mvvm)
├── 1_domain/          # エンティティ・リポジトリI/F・ユースケース・純関数サービス
├── 2_infrastructure/  # ファイルシステム/YAML/JSONL/プロセスのデータソース・モデル・リポジトリ実装
└── 3_application/     # コマンドハンドラ・Runner・プレゼンター・MCP サーバー
```

---

## ライセンス

**デュアルライセンス**:

1. **オープンソース (GNU GPL v3)**
   個人・オープンソースプロジェクトへの使用・フォーク・改変は [GNU GPL v3](LICENSE) のもとで無料で可能です。

2. **商用利用**
   このツール、またはツールが生成したコードの商用利用には別途商用ライセンスが必要です。
   詳細は開発者 ([@code_utakata](https://x.com/code_utakata)) までご連絡ください。

---

## リンク

- [リポジトリ](https://github.com/utakata-code/utakata)
- [pub.dev](https://pub.dev/packages/utakata)
- [X (Twitter) @code_utakata](https://x.com/code_utakata)
- [utakata code](https://github.com/utakata-code)
