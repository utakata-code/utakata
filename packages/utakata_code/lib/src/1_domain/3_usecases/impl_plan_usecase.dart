import '../1_entities/record/impl_plan_meta.dart';
import '../2_repositories/impl_plan_repository.dart';

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
    required DateTime now,
    required String bodyTemplate,
  }) async {
    if (!_featurePattern.hasMatch(feature) || feature.contains('..')) {
      throw ArgumentError('invalid feature name: "$feature" '
          '(use letters, digits, ".", "_", "-")');
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
    );
    await _repo.create(projectDir, meta, bodyTemplate);
    return id;
  }

  Future<List<ImplPlanMeta>> list(String projectDir) => _repo.listAll(projectDir);

  Future<ImplPlanMeta?> find(String projectDir, String id) =>
      _repo.findById(projectDir, id);

  /// 実装軸の遷移。
  Future<ImplTransition> setStatus(
    String projectDir,
    String id,
    ImplPlanStatus status, {
    required DateTime now,
  }) async {
    final meta = await _require(projectDir, id);
    final done = status == ImplPlanStatus.done;
    final updated = meta.copyWith(
      status: status,
      completedOn: done ? now : null,
      // done から戻したら完了日は消す(古い日付が残ると嘘になる)
      clearCompletedOn: !done && status != ImplPlanStatus.archived,
    );
    final movedTo = await _repo.update(projectDir, updated);
    return ImplTransition(before: meta, after: updated, movedTo: movedTo);
  }

  /// 検証軸の遷移。実装が `done` になる前には進められない。
  Future<ImplTransition> setTest(
    String projectDir,
    String id,
    ImplTestStatus test, {
    String? skipReason,
  }) async {
    final meta = await _require(projectDir, id);
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
    final movedTo = await _repo.update(projectDir, updated);
    return ImplTransition(before: meta, after: updated, movedTo: movedTo);
  }

  Future<ImplTransition> archive(String projectDir, String id,
      {required DateTime now}) =>
      setStatus(projectDir, id, ImplPlanStatus.archived, now: now);

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
