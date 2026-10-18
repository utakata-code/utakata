import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../../1_domain/1_entities/record/impl_plan_meta.dart';
import '../../1_domain/3_usecases/impl_plan_usecase.dart';
import '../../1_domain/messages/cli_messages.dart';
import '../../1_domain/services/actor_resolver.dart';
import '../../1_domain/services/case_converter.dart';
import '../../1_domain/services/impl_lane.dart';
import '../3_presenters/impl_board_presenter.dart';
import 'base_command.dart';
import 'logger.dart';

/// utakata impl — feature 実装計画の管理(2軸のライフサイクル)
class ImplCommand extends Command<int> {
  final CliMessages _msg;

  @override
  String get name => 'impl';
  @override
  String get description => _msg.cmdImplDesc;

  ImplCommand(
    ImplPlanUsecase usecase,
    this._msg, {
    required Future<void> Function(String path, String content) writeFile,
  }) {
    addSubcommand(_ImplNewCommand(usecase, _msg, writeFile));
    addSubcommand(_ImplListCommand(usecase, _msg));
    addSubcommand(_ImplBoardCommand(usecase, _msg, writeFile));
    addSubcommand(_ImplStartCommand(usecase, _msg, writeFile));
    addSubcommand(_ImplReviewCommand(usecase, _msg, writeFile));
    addSubcommand(_ImplDoneCommand(usecase, _msg, writeFile));
    addSubcommand(_ImplTestCommand(usecase, _msg, writeFile));
    addSubcommand(_ImplArchiveCommand(usecase, _msg, writeFile));
    addSubcommand(_ImplSyncCommand(usecase, _msg, writeFile));
    addSubcommand(_ImplNoteCommand(usecase, _msg));
    addSubcommand(_ImplReviseCommand(usecase, _msg, writeFile));
  }

  @override
  Future<int> run() async {
    printUsage();
    return 0;
  }
}

const _bodyTemplate = '''
# 実装計画

## 1. 背景・目的

【背景・目的を記載】

## 2. 現状整理・調査結果

| 項目 | 内容 |
|------|------|
| 【現状のコード】 | 【ファイルパス:行番号と要約】 |
| 【要求の根拠】 | 【出典と、合意済みか当方判断かの区別】 |

## 3. 設計方針(決定事項)

## 4. 変更ファイル一覧

| ファイル | 変更 |
|---------|------|

## 5. 実装ステップ

1. 【ステップ1】
2. `flutter analyze` → `utakata check`

## 6. テスト・検証計画

## 7. 文書更新

## 8. スコープ外

<!-- utakata:log -->
## 実施記録

''';

/// 記録者(`UTAKATA_ACTOR` → `USER`)。records と同じ解決順。
String _actor() => ActorResolver.resolve(Platform.environment);

/// 状態を変えたら常にボードを作り直す(プレビューを手で再生成させない)。
Future<void> _refreshBoard(
  ImplPlanUsecase usecase,
  String projectDir,
  Future<void> Function(String path, String content) writeFile,
) async {
  final plans = await usecase.list(projectDir);
  await writeFile(
    '$projectDir/doc/preview/impl_board.md',
    ImplBoardPresenter.render(plans),
  );
}

/// 遷移結果の共通表示。
void _reportTransition(ImplTransition result, CliMessages msg) {
  Logger.success(msg.implTransitionDone(
    result.after.id,
    ImplPlanMeta.statusToString(result.after.status),
    ImplPlanMeta.testToString(result.after.test),
  ));
  final movedTo = result.movedTo;
  if (movedTo != null) Logger.step(msg.implMovedTo(movedTo));
}

class _ImplNewCommand extends BaseCommand {
  final ImplPlanUsecase _usecase;
  final CliMessages _msg;
  final Future<void> Function(String path, String content) _writeFile;

  @override
  String get name => 'new';
  @override
  String get description => _msg.cmdImplNewDesc;

  _ImplNewCommand(this._usecase, this._msg, this._writeFile) {
    argParser
      ..addOption('backlog', defaultsTo: '')
      ..addOption('agreement') // カンマ区切り
      ..addOption('spec')
      ..addOption('message')
      ..addOption('basis', allowed: ['client_agreed', 'developer_judgment'])
      ..addOption('supersedes', help: _msg.optImplSupersedes);
  }

