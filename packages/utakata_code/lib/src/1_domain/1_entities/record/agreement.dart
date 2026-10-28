/// 合意トラッキング(仕様書 §7.2)。
///
/// 追記専用 JSONL + イベント畳み込みで表現する。訂正は過去エントリを
/// 書き換えず、新しいイベント行(`AgreementEventType.correct`)として
/// 追記する(「訂正も履歴ごと残す」実案件慣習をデータ構造で強制する)。
enum AgreementKind { clientAgreement, internalDecision, tentative, correction }

enum AgreementStatus { proposed, agreed, superseded, withdrawn }

enum AgreementEventType { add, statusChange, correct, reflect }

/// `doc/records/agreements.jsonl` の1行(1イベント)。
final class AgreementEvent {
  final AgreementEventType type;
  final String id; // AgrId.value
  final DateTime recordedAt;
  final String recordedBy;

  // add イベント時のフィールド
  final String? title;
  final AgreementKind? kind;
  final double? amountValue;
  final String? amountCurrency;
  final String? paymentTerms;
  final List<String> items;
  final List<String> sources;
  final String? correctsId;
  final String? backlog;

  // statusChange イベント時
  final AgreementStatus? status;
  final DateTime? statusOn;

  // reflect イベント時
  final String? reflectedInPlanId;
  final String? reflectedInSpec;

  const AgreementEvent({
    required this.type,
    required this.id,
    required this.recordedAt,
    required this.recordedBy,
    this.title,
    this.kind,
    this.amountValue,
    this.amountCurrency,
    this.paymentTerms,
    this.items = const [],
    this.sources = const [],
    this.correctsId,
    this.backlog,
    this.status,
    this.statusOn,
    this.reflectedInPlanId,
    this.reflectedInSpec,
  });

  static AgreementKind kindFromString(String raw) {
    switch (raw) {
      case 'client_agreement':
      case 'client':
        return AgreementKind.clientAgreement;
      case 'internal_decision':
      case 'internal':
        return AgreementKind.internalDecision;
      case 'tentative':
        return AgreementKind.tentative;
      case 'correction':
        return AgreementKind.correction;
      default:
        throw ArgumentError('Unknown agreement kind: $raw');
    }
  }

  static String kindToString(AgreementKind kind) {
    switch (kind) {
      case AgreementKind.clientAgreement:
        return 'client_agreement';
      case AgreementKind.internalDecision:
        return 'internal_decision';
      case AgreementKind.tentative:
        return 'tentative';
      case AgreementKind.correction:
        return 'correction';
    }
  }

  /// 未知の値は [ArgumentError](CLI では利用者の入力ミスとして扱われる)。
  static AgreementStatus statusFromString(String raw) {
    for (final status in AgreementStatus.values) {
      if (status.name == raw) return status;
    }
    throw ArgumentError('Unknown agreement status: "$raw" '
        '(use ${AgreementStatus.values.map((s) => s.name).join(" | ")})');
  }

  static String statusToString(AgreementStatus status) => status.name;
}

/// イベント列を畳み込んだ「現在の合意状態」(表示・検索用の派生値)。
final class Agreement {
  final String id;
  final String title;
  final AgreementKind kind;
  final AgreementStatus status;
  final double? amountValue;
  final String? amountCurrency;
  final String? paymentTerms;
  final List<String> items;
  final List<String> sources;
  final String? correctsId;
  final String? backlog;
  final List<String> reflectedInPlanIds;
  final List<String> reflectedInSpecs;
  final DateTime recordedAt;

  const Agreement({
    required this.id,
    required this.title,
    required this.kind,
    required this.status,
    this.amountValue,
    this.amountCurrency,
    this.paymentTerms,
    this.items = const [],
    this.sources = const [],
    this.correctsId,
    this.backlog,
    this.reflectedInPlanIds = const [],
    this.reflectedInSpecs = const [],
    required this.recordedAt,
  });

  bool get isReflected => reflectedInPlanIds.isNotEmpty || reflectedInSpecs.isNotEmpty;

  /// 同一 ID のイベント列を畳み込んで現在状態を導出する(add が先頭のはず)。
  ///
  /// add の無いまとまり(存在しない ID への statusChange 等。1.8.0 までは
  /// 検査せずに追記できた)は畳み込めないので null を返す。呼び出し側は
  /// 落とさずに飛ばし、警告として知らせる(#33)。
  static Agreement? foldFrom(List<AgreementEvent> events) {
    AgreementEvent? add;
    for (final event in events) {
      if (event.type == AgreementEventType.add) {
        add = event;
        break;
      }
    }
    if (add == null) return null;
    var status = add.status ?? AgreementStatus.proposed;
    final planIds = <String>[];
    final specs = <String>[];

    for (final event in events) {
      switch (event.type) {
        case AgreementEventType.statusChange:
          if (event.status != null) status = event.status!;
          break;
        case AgreementEventType.reflect:
          if (event.reflectedInPlanId != null) planIds.add(event.reflectedInPlanId!);
          if (event.reflectedInSpec != null) specs.add(event.reflectedInSpec!);
          break;
        case AgreementEventType.add:
        case AgreementEventType.correct:
          break;
      }
    }

    return Agreement(
      id: add.id,
      title: add.title ?? '',
      kind: add.kind ?? AgreementKind.tentative,
      status: status,
      amountValue: add.amountValue,
      amountCurrency: add.amountCurrency,
      paymentTerms: add.paymentTerms,
      items: add.items,
      sources: add.sources,
      correctsId: add.correctsId,
      backlog: add.backlog,
      reflectedInPlanIds: planIds,
      reflectedInSpecs: specs,
      recordedAt: add.recordedAt,
    );
  }
}

/// 読み出し時に飛ばした記録の種類(#33)。
enum AgreementSkipReason {
  /// JSON として読めない行
  unparsableLine,

  /// JSON だが合意イベントとして解釈できない行(必須項目欠落・未知の値)
  invalidEvent,

  /// add イベントが無い ID のまとまり(存在しない ID への状態変更など)
  missingAdd,
}

/// 読み出し時に飛ばした記録1件。
final class SkippedAgreementRecord {
  final AgreementSkipReason reason;

  /// 行単位の問題なら行番号(1始まり)。ID 単位の問題なら null。
  final int? line;

  /// ID 単位の問題なら合意 ID(改行などを含む生の値のこともある)。
  final String? id;

  const SkippedAgreementRecord(this.reason, {this.line, this.id});
}

/// 合意台帳の読み出し結果: 畳み込めた合意と、飛ばした記録。
final class AgreementLedger {
  final List<Agreement> agreements;
  final List<SkippedAgreementRecord> skipped;

  const AgreementLedger(this.agreements, this.skipped);
}
