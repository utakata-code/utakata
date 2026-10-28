import 'dart:io';

import 'package:args/command_runner.dart';

import '../../1_domain/3_usecases/list_agreements_usecase.dart';
import '../../1_domain/3_usecases/record_agreement_usecase.dart';
import '../../1_domain/messages/cli_messages.dart';
import '../../1_domain/services/actor_resolver.dart';
import 'agreement_cli_support.dart';
import 'base_command.dart';
import 'logger.dart';

/// 記録者。`UTAKATA_ACTOR` があればそれ(エージェント実行時は `agent:claude` 等)。
String _currentUser() => ActorResolver.resolve(Platform.environment);

/// utakata agree — 合意トラッキング(お客様合意・内部決定)
class AgreeCommand extends Command<int> {
  final CliMessages _msg;

  @override
  String get name => 'agree';
  @override
  String get description => _msg.cmdAgreeDesc;

  AgreeCommand(RecordAgreementUsecase recordUsecase, ListAgreementsUsecase listUsecase, this._msg) {
    addSubcommand(_AgreeAddCommand(recordUsecase, _msg));
    addSubcommand(_AgreeListCommand(listUsecase, _msg));
    addSubcommand(_AgreeStatusCommand(recordUsecase, _msg));
    addSubcommand(_AgreeCorrectCommand(recordUsecase, _msg));
    addSubcommand(_AgreeReflectCommand(recordUsecase, _msg));
  }

  @override
  Future<int> run() async {
    printUsage();
    return 0;
  }
}

class _AgreeAddCommand extends BaseCommand {
  final RecordAgreementUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'add';
  @override
  String get description => _msg.cmdAgreeAddDesc;

  _AgreeAddCommand(this._usecase, this._msg) {
    argParser
      ..addOption('title', mandatory: true)
      ..addOption('kind', defaultsTo: 'tentative')
      ..addOption('amount')
      ..addOption('currency', defaultsTo: 'JPY')
      ..addOption('payment-terms')
      ..addMultiOption('item')
      ..addOption('from') // カンマ区切りの MSG ID
      ..addOption('backlog');
  }

  @override
  Future<int> execute() async {
    final amountRaw = argResults!['amount'] as String?;
    final sources = (argResults!['from'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ??
        const <String>[];

    final id = await _usecase.add(
      Directory.current.path,
      title: argResults!['title'] as String,
      kindRaw: argResults!['kind'] as String,
      amountValue: amountRaw != null ? double.tryParse(amountRaw) : null,
      amountCurrency: amountRaw != null ? argResults!['currency'] as String : null,
      paymentTerms: argResults!['payment-terms'] as String?,
      items: argResults!['item'] as List<String>,
      sources: sources,
      backlog: argResults!['backlog'] as String?,
      now: DateTime.now(),
      recordedBy: _currentUser(),
    );

    Logger.success(_msg.agreeAddDone(id));
    return 0;
  }
}

class _AgreeListCommand extends BaseCommand {
  final ListAgreementsUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'list';
  @override
  String get description => _msg.cmdAgreeListDesc;

  _AgreeListCommand(this._usecase, this._msg) {
    argParser.addFlag('unreflected', negatable: false);
  }

  @override
  Future<int> execute() async {
    final ledger = await _usecase.executeWithSkipped(
      Directory.current.path,
      unreflectedOnly: argResults!['unreflected'] as bool,
    );
    final agreements = ledger.agreements;
    // 壊れた行・add の無い ID は落とさずに飛ばし、何を飛ばしたかを見せる(#33)
    warnSkippedAgreements(ledger.skipped, _msg);

    if (agreements.isEmpty) {
      Logger.warn(_msg.agreeListEmpty);
      return 0;
    }

    for (final a in agreements) {
      final amount = a.amountValue != null ? ' ${a.amountValue} ${a.amountCurrency}' : '';
      Logger.info('${a.id}  [${a.status.name}]  ${a.title}$amount');
    }
    return 0;
  }
}

class _AgreeStatusCommand extends BaseCommand {
  final RecordAgreementUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'status';
  @override
  String get description => _msg.cmdAgreeStatusDesc;

  _AgreeStatusCommand(this._usecase, this._msg);

  @override
  Future<int> execute() async {
    if (argResults!.rest.length < 2) {
      Logger.error('使い方: utakata agree status <ID> <status>');
      return 1;
    }
    final id = argResults!.rest[0];
    final status = argResults!.rest[1];

    try {
      await _usecase.updateStatus(
        Directory.current.path,
        id,
        status,
        now: DateTime.now(),
        recordedBy: _currentUser(),
      );
    } on Exception catch (e) {
      final code = reportAgreementIdError(e, _msg);
      if (code == null) rethrow;
      return code;
    }
    Logger.success(_msg.agreeStatusDone(id, status));
    return 0;
  }
}

class _AgreeCorrectCommand extends BaseCommand {
  final RecordAgreementUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'correct';
  @override
  String get description => _msg.cmdAgreeCorrectDesc;

  _AgreeCorrectCommand(this._usecase, this._msg) {
    argParser
      ..addOption('title', mandatory: true)
      ..addOption('kind', defaultsTo: 'correction')
      ..addMultiOption('item');
  }

  @override
  Future<int> execute() async {
    if (argResults!.rest.isEmpty) {
      Logger.error('訂正対象の合意 ID を指定してください: utakata agree correct <ID> --title ...');
      return 1;
    }
    final correctsId = argResults!.rest.first;

    final String newId;
    try {
      newId = await _usecase.correct(
        Directory.current.path,
        correctsId,
        title: argResults!['title'] as String,
        kindRaw: argResults!['kind'] as String,
        items: argResults!['item'] as List<String>,
        now: DateTime.now(),
        recordedBy: _currentUser(),
      );
    } on Exception catch (e) {
      final code = reportAgreementIdError(e, _msg);
      if (code == null) rethrow;
      return code;
    }

    Logger.success('✅ $newId を作成し $correctsId を supersede しました');
    return 0;
  }
}

class _AgreeReflectCommand extends BaseCommand {
  final RecordAgreementUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'reflect';
  @override
  String get description => _msg.cmdAgreeReflectDesc;

  _AgreeReflectCommand(this._usecase, this._msg) {
    argParser
      ..addOption('plan')
      ..addOption('spec');
  }

  @override
  Future<int> execute() async {
    if (argResults!.rest.isEmpty) {
      Logger.error('合意 ID を指定してください: utakata agree reflect <ID> --plan ... / --spec ...');
      return 1;
    }
    final id = argResults!.rest.first;

    try {
      await _usecase.reflect(
        Directory.current.path,
        id,
        planId: argResults!['plan'] as String?,
        spec: argResults!['spec'] as String?,
        now: DateTime.now(),
        recordedBy: _currentUser(),
      );
    } on Exception catch (e) {
      final code = reportAgreementIdError(e, _msg);
      if (code == null) rethrow;
      return code;
    }

    Logger.success('✅ $id の反映を記録しました');
    return 0;
  }
}
