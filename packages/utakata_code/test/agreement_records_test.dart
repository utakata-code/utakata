import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:utakata/src/1_domain/1_entities/record/agreement.dart';
import 'package:utakata/src/1_domain/3_usecases/doctor_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/impl_plan_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/list_agreements_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/record_agreement_usecase.dart';
import 'package:utakata/src/1_domain/exceptions/domain_exceptions.dart';
import 'package:utakata/src/1_domain/messages/ja_messages.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/filesystem_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/front_matter_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/jsonl_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_edit_data_source.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/agreement_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/impl_plan_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/plan_repository_impl.dart';

/// v1.8.1(#33): 合意 ID の検査と、壊れた台帳を落ちずに読むこと。
void main() {
  late Directory dir;
  late AgreementRepositoryImpl repo;
  late RecordAgreementUsecase record;
  final now = DateTime(2026, 10, 28);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('utakata_agreements_');
    repo = const AgreementRepositoryImpl(JsonlDataSource());
    record = RecordAgreementUsecase(repo: repo);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  File ledgerFile() => File('${dir.path}/doc/records/agreements.jsonl');
  String ledgerText() => ledgerFile().existsSync() ? ledgerFile().readAsStringSync() : '';

  Future<String> addOne([String title = '画面A']) => record.add(dir.path,
      title: title, kindRaw: 'client', now: now, recordedBy: 'human');

  void appendRaw(String line) {
    ledgerFile().parent.createSync(recursive: true);
    ledgerFile().writeAsStringSync('$line\n', mode: FileMode.append);
  }

  group('入力の検査(何も書かずに断る)', () {
    test('agree status: 改行入りの ID は断る', () async {
      await addOne();
      final before = ledgerText();
      expect(
        () => record.updateStatus(dir.path, 'AGR-0001\nAGR-0002', 'agreed',
            now: now, recordedBy: 'human'),
        throwsA(isA<InvalidAgreementIdException>()),
      );
      expect(ledgerText(), before);
    });

    test('agree status: 存在しない AGR-9999 は断る', () async {
      await addOne();
      final before = ledgerText();
      await expectLater(
        record.updateStatus(dir.path, 'AGR-9999', 'agreed',
            now: now, recordedBy: 'human'),
        throwsA(isA<AgreementNotFoundException>()),
      );
      expect(ledgerText(), before);
    });

    test('agree status: 未知の状態は StateError ではなく ArgumentError', () async {
      final id = await addOne();
      final before = ledgerText();
      expect(
        () => record.updateStatus(dir.path, id, 'done', now: now, recordedBy: 'human'),
        throwsA(isA<ArgumentError>()),
      );
      expect(ledgerText(), before);
    });

    test('agree status: 存在する ID なら従来どおり記録できる', () async {
      final id = await addOne();
      await record.updateStatus(dir.path, id, 'agreed', now: now, recordedBy: 'human');
      expect((await repo.findById(dir.path, id))!.status, AgreementStatus.agreed);
    });

    test('agree correct: 存在しない ID なら新しい合意も作らない', () async {
      await addOne();
      final before = ledgerText();
      await expectLater(
        record.correct(dir.path, 'AGR-9999',
            title: '訂正', kindRaw: 'correction', now: now, recordedBy: 'human'),
        throwsA(isA<AgreementNotFoundException>()),
      );
      expect(ledgerText(), before);
      expect(await repo.listAll(dir.path), hasLength(1));
    });

    test('agree correct: 存在する ID なら新しい ID を作り元を superseded にする', () async {
      final id = await addOne();
      final newId = await record.correct(dir.path, id,
          title: '訂正', kindRaw: 'correction', now: now, recordedBy: 'human');
      expect(newId, 'AGR-0002');
      expect((await repo.findById(dir.path, id))!.status, AgreementStatus.superseded);
    });

    test('agree reflect: 改行入り・存在しない ID は断る', () async {
      await addOne();
      final before = ledgerText();
      await expectLater(
        record.reflect(dir.path, 'AGR-0001\n', planId: 'PLAN-0001', now: now, recordedBy: 'human'),
        throwsA(isA<InvalidAgreementIdException>()),
      );
      await expectLater(
        record.reflect(dir.path, 'AGR-9999', planId: 'PLAN-0001', now: now, recordedBy: 'human'),
        throwsA(isA<AgreementNotFoundException>()),
      );
      expect(ledgerText(), before);
    });

    group('impl new --agreement', () {
      late ImplPlanUsecase impl;
      setUp(() {
        impl = ImplPlanUsecase(
          repo: const ImplPlanRepositoryImpl(
              FilesystemDataSource(), FrontMatterDataSource(YamlDataSource())),
          agreementRepo: repo,
        );
      });

      bool anyPlanWritten() {
        final implDir = Directory('${dir.path}/doc/impl');
        return implDir.existsSync() &&
            implDir.listSync(recursive: true).whereType<File>().any((f) => f.path.endsWith('.md'));
      }

      test('改行入りの ID は断り、計画書を作らない', () async {
        await addOne();
        await expectLater(
          impl.create(dir.path,
              feature: 'login',
              agreements: ['AGR-0001\nAGR-0002'],
              now: now,
              bodyTemplate: '# x\n'),
          throwsA(isA<InvalidAgreementIdException>()),
        );
        expect(anyPlanWritten(), isFalse);
      });

      test('存在しない ID は断り、計画書を作らない', () async {
        await addOne();
        await expectLater(
          impl.create(dir.path,
              feature: 'login', agreements: ['AGR-0001', 'AGR-9999'], now: now, bodyTemplate: '# x\n'),
          throwsA(isA<AgreementNotFoundException>()),
        );
        expect(anyPlanWritten(), isFalse);
      });

      test('存在する ID(前後の空白は落とす)なら作れる', () async {
        await addOne();
        await addOne('画面B');
        final id = await impl.create(dir.path,
            feature: 'login', agreements: ['AGR-0001', ' AGR-0002'], now: now, bodyTemplate: '# x\n');
        final created = await impl.find(dir.path, id);
        expect(created!.origin.agreements, ['AGR-0001', 'AGR-0002']);
      });
    });
  });

  group('壊れた台帳を落ちずに読む', () {
    test('1.8.0 で書かれた改行入り ID の statusChange があっても一覧が出る', () async {
      await addOne();
      // 1.8.0 の agree status が実際に書いた形
      appendRaw(jsonEncode({
        'type': 'statusChange',
        'id': 'AGR-0001\nAGR-0094',
        'recorded_at': now.toIso8601String(),
        'recorded_by': 'human',
        'status': 'agreed',
      }));
      final ledger = await repo.load(dir.path);
      expect(ledger.agreements.map((a) => a.id), ['AGR-0001']);
      expect(ledger.agreements.single.status, AgreementStatus.proposed);
      expect(ledger.skipped.single.reason, AgreementSkipReason.missingAdd);
      expect(ledger.skipped.single.id, 'AGR-0001\nAGR-0094');
    });

    test('add の無い ID(存在しない AGR-9999 への statusChange)を飛ばす', () async {
      await addOne();
      appendRaw(jsonEncode({
        'type': 'statusChange',
        'id': 'AGR-9999',
        'recorded_at': now.toIso8601String(),
        'recorded_by': 'human',
        'status': 'agreed',
      }));
      final ledger = await ListAgreementsUsecase(repo: repo).executeWithSkipped(dir.path);
      expect(ledger.agreements.map((a) => a.id), ['AGR-0001']);
      expect(ledger.skipped.single.id, 'AGR-9999');
      // 宙に浮いた ID を再利用しない(再利用すると状態変更が新しい合意に付く)
      expect(await repo.nextId(dir.path), 'AGR-10000');
    });

    test('JSON として読めない行と、合意として解釈できない行を行番号付きで飛ばす', () async {
      await addOne();
      appendRaw('{"type": "add", "id": "AGR-00'); // 2行目: 途中で切れた行
      appendRaw(jsonEncode({'type': 'unknown', 'id': 'AGR-0003'})); // 3行目
      await addOne('画面B'); // 4行目(壊れた行の ID は採番に数えない → AGR-0002)
      final ledger = await repo.load(dir.path);
      expect(ledger.agreements.map((a) => a.id), ['AGR-0001', 'AGR-0002']);
      expect(
        ledger.skipped.map((s) => (s.reason, s.line)),
        [(AgreementSkipReason.unparsableLine, 2), (AgreementSkipReason.invalidEvent, 3)],
      );
      // 書き込み側(採番・検査)も落ちない
      await record.updateStatus(dir.path, 'AGR-0002', 'agreed', now: now, recordedBy: 'human');
    });

    test('正しい台帳は従来どおり読め、飛ばす記録は無い', () async {
      final id = await addOne();
      await record.updateStatus(dir.path, id, 'agreed', now: now, recordedBy: 'human');
      await record.reflect(dir.path, id, planId: 'PLAN-0001', now: now, recordedBy: 'human');
      final ledger = await repo.load(dir.path);
      expect(ledger.skipped, isEmpty);
      final a = ledger.agreements.single;
      expect(a.status, AgreementStatus.agreed);
      expect(a.reflectedInPlanIds, ['PLAN-0001']);
    });

    test('foldFrom は add の無いまとまりで null を返す(例外を投げない)', () {
      final orphan = AgreementEvent(
        type: AgreementEventType.statusChange,
        id: 'AGR-9999',
        recordedAt: now,
        recordedBy: 'human',
        status: AgreementStatus.agreed,
      );
      expect(Agreement.foldFrom([orphan]), isNull);
    });

    test('doctor が読めない記録を知らせる', () async {
      await addOne();
      appendRaw(jsonEncode({
        'type': 'statusChange',
        'id': 'AGR-9999',
        'recorded_at': now.toIso8601String(),
        'recorded_by': 'human',
        'status': 'agreed',
      }));
      const fs = FilesystemDataSource();
      final doctor = DoctorUsecase(
        planRepo: const PlanRepositoryImpl(fs, YamlDataSource(), YamlEditDataSource()),
        fileExists: (p) => File(p).existsSync(),
        dirExists: (p) => Directory(p).existsSync(),
        readFile: (p) async => File(p).existsSync() ? File(p).readAsStringSync() : null,
        deleteFile: (p) async {},
        deleteDir: (p) async {},
        movePath: (a, b) async {},
        listEntries: (p) => const [],
        skippedAgreements: (d) async => (await repo.load(d)).skipped,
        msg: JaMessages(),
      );
      final issues = await doctor.diagnose(dir.path);
      expect(issues.where((i) => i.contains('agreements.jsonl') && i.contains('"AGR-9999"')),
          hasLength(1));
    });
  });
}
