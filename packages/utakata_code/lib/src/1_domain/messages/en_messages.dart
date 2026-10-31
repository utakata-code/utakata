import 'cli_messages.dart';

/// 英語メッセージ実装
class EnMessages implements CliMessages {
  const EnMessages();

  // ─── command descriptions ───
  @override
  String get cmdCreateDesc => 'Create a new Flutter project';
  @override
  String get cmdFeatureDesc => 'Add a feature';
  @override
  String get cmdFeatureAddDesc => 'Add a single feature';
  @override
  String get cmdFeatureInitDesc =>
      'Bulk-generate all features from plan_architecture.yaml';
  @override
  String get cmdPlanDesc => 'plan.yaml (intent-level plan) commands';
  @override
  String get cmdScanDesc =>
      'Scan the current directory structure and save to YAML';
  @override
  String get cmdDiffDesc =>
      'Permanent alias for check (verify plan.yaml against the real structure)';
  @override
  String get cmdCheckDesc =>
      'Check architecture health (exit 1 if diff found)';
  @override
  String get cmdImportsDesc =>
      'Audit import health against the architecture import_rules (exit 1 on violations)';
  // ─── message (v1.6.0) ───
  @override
  String get cmdMessageDesc =>
      'Record verbatim correspondence with the client (separate from log summaries)';
  @override
  String get cmdMessageAddDesc =>
      'Record one message (body from arguments or stdin)';
  @override
  String get cmdMessageImportDesc =>
      'Bulk-import existing correspondence (duplicates are skipped)';
  @override
  String get cmdMessageListDesc => 'List recorded messages';
  @override
  String get cmdMessageShowDesc => 'Print one message in full';
  @override
  String get cmdMessageRenderDesc =>
      'Regenerate the monthly preview under doc/preview/messages/';
  @override
  String get cmdMessageLinkDesc =>
      'Attach a log/agreement reference to a message';
  @override
  String get optMessageDirection => 'Direction (inbound | outbound)';
  @override
  String get optMessageChannel => 'Channel (client_portal / mail / chatwork …)';
  @override
  String get optMessageFrom => 'Sender';
  @override
  String get optMessageTo => 'Recipient';
  @override
  String get optMessageSubject => 'Subject';
  @override
  String get optMessageThread => 'Thread name (groups related exchanges)';
  @override
  String get optMessageExternalId =>
      'ID in the source system (used to skip duplicates on re-import)';
  @override
  String get optMessageAttachment => 'Attachment path (repeatable)';
  @override
  String get optMessageFormat => 'Source format (jsonl|md)';
  @override
  String get optMessageFile => 'File to import (defaults to stdin)';
  @override
  String get optMessageMonth => 'Target month (YYYY-MM)';
  @override
  String get optMessageLogRef => 'Conversation log ID to link';
  @override
  String get optMessageAgreementRef => 'Agreement ID to link';
  @override
  String get messageDirectionRequired =>
      'Specify --direction (inbound | outbound)';
  @override
  String get messageBodyRequired =>
      'Provide a body: utakata message add -d inbound "text…" or pipe it via stdin';
  @override
  String get messageIdRequired =>
      'Specify a message ID (see utakata message list)';
  @override
  String get messageImportSourceRequired =>
      'Pass --file or pipe the source via stdin';
  @override
  String get messageImportNothingParsed =>
      'No messages could be parsed. Check --format and the heading form '
      '(e.g. "## [inbound] 2026-08-11 10:24 Yamada").';
  @override
  String get messageLinkTargetRequired => 'Specify --log or --agreement';
  @override
  String get messageListEmpty => 'No messages recorded.';
  @override
  String messageAddDone(String id) => 'Recorded: $id';
  @override
  String messageAddDuplicate(String id) =>
      'A record with the same external_id already exists ($id). Nothing added.';
  @override
  String messageImportDone(int imported, int skipped) =>
      'Imported $imported message(s) ($skipped duplicate(s) skipped)';
  @override
  String messageImportDryRun(int imported, int skipped) =>
      '[DRY] Would import $imported message(s) ($skipped duplicate(s) skipped)';
  @override
  String messageRenderDone(int months) =>
      'Wrote $months month(s) under doc/preview/messages/';
  @override
  String messageLinkDone(String id) => 'Linked: $id';
  @override
  String messageNotFound(String id) => 'Message "$id" not found.';
  @override
  String messageFileNotFound(String path) => 'File not found: $path';

