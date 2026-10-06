import 'cli_messages.dart';

/// 日本語メッセージ実装
class JaMessages implements CliMessages {
  const JaMessages();

  // ─── コマンド description ───
  @override
  String get cmdCreateDesc => 'Flutter プロジェクトを新規作成する';
  @override
  String get cmdFeatureDesc => 'フィーチャーを追加する';
  @override
  String get cmdFeatureAddDesc => 'フィーチャーを 1 件追加する';
  @override
  String get cmdFeatureInitDesc => 'plan_architecture.yaml から全フィーチャーを一括生成する';
  @override
  String get cmdPlanDesc => 'plan.yaml(意図レベル計画)の操作コマンド群';
  @override
  String get cmdScanDesc => '現在のディレクトリ構造をスキャンして YAML に保存する';
  @override
  String get cmdDiffDesc => 'check への永続エイリアス(plan.yaml と実構造の差分検証)';
  @override
  String get cmdCheckDesc => 'アーキテクチャの健全性チェックを行う（差分があれば exit 1）';
  @override
  String get cmdImportsDesc =>
      'import の健全性を監査する（アーキテクチャ定義の import_rules に基づく。違反があれば exit 1）';
  // ─── message (v1.6.0) ───
  @override
  String get cmdMessageDesc => 'クライアントとの送受信原文を記録する(log の要約とは別系統)';
  @override
  String get cmdMessageAddDesc => '送受信メッセージを1件記録する(本文は引数か stdin)';
  @override
  String get cmdMessageImportDesc => '既存のやり取りを一括取り込みする(重複は自動でスキップ)';
  @override
  String get cmdMessageListDesc => '記録済みメッセージの一覧を表示する';
  @override
  String get cmdMessageShowDesc => '指定 ID のメッセージ全文を表示する';
  @override
  String get cmdMessageRenderDesc =>
      'doc/preview/messages/ に月別プレビューを再生成する';
  @override
  String get cmdMessageLinkDesc => 'メッセージに要約ログ・合意への参照を付ける';
  @override
  String get optMessageDirection => '向き(inbound=受信 / outbound=送信)';
  @override
  String get optMessageChannel => 'やり取りの経路(client_portal / mail / chatwork 等)';
  @override
  String get optMessageFrom => '送信者';
  @override
  String get optMessageTo => '宛先';
  @override
  String get optMessageSubject => '件名';
  @override
  String get optMessageThread => 'スレッド名(関連するやり取りをまとめる)';
  @override
  String get optMessageExternalId => '取り込み元での ID(再取り込み時の重複排除に使う)';
  @override
  String get optMessageAttachment => '添付ファイルのパス(複数指定可)';
  @override
  String get optMessageFormat => '取り込み元の形式(jsonl|md)';
  @override
  String get optMessageFile => '取り込むファイル(省略時は stdin)';
  @override
  String get optMessageMonth => '対象月(YYYY-MM)';
  @override
  String get optMessageLogRef => '紐付ける会話ログの ID';
  @override
  String get optMessageAgreementRef => '紐付ける合意の ID';
  @override
  String get messageDirectionRequired =>
      '--direction を指定してください(inbound=受信 / outbound=送信)';
  @override
  String get messageBodyRequired =>
      '本文を指定してください: utakata message add -d inbound "本文..." もしくは stdin から渡してください';
  @override
  String get messageIdRequired => 'メッセージ ID を指定してください(utakata message list で確認)';
  @override
  String get messageImportSourceRequired =>
      '--file を指定するか、stdin から取り込み元を渡してください';
  @override
  String get messageImportNothingParsed =>
      '取り込めるメッセージが1件もありませんでした。形式(--format)と'
      '見出し(例: "## [inbound] 2026-08-11 10:24 山田様")を確認してください。';
  @override
  String get messageLinkTargetRequired => '--log か --agreement のどちらかを指定してください';
  @override
  String get messageListEmpty => '記録されたメッセージがありません。';
  @override
  String messageAddDone(String id) => '記録しました: $id';
  @override
  String messageAddDuplicate(String id) =>
      '同じ external_id の記録が既にあります($id)。追記しませんでした。';
  @override
  String messageImportDone(int imported, int skipped) =>
      '取り込みました: $imported 件(重複スキップ: $skipped 件)';
  @override
  String messageImportDryRun(int imported, int skipped) =>
      '[DRY] 取り込み予定: $imported 件(重複スキップ: $skipped 件)';
  @override
  String messageRenderDone(int months) =>
      'doc/preview/messages/ に $months か月分を生成しました';
  @override
  String messageLinkDone(String id) => '参照を追加しました: $id';
  @override
  String messageNotFound(String id) => 'メッセージ "$id" が見つかりません。';
  @override
  String messageFileNotFound(String path) => 'ファイルが見つかりません: $path';

