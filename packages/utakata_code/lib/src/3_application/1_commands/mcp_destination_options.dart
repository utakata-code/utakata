import 'package:args/args.dart';

import '../../1_domain/3_usecases/generate_claude_integration_usecase.dart';
import '../../1_domain/messages/cli_messages.dart';
import 'logger.dart';

/// `claude init` / `create` 共通の `--mcp*` オプション(#35)。
extension McpDestinationOptions on ArgParser {
  void addMcpDestinationOptions(CliMessages msg) {
    this
      ..addOption('mcp',
          help: msg.optMcp,
          defaultsTo: McpTransport.stdio.cliName,
          allowed: [for (final t in McpTransport.values) t.cliName])
      ..addOption('mcp-url', help: msg.optMcpUrl, valueHelp: 'url')
      // ヘッダーの値にカンマが入ることがあるため、カンマでは分けない。
      ..addMultiOption('mcp-header',
          help: msg.optMcpHeader,
          valueHelp: 'Name: value',
          splitCommas: false)
      ..addOption('mcp-name', help: msg.optMcpName, valueHelp: 'name');
  }
}

/// `--mcp*` を読み取る。組み合わせが不正なら理由を表示して null を返す
/// (呼び出し側は 64 で終える)。
McpDestination? parseMcpDestination(ArgResults args, CliMessages msg) {
  try {
    return McpDestination.parse(
      transport: args.wasParsed('mcp') ? args['mcp'] as String : null,
      url: args['mcp-url'] as String?,
      headers: args['mcp-header'] as List<String>,
      name: args['mcp-name'] as String?,
    );
  } on McpOptionException catch (e) {
    final detail = e.detail ?? '';
    Logger.error(switch (e.error) {
      McpOptionError.urlRequired => msg.mcpUrlRequired,
      McpOptionError.urlNeedsHttp => msg.mcpUrlNeedsHttp(detail),
      McpOptionError.headerNeedsHttp => msg.mcpHeaderNeedsHttp(detail),
      McpOptionError.headerInvalid => msg.mcpHeaderInvalid(detail),
      McpOptionError.nameWithNone => msg.mcpNameWithNone,
      McpOptionError.nameEmpty => msg.mcpNameEmpty,
    });
    return null;
  }
}