  @override
  Future<int> execute() async {
    if (argResults!.rest.isEmpty) {
      Logger.error(_msg.implFeatureRequired);
      return 64;
    }
    // v1.8.0: `[kind:]target`。種別が無ければ feat(1.7.x と同じ)。
    final spec = ImplPlanKind.parseSpec(argResults!.rest.first);
    // feature add / plan.yaml と同じ正規化を通す(ゲート判定が名前の
    // 表記ゆれで食い違わないように)
    final feature = CaseConverter.toSnakeCase(spec.target);
    final basisRaw = argResults!['basis'] as String?;
    final projectDir = Directory.current.path;

    final id = await _usecase.create(
      projectDir,
      feature: feature,
      kind: spec.kind,
      backlog: argResults!['backlog'] as String,
      agreements: _splitCsv(argResults!['agreement'] as String?),
      specs: _splitCsv(argResults!['spec'] as String?),
      messages: _splitCsv(argResults!['message'] as String?),
      basis: basisRaw == 'client_agreed'
          ? ImplPlanBasis.clientAgreed
          : basisRaw == 'developer_judgment'
              ? ImplPlanBasis.developerJudgment
              : null,
      supersedes: argResults!['supersedes'] as String?,
      now: DateTime.now(),
      bodyTemplate: _bodyTemplate,
    );

    await _refreshBoard(_usecase, projectDir, _writeFile);
    final created = (await _usecase.find(projectDir, id))!;
    Logger.success(_msg.implNewDone(
        id, 'doc/impl/${ImplLane.todo.dirName}/${created.fileName}'));
    return 0;
  }

  List<String> _splitCsv(String? raw) =>
      raw?.split(',').where((s) => s.isNotEmpty).toList() ?? const [];
}

class _ImplListCommand extends BaseCommand {
  final ImplPlanUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'list';
  @override
  String get description => _msg.cmdImplListDesc;

  _ImplListCommand(this._usecase, this._msg) {
    argParser
      ..addOption('status', help: _msg.optImplStatus)
      ..addOption('test', help: _msg.optImplTest)
      ..addOption('lane', help: _msg.optImplLane)
      ..addFlag('json', help: _msg.optJson, negatable: false);
  }

  @override
  Future<int> execute() async {
    var plans = await _usecase.list(Directory.current.path);

    final statusRaw = argResults!['status'] as String?;
    final testRaw = argResults!['test'] as String?;
    final laneRaw = argResults!['lane'] as String?;
    if (statusRaw != null) {
      final status = ImplPlanMeta.statusFromString(statusRaw);
      plans = plans.where((p) => p.status == status).toList();
    }
    if (testRaw != null) {
      final test = ImplPlanMeta.testFromString(testRaw);
      plans = plans.where((p) => p.test == test).toList();
    }
    if (laneRaw != null) {
      final lane = ImplLane.fromDirName(laneRaw);
      if (lane == null) {
        Logger.error(_msg.implUnknownLane(laneRaw,
            ImplLane.values.map((l) => l.dirName).join(', ')));
        return 64;
      }
      plans = plans.where((p) => ImplLane.ofMeta(p) == lane).toList();
    }

    if (argResults!['json'] as bool) {
      stdout.writeln(jsonEncode([
        for (final plan in plans)
          {
            'id': plan.id,
            'feature': plan.feature,
            'kind': plan.kind.name,
            'status': ImplPlanMeta.statusToString(plan.status),
            'test': ImplPlanMeta.testToString(plan.test),
            'lane': ImplLane.ofMeta(plan).dirName,
            'created': plan.created.toIso8601String().substring(0, 10),
            if (plan.completedOn != null)
              'completed_on': plan.completedOn!.toIso8601String().substring(0, 10),
            if (plan.origin.agreements.isNotEmpty)
              'agreements': plan.origin.agreements,
            'frozen': plan.isFrozen,
            if (plan.revisions > 0) 'revisions': plan.revisions,
            if (plan.supersedes != null) 'supersedes': plan.supersedes,
          },
      ]));
      return 0;
    }

    if (plans.isEmpty) {
      Logger.warn(_msg.implListEmpty);
      return 0;
    }
    for (final plan in plans) {
      Logger.info(ImplBoardPresenter.renderLine(plan));
    }
    return 0;
  }
}

class _ImplBoardCommand extends BaseCommand {
  final ImplPlanUsecase _usecase;
  final CliMessages _msg;
  final Future<void> Function(String path, String content) _writeFile;

  @override
  String get name => 'board';
  @override
  String get description => _msg.cmdImplBoardDesc;

  _ImplBoardCommand(this._usecase, this._msg, this._writeFile);

