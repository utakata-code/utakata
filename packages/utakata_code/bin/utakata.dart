import 'dart:io';

import 'package:utakata/src/1_domain/messages/messages_resolver.dart';
import 'package:utakata/src/1_domain/3_usecases/add_feature_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/add_log_entry_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/adopt_plan_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/apply_feature_template_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/apply_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/architecture_resolver.dart';
import 'package:utakata/src/1_domain/3_usecases/audit_imports_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/check_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/create_project_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/doctor_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/generate_claude_integration_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/generate_core_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/guide_for_file_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/guide_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/impl_plan_usecase.dart';
import 'package:utakata/src/1_domain/services/impl_plan_gate.dart';
import 'package:utakata/src/1_domain/3_usecases/init_doc_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/import_messages_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/list_agreements_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/query_log_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/record_agreement_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/record_message_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/render_log_preview_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/render_messages_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/render_summary_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/scan_project_status_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/show_doc_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/status_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/sync_skills_usecase.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/filesystem_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/front_matter_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/jsonl_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/markdown_marker_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/yaml_edit_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/2_remote/git_data_source.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/2_remote/process_data_source.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/knowledge_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/agreement_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/architecture_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/config_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/conversation_log_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/feature_template_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/impl_plan_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/message_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/plan_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/project_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/structure_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/template_repository_impl.dart';
import 'package:utakata/src/2_infrastructure/3_repositories/vault_repository_impl.dart';
import 'package:utakata/src/3_application/1_commands/agree_command.dart';
import 'package:utakata/src/3_application/1_commands/apply_command.dart';
import 'package:utakata/src/3_application/1_commands/check_command.dart';
import 'package:utakata/src/3_application/1_commands/claude_command.dart';
import 'package:utakata/src/3_application/1_commands/create_command.dart';
import 'package:utakata/src/3_application/1_commands/diff_command.dart';
import 'package:utakata/src/3_application/1_commands/doc_command.dart';
import 'package:utakata/src/3_application/1_commands/doctor_command.dart';
import 'package:utakata/src/3_application/1_commands/feature_command.dart';
import 'package:utakata/src/3_application/1_commands/guide_command.dart';
import 'package:utakata/src/3_application/1_commands/impl_command.dart';
import 'package:utakata/src/3_application/1_commands/imports_command.dart';
import 'package:utakata/src/3_application/1_commands/log_command.dart';
import 'package:utakata/src/3_application/1_commands/mcp_command.dart';
import 'package:utakata/src/3_application/1_commands/message_command.dart';
import 'package:utakata/src/3_application/1_commands/plan_command.dart';
import 'package:utakata/src/3_application/1_commands/skills_command.dart';
import 'package:utakata/src/3_application/1_commands/status_command.dart';
import 'package:utakata/src/3_application/1_commands/summary_command.dart';
import 'package:utakata/src/3_application/1_commands/vault_command.dart';
import 'package:utakata/src/3_application/3_presenters/log_preview_presenter.dart';
import 'package:utakata/src/3_application/3_presenters/message_preview_presenter.dart';
import 'package:utakata/src/3_application/3_presenters/summary_presenter.dart';
import 'package:utakata/src/3_application/4_server/mcp_server.dart';
import 'package:utakata/src/1_domain/3_usecases/list_architectures_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/show_architecture_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/expand_plan_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/export_architecture_usecase.dart';
import 'package:utakata/src/1_domain/3_usecases/create_architecture_usecase.dart';
import 'package:utakata/src/3_application/1_commands/arch_command.dart';
import 'package:utakata/src/3_application/2_runner/command_runner.dart';