  @override
  String importsSection(String archId) =>
      '🔎 utakata imports — import audit ($archId)';
  @override
  String importsNoRules(String archId) =>
      'Architecture "$archId" has no import_rules. '
      'Add an import_rules section to arch_definition.yaml to enable the audit.';
  @override
  String importsClean(int audited, int excluded) =>
      'No import violations ($audited files audited, $excluded excluded)';
  @override
  String importsViolationSummary(int count, int audited, int excluded) =>
      '$count import violation(s) ($audited files audited, $excluded excluded)';
  @override
  String importsInternalViolation(String from, String to, String allow) =>
      'import from "$from" into "$to" is not allowed (allow: $allow)';
  @override
  String importsExternalViolation(String pattern, String pkg, String deny) =>
      '"$pattern" must not import $pkg (deny: $deny)';
  @override
  String importsPlacementViolation(String pkg, String layers) =>
      '$pkg is only declared for use in: $layers';
  @override
  String get cmdStatusDesc => 'Show overall project status';
  @override
  String get cmdRunnerDesc =>
      'A spec-driven Flutter development CLI tool';

  // ─── command runner ───
  @override
  String get versionHelp => 'Show version';

  // ─── option help ───
  @override
  String get optOrg => 'Package organization name (e.g. com.example)';
  @override
  String get optPlatforms => 'Target platforms (comma-separated)';
  @override
  String get optDescription => 'Project description';
  @override
  String get optArch => 'Architecture to use (e.g. clean_architecture)';
  @override
  String get optEntity => 'Entity name (defaults to feature name)';
  @override
  String get optPermission => 'Permission level';
  @override
  String get optYes => 'Skip confirmation prompt';
  @override
  String get optDryRun => 'Preview without generating files';
  @override
  String get optBrief => 'Lightweight mode (skip flutter analyze/version)';
  @override
  String get optWriteReport => 'Update project_status.yaml/md';

  // ─── Logger.section headers ───
  @override
  String sectionCreate(String name) => '🚀 utakata create — $name';
  @override
  String get sectionPlan => '📝 utakata plan — Generating plan file';
  @override
  String get sectionScan => '📸 utakata scan — Generating snapshot';
  @override
  String get sectionDiff => '⚖️ utakata diff — Architecture diff';
  @override
  String get sectionCheck => '🔍 utakata check — Architecture check';
  @override
  String get sectionStatus => '📊 utakata status — Project status';
  @override
  String sectionFeatureAdd(String name) => '✨ utakata feature add — $name';
  @override
  String sectionFeatureInit(bool dryRun) =>
      '🚀 utakata feature init${dryRun ? ' (dry-run)' : ''}';

  // ─── common ───
  @override
  String get cancel => 'Cancelled.';

  // ─── input errors ───
  @override
  String get missingAppName =>
      'Please specify an app name. Example: utakata create my_app';
  @override
  String get missingFeatureName =>
      'Please specify a feature name. Example: utakata feature add memo';
  @override
  String confirmGenerate(String path) => 'Are you sure you want to generate in "$path"? (y/N)';
  @override
  String projectCreated(String name) => '✅ Project "$name" has been generated!';

  // ─── plan ───
  @override
  String get planMissingFeaturesKey =>
      'feature_request.yaml is missing the "features" key.';
  @override
  String planDone(int count) => 'Architecture plan generated ($count features).';

  // ─── feature add ───
  @override
  String featureAddPath(String path) => '  path: $path';
  @override
  String featureAddDone(String name) => 'Feature "$name" has been generated!';
  @override
  String get featureAddCancel => 'Cancelled.';

