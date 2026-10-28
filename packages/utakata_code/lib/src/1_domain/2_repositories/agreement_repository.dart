import '../1_entities/record/agreement.dart';

/// `doc/records/agreements.jsonl` の読み書きを行うリポジトリのインターフェース。
///
/// 追記専用。現在状態は [Agreement.foldFrom] で導出する。
abstract interface class AgreementRepository {
  Future<void> appendEvent(String projectDir, AgreementEvent event);

  /// 既存 ID の "AGR-" 接頭辞の連番から次の ID を採番する。
  Future<String> nextId(String projectDir);

  /// 全イベントを ID ごとにグルーピングし、畳み込んだ現在状態と、
  /// 読めずに飛ばした記録(壊れた行・add の無い ID)を返す(#33)。
  Future<AgreementLedger> load(String projectDir);

  /// [load] の合意だけ(飛ばした記録は捨てる)。
  Future<List<Agreement>> listAll(String projectDir);

  Future<Agreement?> findById(String projectDir, String id);
}
