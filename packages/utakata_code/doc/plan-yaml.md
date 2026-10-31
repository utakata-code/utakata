# `doc/specs/plan.yaml` の書き方

**何のファイルか**: 「何を作りたいか」だけを宣言する意図レベルの計画書。
具体的なディレクトリ構造は utakata が `arch_definition.yaml` から毎回導出するため、
ここには書きません。

- 生成: `utakata doc init`(雛形)
- 参照: `utakata check`(検証)/ `utakata apply`(生成)
- 編集: 人間が直接書く / `utakata plan add|remove|expand|adopt`

> 旧バージョンとの対応: このファイルは旧 `feature_request.yaml` の役割を担います。
> 旧 `plan_architecture.yaml`(自動生成の具象ツリー)は廃止され、必要な場合のみ
> `plan expand` で `layers:` としてこのファイル内に展開されます。
> 旧 `actual_architecture.yaml`(スナップショット)は廃止され、`check` が毎回
> 実ディレクトリを走査します。

---

## 最小の例

```yaml
schema: 1
project:
  architecture: clean_architecture
features:
  - name: todo
    permission: user
    entities: [todo]
```

これだけで、`utakata apply --scope feature` が `lib/features/user/todo/` 配下に
アーキテクチャ定義どおりの層ディレクトリと、`todo_entity.dart` /
`todo_repository.dart` … といった**必須ファイル(空ファイル)**を生成し(v1.5.0〜)、
`utakata check` がその存在と命名を検証します。既存ファイルは上書きされません。

---

## トップレベル

| キー | 型 | 説明 |
|---|---|---|
| `schema` | int | スキーマバージョン。現在は `1`。省略時は `1` とみなす |
| `project.architecture` | string | 既定のアーキテクチャ ID。**`utakata.yaml` の指定が優先される**(両方あって食い違う場合は警告が出るので、通常は `utakata.yaml` 側に書く) |
| `features` | list | feature の宣言リスト。空なら `features: []` |

---

## `features` の各要素

| キー | 型 | 必須 | 説明 |
|---|---|---|---|
| `name` | string | ✅ | feature 名(snake_case)。ディレクトリ名になる |
| `permission` | string | | `admin` / `user` / `shared` / `direct`。既定は `user`。`direct` のみ `lib/features/<name>/` 直下に置かれ、他は `lib/features/<permission>/<name>/` になる |
| `entities` | list | | この feature が扱うエンティティ名。命名規則の `{name}` に代入され、必須ファイルが導出される。省略時は `name` が使われる |
| `architecture` | string | | この feature だけ別アーキテクチャにする場合の上書き |
| `layers` | map | | 層ごとの明示宣言(後述)。**省略すれば `entities` から自動導出** |
| `baseline` | bool | | `plan adopt` が既存コードを取り込む際に付ける印。手で書く必要はない(※現在は記録のみで挙動に影響しません) |

### 複数エンティティ

```yaml
features:
  - name: purchase
    permission: user
    entities: [purchase_record, exclusion_item]   # 各エンティティ分のファイルが必須になる
```

---

## `layers` — 層ごとの増減(v1.1.0〜)

feature を宣言しても「全部の層が必須」にはしたくない場合に使います。
キーは**アーキテクチャ定義の層パス**(`utakata arch show <id>` で確認できます)。

```yaml
features:
  - name: todo
    permission: user
    entities: [todo]
    layers:
      1_domain/3_usecases: [get_todo, save_todo]     # ①必要なものだけ明示
      2_infrastructure/2_data_sources/2_remote: []   # ②この層は不要
      4_presentation/1_widgets: []                   # ③親パス指定で配下ごと除外
```

### 3つの状態

| 書き方 | 意味 |
|---|---|
| **キーを書かない** | 従来どおり `entities` から自動導出する(**これが基準**) |
| **項目リストを書く** | その項目**だけ**を必須にする |
| **空リスト `[]`** | その層は対象外。`check` の missing に出ず、`apply` も生成しない |