  // ─── feature init ───
  @override
  String get featureInitNone => 'No features found to generate.';
  @override
  String featureInitDone(int count) => '$count feature(s) have been generated!';
  @override
  String featureDryRunRow(String path) => '[DRY] $path';

  // ─── scan ───
  @override
  String get scanDone => 'Snapshot generated.';

  // ─── diff ───
  @override
  String get diffClean => 'No diff! Plan and current structure match perfectly.';
  @override
  String diffSummary(int missing, int extra) =>
      'Missing: $missing, Extra: $extra';
  @override
  String get diffMissingHeader => 'Missing (planned but not implemented):';
  @override
  String get diffExtraHeader => 'Extra (implemented but not in plan):';

  // ─── check ───
  @override
  String get checkOk => 'Architecture is healthy!';
  @override
  String get checkFail =>
      'Architecture has issues. Run `utakata diff` for details.';
  @override
  String checkMissingRow(String path) => '[Missing] $path';

  // ─── status ───
  @override
  String get statusFlutterVersionHeader => '--- Flutter Version ---';
  @override
  String get statusLintHeader => '--- Lint Analysis ---';
  @override
  String get statusLintOk => 'No issues found.';
  @override
  String get statusArchHeader => '--- Architecture Diff ---';
  @override
  String get statusNoPlan =>
      'plan_architecture.yaml not found. Run `utakata plan` first.';
  @override
  String get statusDiffClean => 'Plan and current structure are in sync!';

  // ─── errors ───
  @override
  String featureRequestNotFound(String path) =>
      '$path not found. Please create the specification file.';
  @override
  String planNotFound(String path) =>
      '$path not found. Run `utakata plan` first.';
  @override
  String currentStructureNotFound(String path) =>
      '$path not found. Run `utakata scan` first.';
  @override
  String notFlutterProject(String dir) =>
      '$dir is not a Flutter project. Run from the project root.';
  @override
  String get flutterNotFound =>
      'flutter command not found. '
      'Set the FLUTTER_PATH environment variable to the full path. '
      'Example: export FLUTTER_PATH=/path/to/flutter/bin/flutter '
      '(for a script without the execute bit, set the whole command line, e.g. '
      'UTAKATA_FLUTTER="/system/bin/sh /path/to/flutter/bin/flutter")';
  @override
  String yamlParseFailed(String path) => 'Failed to parse YAML: $path';
  @override
  String get flutterCreateFailed => 'flutter create failed.';
  @override
  String get buildRunnerFailed => 'build_runner execution failed.';

  // ─── add_feature_usecase ───
  @override
  String layerDirCreateFailed(String path) =>
      'Failed to create directory: $path';
  @override
  String templateExpandFailed(String path) =>
      'Failed to expand template: $path';

  // ─── validate ───
  @override
  String get cmdValidateDesc =>
      'Detect naming rule and directory structure violations';
  @override
  String get sectionValidate => '🔎 utakata validate — Naming & Structure Check';
  @override
  String get validateOk =>
      'No naming or directory structure violations found!';
  @override
  String get validateNamingHeader => '[Naming Violations]';
  @override
  String get validateStructureHeader => '[Directory Structure Violations]';
  @override
  String validateNamingViolation(String file, String expected) =>
      '  ❌ $file\n     Expected: $expected';
  @override
  String validateMissingDir(String path) => '  Missing: $path';
  @override
  String validateExtraDir(String path) => '  Extra:   $path';
  @override
  String validateSummary(int naming, int missing, int extra) =>
      'Naming: $naming violation(s) / Missing: $missing / Extra: $extra';