  @override
  String importsSection(String archId) =>
      '🔎 utakata imports — import 監査 ($archId)';
  @override
  String importsNoRules(String archId) =>
      'アーキテクチャ "$archId" に import_rules が定義されていません。'
      '監査するには arch_definition.yaml に import_rules を追加してください。';
  @override
  String importsClean(int audited, int excluded) =>
      'import 違反はありません(監査 $audited ファイル、除外 $excluded)';
  @override
  String importsViolationSummary(int count, int audited, int excluded) =>
      '$count 件の import 違反(監査 $audited ファイル、除外 $excluded)';
  @override
  String importsInternalViolation(String from, String to, String allow) =>
      '「$from」から「$to」への import は許可されていません(allow: $allow)';
  @override
  String importsExternalViolation(String pattern, String pkg, String deny) =>
      '「$pattern」では $pkg の import が禁止されています(deny: $deny)';
  @override
  String importsPlacementViolation(String pkg, String layers) =>
      '$pkg の使用が宣言されているのは次の層のみです: $layers';
  @override
  String get cmdStatusDesc => 'プロジェクトの現在の状態を総合表示する';
  @override
  String get cmdRunnerDesc => '仕様駆動開発を支援する Flutter CLI ツール';

  // ─── コマンドランナー ───
  @override
  String get versionHelp => 'バージョンを表示する';

  // ─── オプション help ───
  @override
  String get optOrg => 'パッケージ組織名 (例: com.example)';
  @override
  String get optPlatforms => '対象プラットフォーム (カンマ区切り)';
  @override
  String get optDescription => 'プロジェクトの説明';
  @override
  String get optArch => '使用するアーキテクチャ (例: clean_architecture)';
  @override
  String get optEntity => 'エンティティ名（省略時はフィーチャー名と同じ）';
  @override
  String get optPermission => '権限レベル';
  @override
  String get optYes => '確認プロンプトをスキップ';
  @override
  String get optDryRun => '実際には生成せず対象を確認するだけ';
  @override
  String get optBrief => '軽量モード(flutter analyze/version を呼ばない)';
  @override
  String get optWriteReport => 'project_status.yaml/md を更新する';

  // ─── Logger.section ───
  @override
  String sectionCreate(String name) => '🚀 utakata create — $name';
  @override
  String get sectionPlan => '📝 utakata plan — 計画ファイルの生成';
  @override
  String get sectionScan => '📸 utakata scan — 実績スナップショット生成';
  @override
  String get sectionDiff => '⚖️ utakata diff — アーキテクチャ差分検証';
  @override
  String get sectionCheck => '🔍 utakata check — アーキテクチャ検証';
  @override
  String get sectionStatus => '📊 utakata status — プロジェクト状態確認';
  @override
  String sectionFeatureAdd(String name) => '✨ utakata feature add — $name';
  @override
  String sectionFeatureInit(bool dryRun) =>
      '🚀 utakata feature init${dryRun ? ' (dry-run)' : ''}';

  // ─── 共通 ───
  @override
  String get cancel => 'キャンセルしました。';

  // ─── エラー入力 ───
  @override
  String get missingAppName => 'アプリ名を指定してください。例: utakata create my_app';
  @override
  String get missingFeatureName =>
      'フィーチャー名を指定してください。例: utakata feature add memo';
  @override
  String confirmGenerate(String path) => '"$path" に生成しますか？ (y/N)';
  @override
  String projectCreated(String name) => '✅ プロジェクト "$name" を生成しました！';

