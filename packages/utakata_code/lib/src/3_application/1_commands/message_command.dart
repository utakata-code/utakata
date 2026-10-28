import 'dart:io';

import 'package:args/command_runner.dart';

import '../../1_domain/1_entities/record/message_record.dart';
import '../../1_domain/2_repositories/agreement_repository.dart';
import '../../1_domain/2_repositories/message_repository.dart';
import '../../1_domain/3_usecases/import_messages_usecase.dart';
import '../../1_domain/3_usecases/record_message_usecase.dart';
import '../../1_domain/3_usecases/render_messages_usecase.dart';
import '../../1_domain/messages/cli_messages.dart';
import '../../1_domain/services/actor_resolver.dart';
import '../../1_domain/services/agreement_id_guard.dart';
import 'agreement_cli_support.dart';
import 'base_command.dart';
import 'logger.dart';

/// utakata message — クライアントとの送受信**原文**の記録(v1.6.0)
///
/// `log`(人間が要約した会話ログ)とは別系統。原文は一次証跡なので
/// 無加工で追記し、既存レコードの書き換えは行わない。
class MessageCommand extends Command<int> {
  final CliMessages _msg;

  @override
  String get name => 'message';

  @override
  String get description => _msg.cmdMessageDesc;

  MessageCommand(
    RecordMessageUsecase recordUsecase,
    ImportMessagesUsecase importUsecase,
    RenderMessagesUsecase renderUsecase,
    MessageRepository repo,
    this._msg, {
    AgreementRepository? agreementRepo,
  }) {
    addSubcommand(_MessageAddCommand(recordUsecase, _msg));
    addSubcommand(_MessageImportCommand(importUsecase, _msg));
    addSubcommand(_MessageListCommand(repo, _msg));
    addSubcommand(_MessageShowCommand(repo, _msg));
    addSubcommand(_MessageRenderCommand(renderUsecase, _msg));
    addSubcommand(_MessageLinkCommand(repo, _msg, agreementRepo));
  }

  @override
  Future<int> run() async {
    printUsage();
    return 0;
  }
}

/// 引数か stdin から本文を読む(どちらも無ければ null)。
Future<String?> _readBody(List<String> rest) async {
  if (rest.isNotEmpty) return rest.join(' ');
  if (!stdin.hasTerminal) {
    return stdin.transform(const SystemEncoding().decoder).join();
  }
  return null;
}

class _MessageAddCommand extends BaseCommand {
  final RecordMessageUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'add';
  @override
  String get description => _msg.cmdMessageAddDesc;

  _MessageAddCommand(this._usecase, this._msg) {
    argParser
      ..addOption('direction',
          abbr: 'd', help: _msg.optMessageDirection, allowed: [
        'inbound',
        'outbound',
        'in',
        'out',
      ])
      ..addOption('channel', abbr: 'c', help: _msg.optMessageChannel)
      ..addOption('at', help: _msg.optLogAt)
      ..addOption('from', help: _msg.optMessageFrom)
      ..addOption('to', help: _msg.optMessageTo)
      ..addOption('subject', help: _msg.optMessageSubject)
      ..addOption('thread', help: _msg.optMessageThread)
      ..addOption('external-id', help: _msg.optMessageExternalId)
      ..addMultiOption('attachment', help: _msg.optMessageAttachment);
  }

  @override
  Future<int> execute() async {
    final direction = argResults!['direction'] as String?;
    if (direction == null) {
      Logger.error(_msg.messageDirectionRequired);
      return 64;
    }

    final body = await _readBody(argResults!.rest);
    if (body == null || body.trim().isEmpty) {
      Logger.error(_msg.messageBodyRequired);
      return 64;
    }

    final result = await _usecase.execute(
      Directory.current.path,
      body: body,
      directionRaw: direction,
      atRaw: argResults!['at'] as String?,
      now: DateTime.now(),
      recordedBy: ActorResolver.resolve(Platform.environment),
      channel: argResults!['channel'] as String?,
      from: argResults!['from'] as String?,
      to: argResults!['to'] as String?,
      subject: argResults!['subject'] as String?,
      thread: argResults!['thread'] as String?,
      externalId: argResults!['external-id'] as String?,
      attachments: argResults!['attachment'] as List<String>,
    );

    if (result.skipped) {
      // 同じ external_id が既にある = 取り込みツールの再実行。増やさない。
      Logger.info(_msg.messageAddDuplicate(result.record.id));
      return 0;
    }
    Logger.success(_msg.messageAddDone(result.record.id));
    return 0;
  }
}