  // ─── arch subcommands ───
  @override
  String get cmdArchDesc => 'Inspect, export, and custom-create architectures';
  @override
  String get cmdArchListDesc => 'List all available architecture definitions';
  @override
  String get cmdArchShowDesc => 'Show detail definition, naming rules, and layer structure tree';
  @override
  String get cmdArchExportDesc => 'Export raw YAML file for the specified architecture';
  @override
  String get cmdArchCreateDesc => 'Create a customizable architecture definition boilerplate locally';
  @override
  String get archListHeader => 'Available Architecture Definitions:';
  @override
  String archShowHeader(String id, String name) => '🏛️ Architecture: $name ($id)';
  @override
  String get archShowLayers => '[Layer Structure (Layers)]';
  @override
  String get archShowNamingRules => '[Naming Rules]';
  @override
  String archExportSuccess(String id, String path) => '✅ Exported architecture "$id" to "$path"!';
  @override
  String archCreateSuccess(String id, String path) => '✅ Created local architecture boilerplate at "$path"!';
  @override
  String architectureAlreadyExists(String path) => '❌ Error: Architecture definition already exists: $path';
  @override
  String get missingArchitectureId => 'Please specify an architecture ID. Example: utakata arch show clean_architecture';
  @override
  String get missingOutputPath => 'Please specify an output path. Example: utakata arch export clean_architecture temp.yaml';

  // ─── other errors ───
  @override
  String guideGenerationFailed(String error) => 'Failed to generate guides: $error';
  @override
  String templatePathResolveFailed(String path) => 'Failed to resolve package template path: $path';

  // ─── core ───
  @override
  String get cmdCoreDesc => 'Generate Core directory structure';
  @override
  String get sectionCore => '🏗️ utakata core — Core directory generation';
  @override
  String coreDone(int count) => '✅ Generated $count Core module directories!';
  @override
  String coreModuleRow(String path) => '  ✅ $path';

  // ─── check (v0.7) ───
  @override
  String get optJson => 'Output as JSON';
  @override
  String get optFile => 'Filter violations to the given path only';
  @override
  String get namingViolationsHeader => '⚠️ Naming violations:';
  @override
  String get checkClean => '✅ Structure matches the plan (no violations)';
  @override
  String checkSummary(int missing, int extra, int naming) =>
      '⚠️ missing: $missing / extra: $extra / naming violations: $naming';
  @override
  String deprecatedAlias(String oldCmd, String newCmd) =>
      '⚠️  `utakata $oldCmd` is deprecated. Use `utakata $newCmd` instead.';

  // ─── apply (v0.7) ───
  @override
  String get cmdApplyDesc => 'Generate feature/core scaffolding missing from plan.yaml';
  @override
  String get optScope => 'Scope to generate (all|feature|core)';
  @override
  String get sectionApply => '🏗️ utakata apply — Generating structure';
  @override
  String applyFeatureRow(String path) => '  ✅ $path';
  @override
  String applyFileRow(String path) => '  📄 $path';
  @override
  String applyFilesDone(int fileCount) =>
      '📄 Created $fileCount empty file(s) (existing files untouched)';
  @override
  String applyDone(int featureCount, int coreCount) =>
      '✅ Generated $featureCount feature(s), $coreCount core module(s)';
  @override
  String get applyNothingToDo => 'Nothing to generate (plan.yaml not found or empty)';

  // ─── plan adopt (v0.7) ───
  @override
  String get cmdPlanAdoptDesc => 'Detect unplanned features and append them to plan.yaml';
  @override
  String get sectionPlanAdopt => '🔍 utakata plan adopt — Detecting unplanned features';
  @override
  String get adoptNoneFound => 'No unplanned features found';
  @override
  String adoptCandidateRow(String permission, String name) => '  - $permission/$name';
  @override
  String adoptConfirm(String permission, String name) =>
      'Add "$permission/$name" to plan.yaml? [y/N] ';
  @override
  String adoptDone(int count) => '✅ Added $count feature(s) to plan.yaml';

  // ─── doc init (v0.8) ───
  @override
  String get cmdDocDesc => 'doc/ project workspace commands';
  @override
  String get cmdDocInitDesc => 'Create the doc/ workspace ahead of the app (pre-contract phase)';
  @override
  String get docInitDone => '✅ Created the doc/ workspace';
  @override
  String get docInitAlreadyExists => 'doc/ already exists';

