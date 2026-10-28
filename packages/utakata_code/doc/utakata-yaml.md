# `utakata.yaml` の書き方

**何のファイルか**: プロジェクト全体のルールと座組を定義するマスター設定。
プロジェクトルート(`lib/` や `doc/` と同じ階層)に置きます。

- 生成: `utakata doc init`
- 検証: `utakata doctor`(未知キー・非対応スキーマを検出)
- 参照: ほぼ全コマンド + MCP の `config_get`

**すべてのキーが任意です。** ファイルが無くても全コマンドは既定値で動作します
(既存プロジェクトの挙動を壊さないための設計)。

---

## 全体像

```yaml
schema: 1

project:
  architecture: clean_architecture
  knowledge_repo:                                  # 任意(オプトイン)
    url: "https://github.com/utakata-code/utakata_arch_lib.git"
    ref: "v1.0.0"

skills:                                            # 任意
  - clean-arch-auditor

team:                                              # 任意
  client: "山田さん(要件の決定権者。仕様変更はこの人の合意が必要)"
  developer: "私(アーキテクチャ責任者。コードの最終レビューを行う)"
  ai_agents:
    - id: feature-builder
      role: "実装担当。plan.yaml と層ごとのガイドを読み込みコードを生成する。"

enforcement:
  impl_plan: "off"                                 # on で計画なしの実装を止める
records:
  agent_write: none                                # none | append | full
  agent_read:
    messages: false
  git: commit                                      # 予約(下記参照)
lang: ja                                           # 予約(下記参照)
```

---

## `schema`

スキーマバージョン。現在は `1`。
CLI が知らない将来のバージョン(`2` 以上)が書かれていると `doctor` がエラーとして報告します。

---

## `project.architecture`

このプロジェクトで使うアーキテクチャ ID(`utakata arch list` で一覧)。

**解決の優先順位**(v1.0.2 で全コマンド統一):

1. コマンドの明示指定(`--arch` / MCP の `architecture_id`)
2. **`utakata.yaml` の `project.architecture`** ← ここ
3. `doc/specs/plan.yaml` の `project.architecture`
4. 既定値 `clean_architecture`

`plan.yaml` にも書いてあって食い違う場合は、`utakata.yaml` が勝ち、警告が出ます。
**アーキテクチャの指定はこのファイルに一本化するのがおすすめです。**

---

## `project.knowledge_repo` — リモートナレッジ(オプトイン)

```yaml
project:
  knowledge_repo:
    url: "https://github.com/your-org/your_arch_lib.git"
    ref: "v1.0.0"     # タグ or ブランチ。省略可
```