  // ─── plan ───
  @override
  String get planMissingFeaturesKey =>
      'feature_request.yaml に features キーがありません。';
  @override
  String planDone(int count) => '計画書を生成しました（$count フィーチャー）';

  // ─── feature add ───
  @override
  String featureAddPath(String path) => '  パス: $path';
  @override
  String featureAddDone(String name) => 'フィーチャー "$name" を生成しました！';
  @override
  String get featureAddCancel => 'キャンセルしました。';

  // ─── feature init ───
  @override
  String get featureInitNone => '生成対象のフィーチャーが見つかりませんでした。';
  @override
  String featureInitDone(int count) => '$count 件のフィーチャーを生成しました！';
  @override
  String featureDryRunRow(String path) => '[DRY] $path';

  // ─── scan ───
  @override
  String get scanDone => 'スナップショットを生成しました';

  // ─── diff ───
  @override
  String get diffClean => '差分なし！ 計画と実績が完全に一致しています。';
  @override
  String diffSummary(int missing, int extra) => 'Missing: $missing, Extra: $extra';
  @override
  String get diffMissingHeader => 'Missing（計画にあるが未実装）:';
  @override
  String get diffExtraHeader => 'Extra（実績にあるが計画外）:';

  // ─── check ───
  @override
  String get checkOk => 'アーキテクチャは健全です！';
  @override
  String get checkFail =>
      'アーキテクチャに問題があります。utakata diff で詳細を確認してください。';
  @override
  String checkMissingRow(String path) => '[Missing] $path';

  // ─── status ───
  @override
  String get statusFlutterVersionHeader => '--- Flutter Version ---';
  @override
  String get statusLintHeader => '--- Lint Analysis ---';
  @override
  String get statusLintOk => '問題なし';
  @override
  String get statusArchHeader => '--- Architecture Diff ---';
  @override
  String get statusNoPlan =>
      'plan_architecture.yaml が見つかりません。utakata plan を先に実行してください。';
  @override
  String get statusDiffClean => '計画と実績が一致しています！';

  // ─── エラー ───
  @override
  String featureRequestNotFound(String path) =>
      '$path が見つかりません。仕様書を作成してください。';
  @override
  String planNotFound(String path) =>
      '$path が見つかりません。先に utakata plan を実行してください。';
  @override
  String currentStructureNotFound(String path) =>
      '$path が見つかりません。先に utakata scan を実行してください。';
  @override
  String notFlutterProject(String dir) =>
      '$dir は Flutter プロジェクトではありません。プロジェクトのルートで実行してください。';
  @override
  String get flutterNotFound =>
      'flutter コマンドが見つかりません。'
      'FLUTTER_PATH 環境変数にフルパスを設定してください。'
      '例: export FLUTTER_PATH=/path/to/flutter/bin/flutter';
  @override
  String yamlParseFailed(String path) => '$path の YAML 解析に失敗しました。';
  @override
  String get flutterCreateFailed => 'flutter create に失敗しました。';
  @override
  String get buildRunnerFailed => 'build_runner の実行に失敗しました。';

  // ─── add_feature_usecase ───
  @override
  String layerDirCreateFailed(String path) => 'ディレクトリの作成に失敗しました: $path';
  @override
  String templateExpandFailed(String path) => 'テンプレートの展開に失敗しました: $path';

  // ─── validate ───
  @override
  String get cmdValidateDesc =>
      '命名規則とディレクトリ構造の違反を検出する';
  @override
  String get sectionValidate => '🔎 utakata validate — 命名規則・構造検証';
  @override
  String get validateOk => '命名規則・ディレクトリ構造ともに問題ありません！';
  @override
  String get validateNamingHeader => '【命名規則違反】';
  @override
  String get validateStructureHeader => '【ディレクトリ構造違反】';
  @override
  String validateNamingViolation(String file, String expected) =>
      '  ❌ $file\n     期待: $expected';
  @override
  String validateMissingDir(String path) => '  Missing: $path';
  @override
  String validateExtraDir(String path) => '  Extra:   $path';
  @override
  String validateSummary(int naming, int missing, int extra) =>
      '命名違反: $naming 件 / Missing: $missing 件 / Extra: $extra 件';