### 項目名 → ファイル名の変換

項目名は、その層の命名規則の接尾辞と連結されます:

| 層の命名規則 | 項目名 | 必須になるファイル |
|---|---|---|
| `{name}_entity.dart` | `todo` | `todo_entity.dart` |
| `{verb}_{name}_usecase.dart` | `get_todo` | `get_todo_usecase.dart` |
| `{feature}_page.dart` | `detail` | `detail_page.dart` |

`.dart` で終わる項目名は、ファイル名そのものとして扱われます(逃げ道):

```yaml
    layers:
      1_domain/1_entities: [legacy_thing.dart]   # そのまま legacy_thing.dart
```

> **なぜ層パスをキーにするのか**: `usecases` / `services` のような呼び名は
> アーキテクチャごとに違うため、`arch_definition.yaml` と同じ層パスを使うことで
> Clean Architecture でも MVVM でも独自アーキテクチャでも同じ書式が通ります。

---

## コマンドとの関係

```sh
# 自動導出されている構成を plan.yaml に書き出す(以後は手で増減できる)
# 書き出される項目は拡張子込みの完全ファイル名(v1.5.0〜。例: todo_entity.dart)
utakata plan expand
utakata plan expand --dry-run          # 書き込まず確認だけ
utakata plan expand --feature todo     # 対象を1つに絞る

# 1項目ずつ増減する(AI エージェント・スクリプト向け。書式は保持される)
utakata plan add todo 1_domain/3_usecases get_todo save_todo
utakata plan remove todo 1_domain/1_entities todo

# lib/features/ にあるが plan.yaml に無い feature を検出して追記する
utakata plan adopt

# 宣言どおりに生成 / 検証
utakata apply --scope feature
utakata check
```

### `plan expand` の注意点

書き出される項目は**拡張子込みの完全ファイル名**です(v1.5.0〜)。
plan.yaml 上で「見たまま」になり編集しやすく、`.dart` で終わる項目は
ファイル名リテラルとして扱われるため check/apply との食い違いも起きません
(`todo` のような項目名での手書きも従来どおり有効です)。

命名が非決定的な層(`{verb}` を含む usecases など)は**書き出されません**。
空リスト `[]` は「不要」を意味するため、導出できない層を `[]` で埋めると
誤って除外扱いになってしまうためです。それらは `plan add` で追加してください。

既に `layers` 宣言がある層は、人間の編集結果として**上書きされません**。

---

## よくある質問

**Q. ファイル名をフルパスで書かなくてよいのか？**
はい。命名規則から導出されるため、`entities` に名前を書くだけで済みます。
逆に、命名が自由な層で特定のファイルを必須にしたい場合だけ `layers` で明示します。

**Q. `check` が「余分なファイル(extra)」と言わないのはなぜ？**
命名規則(`arch_definition.yaml` の `file_pattern`)に合致するファイルは、
`plan.yaml` に列挙されていなくても正当とみなします。規則に合わないものだけが
命名違反として報告されます。

**Q. plan.yaml を書かずに `feature add` してもよい？**
はい。`utakata feature add <name>` は、plan.yaml があればその feature を
`features:` に登録し、check が必須とする空ファイルも作ります(`apply` と同じ
導出。既存ファイルは上書きしません)。続けて `utakata check` がそのまま通ります。

- 書く中身は `name` / `permission` / `entities`(`--entity`、省略時は feature 名)。
  `architecture` は `--arch` を明示したときだけ書きます
- 同じ名前の feature が既にあれば追記せず、plan.yaml 側の宣言で必須ファイルを作ります
- `features: []` へ追記するときも block 形式で書きます(`[{name: ...}]` にしない)
- plan.yaml が無いプロジェクトでは今までどおりフォルダーを作るだけで、
  plan.yaml を新しく作りません(作るなら `utakata doc init`)

逆に既に手で書いたコードがある場合は `utakata plan adopt` で取り込めます。