  @override
  Future<int> execute() async {
    final projectDir = Directory.current.path;
    final plans = await _usecase.list(projectDir);
    final markdown = ImplBoardPresenter.render(plans);
    await _writeFile('$projectDir/doc/preview/impl_board.md', markdown);
    stdout.writeln(markdown);
    Logger.success(_msg.implBoardDone('doc/preview/impl_board.md'));
    return 0;
  }
}

/// 実装軸の遷移コマンド(start / review / done)の共通実装。
abstract class _StatusTransitionCommand extends BaseCommand {
  final ImplPlanUsecase usecase;
  final CliMessages msg;
  final Future<void> Function(String path, String content) writeFile;
  final ImplPlanStatus target;

  _StatusTransitionCommand({
    required this.usecase,
    required this.msg,
    required this.writeFile,
    required this.target,
  });

  @override
  Future<int> execute() async {
    if (argResults!.rest.isEmpty) {
      Logger.error(msg.implIdRequired);
      return 64;
    }
    final projectDir = Directory.current.path;
    final result = await usecase.setStatus(
        projectDir, argResults!.rest.first, target,
        now: DateTime.now(), actor: _actor());
    await _refreshBoard(usecase, projectDir, writeFile);
    _reportTransition(result, msg);
    return 0;
  }
}

class _ImplStartCommand extends _StatusTransitionCommand {
  _ImplStartCommand(ImplPlanUsecase usecase, CliMessages msg,
      Future<void> Function(String, String) writeFile)
      : super(
            usecase: usecase,
            msg: msg,
            writeFile: writeFile,
            target: ImplPlanStatus.inProgress);

  @override
  String get name => 'start';
  @override
  String get description => msg.cmdImplStartDesc;
}

class _ImplReviewCommand extends _StatusTransitionCommand {
  _ImplReviewCommand(ImplPlanUsecase usecase, CliMessages msg,
      Future<void> Function(String, String) writeFile)
      : super(
            usecase: usecase,
            msg: msg,
            writeFile: writeFile,
            target: ImplPlanStatus.review);

  @override
  String get name => 'review';
  @override
  String get description => msg.cmdImplReviewDesc;
}

class _ImplDoneCommand extends _StatusTransitionCommand {
  _ImplDoneCommand(ImplPlanUsecase usecase, CliMessages msg,
      Future<void> Function(String, String) writeFile)
      : super(
            usecase: usecase,
            msg: msg,
            writeFile: writeFile,
            target: ImplPlanStatus.done);

  @override
  String get name => 'done';
  @override
  String get description => msg.cmdImplDoneDesc;
}

class _ImplArchiveCommand extends _StatusTransitionCommand {
  _ImplArchiveCommand(ImplPlanUsecase usecase, CliMessages msg,
      Future<void> Function(String, String) writeFile)
      : super(
            usecase: usecase,
            msg: msg,
            writeFile: writeFile,
            target: ImplPlanStatus.archived);

  @override
  String get name => 'archive';
  @override
  String get description => msg.cmdImplArchiveDesc;
}

/// utakata impl test start|review|done|skip — 検証軸の遷移
class _ImplTestCommand extends Command<int> {
  final CliMessages _msg;

  @override
  String get name => 'test';
  @override
  String get description => _msg.cmdImplTestDesc;

  _ImplTestCommand(
    ImplPlanUsecase usecase,
    this._msg,
    Future<void> Function(String path, String content) writeFile,
  ) {
    addSubcommand(_TestTransitionCommand(
        usecase, _msg, writeFile, 'start', ImplTestStatus.inProgress));
    addSubcommand(_TestTransitionCommand(
        usecase, _msg, writeFile, 'review', ImplTestStatus.review));
    addSubcommand(_TestTransitionCommand(
        usecase, _msg, writeFile, 'done', ImplTestStatus.done));
    addSubcommand(_TestTransitionCommand(
        usecase, _msg, writeFile, 'todo', ImplTestStatus.todo));
    addSubcommand(_TestTransitionCommand(
        usecase, _msg, writeFile, 'skip', ImplTestStatus.notRequired));
  }

  @override
  Future<int> run() async {
    printUsage();
    return 0;
  }
}

class _TestTransitionCommand extends BaseCommand {
  final ImplPlanUsecase _usecase;
  final CliMessages _msg;
  final Future<void> Function(String path, String content) _writeFile;
  final String _name;
  final ImplTestStatus _target;

  @override
  String get name => _name;
  @override
  String get description => _msg.cmdImplTestTransitionDesc(_name);

