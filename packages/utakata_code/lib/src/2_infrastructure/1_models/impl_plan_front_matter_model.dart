import '../../1_domain/1_entities/record/impl_plan_meta.dart';

/// frontmatter(Map)⇔ [ImplPlanMeta] の変換を担う DTO。
///
/// v1.7.0 で検証は `test:` マップへ統合された。旧 `verification:`
/// (`static` / `on_device` のみ)も読めるようにしてある。
abstract final class ImplPlanFrontMatterModel {
  static ImplPlanMeta fromMap(Map<String, dynamic> map) {
    final originMap = map['origin'];
    final origin = originMap is Map
        ? ImplPlanOrigin(
            agreements: (originMap['agreements'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
            specs: (originMap['specs'] as List?)?.map((e) => e.toString()).toList() ?? const [],
            messages:
                (originMap['messages'] as List?)?.map((e) => e.toString()).toList() ?? const [],
          )
        : const ImplPlanOrigin();

    // v1.7.0: test マップ / v1.6.x 以前: verification マップ
    final testNode = map['test'];
    final legacy = map['verification'];
    final staticVerified = _isDone(testNode, 'static') || _isDone(legacy, 'static');
    final onDeviceVerified =
        _isDone(testNode, 'on_device') || _isDone(legacy, 'on_device');

    final ImplTestStatus test;
    if (testNode is Map && testNode['status'] != null) {
      test = ImplPlanMeta.testFromString(testNode['status'].toString());
    } else if (testNode is String) {
      // `test: done` のような素の書き方も受理する
      test = ImplPlanMeta.testFromString(testNode);
    } else if (legacy is Map) {
      // 旧形式からの移行: 両方 done ならテスト完了とみなす
      test = staticVerified && onDeviceVerified
          ? ImplTestStatus.done
          : ImplTestStatus.todo;
    } else {
      test = ImplTestStatus.todo;
    }

    return ImplPlanMeta(
      id: map['id'] as String,
      feature: map['feature'] as String,
      // v1.8.0: 種別。無ければ feat(1.7.x 以前のファイルは全て feature の計画)
      kind: map['kind'] == null
          ? ImplPlanKind.feat
          : ImplPlanKind.fromString(map['kind'].toString()),
      backlog: (map['backlog'] as String?) ?? '',
      status: ImplPlanMeta.statusFromString((map['status'] as String?) ?? 'todo'),
      test: test,
      created: DateTime.parse(map['created'] as String),
      origin: origin,
      basis: map['basis'] == 'client_agreed'
          ? ImplPlanBasis.clientAgreed
          : map['basis'] == 'developer_judgment'
              ? ImplPlanBasis.developerJudgment
              : null,
      staticVerified: staticVerified,
      onDeviceVerified: onDeviceVerified,
      testSkipReason:
          testNode is Map ? testNode['skip_reason']?.toString() : null,
      completedOn: map['completed_on'] != null ? DateTime.parse(map['completed_on'] as String) : null,
      // v1.8.0: 凍結・改訂・置き換え。1.7.x 以前のファイルには無い
      planDigest: map['plan_digest']?.toString(),
      revisions: switch (map['revisions']) {
        final int n => n,
        final String s => int.tryParse(s) ?? 0,
        _ => 0,
      },
      supersedes: map['supersedes']?.toString(),
    );
  }

  static bool _isDone(Object? node, String key) =>
      node is Map && node[key] == 'done';

  static Map<String, dynamic> toMap(ImplPlanMeta meta) => {
        'id': meta.id,
        'feature': meta.feature,
        'kind': meta.kind.name,
        if (meta.backlog.isNotEmpty) 'backlog': meta.backlog,
        'status': ImplPlanMeta.statusToString(meta.status),
        'created': meta.created.toIso8601String().substring(0, 10),
        'origin': {
          'agreements': meta.origin.agreements,
          'specs': meta.origin.specs,
          'messages': meta.origin.messages,
        },
        if (meta.basis != null)
          'basis': meta.basis == ImplPlanBasis.clientAgreed ? 'client_agreed' : 'developer_judgment',
        'test': {
          'status': ImplPlanMeta.testToString(meta.test),
          'static': meta.staticVerified ? 'done' : 'pending',
          'on_device': meta.onDeviceVerified ? 'done' : 'pending',
          if (meta.testSkipReason != null && meta.testSkipReason!.isNotEmpty)
            'skip_reason': meta.testSkipReason,
        },
        if (meta.completedOn != null)
          'completed_on': meta.completedOn!.toIso8601String().substring(0, 10),
        if (meta.planDigest != null) 'plan_digest': meta.planDigest,
        if (meta.revisions > 0) 'revisions': meta.revisions,
        if (meta.supersedes != null) 'supersedes': meta.supersedes,
      };
}