  // ─── arch subcommands ───
  @override
  String get cmdArchDesc => 'アーキテクチャの確認・エクスポート・カスタム作成を行う';
  @override
  String get cmdArchListDesc => '利用可能なアーキテクチャ定義の一覧を表示する';
  @override
  String get cmdArchShowDesc => '指定したアーキテクチャの定義、命名規則、および層構造のツリーを表示する';
  @override
  String get cmdArchExportDesc => '指定したアーキテクチャ定義の生 YAML ファイルをエクスポートする';
  @override
  String get cmdArchCreateDesc => 'プロジェクトのローカルにカスタムアーキテクチャ定義のボイラープレートを作成する';
  @override
  String get archListHeader => '利用可能なアーキテクチャ定義一覧:';
  @override
  String archShowHeader(String id, String name) => '🏛️ アーキテクチャ: $name ($id)';
  @override
  String get archShowLayers => '【レイヤー構造 (Layers)】';
  @override
  String get archShowNamingRules => '【命名規則 (Naming Rules)】';
  @override
  String archExportSuccess(String id, String path) => '✅ アーキテクチャ "$id" の定義を "$path" にエクスポートしました！';
  @override
  String archCreateSuccess(String id, String path) => '✅ ローカルアーキテクチャ定義のボイラープレートを "$path" に作成しました！';
  @override
  String architectureAlreadyExists(String path) => '❌ エラー: アーキテクチャ定義がすでに存在します: $path';
  @override
  String get missingArchitectureId => 'アーキテクチャ ID を指定してください。例: utakata arch show clean_architecture';
  @override
  String get missingOutputPath => 'エクスポート先のパスを指定してください。例: utakata arch export clean_architecture temp.yaml';

  // ─── その他エラー ───
  @override
  String guideGenerationFailed(String error) => 'ガイド生成に失敗しました: $error';
  @override
  String templatePathResolveFailed(String path) => 'パッケージテンプレートのパス解決に失敗しました: $path';

  // ─── core ───
  @override
  String get cmdCoreDesc => 'Core ディレクトリ構造を生成する';
  @override
  String get sectionCore => '🏗️ utakata core — Core ディレクトリ生成';
  @override
  String coreDone(int count) => '✅ $count 件の Core モジュールディレクトリを生成しました！';
  @override
  String coreModuleRow(String path) => '  ✅ $path';

  // ─── check (v0.7) ───
  @override
  String get optJson => 'JSON 形式で出力する';
  @override
  String get optFile => '指定したパス配下の違反のみに絞り込む';
  @override
  String get namingViolationsHeader => '⚠️ 命名規則違反:';
  @override
  String get checkClean => '✅ 構造は計画と一致しています(違反なし)';
  @override
  String checkSummary(int missing, int extra, int naming) =>
      '⚠️ missing: $missing / extra: $extra / naming violations: $naming';
  @override
  String deprecatedAlias(String oldCmd, String newCmd) =>
      '⚠️  `utakata $oldCmd` は非推奨です。`utakata $newCmd` を使用してください。';

  // ─── apply (v0.7) ───
  @override
  String get cmdApplyDesc => 'plan.yaml から未生成の feature/core を生成する';
  @override
  String get optScope => '生成範囲(all|feature|core)';
  @override
  String get sectionApply => '🏗️ utakata apply — 構造の生成';
  @override
  String applyFeatureRow(String path) => '  ✅ $path';
  @override
  String applyFileRow(String path) => '  📄 $path';
  @override
  String applyFilesDone(int fileCount) =>
      '📄 空ファイルを $fileCount 件生成しました(既存ファイルは変更していません)';
  @override
  String applyDone(int featureCount, int coreCount) =>
      '✅ feature: $featureCount 件、core: $coreCount 件を生成しました';
  @override
  String get applyNothingToDo => '生成対象がありません(plan.yaml が見つからないか、空です)';

  // ─── plan adopt (v0.7) ───
  @override
  String get cmdPlanAdoptDesc => '未計画の feature を検出し plan.yaml へ追記する';
  @override
  String get sectionPlanAdopt => '🔍 utakata plan adopt — 未計画 feature の検出';
  @override
  String get adoptNoneFound => '未計画の feature は見つかりませんでした';
  @override
  String adoptCandidateRow(String permission, String name) => '  - $permission/$name';
  @override
  String adoptConfirm(String permission, String name) =>
      '"$permission/$name" を plan.yaml に追記しますか？ [y/N] ';
  @override
  String adoptDone(int count) => '✅ $count 件の feature を plan.yaml に追記しました';