  _TestTransitionCommand(
      this._usecase, this._msg, this._writeFile, this._name, this._target) {
    if (_target == ImplTestStatus.notRequired) {
      argParser.addOption('reason', help: _msg.optImplSkipReason);
    }
  }

  @override
  Future<int> execute() async {
    if (argResults!.rest.isEmpty) {
      Logger.error(_msg.implIdRequired);
      return 64;
    }
    final projectDir = Directory.current.path;
    final result = await _usecase.setTest(
      projectDir,
      argResults!.rest.first,
      _target,
      skipReason: _target == ImplTestStatus.notRequired
          ? argResults!['reason'] as String?
          : null,
      now: DateTime.now(),
      actor: _actor(),
    );
    await _refreshBoard(_usecase, projectDir, _writeFile);
    _reportTransition(result, _msg);
    return 0;
  }
}

/// `utakata impl note <ID> [text]` — 実施記録を 1 件追記(本文は引数か stdin)
class _ImplNoteCommand extends BaseCommand {
  final ImplPlanUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'note';
  @override
  String get description => _msg.cmdImplNoteDesc;

  _ImplNoteCommand(this._usecase, this._msg);

  @override
  Future<int> execute() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      Logger.error(_msg.implIdRequired);
      return 64;
    }
    final text = rest.length > 1
        ? rest.skip(1).join(' ')
        : await _readStdin();
    if (text.trim().isEmpty) {
      Logger.error(_msg.implNoteTextRequired);
      return 64;
    }
    await _usecase.note(Directory.current.path, rest.first, text,
        now: DateTime.now(), actor: _actor());
    Logger.success(_msg.implNoteDone(rest.first));
    return 0;
  }

  /// 端末に繋がっている(= パイプされていない)stdin は読まない。
  /// 読みにいくと入力待ちで止まって見える。
  Future<String> _readStdin() async {
    if (stdin.hasTerminal) return '';
    return utf8.decoder.bind(stdin).join();
  }
}

/// `utakata impl revise <ID> --reason "..."` — 凍結後の書き換えを改訂として受理
class _ImplReviseCommand extends BaseCommand {
  final ImplPlanUsecase _usecase;
  final CliMessages _msg;
  final Future<void> Function(String path, String content) _writeFile;

  @override
  String get name => 'revise';
  @override
  String get description => _msg.cmdImplReviseDesc;

  _ImplReviseCommand(this._usecase, this._msg, this._writeFile) {
    argParser.addOption('reason', help: _msg.optImplReviseReason);
  }

  @override
  Future<int> execute() async {
    if (argResults!.rest.isEmpty) {
      Logger.error(_msg.implIdRequired);
      return 64;
    }
    final reason = argResults!['reason'] as String?;
    if (reason == null || reason.trim().isEmpty) {
      Logger.error(_msg.implReviseReasonRequired);
      return 64;
    }
    final projectDir = Directory.current.path;
    final updated = await _usecase.revise(projectDir, argResults!.rest.first,
        reason: reason, now: DateTime.now(), actor: _actor());
    await _refreshBoard(_usecase, projectDir, _writeFile);
    Logger.success(_msg.implReviseDone(updated.id, updated.revisions));
    return 0;
  }
}

class _ImplSyncCommand extends BaseCommand {
  final ImplPlanUsecase _usecase;
  final CliMessages _msg;
  final Future<void> Function(String path, String content) _writeFile;

  @override
  String get name => 'sync';
  @override
  String get description => _msg.cmdImplSyncDesc;

  _ImplSyncCommand(this._usecase, this._msg, this._writeFile) {
    argParser.addFlag('dry-run', help: _msg.optDryRun, negatable: false);
  }

  @override
  Future<int> execute() async {
    final projectDir = Directory.current.path;
    final dryRun = argResults!['dry-run'] as bool;
    final misplaced = await _usecase.detectMisplaced(projectDir);
    if (misplaced.isEmpty) {
      Logger.success(_msg.implSyncClean);
      return 0;
    }
    for (final entry in misplaced.entries) {
      Logger.step('${entry.key}: ${entry.value.actual} → ${entry.value.expected}');
    }
    final result = await _usecase.sync(projectDir, dryRun: dryRun);
    for (final entry in result.blocked.entries) {
      Logger.error(_msg.implSyncBlocked(entry.key, entry.value));
    }
    if (dryRun) {
      Logger.info(_msg.implSyncDryRun(result.moved.length));
    } else {
      await _refreshBoard(_usecase, projectDir, _writeFile);
      Logger.success(_msg.implSyncDone(result.moved.length));
    }
    return result.blocked.isEmpty ? 0 : 1;
  }
}