  // ─── log (v0.8) ───
  @override
  String get cmdLogDesc => 'Structured client conversation log (human-only writes)';
  @override
  String get cmdLogAddDesc => 'Append one log entry';
  @override
  String get cmdLogShowDesc => 'Show log entries';
  @override
  String get cmdLogRenderDesc => 'Regenerate the Markdown log preview';
  @override
  String logAddDone(String id) => '✅ Recorded $id';
  @override
  String get logShowEmpty => 'No matching log entries found';
  @override
  String get logRenderDone => '✅ Preview regenerated';

  // ─── agree (v0.9) ───
  @override
  String get cmdAgreeDesc => 'Agreement tracking (client agreements, internal decisions)';
  @override
  String get cmdAgreeAddDesc => 'Append one agreement';
  @override
  String get cmdAgreeListDesc => 'List agreements';
  @override
  String get cmdAgreeStatusDesc => 'Update an agreement\'s status';
  @override
  String agreeAddDone(String id) => '✅ Recorded $id';
  @override
  String get agreeListEmpty => 'No agreements recorded';
  @override
  String agreeStatusDone(String id, String status) => '✅ Updated $id to $status';

  // ─── Agreement ID checks and read warnings (v1.8.1, #33) ───
  @override
  String agreementIdInvalid(String quotedId) =>
      'Invalid agreement ID: $quotedId (pass one ID like AGR-0001). Nothing was recorded.';
  @override
  String agreementNotFound(String quotedId) =>
      'Agreement $quotedId is not recorded (check with utakata agree list). Nothing was recorded.';
  @override
  String agreementSkippedUnparsable(int line) =>
      'Skipped agreements.jsonl line $line: not valid JSON (saved to agreements.jsonl.corrupt)';
  @override
  String agreementSkippedInvalid(int line) =>
      'Skipped agreements.jsonl line $line: not a valid agreement event';
  @override
  String agreementSkippedMissingAdd(String quotedId) =>
      'Skipped $quotedId: no add event (e.g. a status change or reflect on a non-existent ID)';
  @override
  String agreementSkippedSummary(int count) =>
      'Skipped $count unreadable agreement record(s). Check agreements.jsonl (it is append-only; decide by hand whether to fix it)';
  @override
  String doctorAgreementsSkipped(int count, String sample) =>
      'doc/records/agreements.jsonl has $count unreadable record(s) ($sample). '
      'Run `utakata agree list` for details.';

  // ─── impl (v0.9) ───
  @override
  String get cmdImplDesc => 'Feature implementation plan management';
  @override
  String get cmdImplNewDesc =>
      'Create a new implementation plan ([kind:]<target>; kind is '
      'feat|fix|refactor|docs|chore|test, default feat)';
  @override
  String get cmdImplListDesc => 'List implementation plans';
  @override
  String get cmdImplDoneDesc => 'Mark an implementation plan as done';
  @override
  String get cmdImplArchiveDesc => 'Move a done implementation plan to archive/';
  @override
  String implNewDone(String id, String path) => 'Created $id: $path';
  @override
  String get implListEmpty => 'No implementation plans found';
  @override
  String implDoneDone(String id) => '✅ Marked $id as done';
  @override
  String implArchiveDone(String id) => '✅ Moved $id to archive/';