| キー | 説明 |
|---|---|
| `url` | [utakata_arch_lib](https://github.com/utakata-code/utakata_arch_lib) と同じ構造(`arches/<id>/...`)を持つ Git リポジトリ |
| `ref` | タグまたはブランチ名。実際に取得したコミット SHA は `utakata.lock` に固定される |

**指定しなければ、公式の utakata_arch_lib(CLI バージョンに対応する固定タグ)が
既定として使われます。** パッケージには実行時必須の `arch_definition.yaml` と
skills だけが同梱されているため、構造コマンド(`create`/`apply`/`check` 等)は
ネットワークなしで完結します。ガイド等の読み物を初めて参照した時のみ、公式
リポジトリから自動フェッチして `~/.utakata/cache/` に保存します(以後はキャッシュ)。
オフラインになる前に `utakata arch get` を一度実行しておけば事前取得できます。

指定した場合の使い方:

```sh
utakata arch get              # フェッチして utakata.lock に SHA を固定
utakata arch get --update     # ref を再解決して更新(SHA の変化が表示される)
```

`utakata.lock` は生成物ですが、**チームで再現性を保つためコミットすることを推奨**します。

---

## `skills` — AI スキルの同期リスト

`utakata skills sync` で `.claude/skills/` に同期する、**アーキテクチャ同梱スキル**の ID を列挙します。

```yaml
skills:
  - clean-arch-auditor
```

利用可能な ID は、間違った ID を指定した際のエラーメッセージに一覧表示されます。

> **注意**: `utakata-structure` など `utakata create` が生成する汎用スキルは
> ここに書きません(既に `.claude/skills/` に配置済みのため)。

同期時の保護ルール:

| 状況 | 挙動 |
|---|---|
| マーカーの無いファイル(人間が作成) | **絶対に上書きしない**(`--force` でも) |
| 未編集の managed ファイル | 更新する |
| 人間が編集した managed ファイル | スキップ(`--force` 指定時のみ上書き) |
| リストから外した managed スキル | 削除候補として報告のみ(自動削除しない) |

---

## `team` — 登場人物と役割

「誰の決定に従い、誰に判断を仰ぐか」を AI エージェントに機械可読で与えます。

```yaml
team:
  client: "山田さん(要件の決定権者)"
  developer: "私(コードの最終レビュー)"
  ai_agents:
    - id: feature-builder
      role: "実装担当。plan.yaml と層ごとのガイドを読み込みコードを生成する。"
    - id: structure-auditor
      role: "監視担当。utakata check で構造違反を検知して人間に報告する。"
```

| キー | 型 | 説明 |
|---|---|---|
| `client` | string | お客様(要件の決定権者)。自由記述 |
| `developer` | string | 開発者。自由記述 |
| `ai_agents` | list | `{id, role}` のリスト |

**どこで使われるか**:

- `utakata create` / `utakata claude init` が生成する `CLAUDE.md` に「登場人物と役割」節として出力される
- MCP の `config_get` ツールで AI が取得できる

`ai_agents` は現時点では**役割の記述**であり、複数 AI を自動でオーケストレーションする
実行機構はまだありません(実案件での必要性が固まってから実装予定)。

---

## `vault` — 実務ナレッジ Vault(クライアント説明用)

外部サービス(Apple / Google / LINE 等)のアカウント取得手順・料金・審査要否など、
**クライアントへの説明に使う知識**を蓄積したリポジトリへの参照。
アーキテクチャ知識(`knowledge_repo`)とは別物です。

```yaml
vault:
  path: "~/dev/utakata_vault"                    # 手元のクローン(優先)
  url: "git@github.com:you/your_vault.git"       # または git から取得(プライベート可)
  ref: main
```

| キー | 説明 |
|---|---|
| `path` | 手元のクローンへのパス(`~` 展開あり)。**存在すればこちらが優先** |
| `url` | リモート Git URL。プライベートリポジトリ可(認証は git の設定に委ねる) |
| `ref` | タグ/ブランチ名 |

**`path` の解決規則**(v1.5.0〜):

- 絶対パス・`~` 始まり → そのまま使う
- 相対パス → **その設定が書かれたファイルの場所**基準で解決する
  - プロジェクトの `utakata.yaml` に書いた場合 → プロジェクトルート基準
  - `~/.utakata/config.yaml` に書いた場合 → `~/.utakata/` 基準

**`path` を優先する理由**: Vault は開発者本人が書き足していく個人資産のため、
毎回 push → fetch するのは非現実的です。手元のクローンを直接見れば編集が即反映されます。
`url` はチーム共有や別マシンでの利用時に使います。

### 全案件共通の設定 — `~/.utakata/config.yaml`

Vault は案件をまたぐ個人資産なので、通常は**グローバル設定**に書きます:

```yaml
# ~/.utakata/config.yaml
vault:
  path: "~/dev/utakata_vault"
```

解決順は **プロジェクトの `utakata.yaml`** → **`~/.utakata/config.yaml`** → 未設定。
グローバル設定はプロジェクト設定と同じスキーマですが、意味を持つのは案件横断の項目のみです。

### 使い方

```sh
utakata vault list                          # エントリ一覧
utakata vault show Google/GCP/Firebase      # 本文を表示
utakata vault get                           # url からの取得(path 運用なら不要)
```

MCP からは `vault_list` / `vault_get` で参照できます。生成される
`utakata-client-explainer` スキルが、この Vault を根拠にクライアント向け説明文を
書くよう AI を誘導します。**AI は Vault に書き込みません**(追記は人間が Vault
リポジトリ側で行う)。

---

## `enforcement.impl_plan` — 計画なしの実装を止める

```yaml
enforcement:
  impl_plan: "on"     # 既定は off
```

`on` にすると `utakata apply --scope feature` と `utakata feature add` が
**feature 単位で**ゲートし、実装計画の無い feature のスキャフォールドを
スキップします(他の feature は通常どおり生成され、スキップがあれば exit 1)。
既にディスクにある feature には作用しません。数えるのは種別が `feat` / `fix` の
計画だけです(`refactor:` 等は feature の実装計画と見なしません。v1.8.0)。

詳細は [impl-plan.md](impl-plan.md)(`utakata doc show impl`)を参照してください。

---

## `records` — 記録の扱いと AI に許す範囲

```yaml
records:
  agent_write: none        # none | append | full(既定: none)
  agent_read:
    messages: false        # 既定 false(送受信原文は AI に見せない)
```

| キー | 説明 |
|---|---|
| `agent_write` | AI エージェントによる記録への書き込み許可。`none` = 読むだけ / `append` = **CLI 経由の追記のみ**(ファイル直接編集は不可) / `full` = 直接編集も可 |
| `agent_read.messages` | `true` で MCP に `message_query` を公開する(false ならツール自体が現れない) |

`append` は「エージェントに記録させたいが、過去の記録は改変させたくない」場合の
中間段階です。詳細・運用のコツは [records.md](records.md)
(`utakata doc show records`)を参照してください。

> **設定を変えたら** `utakata claude init --only settings` で `.claude/settings.json` を
> 再生成してください(オプション無しの `claude init` は既存ファイルを上書きしません。
> `--force` は CLAUDE.md も上書きします)。食い違いは `utakata doctor` が検出します。

---

## 予約キー(現在は未配線)

以下は `doc init` の雛形に含まれ、`doctor` の検証も通りますが、
**まだ挙動には影響しません**。将来のバージョンで配線予定です。

| キー | 想定 | 現状 |
|---|---|---|
| `records.git` | `doc/records/` を commit するか ignore するか | パースのみ |
| `lang` | CLI メッセージの言語 | パースのみ。**現在の言語切り替えは環境変数** `UTAKATA_LANG=ja\|en`(未設定時は `LANG` から推定)で行う |

---

## 検証

```sh
utakata doctor
```

- 未知のトップレベルキー(タイポ)を警告
- 非対応の `schema`(将来バージョン)をエラー報告
- `doc/specs/plan.yaml` の欠落なども併せて診断

---

## プロジェクト内の他のファイルとの関係

| ファイル | 役割 |
|---|---|
| `utakata.yaml` | **プロジェクト全体の設定**(このファイル) |
| `utakata.lock` | `knowledge_repo` のコミット SHA 固定(`arch get` が生成) |
| `doc/specs/plan.yaml` | feature の意図レベル計画 → [plan-yaml.md](plan-yaml.md) |
| `CLAUDE.md` | AI エージェント向けの入口(`team` から自動生成) |
| `.claude/settings.json` | フックと deny ルール(`doc/records/**` への書き込み禁止) |
