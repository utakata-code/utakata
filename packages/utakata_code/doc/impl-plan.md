# doc/impl/ — feature 実装計画のライフサイクル

規模のある変更は、コードを書く前に**実装計画**を作ります。
計画は `doc/impl/<レーン>/PLAN-NNNN_{feature}.md` に置かれ、
状態が変わるとファイルがレーン(サブディレクトリ)間を移動します。
feature に紐づかない作業(リファクタリング・文書整理)は種別を付けて
`PLAN-NNNN_refactor_{target}.md` のように作ります(v1.8.0)。

```sh
utakata doc show impl    # このドキュメントを表示
```

---

## 状態は2軸

```yaml
status: in_progress   # todo | in_progress | review | done | archived
test:   todo          # not_required | todo | in_progress | review | done
```

- **`status`** — 実装そのものの進行。`review` は**自分のレビュー段階**です
- **`test`** — 検証の進行。`not_required` は「テストは不要」と**明示**する値で、
  「まだ決めていない(`todo`)」と区別されます

1本の列にまとめない理由: 「実装完了・テスト未着手」と「実装レビュー中」が
同じ位置になってしまい、テストが落ちて実装へ戻る動きも表現できないためです。

---

## レーン(ディレクトリ)は2軸から導出される

```
doc/impl/
├── 1_todo/                # status: todo
├── 2_in_progress/         # status: in_progress
├── 3_review/              # status: review
├── 4_test_todo/           # status: done かつ test: todo
├── 5_test_in_progress/    # status: done かつ test: in_progress
├── 6_test_review/         # status: done かつ test: review
├── 7_done/                # status: done かつ test: done | not_required
└── archive/               # status: archived
```

導出の規則は「**今どこで止まっているか**」です:

1. 実装が終わっていない → 実装側のレーン(1〜3)
2. 実装は終わったが検証が残っている → テスト側のレーン(4〜6)
3. 両方終わった → `7_done`

### 正は frontmatter、ディレクトリは導出

ディレクトリと frontmatter の**両方を正にはしません**(食い違ったときに
どちらを信じるか決められなくなるため)。コマンドは frontmatter を更新して
から移動するので1操作で両方が揃います。手でファイルを動かした場合は:

```sh
utakata impl sync --dry-run   # 何が動くか確認
utakata impl sync             # frontmatter に合わせて再配置
```

`utakata doctor` も乖離を検出して案内します。

---

## 計画書は「計画」と「実施記録」の2領域(v1.8.0)

本文はマーカー行 `<!-- utakata:log -->` で上下に分かれます。

```md
# 実装計画
## 1. 背景・目的
…(計画。impl start で凍結される)…

<!-- utakata:log -->
## 実施記録

- 2026-10-07 10:12 (haruma) status: todo → in_progress
- 2026-10-07 11:40 (agent:claude) 既存の DataSource を流用する方針に決定
- 2026-10-08 09:00 (haruma) revised (#1): 性能要件の追加で方針変更
```

| 領域 | 誰がいつ書くか | CLI の扱い |
|---|---|---|
| **計画**(マーカーより上) | `todo` の間は自由に編集。`impl start` で**凍結** | 指紋(`plan_digest`)を記録し、変更を検知する |
| **実施記録**(マーカーより下) | いつでも。**ファイルを直接編集せず** `impl note` で追記 | 日時と記録者を付けて 1 行追記。状態遷移も自動で 1 行残る |

分けている理由: 1本の計画書が「計画 → 実施記録 → 追試 → 次ビルドの確認項目」と
時系列で伸び、どこが計画でどこが記録か読めなくなるためです。記録を CLI 経由に
するのは `records.agent_write: append` と同じ考え方で、日時と記録者が必ず付き、
過去の記録を書き換える経路がありません。

CLI が本文を解釈するのは**このマーカー 1 行を探すことだけ**です。節構造は
解析しません。マーカーの無い 1.7.x 以前のファイルは全体が計画として扱われ、
最初の追記(`impl note` または状態遷移)で末尾に領域が作られます。

```sh
utakata impl note PLAN-0001 "既存の DataSource を流用する方針に決定"
cat memo.txt | utakata impl note PLAN-0001        # stdin からも読める
```

記録者は環境変数 `UTAKATA_ACTOR`(無ければ `USER`)で決まります。
`claude init` が生成する settings.json は `agent:claude` を渡すので、
AI の記録は人間の記録と区別できます。

