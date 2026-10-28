import 'dart:io';

import 'package:args/command_runner.dart';

import '../../1_domain/3_usecases/generate_claude_integration_usecase.dart';
import '../../1_domain/messages/cli_messages.dart';
import 'base_command.dart';
import 'logger.dart';

/// utakata claude — Claude Code 統合の管理コマンド群
class ClaudeCommand extends Command<int> {
  final CliMessages _msg;

  @override
  String get name => 'claude';

  @override
  String get description => _msg.cmdClaudeDesc;

  ClaudeCommand(GenerateClaudeIntegrationUsecase usecase, this._msg) {
    addSubcommand(_ClaudeInitCommand(usecase, _msg));
  }

  @override
  Future<int> run() async {
    printUsage();
    return 0;
  }
}

/// utakata claude init — 既存プロジェクトに Claude Code 統合を後付け・再生成する
class _ClaudeInitCommand extends BaseCommand {
  final GenerateClaudeIntegrationUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'init';

  @override
  String get description => _msg.cmdClaudeInitDesc;

  _ClaudeInitCommand(this._usecase, this._msg) {
    argParser
      ..addFlag('force', help: _msg.optForceRegenerate, negatable: false)
      ..addMultiOption('only',
          help: _msg.optClaudeOnly,
          valueHelp: 'target',
          allowed: [
            for (final target in ClaudeIntegrationTarget.values) target.cliName
          ]);
  }

  @override
  Future<int> execute() async {
    final force = argResults!['force'] as bool;
    final onlyNames = argResults!['only'] as List<String>;
    final only = onlyNames.isEmpty
        ? null
        : {
            for (final name in onlyNames)
              ClaudeIntegrationTarget.fromCliName(name)!
          };
    final result = await _usecase.execute(
      Directory.current.path,
      skipExisting: !force,
      forceClaudeMd: force,
      only: only,
    );
    final written = result.written;

    for (final path in result.invalidJson) {
      Logger.warn(_msg.claudeInitInvalidJson(path));
    }
    final exitCode = result.invalidJson.isEmpty ? 0 : 1;

    if (written.isEmpty) {
      if (only == null) {
        Logger.info('すべて揃っています(生成対象なし)。スキルだけ作り直すなら --only skills、全て上書きするなら --force(settings.json と CLAUDE.md も上書き)。');
      }
      return exitCode;
    }
    for (final path in written) {
      Logger.success('wrote: $path');
    }
    if (!force && only == null) {
      Logger.dim('既存ファイルは保護されました。スキルだけ作り直すなら --only skills、全て上書きするなら --force(settings.json と CLAUDE.md も上書き)。');
    }
    return exitCode;
  }
}