  // ─── impl の2軸ライフサイクル (v1.7.0) ───
  @override
  String get cmdImplStartDesc => 'Start implementing (status: in_progress)';
  @override
  String get cmdImplReviewDesc => 'Move to your own review stage (status: review)';
  @override
  String get cmdImplBoardDesc =>
      'Print the lane board and regenerate doc/preview/impl_board.md';
  @override
  String get cmdImplTestDesc =>
      'Advance the verification axis (start|review|done|todo|skip)';
  @override
  String cmdImplTestTransitionDesc(String name) {
    switch (name) {
      case 'start':
        return 'Start testing (test: in_progress)';
      case 'review':
        return 'Move to test review (test: review)';
      case 'done':
        return 'Mark testing complete (test: done)';
      case 'todo':
        return 'Send testing back to not-started (test: todo)';
      default:
        return 'Declare testing unnecessary (test: not_required)';
    }
  }
  @override
  String get cmdImplSyncDesc =>
      'Move plan files back to the lane their frontmatter implies';
  @override
  String get optImplStatus =>
      'Filter by implementation status (todo|in_progress|review|done|archived)';
  @override
  String get optImplTest =>
      'Filter by test status (not_required|todo|in_progress|review|done)';
  @override
  String get optImplLane => 'Filter by lane (directory name)';
  @override
  String get optImplSkipReason => 'Why testing is unnecessary';
  @override
  String get implFeatureRequired =>
      'Specify a target: utakata impl new [kind:]<target> '
      '(e.g. login / refactor:doc_layout)';
  @override
  String get implIdRequired =>
      'Specify a plan ID (see utakata impl list)';
  @override
  String implUnknownLane(String given, String known) =>
      'Unknown lane "$given". Valid lanes: $known';
  @override
  String implTransitionDone(String id, String status, String test) =>
      '$id: status=$status / test=$test';
  @override
  String implMovedTo(String path) => 'moved: $path';
  @override
  String implBoardDone(String path) => 'Board regenerated: $path';
  @override
  String get implSyncClean => 'Every plan is already in the right lane.';
  @override
  String implSyncDryRun(int count) => '[DRY] Would move $count plan(s)';
  @override
  String implSyncDone(int count) => 'Moved $count plan(s) into the right lane';
  @override
  String implSyncBlocked(String id, String destination) =>
      '$id: not moved — $destination is already occupied '
      '(moving would overwrite it; resolve the duplicate first)';
  @override
  String implScanUnreadable(int count, String samples) =>
      "$count implementation plan(s) have unreadable frontmatter ($samples). "
      'They are excluded from listing and ID assignment — fix or move them.';
  @override
  String implScanDuplicates(int count, String samples) =>
      '$count implementation plan ID(s) appear in more than one file '
      '($samples). Updates and moves are refused until one is removed.';
  @override
  String implPlanRequired(String feature) =>
      'Feature "$feature" has no implementation plan '
      '(enforcement.impl_plan: on). Create one with '
      '`utakata impl new $feature`.';
  @override
  String implPlanMissingForCode(int count, String samples) =>
      '$count feature(s) have code but no implementation plan ($samples). '
      'Create one with `utakata impl new <feature>`.';
  @override
  String implPlansMisplaced(int count, String samples) =>
      '$count implementation plan(s) sit in a lane their frontmatter does not '
      'imply ($samples). Run `utakata impl sync` to fix.';

  // ─── impl plan/log split and freezing (v1.8.0) ───
  @override
  String get cmdImplNoteDesc =>
      'Append one progress note (text from arguments or stdin; the plan '
      'section is left untouched)';
  @override
  String get cmdImplReviseDesc =>
      'Accept edits made to a frozen plan as a revision (revisions + 1)';
  @override
  String get optImplReviseReason => 'Why the plan changed (required)';
  @override
  String get optImplSupersedes =>
      'ID of the older plan this one replaces (e.g. PLAN-0001)';
  @override
  String get optImplAgreement =>
      'Agreement IDs this plan is based on, comma-separated (e.g. AGR-0003)';
  @override
  String get optImplSpec =>
      'Spec file paths this plan is based on, comma-separated';
  @override
  String get optImplMessage =>
      'Message IDs this plan is based on, comma-separated '
      '(e.g. MSGR-20260811-001)';
  @override
  String get optImplBasis =>
      'Whether the plan was agreed with the client or is your own judgment';
  @override
  String get optImplBacklog => 'Backlog item this plan belongs to (free text)';
  @override
  String get implNoteTextRequired =>
      'Specify the note text: utakata impl note <ID> "text" (or via stdin)';
  @override
  String implNoteDone(String id) => 'Appended a note to $id';
  @override
  String get implReviseReasonRequired =>
      'Specify --reason (it is written into the plan\'s log)';
  @override
  String implReviseDone(String id, int revisions) =>
      'Accepted the changes to $id as revision $revisions';
  @override
  String implPlansDrifted(int count, String samples) =>
      '$count implementation plan(s) were edited after being frozen '
      '($samples). If intended, accept with '
      '`utakata impl revise <ID> --reason "..."`.';
  @override
  String staleGeneratedSkill(String skillId) =>
      '.claude/skills/$skillId/SKILL.md is from an older version '
      '(claude init never overwrites existing files). '
      'Regenerate it with `utakata claude init --only skills` '
      '(not --force, which also overwrites settings.json and CLAUDE.md).';


