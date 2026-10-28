# doc/records/ — 案件の記録と、AI に許す範囲

お客様とのやり取りをどこに何の形で残すか、そして AI エージェントに
どこまで触らせるか(`records.agent_write`)のリファレンス。

```sh
utakata doc show records    # このドキュメントを表示
```

---

## 4つの系統

`doc/records/` は性質の違う4系統に分かれています。**混ぜないこと**が要点です。

| 系統 | 保存先 | 中身 | 誰が書くか |
|---|---|---|---|
| 会話ログ | `doc/records/log/YYYY-MM.jsonl` | 人間が**要約・整理した**やり取り | `utakata log add` |
| 合意 | `doc/records/agreements.jsonl` | 決まったこと(金額・納期・仕様) | `utakata agree add` |
| **送受信原文** | `doc/records/messages/YYYY-MM.jsonl` | 実際に送受信した**文面そのまま** | `utakata message add` / `import` |
| AI セッション | `doc/records/sessions/` | Claude Code との会話 | `utakata log import claude-session` |

**要約(log)と原文(messages)を分けている理由**: 原文は「言った / 言わない」の
一次証跡なので、改変せず全文を残します。要約は検索・把握のためのもので、
書き直して当然です。同じファイルに混ぜると、量とノイズで要約の検索性が落ち、
保持ポリシーも曖昧になります。

いずれも**追記専用**で、プレビュー(`doc/preview/`)は
`utakata log render` / `utakata message render` でいつでも再生成できます。

---

## `utakata message` — 送受信原文

```sh
# 1件記録(本文は引数か stdin)
utakata message add -d inbound -c client_portal --from "山田様" --at "2026-08-11 10:24" "本文…"
cat mail.txt | utakata message add -d outbound -c mail --subject "お見積り"

# 既存のやり取りを一括取り込み(重複は自動でスキップ)
utakata message import --format jsonl --file exported.jsonl
utakata message import --format md --file thread.md --channel client_portal
utakata message import --format md --file thread.md --dry-run   # 件数だけ確認

# 参照・整形
utakata message list --direction inbound --month 2026-08
utakata message show MSGR-20260811-001
utakata message render          # doc/preview/messages/YYYY-MM.md を再生成

# 後から要約ログ・合意に紐付ける(本文には触れない)
utakata message link MSGR-20260811-001 --log MSG-20260811-003 --agreement AGR-0003
```

| オプション | 説明 |
|---|---|
| `-d, --direction` | **必須**。`inbound`(先方→自分) / `outbound`(自分→先方) |
| `-c, --channel` | `client_portal` / `mail` / `chatwork` など自由文字列 |
| `--at` | 送受信日時。省略時は現在時刻を使い「概算」印が付く |
| `--from` / `--to` / `--subject` / `--thread` | 任意のメタ情報 |
| `--external-id` | 取り込み元での ID。**再取り込み時の重複排除キー** |
| `--attachment` | 添付ファイルのパス(複数指定可) |

### 重複排除

`message add` と `message import` の**どちらでも**効きます。`--external-id`
付きの `add` は、同じ ID の記録が既にあれば追記せずスキップします
(取り込みツールが同じメッセージを何度投入しても増えない)。

判定の主軸は `external_id` です。取り込み元が ID を持たない場合は
**取り込み元の内容と並び順から合成した ID** を使うため、同じファイルを
何度流し込んでも増えず、かつ同じ文面が複数回現れても別メッセージとして残ります
(日時が原文に無い md では時刻が記録時刻になるため、本文の一致だけで
判定すると「はい」「承知しました」のような定型文が消えてしまう)。

取り込み元が `external_id` を持たず、かつ**日時が原文由来**である場合のみ、
`(direction, 日時, 本文)` の一致でも重複と判定します。

### `--format md` の書式

見出し行でメッセージを区切ります(日時・送信者名は省略可):

```md
## [inbound] 2026-08-11 10:24 山田様
お世話になります。
見積もりの件ですが……

## [outbound] 2026-08-11 12:00
ご連絡ありがとうございます。
```

### 原文はマスクしない

`log import claude-session` は秘密情報らしき記述を `[REDACTED]` に置換しますが、
**`message` は一切加工しません**(原文性が壊れるため)。秘匿が必要な案件は
下記の `agent_read` と `.gitignore` で制御してください。

---

## `records.agent_write` — AI に許す書き込みの3段階

`utakata.yaml`:

```yaml
records:
  agent_write: none        # none | append | full(既定: none)
  agent_read:
    messages: false        # 既定 false(原文は AI に見せない)
```

| 値 | AI にできること | 生成される `.claude/settings.json` |
|---|---|---|
| `none`(既定) | 読むだけ | `doc/records/**` と `doc/preview/**` を deny |
| `append` | **CLI 経由の追記のみ** | deny はそのまま + `Bash(utakata log add:*)` 等を allow |
| `full` | `doc/records/` の直接編集も可 | `doc/preview/**` のみ deny |

### なぜ `append` が要なのか

ファイルを直接触らせず CLI を通させることで、

- ID 採番・スキーマ検証・`reply_to` の存在確認が必ず通る(壊れた JSONL が混入しない)
- **追記しかできない** = 過去の記録の改変・削除が構造的に不可能(証跡性が保たれる)
- `recorded_by` に実行者が残り、人間の記録と区別できる

記録者は環境変数 `UTAKATA_ACTOR` で決まります。`append` / `full` では
生成される `.claude/settings.json` が `UTAKATA_ACTOR=agent:claude` を
env として渡すので、エージェントの記録は `recorded_by: agent:claude` として
残り、人間の記録と区別できます(手動で確認するなら
`UTAKATA_ACTOR=agent:claude utakata message add …` のように前置きしても同じです)。

`full` は社内案件・自分用プロジェクト向けの逃げ道です。
**クライアント案件では推奨しません**(`utakata doctor` が警告します)。

### 設定を変えたら再生成が要る

`utakata claude init` は既存の `.claude/settings.json` を上書きしません。
`records.agent_write` を変えたら:

```sh
utakata claude init --only settings
```

`--only settings` は `.claude/settings.json` だけをファイルごと作り直します
(手で足した hooks・permissions は消えるので、先に差分を控えてください)。
`--force` は `CLAUDE.md` も上書きするので、ここでは使いません。

生成された `CLAUDE.md` の記録についての一文も `agent_write` に連動します。
`CLAUDE.md` に手を入れていなければ `--only settings,claude-md` で両方を
作り直せます。手を入れているなら、該当の一文だけを手で直してください。

設定と実ファイルが食い違っている場合は `utakata doctor` が検出して案内します。

### `agent_read.messages`

`true` にすると MCP に `message_query` ツールが公開され、AI が原文を検索できます。
既定は `false` で、**ツール自体が tools/list に載りません**(公開しなければ
呼べない = 最も確実な保護)。

---

## プレビューと git

- `doc/preview/` はすべて**導出可能な生成物**です。`project_status.{yaml,md}` も
  v1.6.0 からここに出力されます(それ以前は `AI/snapshots/`)
- 生成物なので AI には常に編集させません(`agent_write: full` でも deny のまま)
- git に含めるかは案件次第です。レビューで共有したいならコミットして構いません
