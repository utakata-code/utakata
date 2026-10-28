import 'dart:io';

import 'package:args/command_runner.dart';

import '../../1_domain/2_repositories/plan_repository.dart';
import '../../1_domain/3_usecases/adopt_plan_usecase.dart';
import '../../1_domain/3_usecases/expand_plan_usecase.dart';
import '../../1_domain/messages/cli_messages.dart';
import 'base_command.dart';
import 'logger.dart';

/// utakata plan — plan.yaml 関連コマンド群
///
/// v0.7 で意図レベル化(仕様書 §6)に伴い再編。旧来の
/// `plan_architecture.yaml`(具象ツリー)生成は廃止し、`utakata plan`
/// 単体実行は非推奨の案内のみを表示する no-op になる。
/// 新設の `plan adopt` が実質的な後継機能。
class PlanCommand extends Command<int> {
  final CliMessages _msg;

  @override
  String get name => 'plan';

  @override
  String get description => _msg.cmdPlanDesc;

  PlanCommand(
    AdoptPlanUsecase adoptUsecase,
    this._msg, {
    required ExpandPlanUsecase expandUsecase,
    required PlanRepository planRepo,
  }) {
    addSubcommand(_PlanAdoptCommand(adoptUsecase, _msg));
    addSubcommand(_PlanExpandCommand(expandUsecase, _msg));
    addSubcommand(_PlanAddCommand(planRepo, _msg));
    addSubcommand(_PlanRemoveCommand(planRepo, _msg));
  }

  @override
  Future<int> run() async {
    Logger.warn(_msg.deprecatedAlias('plan', 'plan adopt'));
    return 0;
  }
}

/// utakata plan adopt
class _PlanAdoptCommand extends BaseCommand {
  final AdoptPlanUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'adopt';

  @override
  String get description => _msg.cmdPlanAdoptDesc;

  _PlanAdoptCommand(this._usecase, this._msg) {
    argParser.addFlag('yes', abbr: 'y', help: _msg.optYes);
  }

  @override
  Future<int> execute() async {
    Logger.section(_msg.sectionPlanAdopt);

    final projectDir = Directory.current.path;
    final candidates = await _usecase.detect(projectDir);

    if (candidates.isEmpty) {
      Logger.info(_msg.adoptNoneFound);
      return 0;
    }

    for (final candidate in candidates) {
      Logger.step(_msg.adoptCandidateRow(candidate.permission, candidate.name));
    }

    final skipConfirm = argResults!['yes'] as bool;
    var adopted = 0;
    for (final candidate in candidates) {
      if (!skipConfirm) {
        stdout.write(_msg.adoptConfirm(candidate.permission, candidate.name));
        final confirm = stdin.readLineSync();
        if (confirm?.toLowerCase() != 'y') continue;
      }
      await _usecase.adopt(projectDir, candidate);
      adopted++;
    }

    Logger.success(_msg.adoptDone(adopted));
    return 0;
  }
}

/// utakata plan expand — 自動導出されている層構成を plan.yaml に書き出す
class _PlanExpandCommand extends BaseCommand {
  final ExpandPlanUsecase _usecase;
  final CliMessages _msg;

  @override
  String get name => 'expand';

  @override
  String get description => _msg.cmdPlanExpandDesc;

  _PlanExpandCommand(this._usecase, this._msg) {
    argParser
      ..addFlag('dry-run', help: _msg.optExpandDryRun, negatable: false)
      ..addOption('feature', help: _msg.optExpandFeature);
  }

  @override
  Future<int> execute() async {
    final dryRun = argResults!['dry-run'] as bool;
    final results = await _usecase.execute(
      Directory.current.path,
      dryRun: dryRun,
      onlyFeature: argResults!['feature'] as String?,
    );

    if (results.isEmpty) {
      Logger.warn('展開対象がありません(plan.yaml が無い、または features が空)。');
      return 0;
    }

    for (final feature in results) {
      Logger.section(feature.name);
      if (feature.layers.isEmpty && feature.skipped.isEmpty) {
        Logger.step('(導出できる層がありません)');
      }
      for (final entry in feature.layers.entries) {
        Logger.step('${entry.key}: [${entry.value.join(', ')}]');
      }
      for (final path in feature.skipped) {
        Logger.dim('  skip(宣言済み): $path');
      }
    }

    if (dryRun) {
      Logger.info('');
      Logger.info('--dry-run のため書き込んでいません。');
    } else {
      Logger.success('plan.yaml に書き出しました。'
          '不要な層は空リスト([])に、追加は `utakata plan add` で編集できます。');
    }
    return 0;
  }
}

/// utakata plan add `<feature> <layer> <item...>` — 層に項目を追加する
class _PlanAddCommand extends BaseCommand {
  final PlanRepository _planRepo;
  final CliMessages _msg;

  @override
  String get name => 'add';

  @override
  String get description => _msg.cmdPlanAddDesc;

  _PlanAddCommand(this._planRepo, this._msg);

  @override
  Future<int> execute() async {
    final rest = argResults!.rest;
    if (rest.length < 3) {
      Logger.error('引数が足りません: utakata plan add <feature> <layer> <item...>\n'
          '  例: utakata plan add todo 1_domain/3_usecases get_todo save_todo');
      return 64;
    }

    final projectDir = Directory.current.path;
    final featureName = rest[0];
    final layerPath = rest[1];
    final newItems = rest.sublist(2);

    final plan = await _planRepo.read(projectDir);
    final feature = plan?.features.where((f) => f.name == featureName).firstOrNull;
    if (feature == null) {
      Logger.error('feature "$featureName" が plan.yaml に見つかりません。');
      return 66;
    }

    // 既存宣言があればそれに追記、無ければ新規作成(重複は除く)。
    // 一覧を丸ごと置き換えるとコメントがずれるため、足りない項目だけを
    // 追記する(Issue #29)
    final current = feature.declarationFor(layerPath) ?? const <String>[];
    final merged = <String>[...current];
    for (final item in newItems) {
      if (!merged.contains(item)) merged.add(item);
    }

    final ok = await _planRepo.appendLayerItems(
        projectDir, featureName, layerPath, newItems);
    if (!ok) {
      Logger.error('plan.yaml の更新に失敗しました。');
      return 1;
    }
    Logger.success('$featureName / $layerPath: [${merged.join(', ')}]');
    return 0;
  }
}

/// utakata plan remove `<feature> <layer> <item>` — 層から項目を削除する
class _PlanRemoveCommand extends BaseCommand {
  final PlanRepository _planRepo;
  final CliMessages _msg;

  @override
  String get name => 'remove';

  @override
  String get description => _msg.cmdPlanRemoveDesc;

  _PlanRemoveCommand(this._planRepo, this._msg);

  @override
  Future<int> execute() async {
    final rest = argResults!.rest;
    if (rest.length < 3) {
      Logger.error('引数が足りません: utakata plan remove <feature> <layer> <item>');
      return 64;
    }

    final ok = await _planRepo.removeLayerItem(
        Directory.current.path, rest[0], rest[1], rest[2]);
    if (!ok) {
      Logger.warn('該当する項目が見つかりませんでした(feature / 層 / 項目名を確認してください)。');
      return 1;
    }
    Logger.success('削除しました: ${rest[0]} / ${rest[1]} から ${rest[2]}');
    return 0;
  }
}
