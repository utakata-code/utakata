/// feature 実装計画書(`doc/impl/<lane>/PLAN-NNNN_{feature}.md`)の
/// frontmatter 相当(仕様書 §8)。本文(Markdown)は人間/AI の自由記述領域であり、
/// CLI は frontmatter のみを機械管理する。
///
/// v1.7.0 から状態は**2軸**になった:
///   - [status] 実装そのものの進行
///   - [test]   検証の進行
/// 1本の列にすると「実装完了・テスト未着手」と「実装レビュー中」を区別できず、
/// テストが落ちて実装へ戻る動きも表現できないため。
/// ディレクトリ(レーン)はこの2軸から導出する([ImplLane])。
library;

enum ImplPlanStatus { todo, inProgress, review, done, archived }

/// 検証の進行。[notRequired] は「テスト不要」を**明示**するための値で、
/// 「まだ決めていない([todo])」と区別する。
enum ImplTestStatus { notRequired, todo, inProgress, review, done }

enum ImplPlanBasis { clientAgreed, developerJudgment }

/// 計画の**種別**(v1.8.0)。issue / コミットのプレフィックスと同じ語彙。
///
/// `impl new` は長らく feature 名を必須にしてきたが、それは分類のためではなく
/// `enforcement.impl_plan` のゲートが plan.yaml の feature 名と照合するため。
/// ディレクトリ整理や文書更新のように feature に対応しない作業の計画書に
/// 置き場が無かったので、種別を前置きして「feature を対象にする計画か」を
/// 明示できるようにした。引数を任意にしなかったのは、「計画はあるのに
/// feature 名が無いので apply が止まる」事故を避けるため。
enum ImplPlanKind {
  feat,
  fix,
  refactor,
  docs,
  chore,
  test;

  /// feature(`lib/features/<name>`)を対象にする種別か。
  /// ゲートの照合対象になるのはこれらだけ。
  bool get targetsFeature => this == feat || this == fix;

  static const _byName = {
    'feat': feat,
    'fix': fix,
    'refactor': refactor,
    'docs': docs,
    'chore': chore,
    'test': test,
  };

  static Iterable<String> get names => _byName.keys;

  /// `kind:` の値を読む。未知の値は例外(黙って feat にすると、ゲートの
  /// 対象外のつもりで書いた計画が feature 扱いになる)。
  static ImplPlanKind fromString(String raw) {
    final kind = _byName[raw];
    if (kind == null) {
      throw ArgumentError('Unknown impl plan kind: "$raw" '
          '(use one of ${names.join(", ")})');
    }
    return kind;
  }

  /// `impl new <spec>` の引数 `[kind:]target` を分解する。
  /// 種別が無ければ [feat](1.7.x までの `impl new <feature>` と同じ意味)。
  static ({ImplPlanKind kind, String target}) parseSpec(String spec) {
    final colon = spec.indexOf(':');
    if (colon < 0) return (kind: feat, target: spec);
    return (
      kind: fromString(spec.substring(0, colon)),
      target: spec.substring(colon + 1),
    );
  }
}

final class ImplPlanOrigin {
  final List<String> agreements;
  final List<String> specs;
  final List<String> messages;

  const ImplPlanOrigin({
    this.agreements = const [],
    this.specs = const [],
    this.messages = const [],
  });

  bool get isEmpty => agreements.isEmpty && specs.isEmpty && messages.isEmpty;
}

final class ImplPlanMeta {
  final String id; // PlanId.value

  /// 計画の対象。[kind] が feature を対象にする種別なら plan.yaml の feature 名、
  /// そうでなければ作業の対象名(`doc_layout` 等)。キー名は 1.7.x 以前との
  /// 互換のため `feature` のまま。
  final String feature;

  /// 計画の種別(v1.8.0)。1.7.x 以前のファイルには無いので [ImplPlanKind.feat]。
  final ImplPlanKind kind;
  final String backlog;
  final ImplPlanStatus status;
  final ImplTestStatus test;
  final DateTime created;
  final ImplPlanOrigin origin;
  final ImplPlanBasis? basis;

  /// `flutter analyze` / `utakata check` などの自動検証が通ったか([test] の内訳)
  final bool staticVerified;

  /// 実機確認が済んだか([test] の内訳)
  final bool onDeviceVerified;

  /// テスト不要とした理由([test] が [ImplTestStatus.notRequired] のとき)
  final String? testSkipReason;

  final DateTime? completedOn;