class _MessageImportCommand extends BaseCommand {
  final ImportMessagesUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'import';
  @override
  String get description => _msg.cmdMessageImportDesc;

  _MessageImportCommand(this._usecase, this._msg) {
    argParser
      ..addOption('format',
          defaultsTo: 'jsonl', allowed: ['jsonl', 'md'], help: _msg.optMessageFormat)
      ..addOption('file', abbr: 'f', help: _msg.optMessageFile)
      ..addOption('channel', abbr: 'c', help: _msg.optMessageChannel)
      ..addFlag('dry-run', help: _msg.optDryRun, negatable: false);
  }

  @override
  Future<int> execute() async {
    final filePath = argResults!['file'] as String?;
    String content;
    if (filePath != null) {
      final file = File(filePath);
      if (!file.existsSync()) {
        Logger.error(_msg.messageFileNotFound(filePath));
        return 66;
      }
      content = await file.readAsString();
    } else if (!stdin.hasTerminal) {
      content = await stdin.transform(const SystemEncoding().decoder).join();
    } else {
      Logger.error(_msg.messageImportSourceRequired);
      return 64;
    }

    final dryRun = argResults!['dry-run'] as bool;
    final results = await _usecase.execute(
      Directory.current.path,
      content: content,
      format: argResults!['format'] as String,
      now: DateTime.now(),
      recordedBy: ActorResolver.resolve(Platform.environment),
      defaultChannel: argResults!['channel'] as String?,
      sourceKey: filePath,
      dryRun: dryRun,
    );

    if (results.isEmpty) {
      Logger.warn(_msg.messageImportNothingParsed);
      return 65; // EX_DATAERR
    }

    final imported = results.where((r) => !r.skipped).length;
    final skipped = results.length - imported;
    for (final result in results.where((r) => !r.skipped)) {
      Logger.step('${result.record.id}  '
          '${MessageRecord.directionToString(result.record.direction)}  '
          '${result.record.body.split('\n').first}');
    }
    if (dryRun) {
      Logger.info(_msg.messageImportDryRun(imported, skipped));
    } else {
      Logger.success(_msg.messageImportDone(imported, skipped));
    }
    return 0;
  }
}

class _MessageListCommand extends BaseCommand {
  final MessageRepository _repo;
  final CliMessages _msg;

  @override
  String get name => 'list';
  @override
  String get description => _msg.cmdMessageListDesc;

  _MessageListCommand(this._repo, this._msg) {
    argParser
      ..addOption('direction', abbr: 'd', allowed: ['inbound', 'outbound'])
      ..addOption('channel', abbr: 'c')
      ..addOption('thread')
      ..addOption('month', help: _msg.optMessageMonth);
  }

  @override
  Future<int> execute() async {
    final directionRaw = argResults!['direction'] as String?;
    final records = await _repo.query(
      Directory.current.path,
      direction: directionRaw != null
          ? MessageRecord.directionFromString(directionRaw)
          : null,
      channel: argResults!['channel'] as String?,
      thread: argResults!['thread'] as String?,
      month: argResults!['month'] as String?,
    );

    if (records.isEmpty) {
      Logger.warn(_msg.messageListEmpty);
      return 0;
    }

    for (final record in records) {
      final at = record.at.toIso8601String().substring(0, 16).replaceAll('T', ' ');
      final arrow =
          record.direction == MessageDirection.inbound ? '←' : '→';
      Logger.info('${record.id}  $at  $arrow  '
          '${record.channel ?? '-'}  ${record.from ?? record.to ?? ''}');
      Logger.step(record.body.split('\n').first);
    }
    return 0;
  }
}