/// utakata CLI エントリポイント
///
/// ここで全ての依存を組み立てる（手動 DI）。
/// 依存の流れ: Infrastructure → Domain UseCase → Application Command
Future<void> main(List<String> arguments) async {
  // ─── 言語解決（最初に 1 度だけ行う）───
  final msg = MessagesResolver.resolve();

  // ─── Infrastructure 層の組み立て ───
  const fs = FilesystemDataSource();
  const yaml = YamlDataSource();
  const yamlEdit = YamlEditDataSource();

  // flutter 実行ファイルのパスは初回使用時に遅延解決する
  // (plan/check/status --brief 等 flutter を使わないコマンドを妨げない)。
  const process = ProcessDataSource();
  const jsonl = JsonlDataSource();
  const frontMatter = FrontMatterDataSource(yaml);
  const marker = MarkdownMarkerDataSource();

  // リポジトリ実装
  final homeDir =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';

  final knowledgeRepo = KnowledgeRepositoryImpl(
    const GitDataSource(),
    yaml,
    homeDir,
  );

  // テンプレートパス解決(v1.4.0 / Issue #15 の slim 同梱に対応):
  //   ① 設定済みリモートキャッシュ(knowledge_repo 指定 + lock 済みの場合)
  //   ② 同梱(arch_definition.yaml と skills/ のみ同梱している)
  //   ③ 既定ナレッジキャッシュ(無ければ公式 utakata_arch_lib を自動フェッチ)
  // 構造コマンドは②で完結するためオフラインでも動作し、読み物(ガイド等)の
  // 参照時のみ③に到達する。
  bool pathExists(String path) =>
      File(path).existsSync() || Directory(path).existsSync();

  Future<String> resolveTemplatePath(String relativePath) async {
    final remoteRoot = await knowledgeRepo.materializedRoot(Directory.current.path);
    if (remoteRoot != null) {
      final candidate = '$remoteRoot/$relativePath';
      if (pathExists(candidate)) return candidate;
    }

    final bundled = await fs.resolvePackageTemplatePath(relativePath);
    if (pathExists(bundled)) return bundled;

    final defaultRoot = await knowledgeRepo.ensureDefaultAvailable();
    if (defaultRoot != null) {
      final candidate = '$defaultRoot/$relativePath';
      if (pathExists(candidate)) return candidate;
    }
    return bundled;
  }

  final archRepo = ArchitectureRepositoryImpl(fs, yaml, resolveTemplatePath: resolveTemplatePath);
  final templateRepo = TemplateRepositoryImpl(fs);
  final projectRepo = ProjectRepositoryImpl(fs, yaml);
  final configRepo = ConfigRepositoryImpl(fs, yaml, homeDir: homeDir);
  final vaultRepo =
      VaultRepositoryImpl(configRepo, const GitDataSource(), homeDir);
  final planRepo = PlanRepositoryImpl(fs, yaml, yamlEdit, configRepo: configRepo);
  final structureRepo = StructureRepositoryImpl(fs);
  final logRepo = ConversationLogRepositoryImpl(jsonl);
  final messageRepo = MessageRepositoryImpl(jsonl);
  final agreementRepo = AgreementRepositoryImpl(jsonl);
  final implPlanRepo = ImplPlanRepositoryImpl(fs, frontMatter);
  final featureTemplateRepo = FeatureTemplateRepositoryImpl(fs, yaml);

  // ─── Domain UseCase の組み立て ───
  final addFeatureUsecase = AddFeatureUsecase(
    archRepo: archRepo,
    templateRepo: templateRepo,
    msg: msg,
    writeFile: fs.writeFile,
    ensureDir: fs.ensureDir,
  );

  final createProjectUsecase = CreateProjectUsecase(
    archRepo: archRepo,
    templateRepo: templateRepo,
    msg: msg,
    runFlutterCreate: ({
      required appName,
      required projectName,
      required org,
      required platforms,
      required description,
    }) =>
        process.flutterCreate(
      appName: appName,
      projectName: projectName,
      org: org,
      platforms: platforms,
      description: description,
    ),
    runBuildRunner: ({required appName}) => process.flutterPubRunBuildRunner(appName: appName),
    readFile: fs.readFile,
    writeFile: fs.writeFile,
    ensureDir: fs.ensureDir,
  );

  final generateCoreUsecase = GenerateCoreUsecase(
    archRepo: archRepo,
    ensureDir: fs.ensureDir,
    readFile: fs.readFile,
  );

  final checkUsecase = CheckUsecase(
    planRepo: planRepo,
    archRepo: archRepo,
    structureRepo: structureRepo,
    msg: msg,
  );

  // enforcement.impl_plan: on のときだけ、実装計画のある feature 名を返す
  // (off なら null を返してゲートを完全に無効化する)。
  Future<Set<String>?> featuresWithImplPlan(String projectDir) async {
    final config = await configRepo.read(projectDir);
    // off(既定)なら null = ゲートしない。空集合を返すと「全 feature に
    // 計画が無い」と解釈されてしまうので、必ず null で返すこと。
    if (config?.implPlanEnforcement != 'on') return null;
    return ImplPlanGate.featuresWithPlan(await implPlanRepo.listAll(projectDir));
  }

  final applyUsecase = ApplyUsecase(
    planRepo: planRepo,
    archRepo: archRepo,
    addFeatureUsecase: addFeatureUsecase,
    generateCoreUsecase: generateCoreUsecase,
    fileExists: fs.entityExists,
    writeFile: fs.writeFile,
    featuresWithPlan: featuresWithImplPlan,
  );

  final expandPlanUsecase = ExpandPlanUsecase(
    planRepo: planRepo,
    archRepo: archRepo,
  );

  final adoptPlanUsecase = AdoptPlanUsecase(
    planRepo: planRepo,
    structureRepo: structureRepo,
  );

  final scanProjectStatusUsecase = ScanProjectStatusUsecase(
    archRepo: archRepo,
    readFile: fs.readFile,
    fileExists: fs.fileExists,
    dirExists: fs.dirExists,
    scanDartFiles: fs.scanDartFiles,
  );

  final statusUsecase = StatusUsecase(
    checkUsecase: checkUsecase,
    scanStatusUsecase: scanProjectStatusUsecase,
    msg: msg,
    runFlutterAnalyze: process.flutterAnalyze,
    getFlutterVersion: process.flutterVersion,
  );

  final listArchitecturesUsecase = ListArchitecturesUsecase(
    archRepo: archRepo,
  );

  final showArchitectureUsecase = ShowArchitectureUsecase(
    archRepo: archRepo,
  );

  final exportArchitectureUsecase = ExportArchitectureUsecase(
    archRepo: archRepo,
    writeFile: fs.writeFile,
    ensureDir: fs.ensureDir,
  );

  final createArchitectureUsecase = CreateArchitectureUsecase(
    writeFile: fs.writeFile,
    ensureDir: fs.ensureDir,
    fileExists: fs.fileExists,
    msg: msg,
  );

  final initDocUsecase = InitDocUsecase(
    ensureDir: fs.ensureDir,
    writeFile: fs.writeFile,
    fileExists: fs.fileExists,
  );

  final showDocUsecase = ShowDocUsecase(
    resolvePackageFilePath: fs.resolvePackageFilePath,
    readFile: fs.readFile,
  );

  final addLogEntryUsecase = AddLogEntryUsecase(repo: logRepo);
  final queryLogUsecase = QueryLogUsecase(repo: logRepo);
  final renderLogPreviewUsecase = RenderLogPreviewUsecase(
    repo: logRepo,
    renderDay: LogPreviewPresenter.renderDay,
    writeFile: fs.writeFile,
  );

  final recordMessageUsecase = RecordMessageUsecase(repo: messageRepo);
  final importMessagesUsecase = ImportMessagesUsecase(repo: messageRepo);
  final renderMessagesUsecase = RenderMessagesUsecase(
    repo: messageRepo,
    renderMonth: MessagePreviewPresenter.renderMonth,
    writeFile: fs.writeFile,
  );

  final implPlanUsecase = ImplPlanUsecase(repo: implPlanRepo);

  final doctorUsecase = DoctorUsecase(
    driftedImplPlans: implPlanUsecase.listDrifted,
    detectMisplacedPlans: implPlanRepo.detectMisplaced,
    featuresWithImplPlan: featuresWithImplPlan,
    scanImplPlans: implPlanRepo.scanAll,
    msg: msg,
    planRepo: planRepo,
    configRepo: configRepo,
    fileExists: fs.fileExists,
    dirExists: fs.dirExists,
    readFile: fs.readFile,
    deleteFile: fs.deleteFile,
    deleteDir: fs.deleteDir,
    movePath: fs.movePath,
    listEntries: fs.listEntries,
    listFilesNamed: fs.listFilesNamed,
  );

  final recordAgreementUsecase = RecordAgreementUsecase(repo: agreementRepo);
  final listAgreementsUsecase = ListAgreementsUsecase(repo: agreementRepo);

  final renderSummaryUsecase = RenderSummaryUsecase(
    agreementRepo: agreementRepo,
    readFile: fs.readFile,
    writeFile: fs.writeFile,
    replaceSection: marker.replaceSection,
    renderAgreements: SummaryPresenter.renderAgreements,
  );

  final guideUsecase = GuideUsecase(
    archRepo: archRepo,
    readFile: fs.readFile,
    writeFile: fs.writeFile,
    ensureDir: fs.ensureDir,
    resolvePackageTemplatePath: resolveTemplatePath,
  );

  final generateClaudeIntegrationUsecase = GenerateClaudeIntegrationUsecase(
    writeFile: fs.writeFile,
    ensureDir: fs.ensureDir,
    fileExists: fs.fileExists,
    configRepo: configRepo,
  );

  final applyFeatureTemplateUsecase = ApplyFeatureTemplateUsecase(
    templateRepo: featureTemplateRepo,
    planRepo: planRepo,
    addFeatureUsecase: addFeatureUsecase,
    msg: msg,
  );

  final archResolver = ArchitectureResolver(
    configRepo: configRepo,
    planRepo: planRepo,
  );

  final guideForFileUsecase = GuideForFileUsecase(
    archRepo: archRepo,
    configRepo: configRepo,
    planRepo: planRepo,
    showGuide: guideUsecase.show,
  );

  final auditImportsUsecase = AuditImportsUsecase(
    archResolver: archResolver,
    archRepo: archRepo,
    listFilesWithSuffix: fs.listFilesWithSuffix,
    readFile: fs.readFile,
  );

  final syncSkillsUsecase = SyncSkillsUsecase(
    configRepo: configRepo,
    planRepo: planRepo,
    resolveTemplatePath: resolveTemplatePath,
    readFile: fs.readFile,
    writeFile: fs.writeFile,
    ensureDir: fs.ensureDir,
    dirExists: fs.dirExists,
    listEntries: fs.listEntries,
  );

  final mcpServer = McpServer(
    checkUsecase: checkUsecase,
    planRepo: planRepo,
    queryLogUsecase: queryLogUsecase,
    listAgreementsUsecase: listAgreementsUsecase,
    guideUsecase: guideUsecase,
    guideForFileUsecase: guideForFileUsecase,
    configRepo: configRepo,
    archResolver: archResolver,
    showDocUsecase: showDocUsecase,
    vaultRepo: vaultRepo,
    messageRepo: messageRepo,
  );

  // ─── Application 層の組み立て ───
  final runner = UtakataCommandRunner(
    msg: msg,
    createCommand: CreateCommand(createProjectUsecase, generateClaudeIntegrationUsecase, msg),
    featureCommand: FeatureCommand(addFeatureUsecase, applyFeatureTemplateUsecase, msg,
        archResolver: archResolver, featuresWithPlan: featuresWithImplPlan),
    planCommand: PlanCommand(adoptPlanUsecase, msg,
        expandUsecase: expandPlanUsecase, planRepo: planRepo),
    diffCommand: DiffCommand(checkUsecase, msg),
    checkCommand: CheckCommand(checkUsecase, msg),
    importsCommand: ImportsCommand(auditImportsUsecase, msg),
    applyCommand: ApplyCommand(applyUsecase, msg),
    statusCommand: StatusCommand(statusUsecase, projectRepo, msg),
    archCommand: ArchCommand(
      listArchitecturesUsecase,
      showArchitectureUsecase,
      exportArchitectureUsecase,
      createArchitectureUsecase,
      msg,
      configRepo: configRepo,
      knowledgeRepo: knowledgeRepo,
    ),
    docCommand: DocCommand(initDocUsecase, msg, showUsecase: showDocUsecase),
    logCommand: LogCommand(addLogEntryUsecase, queryLogUsecase, renderLogPreviewUsecase, msg),
    messageCommand: MessageCommand(recordMessageUsecase, importMessagesUsecase,
        renderMessagesUsecase, messageRepo, msg),
    doctorCommand: DoctorCommand(doctorUsecase, msg),
    agreeCommand: AgreeCommand(recordAgreementUsecase, listAgreementsUsecase, msg),
    implCommand: ImplCommand(implPlanUsecase, msg, writeFile: fs.writeFile),
    summaryCommand: SummaryCommand(renderSummaryUsecase, msg),
    guideCommand: GuideCommand(guideUsecase, msg,
        guideForFileUsecase: guideForFileUsecase, archResolver: archResolver),
    mcpCommand: McpCommand(mcpServer, msg),
    skillsCommand: SkillsCommand(syncSkillsUsecase, msg),
    claudeCommand: ClaudeCommand(generateClaudeIntegrationUsecase, msg),
    vaultCommand: VaultCommand(vaultRepo, msg),
  );

  // ─── 実行 ───
  final exitCode = await runner.run(arguments) ?? 0;
  exit(exitCode);
}