  const ImplPlanMeta({
    required this.id,
    required this.feature,
    this.kind = ImplPlanKind.feat,
    this.backlog = '',
    this.status = ImplPlanStatus.todo,
    this.test = ImplTestStatus.todo,
    required this.created,
    this.origin = const ImplPlanOrigin(),
    this.basis,
    this.staticVerified = false,
    this.onDeviceVerified = false,
    this.testSkipReason,
    this.completedOn,
  });

  /// 実装・検証ともに完了しているか(レーン導出と `list` の表示に使う)。
  bool get isComplete =>
      status == ImplPlanStatus.done &&
      (test == ImplTestStatus.done || test == ImplTestStatus.notRequired);

  /// レーン内でのファイル名。
  ///
  /// `feat` は 1.7.x までと同じ `PLAN-NNNN_<feature>.md`(種別を入れると
  /// 既存ファイルが全て「配置違い」になり、CLI を上げただけで移動が走る)。
  /// それ以外は `PLAN-NNNN_<kind>_<target>.md` で、ファイラ上でも
  /// feature の計画と見分けがつく。
  String get fileName => kind == ImplPlanKind.feat
      ? '${id}_$feature.md'
      : '${id}_${kind.name}_$feature.md';

  /// ボード・一覧での表示名(`refactor:doc_layout` / `login`)。
  String get displayName =>
      kind == ImplPlanKind.feat ? feature : '${kind.name}:$feature';

  /// null は「据え置き」を意味するため、**値を消す**用途には
  /// `clear...` フラグを使う(逆行時に completed_on や検証済みフラグが
  /// 残り続けると frontmatter とボードが嘘をつく)。
  ImplPlanMeta copyWith({
    ImplPlanStatus? status,
    ImplTestStatus? test,
    bool? staticVerified,
    bool? onDeviceVerified,
    String? testSkipReason,
    DateTime? completedOn,
    bool clearCompletedOn = false,
    bool clearVerified = false,
    bool clearSkipReason = false,
  }) =>
      ImplPlanMeta(
        id: id,
        feature: feature,
        kind: kind,
        backlog: backlog,
        status: status ?? this.status,
        test: test ?? this.test,
        created: created,
        origin: origin,
        basis: basis,
        staticVerified:
            clearVerified ? false : (staticVerified ?? this.staticVerified),
        onDeviceVerified:
            clearVerified ? false : (onDeviceVerified ?? this.onDeviceVerified),
        testSkipReason:
            clearSkipReason ? null : (testSkipReason ?? this.testSkipReason),
        completedOn:
            clearCompletedOn ? null : (completedOn ?? this.completedOn),
      );

  /// v1.6.x までの `draft` は `todo` として読む(書き戻しは常に `todo`)。
  static ImplPlanStatus statusFromString(String raw) {
    switch (raw) {
      case 'draft': // 旧称
      case 'todo':
        return ImplPlanStatus.todo;
      case 'in_progress':
        return ImplPlanStatus.inProgress;
      case 'review':
        return ImplPlanStatus.review;
      case 'done':
        return ImplPlanStatus.done;
      case 'archived':
        return ImplPlanStatus.archived;
      default:
        throw ArgumentError('Unknown impl plan status: $raw');
    }
  }

  static String statusToString(ImplPlanStatus status) {
    switch (status) {
      case ImplPlanStatus.todo:
        return 'todo';
      case ImplPlanStatus.inProgress:
        return 'in_progress';
      case ImplPlanStatus.review:
        return 'review';
      case ImplPlanStatus.done:
        return 'done';
      case ImplPlanStatus.archived:
        return 'archived';
    }
  }

  static ImplTestStatus testFromString(String raw) {
    switch (raw) {
      case 'not_required':
        return ImplTestStatus.notRequired;
      case 'todo':
        return ImplTestStatus.todo;
      case 'in_progress':
        return ImplTestStatus.inProgress;
      case 'review':
        return ImplTestStatus.review;
      case 'done':
        return ImplTestStatus.done;
      default:
        throw ArgumentError('Unknown impl test status: $raw');
    }
  }

  static String testToString(ImplTestStatus test) {
    switch (test) {
      case ImplTestStatus.notRequired:
        return 'not_required';
      case ImplTestStatus.todo:
        return 'todo';
      case ImplTestStatus.inProgress:
        return 'in_progress';
      case ImplTestStatus.review:
        return 'review';
      case ImplTestStatus.done:
        return 'done';
    }
  }
}