class _MessageShowCommand extends BaseCommand {
  final MessageRepository _repo;
  final CliMessages _msg;

  @override
  String get name => 'show';
  @override
  String get description => _msg.cmdMessageShowDesc;

  _MessageShowCommand(this._repo, this._msg);

  @override
  Future<int> execute() async {
    if (argResults!.rest.isEmpty) {
      Logger.error(_msg.messageIdRequired);
      return 64;
    }
    final records = await _repo.query(Directory.current.path,
        id: argResults!.rest.first);
    if (records.isEmpty) {
      Logger.error(_msg.messageNotFound(argResults!.rest.first));
      return 66;
    }

    final record = records.first;
    Logger.section('${record.id}  '
        '${MessageRecord.directionToString(record.direction)}'
        '${record.channel != null ? '  [${record.channel}]' : ''}');
    Logger.info('日時: ${record.at.toIso8601String()}'
        '${record.atApprox ? ' (概算)' : ''}');
    if (record.from != null) Logger.info('From: ${record.from}');
    if (record.to != null) Logger.info('To: ${record.to}');
    if (record.subject != null) Logger.info('件名: ${record.subject}');
    if (record.thread != null) Logger.info('スレッド: ${record.thread}');
    if (record.logRef != null) Logger.info('ログ参照: ${record.logRef}');
    if (record.agreementRef != null) {
      Logger.info('合意参照: ${record.agreementRef}');
    }
    Logger.info('記録: ${record.recordedBy} '
        '(${record.recordedAt.toIso8601String().substring(0, 16)})');
    stdout
      ..writeln()
      ..writeln(record.body);
    return 0;
  }
}

class _MessageRenderCommand extends BaseCommand {
  final RenderMessagesUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'render';
  @override
  String get description => _msg.cmdMessageRenderDesc;

  _MessageRenderCommand(this._usecase, this._msg);

  @override
  Future<int> execute() async {
    final months = await _usecase.execute(Directory.current.path);
    if (months.isEmpty) {
      Logger.warn(_msg.messageListEmpty);
      return 0;
    }
    Logger.success(_msg.messageRenderDone(months.length));
    return 0;
  }
}

class _MessageLinkCommand extends BaseCommand {
  final MessageRepository _repo;
  final CliMessages _msg;

  /// `--agreement` の存在確認に使う(#33)。未注入なら形だけを確かめる。
  final AgreementRepository? _agreementRepo;

  @override
  String get name => 'link';
  @override
  String get description => _msg.cmdMessageLinkDesc;

  _MessageLinkCommand(this._repo, this._msg, this._agreementRepo) {
    argParser
      ..addOption('log', help: _msg.optMessageLogRef)
      ..addOption('agreement', help: _msg.optMessageAgreementRef);
  }

  @override
  Future<int> execute() async {
    if (argResults!.rest.isEmpty) {
      Logger.error(_msg.messageIdRequired);
      return 64;
    }
    final logRef = argResults!['log'] as String?;
    final agreementRef = argResults!['agreement'] as String?;
    if (logRef == null && agreementRef == null) {
      Logger.error(_msg.messageLinkTargetRequired);
      return 64;
    }

    final id = argResults!.rest.first;
    if (agreementRef != null) {
      // 不正・存在しない合意 ID を紐付けない(#33)
      try {
        final agreementRepo = _agreementRepo;
        if (agreementRepo == null) {
          AgreementIdGuard.ensureWellFormed(agreementRef);
        } else {
          await AgreementIdGuard(agreementRepo)
              .ensureExists(Directory.current.path, agreementRef);
        }
      } on Exception catch (e) {
        final code = reportAgreementIdError(e, _msg);
        if (code == null) rethrow;
        return code;
      }
    }
    final ok = await _repo.link(Directory.current.path, id,
        logRef: logRef, agreementRef: agreementRef);
    if (!ok) {
      Logger.error(_msg.messageNotFound(id));
      return 66;
    }
    Logger.success(_msg.messageLinkDone(id));
    return 0;
  }
}
