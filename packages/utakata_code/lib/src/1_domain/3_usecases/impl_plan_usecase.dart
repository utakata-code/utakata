import '../1_entities/record/impl_plan_meta.dart';
import '../2_repositories/impl_plan_repository.dart';
import '../services/impl_plan_body.dart';

/// `utakata impl` — feature 実装計画のライフサイクル管理(仕様書 §8)。
///
/// 状態は2軸([ImplPlanMeta.status] / [ImplPlanMeta.test])で、
/// ファイルの置き場所(レーン)はそこから導出される。
///
/// **逆行は許可する** — テストが落ちて実装へ戻るのは正常な流れであり、
/// 一方向しか許さないと現実の作業を記録できなくなる。
class ImplPlanUsecase {
  final ImplPlanRepository _repo;

  const ImplPlanUsecase({required ImplPlanRepository repo}) : _repo = repo;

  /// feature 名として許す形。パス区切り・`..`・空文字を弾く
  /// (ファイル名に素で使うため、doc/impl の外へ書き出せてしまう)。
  static final _featurePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  Future<String> create(
    String projectDir, {
    required String feature,
    ImplPlanKind kind = ImplPlanKind.feat,
    String backlog = '',
    List<String> agreements = const [],
    List<String> specs = const [],
    List<String> messages = const [],
    ImplPlanBasis? basis,
    String? supersedes,
    required DateTime now,
    required String bodyTemplate,
  }) async {
    if (!_featurePattern.hasMatch(feature) || feature.contains('..')) {
      throw ArgumentError('invalid feature name: "$feature" '
          '(use letters, digits, ".", "_", "-")');
    }
    if (supersedes != null && await _repo.findById(projectDir, supersedes) == null) {
      // 存在しない ID を繋いでも辿れない。タイポをここで止める
      throw ArgumentError('superseded plan "$supersedes" not found');
    }
    final id = await _repo.nextId(projectDir);
    final meta = ImplPlanMeta(
      id: id,
      feature: feature,
      kind: kind,
      backlog: backlog,
      status: ImplPlanStatus.todo,
      test: ImplTestStatus.todo,
      created: now,
      origin: ImplPlanOrigin(agreements: agreements, specs: specs, messages: messages),
      basis: basis,
      supersedes: supersedes,
    );
    await _repo.create(projectDir, meta, bodyTemplate);
    return id;
  }

  /// 現在の本文から計画部分の指紋を計算する。
  Future<String> _currentDigest(String projectDir, String id) async =>
      ImplPlanBody.digest(ImplPlanBody.split(await _repo.readBody(projectDir, id)).plan);

  /// 凍結後に計画部分が書き換えられていれば例外(v1.8.0, #22)。
  ///
  /// 「書き換えるな」をシステムプロンプトで頼むだけでなく CLI で止める。
  /// 止めるのは**状態遷移**であって編集そのものではない — 誤字 1 つ直す
  /// のに新しい計画書が要る運用にはしない。意図した変更は `impl revise`
  /// で受理すれば先へ進める。
  Future<void> _refuseIfDrifted(String projectDir, ImplPlanMeta meta) async {
    if (!meta.isFrozen) return;
    final current = await _currentDigest(projectDir, meta.id);
    if (current != meta.planDigest) {
      throw ImplPlanFrozenException(meta.id);
    }
  }

  /// `todo` を離れる最初の遷移で計画部分を凍結する(指紋を記録する)。
  Future<ImplPlanMeta> _freezeIfLeavingTodo(
      String projectDir, ImplPlanMeta meta, ImplPlanStatus next) async {
    if (meta.isFrozen || next == ImplPlanStatus.todo) return meta;
    return meta.copyWith(planDigest: await _currentDigest(projectDir, meta.id));
  }