---

## 凍結と改訂(v1.8.0)

計画書は仕様書ではないので、常に最新である必要はありません。むしろ
「着手時に何を計画していたか」が残っていることに価値があります。

- `impl start`(`todo` を離れる最初の遷移)で計画部分の指紋を `plan_digest` に記録します
- 以後、計画部分が書き換えられていると**状態遷移が止まります**(`archive` は除く)。
  `utakata doctor` も受理されていない書き換えを報告します
- 止めるのは遷移であって編集そのものではありません。誤字 1 つ直すのに
  新しい計画書が要る運用にはしていません

凍結後に計画を変えたくなったら、変更の大きさで 2 つに分けます。

| 変更 | やること |
|---|---|
| 小さな修正(誤字・補足・手順の入れ替え) | 計画部分を直したうえで `utakata impl revise <ID> --reason "理由"`。`revisions` が +1 され、理由が実施記録に残る |
| 設計方針・スコープが変わる | 凍結した計画書に上書きせず、`utakata impl new <target> --supersedes <旧ID>` で新しい計画書を切る。旧計画は `impl archive`。ボードに双方向で「置き換え」が表示される |

```sh
utakata impl revise PLAN-0001 --reason "性能要件の追加で方針変更"
utakata impl new login --supersedes PLAN-0001
```

`revise` は変更が無いとき・`todo` のまま(まだ凍結されていない)・理由が
無いときは拒否します。回数がボードに出るので、「何度も計画が変わった
feature」が見えます。

指紋は改行コード・行末の空白・末尾の空行を正規化してから計算するので、
エディタの自動整形で「変更あり」にはなりません。

---

## 種別(v1.8.0)

`impl new` の引数は `[kind:]<target>` です。

```sh
utakata impl new login                   # feat:login と同じ(1.7.x までと同じ書き方)
utakata impl new fix:login               # login の不具合修正
utakata impl new refactor:doc_layout     # feature に紐づかない作業
utakata impl new docs:readme
```

| kind | 対象 | ファイル名 | `enforcement.impl_plan` の照合 |
|---|---|---|---|
| `feat`(既定)/ `fix` | plan.yaml の feature | `PLAN-NNNN_<feature>.md` | **対象** |
| `refactor` / `docs` / `chore` / `test` | 作業の対象名 | `PLAN-NNNN_<kind>_<target>.md` | 対象外 |

引数を任意にせず種別を前置きさせるのは、feature 名がゲートの照合キーだから
です。`refactor:login` の計画があっても、login feature の実装計画があるとは
見なしません。

---

## コマンド

```sh
# 作成
utakata impl new [kind:]<target> [--agreement AGR-003] [--spec <path>] [--message MSGR-20260811-001] [--basis client_agreed] [--backlog <項目>] [--supersedes PLAN-0001]

# 記録・改訂
utakata impl note <ID> "本文"             # 実施記録を 1 件追記(stdin 可)
utakata impl revise <ID> --reason "..."  # 凍結後の書き換えを改訂として受理

# 実装軸
utakata impl start <ID>      # → in_progress
utakata impl review <ID>     # → review(自分のレビュー)
utakata impl done <ID>       # → done(完了日を記録)

# 検証軸(実装が done になってから)
utakata impl test start <ID>
utakata impl test review <ID>
utakata impl test done <ID>
utakata impl test todo <ID>                    # 差し戻し
utakata impl test skip <ID> --reason "設定変更のみ"

# 参照
utakata impl list [--status <s>] [--test <s>] [--lane <lane>] [--json]
utakata impl board            # レーン別ボード(doc/preview/impl_board.md を再生成)

utakata impl archive <ID>     # 参照しなくなったら archive/ へ
                              # 戻すときは utakata impl start <ID> 等で通常の遷移
utakata impl sync [--dry-run]
```

### 逆行は許可されています

`done` にした後で `utakata impl start` を実行すれば `2_in_progress` に戻ります。
テストが落ちて実装に戻るのは正常な流れであり、一方通行にすると現実の作業を
記録できなくなるためです。

ただし**検証軸は実装が `done` になるまで進められません**(実装が終わって
いないのにテスト完了はあり得ないため)。`--force` は用意していません。

### 壊れた計画・重複 ID は動かさない