  // ─── summary (v0.9) ───
  @override
  String get cmdSummaryDesc => 'Regenerate the marked sections of the project summary';
  @override
  String get summaryRenderDone => '✅ Regenerated the marked sections of summary.md';

  // ─── guide (v1.0) ───
  @override
  String get cmdGuideDesc => 'Browse reference knowledge (GUIDE etc.) and start customizing';
  @override
  String get cmdGuideListDesc => 'List available guides';
  @override
  String get cmdGuideShowDesc => 'Show a guide\'s content';
  @override
  String get cmdGuideEjectDesc => 'Eject a guide locally to start customizing';
  @override
  String get guideListEmpty => 'No guides found';
  @override
  String guideEjectDone(String id, String path) => '✅ Ejected $id: $path';
  @override
  String get missingGuideId => 'Please specify a guide ID';

  // ─── doctor (v1.0) ───
  @override
  String get cmdDoctorDesc => 'Diagnose environment/schema/layout and migrate';
  @override
  String get doctorOk => '✅ No issues found';
  @override
  String doctorIssueRow(String message) => '  ⚠️ $message';
  @override
  String get doctorMigrateNoneFound => 'Nothing to migrate';
  @override
  String doctorMigrateDone(int count) => '✅ Migrated $count item(s)';

  // ─── mcp (v1.1) ───
  @override
  String get cmdMcpDesc => 'Start the MCP server (stdio, read-only)';

  @override
  String get cmdClaudeDesc =>
      'Generate or repair the Claude Code integration (.claude/, .mcp.json, CLAUDE.md)';
  @override
  String get cmdClaudeInitDesc =>
      'Write .claude/ (skills, agent, settings) + .mcp.json + CLAUDE.md. '
      'Default repairs missing files only (existing ones are protected); '
      '--only regenerates the chosen targets, --force regenerates everything';
  @override
  String get cmdSkillsDesc => 'Sync architecture-bundled SKILLs into .claude/skills/';
  @override
  String get cmdSkillsSyncDesc =>
      'Sync the skills list in utakata.yaml into .claude/skills/ (managed-marker protection)';
  @override
  String get cmdVaultDesc =>
      'Browse the personal knowledge vault (client-facing service know-how)';
  @override
  String get cmdVaultListDesc => 'List vault entries';
  @override
  String get cmdVaultShowDesc => 'Print a vault entry: vault show Google/GCP/Firebase';
  @override
  String get cmdVaultGetDesc => 'Fetch (or re-fetch) the vault from its configured url';
  @override
  String get cmdDocShowDesc =>
      'Print the reference for a config file: doc show config|plan (see doc list)';
  @override
  String get cmdDocListDesc => 'List the available documentation topics';
  @override
  String get cmdPlanExpandDesc =>
      'Materialize the auto-derived per-layer lists into plan.yaml (editable afterwards)';
  @override
  String get cmdPlanAddDesc =>
      'Add items to a layer list in plan.yaml: plan add <feature> <layer> <item...>';
  @override
  String get cmdPlanRemoveDesc =>
      'Remove an item from a layer list in plan.yaml: plan remove <feature> <layer> <item>';
  @override
  String get cmdGuideForDesc =>
      'Deterministically resolve the layer guide for a file path (fix-context for lint errors)';
  @override
  String get cmdArchGetDesc =>
      'Fetch the knowledge repo (the official utakata_arch_lib when knowledge_repo is unset)';
  @override
  String get cmdAgreeCorrectDesc => 'Correct (supersede) a past agreement';
  @override
  String get cmdAgreeReflectDesc =>
      'Record where an agreement was reflected (impl plan / spec)';
  @override
  String get cmdLogImportDesc =>
      'Import a Claude Code session transcript into doc/records/sessions/ (human-only)';

