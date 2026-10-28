import 'package:path/path.dart' as p;

import '../../1_domain/1_entities/record/agreement.dart';
import '../../1_domain/2_repositories/agreement_repository.dart';
import '../1_models/agreement_event_model.dart';
import '../2_data_sources/1_local/jsonl_data_source.dart';

class AgreementRepositoryImpl implements AgreementRepository {
  final JsonlDataSource _jsonl;

  const AgreementRepositoryImpl(this._jsonl);

  static const _path = 'doc/records/agreements.jsonl';

  String _fullPath(String projectDir) => p.join(projectDir, _path);

  /// 全イベントを読む。JSON として読めない行・イベントとして解釈できない
  /// 行は落とさずに [skipped] へ積んで飛ばす(#33)。
  Future<List<AgreementEvent>> _readAllEvents(
    String projectDir, [
    List<SkippedAgreementRecord>? skipped,
  ]) async {
    final result = await _jsonl.readAllDetailed(_fullPath(projectDir));
    for (final c in result.corrupt) {
      skipped?.add(SkippedAgreementRecord(AgreementSkipReason.unparsableLine,
          line: c.line));
    }
    final events = <AgreementEvent>[];
    for (final row in result.rows) {
      try {
        events.add(AgreementEventModel.fromMap(row.record));
      } catch (_) {
        // 型の食い違い(TypeError)・未知の値(ArgumentError / StateError)・
        // 日付の形(FormatException)のどれでも、その行だけを飛ばす
        final rawId = row.record['id'];
        skipped?.add(SkippedAgreementRecord(AgreementSkipReason.invalidEvent,
            line: row.line, id: rawId is String ? rawId : null));
      }
    }
    return events;
  }

  @override
  Future<void> appendEvent(String projectDir, AgreementEvent event) async {
    await _jsonl.append(_fullPath(projectDir), AgreementEventModel.toMap(event));
  }

  @override
  Future<String> nextId(String projectDir) async {
    // add の無い ID(存在しない ID への状態変更など)も数に入れる。
    // それを再利用すると、宙に浮いていた状態変更が新しい合意に付いてしまう。
    final events = await _readAllEvents(projectDir);
    final pattern = RegExp(r'^AGR-(\d+)$');
    var maxSeq = 0;
    for (final event in events) {
      final match = pattern.firstMatch(event.id);
      if (match != null) {
        final seq = int.parse(match.group(1)!);
        if (seq > maxSeq) maxSeq = seq;
      }
    }
    return 'AGR-${(maxSeq + 1).toString().padLeft(4, '0')}';
  }

  @override
  Future<AgreementLedger> load(String projectDir) async {
    final skipped = <SkippedAgreementRecord>[];
    final events = await _readAllEvents(projectDir, skipped);
    final byId = <String, List<AgreementEvent>>{};
    for (final event in events) {
      byId.putIfAbsent(event.id, () => []).add(event);
    }
    final agreements = <Agreement>[];
    for (final entry in byId.entries) {
      final folded = Agreement.foldFrom(entry.value);
      if (folded == null) {
        skipped.add(SkippedAgreementRecord(AgreementSkipReason.missingAdd,
            id: entry.key));
      } else {
        agreements.add(folded);
      }
    }
    agreements.sort((a, b) => a.id.compareTo(b.id));
    return AgreementLedger(agreements, skipped);
  }

  @override
  Future<List<Agreement>> listAll(String projectDir) async =>
      (await load(projectDir)).agreements;

  @override
  Future<Agreement?> findById(String projectDir, String id) async {
    for (final a in await listAll(projectDir)) {
      if (a.id == id) return a;
    }
    return null;
  }
}