frontmatter が読めない計画(手編集で YAML を壊した等)は一覧・採番から
外れますが、**`utakata doctor` が件数とパスを報告**します(黙って消えると
ID が再利用されて別の計画を上書きするため)。同じ ID のファイルが複数ある
場合も同様に報告し、遷移・移動は拒否されます — どちらを残すかは人が決めます。

移動先に同名ファイルが既にある場合、`impl sync` はそれを**上書きせずスキップ**
して報告します(exit 1)。

### ボードは自動で最新に保たれる

状態を変えるコマンド(`start` / `review` / `done` / `test *` / `archive` /
`sync` / `new`)は、実行後に `doc/preview/impl_board.md` を再生成します。
手動で再生成する必要はありません。

---

## `enforcement.impl_plan` — 計画なしの実装を止める

`utakata.yaml`:

```yaml
enforcement:
  impl_plan: "on"     # 既定は off
```

`on` にすると、`utakata apply --scope feature` と `utakata feature add` が
**feature 単位で**ゲートします:

- **これから新規に**スキャフォールドする feature に、archived でない計画が
  無ければ、その feature だけスキップして `utakata impl new <feature>` を案内
- 他の feature の生成は通常どおり進む(1つ欠けただけで全体を止めない)
- 1件でもスキップしたら exit 1(CI で気づける)
- **既にディスクにある feature には作用しません**(これから実装を始める
  わけではないため)

計画の有無は「archived 以外の計画が1つでもあるか」で判定します。`done` でも
満たします — 細かすぎる要求は運用を殺すためです。数えるのは種別が `feat` /
`fix` の計画だけで、`refactor:login` のような計画は login の実装計画とは
見なしません(v1.8.0)。

CLI を通さずに直接コードを書いた場合はゲートできないので、
`utakata doctor` が「実装があるのに実装計画が無い feature」を情報として
報告します。

---

## frontmatter

```yaml
---
id: PLAN-0001
feature: login             # kind が feat/fix なら feature 名、それ以外は作業の対象名
kind: feat                 # feat | fix | refactor | docs | chore | test(v1.8.0)
status: in_progress
created: 2026-08-11
origin:                    # 根拠へのリンク
  agreements: [AGR-003]
  specs: []
  messages: [MSGR-20260811-001]
basis: client_agreed       # client_agreed | developer_judgment
test:
  status: todo
  static: pending          # 自動検証(flutter analyze / utakata check)
  on_device: pending       # 実機確認
completed_on: 2026-08-20   # done のときだけ書かれる(戻すと消える)
plan_digest: 3f9a…         # impl start で記録される計画部分の指紋(v1.8.0)
revisions: 1               # impl revise の回数。0 なら書かれない(v1.8.0)
supersedes: PLAN-0001      # 置き換えた旧計画(--supersedes を付けたときだけ)(v1.8.0)
---
```

`skip_reason` は `test: not_required` のときだけ書かれ、他の状態へ移ると消えます。
`static` / `on_device` は `impl test done` で `done` になり、差し戻すと `pending` に戻ります。

本文(Markdown)のうち計画部分は人間/AI の記述領域、実施記録は CLI 経由の
追記領域です。**frontmatter は CLI が機械管理する**ので手で編集せず、
コマンドで遷移させてください(編集してしまった場合は `utakata impl sync` で
配置を戻せます)。

---

## v1.7.x からの移行

**何もしなくても読めます。** 1.7.x で作った計画書は:

- `kind` が無いので `feat` として読まれます。ファイル名は変わらず、移動も起きません
- `plan_digest` が無いので未凍結として読まれ、次の状態遷移で凍結されます
- マーカーが無いので全体が計画として扱われ、最初の追記で末尾に実施記録の
  領域が作られます(計画部分の指紋は変わりません)

`claude init` が生成する `utakata-impl-flow` スキルは新しいフローに
書き換わっています。既存プロジェクトでは古いスキルが残るので、
`utakata doctor` の案内に従って再生成してください
(`doc/skills/utakata-upgrade/SKILL.md` に手順があります)。

---

## v1.6.x からの移行

- `status: draft` は `todo` として読まれます(書き戻しは `todo`)
- 旧 `verification:`(`static` / `on_device`)は `test:` に統合されます。
  両方 `done` なら `test: done` として読まれます
- フラット配置(`doc/impl/*.md`)のままでも読めます。
  `utakata impl sync` でレーンへ移動できます