  @override
  String get optForceOverwrite =>
      'Also overwrite human-edited managed files (unmanaged files are never touched)';
  @override
  String get optForceRegenerate =>
      'Regenerate existing files too. .claude/settings.json and CLAUDE.md are '
      'overwritten as whole files (hand-added settings and text are lost). '
      '.mcp.json only gets the utakata entry added/replaced; other servers are kept. '
      'Use --only to regenerate just some targets';
  @override
  String get optClaudeOnly =>
      'Regenerate only the given targets, overwriting existing files '
      '(repeatable: --only skills,agents). '
      'skills = .claude/skills/utakata-*, agents = .claude/agents/, '
      'mcp = .mcp.json (only the --mcp-name entry, default utakata, is added/replaced), '
      'settings = .claude/settings.json (overwritten), claude-md = CLAUDE.md (overwritten)';
  @override
  String claudeInitInvalidJson(String path) =>
      '$path was not written: it is not valid JSON '
      '(or mcpServers is not an object). Fix it and run again.';
  @override
  String get optMcp =>
      'Where .mcp.json points the MCP client. stdio = launch `utakata mcp` (default), '
      'http = the HTTP server given by --mcp-url, none = leave .mcp.json untouched. '
      'Giving only --mcp-url implies http';
  @override
  String get optMcpUrl =>
      'URL of the HTTP MCP server (required with --mcp=http). Written verbatim, '
      "so '\${MIDE_MCP_URL}' is expanded by Claude Code from the environment";
  @override
  String get optMcpHeader =>
      "Header sent to the HTTP MCP server ('Name: value', repeatable, --mcp=http only). "
      "Written verbatim (e.g. 'Authorization: Bearer \${TOKEN}')";
  @override
  String get optMcpName =>
      'Key under mcpServers in .mcp.json that utakata adds/replaces (default: utakata). '
      'Other keys are kept';
  @override
  String get mcpUrlRequired => '--mcp=http requires --mcp-url <url>.';
  @override
  String mcpUrlNeedsHttp(String transport) =>
      '--mcp-url can only be used with --mcp=http (got --mcp=$transport).';
  @override
  String mcpHeaderNeedsHttp(String transport) =>
      '--mcp-header can only be used with --mcp=http (or --mcp-url) '
      '(got --mcp=$transport).';
  @override
  String mcpHeaderInvalid(String header) =>
      "--mcp-header must be in the form 'Name: value': $header";
  @override
  String get mcpNameWithNone =>
      '--mcp-name cannot be used with --mcp=none (.mcp.json is not touched).';
  @override
  String get mcpNameEmpty => '--mcp-name is empty.';
  @override
  String get claudeInitMcpNone =>
      '--mcp=none: .mcp.json is left untouched (--only mcp does nothing).';
  @override
  String get optUpdateRef => 'Re-resolve the ref and update';
  @override
  String get optExpandDryRun => 'Show the result without writing';
  @override
  String get optExpandFeature => 'Limit to a single feature';
  @override
  String get optJsonOutput => 'Output as JSON';
  @override
  String get optArchAuto => 'Resolved from utakata.yaml / plan.yaml when omitted';
  @override
  String get optImportList => 'List this project\'s sessions';
  @override
  String get optImportSession => 'Import the session with this id (prefix match)';
  @override
  String get optImportLast => 'Import the most recent session';
  @override
  String get optImportFull =>
      'Include thinking / tool_use as well (tool_result is always excluded)';
  @override
  String get optSkipConfirm => 'Skip the confirmation prompt';
  @override
  String get optMigrate => 'Migrate the legacy layout to the current one';
  @override
  String get optFeatureTemplate => 'Apply a feature preset template by id';
  @override
  String get optLogAt => 'e.g. "6/30 17:41" (defaults to now)';

  // ─── feature --template (v1.0) ───
  @override
  String get missingTemplateId => 'Please specify a template ID';
  @override
  String templateNotFound(String id) => 'Template "$id" was not found';
  @override
  String templateApplied(String id, String featureName) =>
      '✅ Applied template "$id": $featureName';
}