  // ─── doc init (v0.8) ───
  @override
  String get cmdDocDesc => 'doc/ 案件ワークスペース操作コマンド群';
  @override
  String get cmdDocInitDesc => 'doc/ 案件ワークスペースを先行作成する(契約前フェーズ用)';
  @override
  String get docInitDone => '✅ doc/ ワークスペースを作成しました';
  @override
  String get docInitAlreadyExists => 'doc/ は既に存在します';

  // ─── log (v0.8) ───
  @override
  String get cmdLogDesc => 'お客様会話ログの構造化記録(人間専用)';
  @override
  String get cmdLogAddDesc => '会話ログを1件追記する';
  @override
  String get cmdLogShowDesc => '会話ログを表示する';
  @override
  String get cmdLogRenderDesc => '会話ログの Markdown プレビューを再生成する';
  @override
  String logAddDone(String id) => '✅ $id を記録しました';
  @override
  String get logShowEmpty => '該当する会話ログが見つかりませんでした';
  @override
  String get logRenderDone => '✅ プレビューを再生成しました';

  // ─── agree (v0.9) ───
  @override
  String get cmdAgreeDesc => '合意トラッキング(お客様合意・内部決定)';
  @override
  String get cmdAgreeAddDesc => '合意を1件追記する';
  @override
  String get cmdAgreeListDesc => '合意の一覧を表示する';
  @override
  String get cmdAgreeStatusDesc => '合意の状態を更新する';
  @override
  String agreeAddDone(String id) => '✅ $id を記録しました';
  @override
  String get agreeListEmpty => '合意が記録されていません';
  @override
  String agreeStatusDone(String id, String status) => '✅ $id の状態を $status に更新しました';

  // ─── impl (v0.9) ───
  @override
  String get cmdImplDesc => 'feature 実装計画の管理';
  @override
  String get cmdImplNewDesc =>
      '実装計画書を新規作成する([kind:]<target>。kind は feat|fix|refactor|docs|chore|test、省略時 feat)';
  @override
  String get cmdImplListDesc => '実装計画の一覧を表示する';
  @override
  String get cmdImplDoneDesc => '実装計画を完了にする';
  @override
  String get cmdImplArchiveDesc => '完了済みの実装計画を archive/ へ移動する';
  @override
  String implNewDone(String id, String path) => '✅ $id を作成しました: $path';
  @override
  String get implListEmpty => '実装計画が見つかりませんでした';
  @override
  String implDoneDone(String id) => '✅ $id を完了にしました';
  @override
  String implArchiveDone(String id) => '✅ $id を archive/ へ移動しました';

