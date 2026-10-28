import '../1_entities/record/record_id.dart';
import '../2_repositories/agreement_repository.dart';
import '../exceptions/domain_exceptions.dart';

/// 入力として受け取った合意 ID を、書き込む前に確かめる(#33)。
///
/// 1.8.0 までは `agree status` 等が ID を検査せずに追記していたため、
/// 改行入りの値や存在しない ID が台帳に残り、`agree list` が落ちていた。
/// 合意 ID を受け取る所はすべてここを通す。
class AgreementIdGuard {
  final AgreementRepository _repo;

  const AgreementIdGuard(this._repo);

  /// 形だけを確かめる(リポジトリを読まない)。
  static void ensureWellFormed(String id) {
    if (!AgrId.matches(id)) throw InvalidAgreementIdException(id);
  }

  /// 形と存在を確かめる。どちらか満たさなければ例外(何も書かない)。
  Future<void> ensureExists(String projectDir, String id) =>
      ensureAllExist(projectDir, [id]);

  /// [ids] すべての形と存在を確かめる。形の検査を先に全件行い、
  /// 台帳の読み出しは1回だけにする。
  Future<void> ensureAllExist(String projectDir, Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    list.forEach(ensureWellFormed);
    final known = {for (final a in await _repo.listAll(projectDir)) a.id};
    for (final id in list) {
      if (!known.contains(id)) throw AgreementNotFoundException(id);
    }
  }
}
