---
name: utakata-upgrade
description: utakata CLI を上げた既存プロジェクトを、新しいバージョンに追従させる。`utakata doctor` が「生成済みスキルが古い」と言う、CLI を上げたのに AI が古い手順で動く、1.7.x → 1.8.0 で実装計画書がどう変わるか知りたい、というときに使う。
---

# utakata CLI の更新手順(既存プロジェクト向け)

CLI を上げるだけでは、プロジェクト側に**生成済みのファイル**は古いまま残る。
`utakata claude init` は既存ファイルを上書きしないので、`.claude/skills/` の
スキルや `CLAUDE.md` は、生成した当時のバージョンの手順を AI に教え続ける。

この手順は**ユーザーの確認なしに `--force` を使わない**ことが要点。

## Step 0. 現状確認

```bash
utakata --version          # 上がっていること
git status                 # 未コミットの変更が無いこと
utakata doctor
```

`doctor` の出力をユーザーに見せる。この手順で扱うのは次の 2 種類だけ。

| doctor の指摘 | 対応 |
|---|---|
| `.claude/skills/<name>/SKILL.md が古いバージョンのまま` | Step 1 |
| 実装計画に関する案内(凍結後の書き換え・配置違い) | Step 2 |

それ以外(utakata.yaml の未知キー、records の設定と settings.json の乖離等)は
この手順の対象外。別途ユーザーに確認する。

## Step 1. 古い生成済みスキルだけを再生成する

**`utakata claude init --force` は使わない。** `--force` は `settings.json` と
`CLAUDE.md` も作り直すので、人が足した hooks・permissions・CLAUDE.md の記述が
消える。

代わりに、古いと言われたスキルの SKILL.md だけを消して `claude init` を
通常実行する。`claude init` は**無いファイルだけ**を書くので、そのスキルだけが
新しい内容で生成され、他のファイルには触れない。

```bash
git rm .claude/skills/utakata-impl-flow/SKILL.md     # doctor が名指ししたものだけ
utakata claude init
git diff --stat                                      # そのスキルだけが変わっていること
utakata doctor                                       # 指摘が消えていること
```

スキルを**人が編集していた**場合は、消す前に差分を確認してユーザーに聞く。
生成物に手を入れていたなら、新しい生成物にその編集を移す必要がある。

ここでコミットする(`chore: utakata <version> に合わせて生成済みスキルを更新`)。

## Step 2. 実装計画書(doc/impl/)の確認

**1.7.x → 1.8.0 では、既存の計画書に対して何もしなくてよい。** 読み方が
変わっただけで、ファイルの移動も書き換えも起きない。

| 1.8.0 の変更 | 既存ファイルの扱い |
|---|---|
| 種別 `kind:`(feat / fix / refactor / docs / chore / test) | 無ければ `feat`。ファイル名はそのまま |
| 計画部分の凍結(`plan_digest`) | 無ければ未凍結。**次の状態遷移で凍結される** |
| 本文の `<!-- utakata:log -->` マーカー | 無ければ全体が計画。**最初の追記で末尾に作られる** |

ただし運用は変わる。ユーザーに次を伝える。

- `impl start` 以降、計画部分(マーカーより上)を書き換えると状態遷移が止まる。
  意図した変更なら `utakata impl revise <ID> --reason "..."` で受理する
- 進捗や試行錯誤は本文に直接書かず `utakata impl note <ID> "..."` で追記する
- 既に進行中(`2_in_progress` 以降)の計画書は、**次の遷移の時点の本文**が
  凍結の基準になる。それまでに書き溜めた記録を計画部分から実施記録へ
  移したいなら、遷移の前に手で移してよい(まだ凍結されていないので止まらない)

`doctor` が「凍結後に書き換えられています」と言う場合は、`revise` するか
計画部分を元に戻すかをユーザーに聞く。**勝手に revise しない。**

## Step 3. CLAUDE.md の確認

`CLAUDE.md` は `claude init` が初回に生成した後、人が育てていることが多い。
再生成せず、`utakata doc show impl` の内容と食い違う記述(「本文は自由に
追記してよい」等)があれば、該当箇所だけ直す。差分はユーザーに見せる。

## やってはいけないこと

- `utakata claude init --force`(settings.json と CLAUDE.md が消える)
- doctor が名指ししていないスキルを消す
- 人が編集した生成物を、確認せずに捨てる
- `impl revise` を代行する(計画を変えた理由は人が書く)
- `doc/impl/` の frontmatter を手で直す(`utakata impl sync` を使う)

## 更新と同時にやらないこと

- 既存の計画書を種別付き(`refactor:` 等)に作り直す。1.7.x の計画書は
  `feat` のままで問題なく動く
- `enforcement.impl_plan` の切り替え。更新が落ち着いてから別途相談する