  // ─── impl の2軸ライフサイクル (v1.7.0) ───
  @override
  String get cmdImplStartDesc => '実装を開始する(status: in_progress)';
  @override
  String get cmdImplReviewDesc => '自分のレビュー段階へ進める(status: review)';
  @override
  String get cmdImplBoardDesc =>
      'レーン別のボードを表示し doc/preview/impl_board.md を再生成する';
  @override
  String get cmdImplTestDesc => '検証軸の状態を進める(start|review|done|todo|skip)';
  @override
  String cmdImplTestTransitionDesc(String name) {
    switch (name) {
      case 'start':
        return 'テストを開始する(test: in_progress)';
      case 'review':
        return 'テスト結果のレビューへ進める(test: review)';
      case 'done':
        return 'テスト完了にする(test: done)';
      case 'todo':
        return 'テスト未着手へ戻す(test: todo)';
      default:
        return 'テスト不要と明示する(test: not_required)';
    }
  }
  @override
  String get cmdImplSyncDesc => 'frontmatter に合わせてファイルの配置を是正する';
  @override
  String get optImplStatus => '実装の状態で絞る(todo|in_progress|review|done|archived)';
  @override
  String get optImplTest =>
      '検証の状態で絞る(not_required|todo|in_progress|review|done)';
  @override
  String get optImplLane => 'レーン(ディレクトリ名)で絞る';
  @override
  String get optImplSkipReason => 'テスト不要とする理由';
  @override
  String get implFeatureRequired =>
      '対象を指定してください: utakata impl new [kind:]<target>'
      '(例: login / refactor:doc_layout)';
  @override
  String get implIdRequired => '実装計画 ID を指定してください(utakata impl list で確認)';
  @override
  String implUnknownLane(String given, String known) =>
      'レーン "$given" は存在しません。指定できるのは: $known';
  @override
  String implTransitionDone(String id, String status, String test) =>
      '$id: status=$status / test=$test';
  @override
  String implMovedTo(String path) => '移動: $path';
  @override
  String implBoardDone(String path) => 'ボードを再生成しました: $path';
  @override
  String get implSyncClean => '配置は frontmatter と一致しています。';
  @override
  String implSyncDryRun(int count) => '[DRY] $count 件を移動します';
  @override
  String implSyncDone(int count) => '$count 件を正しいレーンへ移動しました';
  @override
  String implSyncBlocked(String id, String destination) =>
      '$id: 移動先 $destination に別のファイルがあるため移動しませんでした'
      '(上書きすると内容が失われます。重複を解消してください)';
  @override
  String implScanUnreadable(int count, String samples) =>
      '実装計画 $count 件の frontmatter が読めません($samples)。'
      '一覧・採番から外れるため、書式を直すか退避してください。';
  @override
  String implScanDuplicates(int count, String samples) =>
      '同じ ID を持つ実装計画が $count 組あります($samples)。'
      '移動・更新ができないので、どちらかを削除・改番してください。';
  @override
  String implPlanRequired(String feature) =>
      'feature "$feature" には実装計画がありません(enforcement.impl_plan: on)。'
      '`utakata impl new $feature` で作成してください。';
  @override
  String implPlanMissingForCode(int count, String samples) =>
      '実装があるのに実装計画が無い feature が $count 件あります($samples)。'
      '`utakata impl new <feature>` で作成できます。';
  @override
  String implPlansMisplaced(int count, String samples) =>
      '実装計画 $count 件が frontmatter と違うレーンにあります($samples)。'
      '`utakata impl sync` で是正できます。';
  @override
  String staleGeneratedSkill(String skillId) =>
      '.claude/skills/$skillId/SKILL.md が古いバージョンのままです'
      '(claude init は既存ファイルを上書きしません)。'
      '`utakata claude init --force` で再生成してください。';


  // ─── summary (v0.9) ───
  @override
  String get cmdSummaryDesc => '案件整理サマリーのマーカー区間を再生成する';
  @override
  String get summaryRenderDone => '✅ summary.md のマーカー区間を再生成しました';

  // ─── guide (v1.0) ───
  @override
  String get cmdGuideDesc => '参照型ナレッジ(GUIDE 等)の閲覧・カスタム開始';
  @override
  String get cmdGuideListDesc => '利用可能なガイドの一覧を表示する';
  @override
  String get cmdGuideShowDesc => 'ガイドの内容を表示する';
  @override
  String get cmdGuideEjectDesc => 'ガイドをローカルへ書き出しカスタムを開始する';
  @override
  String get guideListEmpty => 'ガイドが見つかりませんでした';
  @override
  String guideEjectDone(String id, String path) => '✅ $id を書き出しました: $path';
  @override
  String get missingGuideId => 'ガイド ID を指定してください';

  // ─── doctor (v1.0) ───
  @override
  String get cmdDoctorDesc => '環境・スキーマ・レイアウトの診断と移行';
  @override
  String get doctorOk => '✅ 問題は見つかりませんでした';
  @override
  String doctorIssueRow(String message) => '  ⚠️ $message';
  @override
  String get doctorMigrateNoneFound => '移行対象が見つかりませんでした';
  @override
  String doctorMigrateDone(int count) => '✅ $count 件を移行しました';

  // ─── mcp (v1.1) ───
  @override
  String get cmdMcpDesc => 'MCP サーバーを起動する(stdio・読み取り専用)';

