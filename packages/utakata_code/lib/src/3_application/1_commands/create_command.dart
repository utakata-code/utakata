import 'package:path/path.dart' as p;

import '../../1_domain/1_entities/project_spec_entity.dart';
import '../../1_domain/3_usecases/create_project_usecase.dart';
import '../../1_domain/3_usecases/generate_claude_integration_usecase.dart';
import '../../1_domain/messages/cli_messages.dart';
import '../../1_domain/services/case_converter.dart';
import 'base_command.dart';
import 'logger.dart';
import 'mcp_destination_options.dart';

/// utakata create — Flutter プロジェクトを新規作成する
class CreateCommand extends BaseCommand {
  final CreateProjectUsecase _usecase;
  final GenerateClaudeIntegrationUsecase _claudeUsecase;
  final CliMessages _msg;

  @override
  String get name => 'create';

  @override
  String get description => _msg.cmdCreateDesc;

  CreateCommand(this._usecase, this._claudeUsecase, this._msg) {
    argParser
      ..addOption('org',
          abbr: 'o',
          defaultsTo: 'com.example',
          help: _msg.optOrg)
      ..addOption('platforms',
          defaultsTo: 'android,ios,web,macos',
          help: _msg.optPlatforms)
      ..addOption('description',
          abbr: 'd',
          defaultsTo: 'Flutter app',
          help: _msg.optDescription)
      ..addOption('arch',
          defaultsTo: 'clean_architecture',
          help: _msg.optArch)
      ..addMcpDestinationOptions(_msg);
  }

  @override
  Future<int> execute() async {
    if (argResults!.rest.isEmpty) {
      Logger.error(_msg.missingAppName);
      return 1;
    }

    final mcp = parseMcpDestination(argResults!, _msg);
    if (mcp == null) return 64; // EX_USAGE

    final appName = argResults!.rest.first;
    final projectName = CaseConverter.toSnakeCase(p.basename(appName));

    Logger.section(_msg.sectionCreate(appName));

    final spec = ProjectSpecEntity(
      appName: appName,
      projectName: projectName,
      org: argResults!['org'] as String,
      platforms: argResults!['platforms'] as String,
      description: argResults!['description'] as String,
      architectureId: argResults!['arch'] as String,
    );

    await _usecase.execute(spec);
    final claude = await _claudeUsecase.execute(appName, mcp: mcp);
    for (final path in claude.invalidJson) {
      Logger.warn(_msg.claudeInitInvalidJson(path));
    }
    Logger.success(_msg.projectCreated(appName));
    return 0;
  }
}
