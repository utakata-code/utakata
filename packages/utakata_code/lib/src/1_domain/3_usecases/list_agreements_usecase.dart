import '../1_entities/record/agreement.dart';
import '../2_repositories/agreement_repository.dart';

class ListAgreementsUsecase {
  final AgreementRepository _repo;

  const ListAgreementsUsecase({required AgreementRepository repo}) : _repo = repo;

  Future<List<Agreement>> execute(String projectDir, {bool unreflectedOnly = false}) async {
    final all = await _repo.listAll(projectDir);
    if (!unreflectedOnly) return all;
    return all.where((a) => !a.isReflected).toList();
  }

  /// [execute] と同じ絞り込みに加え、読めずに飛ばした記録も返す(#33)。
  /// 一覧を表示する側はこれで警告を出す。
  Future<AgreementLedger> executeWithSkipped(String projectDir,
      {bool unreflectedOnly = false}) async {
    final ledger = await _repo.load(projectDir);
    if (!unreflectedOnly) return ledger;
    return AgreementLedger(
      ledger.agreements.where((a) => !a.isReflected).toList(),
      ledger.skipped,
    );
  }
}
