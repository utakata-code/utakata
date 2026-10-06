import '../../1_domain/1_entities/record/impl_plan_meta.dart';
import '../../1_domain/services/impl_lane.dart';

/// 実装計画をレーン別のカンバンとして Markdown に整形する。
abstract final class ImplBoardPresenter {
  static const laneTitles = <ImplLane, String>{
    ImplLane.todo: '1. 未着手',
    ImplLane.inProgress: '2. 実装中',
    ImplLane.review: '3. レビュー',
    ImplLane.testTodo: '4. テスト未着手',
    ImplLane.testInProgress: '5. テスト中',
    ImplLane.testReview: '6. テストレビュー',
    ImplLane.done: '7. 完了',
    ImplLane.archive: 'アーカイブ',
  };

  static String render(List<ImplPlanMeta> plans) {
    final byLane = <ImplLane, List<ImplPlanMeta>>{};
    for (final plan in plans) {
      byLane.putIfAbsent(ImplLane.ofMeta(plan), () => []).add(plan);
    }

    final active =
        plans.where((p) => p.status != ImplPlanStatus.archived).length;
    final buffer = StringBuffer()
      ..writeln('> ⚠️ 自動生成 — 編集しないでください。'
          '`utakata impl board` で再生成されます。')
      ..writeln()
      ..writeln('# 実装計画ボード')
      ..writeln()
      ..writeln('進行中 $active 件(アーカイブ除く)')
      ..writeln();

    for (final lane in ImplLane.ordered) {
      final items = byLane[lane] ?? const <ImplPlanMeta>[];
      // アーカイブは件数が増える一方なので、空なら節ごと省く
      if (lane == ImplLane.archive && items.isEmpty) continue;
      buffer
        ..writeln('## ${laneTitles[lane]}  (${items.length})')
        ..writeln();
      if (items.isEmpty) {
        buffer
          ..writeln('_なし_')
          ..writeln();
        continue;
      }
      for (final plan in items) {
        final notes = <String>[
          if (plan.basis == ImplPlanBasis.clientAgreed) '合意ベース',
          if (plan.test == ImplTestStatus.notRequired)
            'テスト不要${plan.testSkipReason != null ? '(${plan.testSkipReason})' : ''}',
          if (plan.origin.agreements.isNotEmpty)
            '根拠: ${plan.origin.agreements.join(", ")}',
        ];
        buffer.writeln('- **${plan.id}** ${plan.displayName}'
            '${notes.isEmpty ? '' : ' — ${notes.join(" / ")}'}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// 端末表示用(1行1計画)。
  static String renderLine(ImplPlanMeta plan) =>
      '${plan.id}  [${ImplPlanMeta.statusToString(plan.status)}'
      ' / test:${ImplPlanMeta.testToString(plan.test)}]  ${plan.displayName}';
}
