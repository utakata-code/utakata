import 'dart:io';

import 'package:args/command_runner.dart';

import '../../1_domain/1_entities/feature_spec_entity.dart';
import '../../1_domain/1_entities/plan/plan_intent.dart';
import '../../1_domain/2_repositories/plan_repository.dart';
import '../../1_domain/3_usecases/add_feature_usecase.dart';
import '../../1_domain/3_usecases/architecture_resolver.dart';
import '../../1_domain/3_usecases/apply_feature_template_usecase.dart';
import '../../1_domain/3_usecases/register_feature_in_plan_usecase.dart';
import '../../1_domain/messages/cli_messages.dart';
import '../../1_domain/services/case_converter.dart';
import 'base_command.dart';
import 'logger.dart';

/// utakata feature — フィーチャー操作コマンド群
class FeatureCommand extends Command<int> {
  final AddFeatureUsecase _addUsecase;
  final ApplyFeatureTemplateUsecase _templateUsecase;
  final CliMessages _msg;

  @override
  String get name => 'feature';

  @override
  String get description => _msg.cmdFeatureDesc;

  FeatureCommand(this._addUsecase, this._templateUsecase, this._msg,
      {required ArchitectureResolver archResolver,
      required RegisterFeatureInPlanUsecase registerUsecase,
      Future<Set<String>?> Function(String projectDir)? featuresWithPlan}) {
    addSubcommand(_FeatureAddCommand(_addUsecase, _templateUsecase,
        registerUsecase, _msg, archResolver, featuresWithPlan));
  }

  @override
  Future<int> run() async {
    printUsage();
    return 0;
  }
}

/// utakata feature add
class _FeatureAddCommand extends BaseCommand {
  final AddFeatureUsecase _usecase;
  final ApplyFeatureTemplateUsecase _templateUsecase;
  final RegisterFeatureInPlanUsecase _registerUsecase;
  final CliMessages _msg;

  @override
  String get name => 'add';

  @override
  String get description => _msg.cmdFeatureAddDesc;

  final ArchitectureResolver _archResolver;

  /// `enforcement.impl_plan: on` のゲート(v1.7.0)。
  /// **null を返せばゲートしない**(未注入も同じ)。
  final Future<Set<String>?> Function(String projectDir)? _featuresWithPlan;

  _FeatureAddCommand(this._usecase, this._templateUsecase,
      this._registerUsecase, this._msg, this._archResolver,
      this._featuresWithPlan) {
    argParser
      ..addOption('entity', abbr: 'e', help: _msg.optEntity)
      ..addOption('permission',
          abbr: 'p',
          defaultsTo: 'user',
          allowed: ['admin', 'user', 'shared', 'direct'],
          help: _msg.optPermission)
      ..addOption('arch', help: _msg.optArch)
      ..addOption('template', help: _msg.optFeatureTemplate)
      ..addFlag('yes', abbr: 'y', help: _msg.optYes);
  }

  @override
  Future<int> execute() async {
    if (argResults!.rest.isEmpty) {
      Logger.error(_msg.missingFeatureName);
      return 1;
    }

    final featureName = CaseConverter.toSnakeCase(argResults!.rest.first);

    // 実装計画ゲート(enforcement.impl_plan)。apply と同じ判定を使う。
    final withPlan = await _featuresWithPlan?.call(Directory.current.path);
    if (withPlan != null && !withPlan.contains(featureName)) {
      Logger.error(_msg.implPlanRequired(featureName));
      return 1;
    }

    final templateId = argResults!['template'] as String?;
    final explicitArch = argResults!['arch'] as String?;
    // --arch 未指定なら utakata.yaml / plan.yaml から解決する(Issue #11)
    final archId = await _archResolver.resolve(Directory.current.path,
        explicit: explicitArch);

    if (templateId != null) {
      Logger.section(_msg.sectionFeatureAdd(featureName));
      final (spec, registration) = await _templateUsecase.execute(
        Directory.current.path,
        featureName,
        templateId,
        architectureId: archId,
      );
      _reportRegistration(featureName, registration);
      Logger.success(_msg.templateApplied(templateId, spec.relativePath));
      return 0;
    }

    final entityName = CaseConverter.toSnakeCase(
      (argResults!['entity'] as String?) ?? featureName,
    );
    final permission = argResults!['permission'] as String;

    Logger.section(_msg.sectionFeatureAdd(featureName));

    final spec = FeatureSpecEntity(
      featureName: featureName,
      entityName: entityName,
      permission: permission,
      architectureId: archId,
    );

    Logger.info(_msg.featureAddPath(spec.relativePath));

    final skipConfirm = argResults!['yes'] as bool;
    if (!skipConfirm) {
      stdout.write(_msg.confirmGenerate(spec.relativePath));
      final confirm = stdin.readLineSync();
      if (confirm?.toLowerCase() != 'y') {
        Logger.warn(_msg.featureAddCancel);
        return 0;
      }
    }

    await _usecase.execute(Directory.current.path, spec);

    // plan.yaml があるときだけ登録し、必須ファイルを作る(Issue #34)。
    // plan.yaml が無い旧来のプロジェクトでは作らない(フォルダーだけ)。
    // architecture は --arch を明示したときだけ書く(既定は project の設定に
    // 従わせ、後で utakata.yaml を変えたときに feature だけ取り残さない)。
    final registration = await _registerUsecase.execute(
      Directory.current.path,
      PlanFeatureIntent(
        name: featureName,
        permission: permission,
        entities: [entityName],
        architectureId: explicitArch,
      ),
    );
    _reportRegistration(featureName, registration);

    Logger.success(_msg.featureAddDone(featureName));
    return 0;
  }

  void _reportRegistration(String featureName, RegisterFeatureResult result) {
    switch (result.adopt) {
      case AdoptFeatureResult.added:
        Logger.info(_msg.featureAddPlanAdded(featureName));
      case AdoptFeatureResult.alreadyPlanned:
        Logger.info(_msg.featureAddPlanAlreadyPlanned(featureName));
      case AdoptFeatureResult.noPlan:
        return;
    }
    for (final path in result.createdFiles) {
      Logger.step(_msg.applyFileRow(path));
    }
    if (result.createdFiles.isNotEmpty) {
      Logger.success(_msg.applyFilesDone(result.createdFiles.length));
    }
  }
}