  /// 凍結後の書き換えを改訂として受理する(v1.8.0, #22)。
  ///
  /// 指紋を現在の本文に合わせ直し、`revisions` を +1 して、理由を記録領域に
  /// 残す。「何度も計画が変わった feature」がボードから見えるようにするため。
  Future<ImplPlanMeta> revise(
    String projectDir,
    String id, {
    required String reason,
    required DateTime now,
    String actor = '',
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('a reason is required to revise a frozen plan');
    }
    final meta = await _require(projectDir, id);
    if (!meta.isFrozen) {
      throw ArgumentError('plan "$id" is not frozen yet (status: '
          '${ImplPlanMeta.statusToString(meta.status)}); edit it freely');
    }
    final current = await _currentDigest(projectDir, id);
    if (current == meta.planDigest) {
      throw ArgumentError('plan "$id" has no changes in its plan section');
    }
    final updated = meta.copyWith(
      planDigest: current,
      revisions: meta.revisions + 1,
    );
    await _repo.update(
      projectDir,
      updated,
      logEntry: ImplPlanBody.formatEntry(
        at: now,
        actor: actor,
        text: 'revised (#${updated.revisions}): ${reason.trim()}',
      ),
    );
    return updated;
  }

  /// 凍結後に計画部分が書き換えられたまま受理されていない計画の ID
  /// (`utakata doctor` 用)。
  Future<List<String>> listDrifted(String projectDir) async {
    final drifted = <String>[];
    for (final meta in await _repo.listAll(projectDir)) {
      if (!meta.isFrozen) continue;
      if (await _currentDigest(projectDir, meta.id) != meta.planDigest) {
        drifted.add(meta.id);
      }
    }
    return drifted;
  }

  Future<List<ImplPlanMeta>> list(String projectDir) => _repo.listAll(projectDir);

  Future<ImplPlanMeta?> find(String projectDir, String id) =>
      _repo.findById(projectDir, id);

  /// 実装軸の遷移。
  ///
  /// 遷移は本文の記録領域にも 1 行残す(v1.8.0)。記録領域だけ読めば
  /// 時系列が追えるようにするため。[actor] は `UTAKATA_ACTOR` 由来の記録者。
  Future<ImplTransition> setStatus(
    String projectDir,
    String id,
    ImplPlanStatus status, {
    required DateTime now,
    String actor = '',
  }) async {
    var meta = await _require(projectDir, id);
    // archive は「離れる」操作なので、書き換えられていても止めない
    if (status != ImplPlanStatus.archived) {
      await _refuseIfDrifted(projectDir, meta);
    }
    meta = await _freezeIfLeavingTodo(projectDir, meta, status);
    final done = status == ImplPlanStatus.done;
    final updated = meta.copyWith(
      status: status,
      completedOn: done ? now : null,
      // done から戻したら完了日は消す(古い日付が残ると嘘になる)
      clearCompletedOn: !done && status != ImplPlanStatus.archived,
    );
    final movedTo = await _repo.update(
      projectDir,
      updated,
      logEntry: ImplPlanBody.formatEntry(
        at: now,
        actor: actor,
        text: 'status: ${ImplPlanMeta.statusToString(meta.status)} → '
            '${ImplPlanMeta.statusToString(status)}',
      ),
    );
    return ImplTransition(before: meta, after: updated, movedTo: movedTo);
  }

