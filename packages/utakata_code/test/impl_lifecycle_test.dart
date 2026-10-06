import 'dart:io';

import 'package:test/test.dart';
import 'package:utakata/src/1_domain/1_entities/config/utakata_config_entity.dart';
import 'package:utakata/src/1_domain/1_entities/record/impl_plan_meta.dart';
import 'package:utakata/src/1_domain/3_usecases/impl_plan_usecase.dart';
import 'package:utakata/src/1_domain/services/impl_lane.dart';
import 'package:utakata/src/1_domain/services/impl_plan_body.dart';
import 'package:utakata/src/1_domain/services/impl_plan_gate.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/filesystem_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/front_matter_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_data_source.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/impl_plan_repository_impl.dart';

/// v1.7.0: impl の2軸ライフサイクルとレーン(ディレクトリ)導出。
void main() {
  late Directory dir;
  late ImplPlanRepositoryImpl repo;
  late ImplPlanUsecase usecase;
  final now = DateTime(2026, 8, 11);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('utakata_impl_');
    repo = const ImplPlanRepositoryImpl(
        FilesystemDataSource(), FrontMatterDataSource(YamlDataSource()));
    usecase = ImplPlanUsecase(repo: repo);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<String> newPlan(String feature) => usecase.create(
        dir.path,
        feature: feature,
        now: now,
        bodyTemplate: '# 実装計画\n',
      );

  bool existsIn(ImplLane lane, String fileName) =>
      File('${dir.path}/doc/impl/${lane.dirName}/$fileName').existsSync();

  group('レーン導出', () {
    test('実装が終わるまでは実装側のレーン', () {
      expect(ImplLane.of(ImplPlanStatus.todo, ImplTestStatus.todo),
          ImplLane.todo);
      expect(ImplLane.of(ImplPlanStatus.inProgress, ImplTestStatus.todo),
          ImplLane.inProgress);
      expect(ImplLane.of(ImplPlanStatus.review, ImplTestStatus.todo),
          ImplLane.review);
    });

    test('実装完了後はテスト側のレーン', () {
      expect(ImplLane.of(ImplPlanStatus.done, ImplTestStatus.todo),
          ImplLane.testTodo);
      expect(ImplLane.of(ImplPlanStatus.done, ImplTestStatus.inProgress),
          ImplLane.testInProgress);
      expect(ImplLane.of(ImplPlanStatus.done, ImplTestStatus.review),
          ImplLane.testReview);
    });

    test('両方完了(またはテスト不要)なら done', () {
      expect(ImplLane.of(ImplPlanStatus.done, ImplTestStatus.done),
          ImplLane.done);
      expect(ImplLane.of(ImplPlanStatus.done, ImplTestStatus.notRequired),
          ImplLane.done);
    });

    test('archived はテスト状態に関係なく archive', () {
      expect(ImplLane.of(ImplPlanStatus.archived, ImplTestStatus.inProgress),
          ImplLane.archive);
    });
  });

  group('遷移とファイル移動', () {
    test('new は 1_todo に置かれる', () async {
      final id = await newPlan('login');
      expect(existsIn(ImplLane.todo, '${id}_login.md'), isTrue);
    });

    test('状態を変えるとレーンを移動する', () async {
      final id = await newPlan('login');

      await usecase.setStatus(dir.path, id, ImplPlanStatus.inProgress, now: now);
      expect(existsIn(ImplLane.inProgress, '${id}_login.md'), isTrue);
      expect(existsIn(ImplLane.todo, '${id}_login.md'), isFalse);

      await usecase.setStatus(dir.path, id, ImplPlanStatus.done, now: now);
      expect(existsIn(ImplLane.testTodo, '${id}_login.md'), isTrue);

      await usecase.setTest(dir.path, id, ImplTestStatus.done);
      expect(existsIn(ImplLane.done, '${id}_login.md'), isTrue);
    });

    test('逆行できる(テストが落ちて実装へ戻る)', () async {
      final id = await newPlan('login');
      await usecase.setStatus(dir.path, id, ImplPlanStatus.done, now: now);
      await usecase.setTest(dir.path, id, ImplTestStatus.inProgress);

      await usecase.setStatus(dir.path, id, ImplPlanStatus.inProgress, now: now);
      expect(existsIn(ImplLane.inProgress, '${id}_login.md'), isTrue);
    });

    test('実装が done でないとテストを進められない', () async {
      final id = await newPlan('login');
      expect(() => usecase.setTest(dir.path, id, ImplTestStatus.inProgress),
          throwsArgumentError);
    });

    test('テスト不要は実装完了前でも宣言できる', () async {
      final id = await newPlan('login');
      final result = await usecase
          .setTest(dir.path, id, ImplTestStatus.notRequired, skipReason: '設定変更のみ');
      expect(result.after.test, ImplTestStatus.notRequired);
      expect(result.after.testSkipReason, '設定変更のみ');
    });

    test('存在しない ID は ArgumentError', () {
      expect(
          () => usecase.setStatus(dir.path, 'PLAN-9999', ImplPlanStatus.done,
              now: now),
          throwsArgumentError);
    });
  });

  group('ID 採番', () {
    test('archive 済みの ID を再利用しない(v1.6.x の欠陥)', () async {
      await newPlan('login');
      final second = await newPlan('payment');
      await usecase.archive(dir.path, second, now: now);

      final third = await newPlan('search');
      expect(third, 'PLAN-0003');
    });
  });

  group('sync', () {
    test('手で動かしたファイルを frontmatter に合わせて戻す', () async {
      final id = await newPlan('login');
      await usecase.setStatus(dir.path, id, ImplPlanStatus.review, now: now);

      // 人が手で 1_todo に戻してしまった状況
      final from = File('${dir.path}/doc/impl/3_review/${id}_login.md');
      final to = Directory('${dir.path}/doc/impl/1_todo')
        ..createSync(recursive: true);
      from.renameSync('${to.path}/${id}_login.md');

      final misplaced = await usecase.detectMisplaced(dir.path);
      expect(misplaced.keys, [id]);

      final movedDry = await usecase.sync(dir.path, dryRun: true);
      expect(movedDry.moved, [id]);
      expect(movedDry.blocked, isEmpty);
      expect(existsIn(ImplLane.review, '${id}_login.md'), isFalse,
          reason: 'dry-run では動かさない');

      await usecase.sync(dir.path);
      expect(existsIn(ImplLane.review, '${id}_login.md'), isTrue);
    });
  });

  group('後方互換', () {
    test('v1.6.x のフラット配置・draft・verification を読める', () async {
      final legacy = File('${dir.path}/doc/impl/PLAN-0007_legacy.md')
        ..createSync(recursive: true);
      legacy.writeAsStringSync('''---
id: "PLAN-0007"
feature: "legacy"
status: "draft"
created: "2026-07-01"
verification:
  static: "done"
  on_device: "done"
---
# 実装計画
''');

      final plans = await usecase.list(dir.path);
      expect(plans.single.status, ImplPlanStatus.todo, reason: 'draft → todo');
      expect(plans.single.test, ImplTestStatus.done,
          reason: 'verification が両方 done ならテスト完了');

      // status が todo である以上、検証が済んでいてもレーンは 1_todo
      await usecase.sync(dir.path);
      expect(existsIn(ImplLane.todo, 'PLAN-0007_legacy.md'), isTrue);
    });

    test('採番は旧配置の計画も含めて最大 + 1', () async {
      File('${dir.path}/doc/impl/PLAN-0009_legacy.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('''---
id: "PLAN-0009"
feature: "legacy"
status: "todo"
created: "2026-07-01"
---
''');
      expect(await newPlan('fresh'), 'PLAN-0010');
    });
  });

  group('レビュー指摘の回帰(1.7.0)', () {
    test('移動先が埋まっていたら上書きせず失敗する', () async {
      final id = await newPlan('login');
      // 別ブランチのマージ等で 2_in_progress にも同名ファイルがある状況
      final decoy = File('${dir.path}/doc/impl/2_in_progress/${id}_login.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nid: "$id"\nfeature: "login"\n'
            'status: "in_progress"\ncreated: "2026-08-11"\n---\n作業メモ\n');

      await expectLater(
        usecase.setStatus(dir.path, id, ImplPlanStatus.inProgress, now: now),
        throwsA(isA<StateError>()),
      );
      expect(decoy.readAsStringSync(), contains('作業メモ'),
          reason: '既存ファイルの本文が消えてはいけない');
    });

    test('sync は移動先が埋まっている計画をスキップして報告する', () async {
      final id = await newPlan('login');
      File('${dir.path}/doc/impl/3_review/${id}_login.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('別の中身\n');
      // frontmatter だけ review に(ファイルは 1_todo のまま)
      final planFile = File('${dir.path}/doc/impl/1_todo/${id}_login.md');
      planFile.writeAsStringSync(planFile
          .readAsStringSync()
          .replaceFirst('status: "todo"', 'status: "review"'));

      final result = await usecase.sync(dir.path);
      expect(result.moved, isEmpty);
      expect(result.blocked.keys, [id]);
      expect(File('${dir.path}/doc/impl/3_review/${id}_login.md')
          .readAsStringSync(), '別の中身\n');
    });

    test('feature 名にパス区切りや .. を含むと拒否する', () {
      for (final bad in ['../../escape', 'auth/login', '', '.hidden']) {
        expect(
            () => usecase.create(dir.path,
                feature: bad, now: now, bodyTemplate: '# x\n'),
            throwsArgumentError,
            reason: bad);
      }
    });

    test('入れ子に置かれた計画も採番に含める(archive/2026/ 等)', () async {
      File('${dir.path}/doc/impl/archive/2026/PLAN-0005_old.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nid: "PLAN-0005"\nfeature: "old"\n'
            'status: "archived"\ncreated: "2026-01-01"\n---\n');

      expect(await newPlan('fresh'), 'PLAN-0006');
    });

    test('frontmatter が壊れた計画は報告され、ID も再利用しない', () async {
      File('${dir.path}/doc/impl/1_todo/PLAN-0003_broken.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nid: "PLAN-0003"\nstatus: [\n---\n');

      final scan = await usecase.scan(dir.path);
      expect(scan.unreadable, hasLength(1));
      expect(scan.isHealthy, isFalse);
      // 壊れていても ID は消費済みとして扱う
      expect(await newPlan('fresh'), 'PLAN-0004');
    });

    test('重複 ID は検出され、更新は拒否される', () async {
      final id = await newPlan('login');
      File('${dir.path}/doc/impl/3_review/${id}_other.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nid: "$id"\nfeature: "other"\n'
            'status: "review"\ncreated: "2026-08-11"\n---\n');

      final scan = await usecase.scan(dir.path);
      expect(scan.duplicates.keys, [id]);
      await expectLater(
        usecase.setStatus(dir.path, id, ImplPlanStatus.done, now: now),
        throwsA(isA<StateError>()),
      );
    });

    test('done から戻すと completed_on が消える', () async {
      final id = await newPlan('login');
      await usecase.setStatus(dir.path, id, ImplPlanStatus.done, now: now);
      expect((await usecase.find(dir.path, id))!.completedOn, isNotNull);

      await usecase.setStatus(dir.path, id, ImplPlanStatus.inProgress, now: now);
      expect((await usecase.find(dir.path, id))!.completedOn, isNull);
    });

    test('テストを差し戻すと static/on_device も pending に戻る', () async {
      final id = await newPlan('login');
      await usecase.setStatus(dir.path, id, ImplPlanStatus.done, now: now);
      await usecase.setTest(dir.path, id, ImplTestStatus.done);
      expect((await usecase.find(dir.path, id))!.staticVerified, isTrue);

      await usecase.setTest(dir.path, id, ImplTestStatus.inProgress);
      final after = (await usecase.find(dir.path, id))!;
      expect(after.staticVerified, isFalse);
      expect(after.onDeviceVerified, isFalse);
    });

    test('テスト不要から抜けると理由が消える', () async {
      final id = await newPlan('login');
      await usecase.setTest(dir.path, id, ImplTestStatus.notRequired,
          skipReason: '設定変更のみ');
      expect((await usecase.find(dir.path, id))!.testSkipReason, '設定変更のみ');

      await usecase.setTest(dir.path, id, ImplTestStatus.todo);
      expect((await usecase.find(dir.path, id))!.testSkipReason, isNull);
    });

    test('引用符やバックスラッシュを含む値でも frontmatter が壊れない', () async {
      const tricky = r'BL-1 "quoted" C:\path\to';
      final id = await usecase.create(dir.path,
          feature: 'login',
          backlog: tricky,
          now: now,
          bodyTemplate: '# x\n');
      await usecase.setTest(dir.path, id, ImplTestStatus.notRequired,
          skipReason: r'"設定のみ" \ 続き');

      final reloaded = await usecase.find(dir.path, id);
      expect(reloaded, isNotNull, reason: '読み戻せること(YAML が壊れていない)');
      expect(reloaded!.backlog, tricky);
      expect(reloaded.testSkipReason, r'"設定のみ" \ 続き');
    });
  });

  group('種別プレフィックス(v1.8.0, #24)', () {
    test('種別無しは feat として読む(1.7.x の impl new <feature> と同じ)', () {
      final spec = ImplPlanKind.parseSpec('login');
      expect(spec.kind, ImplPlanKind.feat);
      expect(spec.target, 'login');
    });

    test('kind:target を分解する。未知の種別は拒否', () {
      final spec = ImplPlanKind.parseSpec('refactor:doc_layout');
      expect(spec.kind, ImplPlanKind.refactor);
      expect(spec.target, 'doc_layout');
      expect(() => ImplPlanKind.parseSpec('feature:login'), throwsArgumentError,
          reason: 'feat ではなく feature と書いた誤りを黙って通さない');
    });

    test('feat のファイル名は 1.7.x と同じ、それ以外は種別が入る', () async {
      final featId = await newPlan('login');
      expect(existsIn(ImplLane.todo, '${featId}_login.md'), isTrue);

      final refId = await usecase.create(dir.path,
          feature: 'doc_layout',
          kind: ImplPlanKind.refactor,
          now: now,
          bodyTemplate: '# x\n');
      expect(existsIn(ImplLane.todo, '${refId}_refactor_doc_layout.md'), isTrue);

      await usecase.setStatus(dir.path, refId, ImplPlanStatus.inProgress,
          now: now);
      expect(
          existsIn(ImplLane.inProgress, '${refId}_refactor_doc_layout.md'),
          isTrue,
          reason: 'レーン移動後も種別付きの名前を保つ');
    });

    test('kind の無い 1.7.x のファイルは feat として読み、配置違いにならない',
        () async {
      File('${dir.path}/doc/impl/2_in_progress/PLAN-0004_login.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nid: "PLAN-0004"\nfeature: "login"\n'
            'status: "in_progress"\ncreated: "2026-08-11"\n---\n');

      final plan = (await usecase.find(dir.path, 'PLAN-0004'))!;
      expect(plan.kind, ImplPlanKind.feat);
      expect(await usecase.detectMisplaced(dir.path), isEmpty,
          reason: 'CLI を上げただけでファイルが動いてはいけない');
    });

    test('ゲートは feat / fix だけを数える', () {
      ImplPlanMeta plan(String id, String feature, ImplPlanKind kind) =>
          ImplPlanMeta(
              id: id, feature: feature, kind: kind, created: DateTime(2026));
      final plans = [
        plan('PLAN-0001', 'login', ImplPlanKind.feat),
        plan('PLAN-0002', 'payment', ImplPlanKind.fix),
        plan('PLAN-0003', 'search', ImplPlanKind.refactor),
        plan('PLAN-0004', 'readme', ImplPlanKind.docs),
      ];
      expect(ImplPlanGate.featuresWithPlan(plans), {'login', 'payment'},
          reason: 'refactor:search があっても search feature の計画にはならない');
    });

    test('displayName は feat なら対象名のみ、それ以外は kind:target', () {
      expect(
          ImplPlanMeta(id: 'PLAN-0001', feature: 'login', created: DateTime(2026))
              .displayName,
          'login');
      expect(
          ImplPlanMeta(
                  id: 'PLAN-0002',
                  feature: 'readme',
                  kind: ImplPlanKind.docs,
                  created: DateTime(2026))
              .displayName,
          'docs:readme');
    });
  });

  group('計画と実施記録の分離(v1.8.0, #23)', () {
    String bodyOf(String relativePath) {
      final content = File('${dir.path}/$relativePath').readAsStringSync();
      return content.substring(content.indexOf('\n---\n') + 5);
    }

    test('split: マーカーの上が計画、下が記録。無ければ全体が計画', () {
      final parts = ImplPlanBody.split(
          '# 計画\n本文\n${ImplPlanBody.marker}\n## 実施記録\n\n- 1件目\n');
      expect(parts.plan, '# 計画\n本文\n');
      expect(parts.log, '## 実施記録\n\n- 1件目\n');

      final none = ImplPlanBody.split('# 計画だけ\n');
      expect(none.plan, '# 計画だけ\n');
      expect(none.log, isNull);
    });

    test('行頭にないマーカー(本文中の引用)は境界と見なさない', () {
      final parts = ImplPlanBody.split(
          '説明: `${ImplPlanBody.marker}` を書くと…\n${ImplPlanBody.marker}\n- x\n');
      expect(parts.plan, '説明: `${ImplPlanBody.marker}` を書くと…\n');
      expect(parts.log, '- x\n');
    });

    test('formatEntry: 日時・記録者・本文。複数行は字下げで続ける', () {
      expect(
          ImplPlanBody.formatEntry(
              at: DateTime(2026, 10, 7, 9, 5), actor: 'agent:claude', text: 'x'),
          '- 2026-10-07 09:05 (agent:claude) x');
      expect(
          ImplPlanBody.formatEntry(
              at: DateTime(2026, 10, 7, 9, 5), actor: '', text: '1行目\n2行目\n'),
          '- 2026-10-07 09:05 1行目\n  2行目');
    });

    test('note は記録領域に追記し、計画部分を変えない', () async {
      final id = await usecase.create(dir.path,
          feature: 'login',
          now: now,
          bodyTemplate: '# 計画\n\n設計方針。\n\n${ImplPlanBody.marker}\n'
              '${ImplPlanBody.logHeading}\n\n');
      await usecase.note(dir.path, id, '調査完了',
          now: DateTime(2026, 8, 11, 10, 0), actor: 'me');
      await usecase.note(dir.path, id, '方針を確認',
          now: DateTime(2026, 8, 11, 11, 0), actor: 'agent:claude');

      final parts =
          ImplPlanBody.split(bodyOf('doc/impl/1_todo/${id}_login.md'));
      expect(parts.plan, '# 計画\n\n設計方針。\n\n');
      expect(parts.log, '${ImplPlanBody.logHeading}\n\n'
          '- 2026-08-11 10:00 (me) 調査完了\n'
          '- 2026-08-11 11:00 (agent:claude) 方針を確認\n');
    });

    test('マーカーの無い 1.7.x のファイルには、初回の追記で末尾に領域を作る',
        () async {
      final id = await newPlan('login'); // bodyTemplate は '# 実装計画\n' のみ
      await usecase.note(dir.path, id, 'メモ', now: now, actor: 'me');

      final body = bodyOf('doc/impl/1_todo/${id}_login.md');
      expect(body, '# 実装計画\n\n${ImplPlanBody.marker}\n'
          '${ImplPlanBody.logHeading}\n\n- 2026-08-11 00:00 (me) メモ\n');
      expect(ImplPlanBody.split(body).plan, '# 実装計画\n\n',
          reason: '計画部分は元の本文のまま(末尾の空行は正規化で吸収される)');
    });

    test('状態遷移は記録領域に 1 行残る', () async {
      final id = await newPlan('login');
      await usecase.setStatus(dir.path, id, ImplPlanStatus.inProgress,
          now: DateTime(2026, 8, 11, 9, 0), actor: 'me');
      await usecase.setStatus(dir.path, id, ImplPlanStatus.done,
          now: DateTime(2026, 8, 11, 12, 0), actor: 'me');
      await usecase.setTest(dir.path, id, ImplTestStatus.notRequired,
          skipReason: '設定のみ', now: DateTime(2026, 8, 11, 12, 30), actor: 'me');

      final log =
          ImplPlanBody.split(bodyOf('doc/impl/7_done/${id}_login.md')).log!;
      expect(log, contains('- 2026-08-11 09:00 (me) status: todo → in_progress'));
      expect(log, contains('- 2026-08-11 12:00 (me) status: in_progress → done'));
      expect(log,
          contains('- 2026-08-11 12:30 (me) test: todo → not_required (設定のみ)'));
    });

    test('空の記録は拒否', () {
      expect(() => usecase.note(dir.path, 'PLAN-0001', '  \n', now: now),
          throwsArgumentError);
    });
  });

  group('ImplPlanGate', () {
    test('archived 以外の計画があれば「計画あり」', () {
      final plans = [
        ImplPlanMeta(
            id: 'PLAN-0001',
            feature: 'todo',
            status: ImplPlanStatus.done,
            created: DateTime(2026)),
        ImplPlanMeta(
            id: 'PLAN-0002',
            feature: 'memo',
            status: ImplPlanStatus.archived,
            created: DateTime(2026)),
      ];
      expect(ImplPlanGate.featuresWithPlan(plans), {'todo'});
    });

    test('enforced が false なら何も止めない', () {
      expect(
          ImplPlanGate.blocked(
              enforced: false, featureNames: ['a', 'b'], withPlan: const {}),
          isEmpty);
    });

    test('既定は off(CLI を上げただけでは止まらない)', () {
      expect(const UtakataConfig().implPlanEnforcement, 'off');
      expect(UtakataConfig.fromMap(const {}).implPlanEnforcement, 'off');
      expect(
          UtakataConfig.fromMap(const {
            'enforcement': {'impl_plan': 'on'}
          }).implPlanEnforcement,
          'on');
    });

    test('enforced なら計画の無い feature だけ止める', () {
      expect(
          ImplPlanGate.blocked(
              enforced: true, featureNames: ['a', 'b'], withPlan: {'a'}),
          ['b']);
    });
  });
}
