import '../1_entities/record/agreement.dart';
import '../2_repositories/agreement_repository.dart';
import '../services/agreement_id_guard.dart';

/// `utakata agree add/status/correct/reflect` — 合意の記録・状態遷移・
/// 反映記録を行うユースケース(すべて追記イベントとして表現。仕様書 §7.2)。
///
/// 既存の合意 ID を受け取る操作(status / correct / reflect)は、書き込む前に
/// ID の形と存在を確かめ、満たさなければ何も書かずに例外を投げる(#33)。
class RecordAgreementUsecase {
  final AgreementRepository _repo;
  final AgreementIdGuard _guard;

  RecordAgreementUsecase({required AgreementRepository repo})
      : _repo = repo,
        _guard = AgreementIdGuard(repo);

  Future<String> add(
    String projectDir, {
    required String title,
    required String kindRaw,
    double? amountValue,
    String? amountCurrency,
    String? paymentTerms,
    List<String> items = const [],
    List<String> sources = const [],
    String? backlog,
    required DateTime now,
    required String recordedBy,
  }) async {
    final id = await _repo.nextId(projectDir);
    await _repo.appendEvent(
      projectDir,
      AgreementEvent(
        type: AgreementEventType.add,
        id: id,
        recordedAt: now,
        recordedBy: recordedBy,
        title: title,
        kind: AgreementEvent.kindFromString(kindRaw),
        status: AgreementStatus.proposed,
        amountValue: amountValue,
        amountCurrency: amountCurrency,
        paymentTerms: paymentTerms,
        items: items,
        sources: sources,
        backlog: backlog,
      ),
    );
    return id;
  }

  Future<void> updateStatus(
    String projectDir,
    String id,
    String statusRaw, {
    required DateTime now,
    required String recordedBy,
  }) async {
    final status = AgreementEvent.statusFromString(statusRaw);
    await _guard.ensureExists(projectDir, id);
    await _repo.appendEvent(
      projectDir,
      AgreementEvent(
        type: AgreementEventType.statusChange,
        id: id,
        recordedAt: now,
        recordedBy: recordedBy,
        status: status,
        statusOn: now,
      ),
    );
  }

  Future<String> correct(
    String projectDir,
    String correctsId, {
    required String title,
    required String kindRaw,
    List<String> items = const [],
    required DateTime now,
    required String recordedBy,
  }) async {
    // 訂正は新しい ID で記録し、元エントリは superseded にする。
    // 2行を書くので、どちらかを書いた後で失敗しないよう先に全部確かめる
    final kind = AgreementEvent.kindFromString(kindRaw);
    await _guard.ensureExists(projectDir, correctsId);
    final newId = await _repo.nextId(projectDir);
    await _repo.appendEvent(
      projectDir,
      AgreementEvent(
        type: AgreementEventType.add,
        id: newId,
        recordedAt: now,
        recordedBy: recordedBy,
        title: title,
        kind: kind,
        status: AgreementStatus.agreed,
        items: items,
        correctsId: correctsId,
      ),
    );
    await _repo.appendEvent(
      projectDir,
      AgreementEvent(
        type: AgreementEventType.statusChange,
        id: correctsId,
        recordedAt: now,
        recordedBy: recordedBy,
        status: AgreementStatus.superseded,
      ),
    );
    return newId;
  }

  Future<void> reflect(
    String projectDir,
    String id, {
    String? planId,
    String? spec,
    required DateTime now,
    required String recordedBy,
  }) async {
    await _guard.ensureExists(projectDir, id);
    await _repo.appendEvent(
      projectDir,
      AgreementEvent(
        type: AgreementEventType.reflect,
        id: id,
        recordedAt: now,
        recordedBy: recordedBy,
        reflectedInPlanId: planId,
        reflectedInSpec: spec,
      ),
    );
  }
}