  /// 検証軸の遷移。実装が `done` になる前には進められない。
  Future<ImplTransition> setTest(
    String projectDir,
    String id,
    ImplTestStatus test, {
    String? skipReason,
    DateTime? now,
    String actor = '',
  }) async {
    final meta = await _require(projectDir, id);
    await _refuseIfDrifted(projectDir, meta);
    final advancing =
        test != ImplTestStatus.todo && test != ImplTestStatus.notRequired;
    if (advancing && meta.status != ImplPlanStatus.done) {
      throw ArgumentError(
        'implementation is not done yet (status: '
        '${ImplPlanMeta.statusToString(meta.status)}). '
        'Run `utakata impl done $id` first.',
      );
    }
    final complete = test == ImplTestStatus.done;
    final updated = meta.copyWith(
      test: test,
      testSkipReason: test == ImplTestStatus.notRequired ? skipReason : null,
      // 「テスト不要」以外へ移ったら理由を消す(前回の理由が残らないように)
      clearSkipReason: test != ImplTestStatus.notRequired,
      // 検証の内訳は「テスト完了」で両方満たされたとみなし、
      // 差し戻したら両方 pending に戻す
      staticVerified: complete ? true : null,
      onDeviceVerified: complete ? true : null,
      clearVerified: !complete,
    );
    final reason = (test == ImplTestStatus.notRequired &&
            skipReason != null &&
            skipReason.isNotEmpty)
        ? ' ($skipReason)'
        : '';
    final movedTo = await _repo.update(
      projectDir,
      updated,
      logEntry: ImplPlanBody.formatEntry(
        at: now ?? DateTime.now(),
        actor: actor,
        text: 'test: ${ImplPlanMeta.testToString(meta.test)} → '
            '${ImplPlanMeta.testToString(test)}$reason',
      ),
    );
    return ImplTransition(before: meta, after: updated, movedTo: movedTo);
  }

  Future<ImplTransition> archive(String projectDir, String id,
          {required DateTime now, String actor = ''}) =>
      setStatus(projectDir, id, ImplPlanStatus.archived,
          now: now, actor: actor);

  /// 実施記録を 1 件追記する(v1.8.0)。計画部分には触れない。
  ///
  /// ファイルを直接編集させず CLI を通すのは records の `append` と同じ
  /// 理由 — 日時と記録者が必ず付き、過去の記録を書き換える経路が無い。
  Future<void> note(
    String projectDir,
    String id,
    String text, {
    required DateTime now,
    String actor = '',
  }) async {
    if (text.trim().isEmpty) {
      throw ArgumentError('note text must not be empty');
    }
    final meta = await _require(projectDir, id);
    await _repo.update(
      projectDir,
      meta,
      logEntry: ImplPlanBody.formatEntry(at: now, actor: actor, text: text),
    );
  }

  /// frontmatter に合わせてファイル配置を是正する。
  Future<ImplSyncResult> sync(String projectDir, {bool dryRun = false}) =>
      _repo.sync(projectDir, dryRun: dryRun);

  /// 走査の生結果(読めないファイル・重複 ID を含む)。
  Future<ImplScanResult> scan(String projectDir) => _repo.scanAll(projectDir);

  Future<Map<String, ({String actual, String expected})>> detectMisplaced(
          String projectDir) =>
      _repo.detectMisplaced(projectDir);

  Future<ImplPlanMeta> _require(String projectDir, String id) async {
    final meta = await _repo.findById(projectDir, id);
    if (meta == null) {
      throw ArgumentError('implementation plan "$id" not found');
    }
    return meta;
  }
}

/// 凍結後に計画部分が書き換えられたまま遷移しようとした(v1.8.0, #22)。
///
/// `Exception` にしてあるのは、BaseCommand がスタックトレース無しで
/// メッセージだけを表示するため(`StateError` だと落ちて見える)。
final class ImplPlanFrozenException implements Exception {
  final String id;

  const ImplPlanFrozenException(this.id);

  @override
  String toString() =>
      'plan "$id" was edited after it was frozen (impl start). '
      'If the change is intended, accept it with '
      '`utakata impl revise $id --reason "..."`; otherwise restore the '
      'plan section. Progress notes go below the `<!-- utakata:log -->` '
      'marker via `utakata impl note`.';
}

/// 状態遷移の結果(表示用)。
final class ImplTransition {
  final ImplPlanMeta before;
  final ImplPlanMeta after;

  /// レーンが変わった場合の移動先(プロジェクト相対パス)。変わらなければ null。
  final String? movedTo;

  const ImplTransition({
    required this.before,
    required this.after,
    this.movedTo,
  });
}
