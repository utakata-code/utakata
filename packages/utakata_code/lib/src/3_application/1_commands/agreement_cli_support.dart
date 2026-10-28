import '../../1_domain/1_entities/record/agreement.dart';
import '../../1_domain/exceptions/domain_exceptions.dart';
import '../../1_domain/messages/cli_messages.dart';
import 'logger.dart';

/// 合意 ID の検査で断られた場合の表示と終了コード(#33)。
///
/// 合意 ID を受け取るコマンド(agree status / correct / reflect、
/// impl new --agreement、message link --agreement)で共有する。
/// 該当しない例外なら null(呼び出し側で投げ直す)。
int? reportAgreementIdError(Object error, CliMessages msg) {
  switch (error) {
    case InvalidAgreementIdException(:final id):
      Logger.error(msg.agreementIdInvalid(quoteRecordId(id)));
      return 64; // EX_USAGE
    case AgreementNotFoundException(:final id):
      Logger.error(msg.agreementNotFound(quoteRecordId(id)));
      return 66; // EX_NOINPUT(message link の「見つからない」と揃える)
    default:
      return null;
  }
}

/// 読み出しで飛ばした合意の記録を警告として1件ずつ見せる。
void warnSkippedAgreements(List<SkippedAgreementRecord> skipped, CliMessages msg) {
  if (skipped.isEmpty) return;
  for (final s in skipped) {
    Logger.warn(switch (s.reason) {
      AgreementSkipReason.unparsableLine => msg.agreementSkippedUnparsable(s.line!),
      AgreementSkipReason.invalidEvent => msg.agreementSkippedInvalid(s.line!),
      AgreementSkipReason.missingAdd => msg.agreementSkippedMissingAdd(quoteRecordId(s.id!)),
    });
  }
  Logger.warn(msg.agreementSkippedSummary(skipped.length));
}