  @override
  String get cmdClaudeDesc => 'Claude Code 統合(.claude/・.mcp.json・CLAUDE.md)の生成・補修';
  @override
  String get cmdClaudeInitDesc =>
      '.claude/(スキル・エージェント・settings)+ .mcp.json + CLAUDE.md を生成する。'
      '既定は欠けているファイルのみ補修(既存は保護)。--force で再生成';
  @override
  String get cmdSkillsDesc => 'アーキテクチャ同梱 SKILL を .claude/skills/ へ同期する';
  @override
  String get cmdSkillsSyncDesc =>
      'utakata.yaml の skills リストを .claude/skills/ に同期する(managed マーカー方式)';
  @override
  String get cmdVaultDesc => '実務ナレッジ Vault(クライアント説明用の外部サービス知識)を参照する';
  @override
  String get cmdVaultListDesc => 'Vault のエントリ一覧を表示する';
  @override
  String get cmdVaultShowDesc => 'Vault のエントリ本文を表示する: vault show Google/GCP/Firebase';
  @override
  String get cmdVaultGetDesc => '設定された url から Vault を取得(再取得)してキャッシュする';
  @override
  String get cmdDocShowDesc => '設定ファイルの書き方を表示する: doc show config|plan(一覧は doc list)';
  @override
  String get cmdDocListDesc => '表示できるドキュメントのトピック一覧';
  @override
  String get cmdPlanExpandDesc =>
      '自動導出されている層構成を plan.yaml に明示的に書き出す(以後は手動で増減できる)';
  @override
  String get cmdPlanAddDesc =>
      'plan.yaml の feature に層の項目を追加する: plan add <feature> <layer> <item...>';
  @override
  String get cmdPlanRemoveDesc =>
      'plan.yaml の feature から層の項目を削除する: plan remove <feature> <layer> <item>';
  @override
  String get cmdGuideForDesc =>
      'ファイルパスから該当レイヤーのガイドを決定論的に解決する(lint エラー修正のコンテキスト供給用)';
  @override
  String get cmdArchGetDesc =>
      'ナレッジリポジトリをフェッチする(knowledge_repo 未指定なら公式 utakata_arch_lib を取得)';
  @override
  String get cmdAgreeCorrectDesc => '過去の合意を訂正する(supersede)';
  @override
  String get cmdAgreeReflectDesc => '合意の反映先(実装計画/仕様書)を記録する';
  @override
  String get cmdLogImportDesc =>
      'Claude Code セッション生ログを doc/records/sessions/ に取り込む(人間専用)';

  @override
  String get optForceOverwrite =>
      '人間が編集した managed ファイルも上書きする(マーカーの無いファイルは対象外)';
  @override
  String get optForceRegenerate => '既存ファイル(CLAUDE.md 含む)も上書きして再生成する';
  @override
  String get optUpdateRef => 'ref を再解決して更新する';
  @override
  String get optExpandDryRun => '書き込まずに結果だけ表示する';
  @override
  String get optExpandFeature => '対象の feature を1つに限定する';
  @override
  String get optJsonOutput => 'JSON で出力する';
  @override
  String get optArchAuto => '未指定なら utakata.yaml / plan.yaml から解決する';
  @override
  String get optImportList => 'このプロジェクトのセッション一覧を表示する';
  @override
  String get optImportSession => 'セッション ID(先頭一致可)を指定して取り込む';
  @override
  String get optImportLast => '最新のセッションを取り込む';
  @override
  String get optImportFull => 'thinking / tool_use も含める(tool_result は常に除外)';
  @override
  String get optSkipConfirm => '確認プロンプトをスキップする';
  @override
  String get optMigrate => '旧レイアウトから新レイアウトへ移行する';
  @override
  String get optFeatureTemplate => 'feature プリセットテンプレート ID を適用する';
  @override
  String get optLogAt => '例: "6/30 17:41"(省略時は現在時刻)';

  // ─── feature --template (v1.0) ───
  @override
  String get missingTemplateId => 'テンプレート ID を指定してください';
  @override
  String templateNotFound(String id) => 'テンプレート "$id" が見つかりませんでした';
  @override
  String templateApplied(String id, String featureName) =>
      '✅ テンプレート "$id" を適用しました: $featureName';
}

