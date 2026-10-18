import '../2_repositories/config_repository.dart';
import '../2_repositories/impl_plan_repository.dart';
import '../2_repositories/plan_repository.dart';
import '../messages/cli_messages.dart';

/// 1件の移行操作を表す(dry-run 表示・実行ログ共用)。
class MigrationAction {
  final String description;
  final bool automated;

  const MigrationAction(this.description, {this.automated = true});
}

/// `utakata doctor` — 環境・レイアウトの診断と移行。
///
/// 移行対象は構造計画書 §6 の変換表のうち、自動化が安全なものに限定する
/// (案件整理サマリーの合意抽出・アーキテクチャ定義の override 判定等、
/// 人間の確認が前提のものは情報提示のみに留める)。
class DoctorUsecase {
  final PlanRepository _planRepo;
  final ConfigRepository? _configRepo;

  final bool Function(String path) _fileExists;
  final bool Function(String path) _dirExists;
  final Future<String?> Function(String path) _readFile;
  final Future<void> Function(String path) _deleteFile;
  final Future<void> Function(String path) _deleteDir;
  final Future<void> Function(String from, String to) _movePath;
  final List<String> Function(String dirPath) _listEntries;
  final List<String> Function(String dirPath, String fileName)? _listFilesNamed;

  /// 実装計画のレーン乖離・未作成を診断するための注入(v1.7.0)。
  /// 未注入なら該当の診断を行わない。
  final Future<Map<String, ({String actual, String expected})>> Function(
      String projectDir)? _detectMisplacedPlans;
  final Future<Set<String>?> Function(String projectDir)? _featuresWithImplPlan;
  final Future<ImplScanResult> Function(String projectDir)? _scanImplPlans;

  /// 凍結後に計画部分が書き換えられたまま受理されていない計画(v1.8.0)。
  final Future<List<String>> Function(String projectDir)? _driftedImplPlans;
  final CliMessages? _msg;

  const DoctorUsecase({
    required PlanRepository planRepo,
    ConfigRepository? configRepo,
    required bool Function(String path) fileExists,
    required bool Function(String path) dirExists,
    required Future<String?> Function(String path) readFile,
    required Future<void> Function(String path) deleteFile,
    required Future<void> Function(String path) deleteDir,
    required Future<void> Function(String from, String to) movePath,
    required List<String> Function(String dirPath) listEntries,
    List<String> Function(String dirPath, String fileName)? listFilesNamed,
    Future<Map<String, ({String actual, String expected})>> Function(
            String projectDir)?
        detectMisplacedPlans,
    Future<Set<String>?> Function(String projectDir)? featuresWithImplPlan,
    Future<ImplScanResult> Function(String projectDir)? scanImplPlans,
    Future<List<String>> Function(String projectDir)? driftedImplPlans,
    CliMessages? msg,
  })  : _planRepo = planRepo,
        _configRepo = configRepo,
        _fileExists = fileExists,
        _dirExists = dirExists,
        _readFile = readFile,
        _deleteFile = deleteFile,
        _deleteDir = deleteDir,
        _movePath = movePath,
        _listEntries = listEntries,
        _listFilesNamed = listFilesNamed,
        _detectMisplacedPlans = detectMisplacedPlans,
        _featuresWithImplPlan = featuresWithImplPlan,
        _scanImplPlans = scanImplPlans,
        _driftedImplPlans = driftedImplPlans,
        _msg = msg;

  /// 診断のみ行う(環境チェック + utakata.yaml スキーマ検証)。
  Future<List<String>> diagnose(String projectDir) async {
    final issues = <String>[];
    if (!_fileExists('$projectDir/utakata.yaml') &&
        !_fileExists('$projectDir/doc/specs/plan.yaml') &&
        !_fileExists('$projectDir/AI/specs/feature_request.yaml')) {
      issues.add('doc/specs/plan.yaml も旧 feature_request.yaml も見つかりません。'
          '`utakata doc init` で doc/ ワークスペースを作成してください。');
    }
    final configRepo = _configRepo;
    if (configRepo != null) {
      issues.addAll(await configRepo.validate(projectDir));
    }

    // v1.4.0(Issue #13)で GUIDE.md の生成を廃止したため、過去の apply が
    // 撒いた残存 GUIDE.md を情報として報告する(手編集の可能性があるため
    // 自動削除はしない)。
    final listFilesNamed = _listFilesNamed;
    if (listFilesNamed != null) {
      final guides = listFilesNamed('$projectDir/lib/features', 'GUIDE.md');
      if (guides.isNotEmpty) {
        issues.add('lib/features/ 配下に GUIDE.md が ${guides.length} 件あります。'
            'v1.4.0 から生成されなくなりました(ガイドは `utakata guide for <file>` で参照)。'
            '編集していなければ削除して問題ありません。');
      }
    }

    // v1.6.0 で status の出力先を doc/preview/ へ移した。旧出力が残っていれば
    // 案内する(すべて導出可能な生成物なので削除して構わない)。
    if (_dirExists('$projectDir/AI/snapshots')) {
      issues.add('AI/snapshots/ が残っています。v1.6.0 から '
          'doc/preview/project_status.{yaml,md} に出力先が変わりました。'
          'すべて導出可能な生成物なので削除して構いません'
          '(`utakata doctor --migrate` でも削除できます)。');
    }

    // utakata.yaml が壊れていても診断結果ごと失わない
    // (壊れている事実は configRepo.validate が既に報告している)。
    try {
      issues.addAll(await _diagnoseImplPlans(projectDir));
    } catch (_) {
      // 実装計画を読めない場合はその診断だけ諦める
    }
    try {
      issues.addAll(await _diagnoseRecordsPolicy(projectDir));
      issues.addAll(await _diagnoseGeneratedSkills(projectDir));
    } catch (_) {
      // 設定を読めない場合はポリシー診断だけ諦める
    }
    return issues;
  }

  /// 実装計画(v1.7.0)の診断:
  ///   - frontmatter とレーン(ディレクトリ)の乖離
  ///   - 実装があるのに計画が無い feature(CLI で止められない経路の補完)
  Future<List<String>> _diagnoseImplPlans(String projectDir) async {
    final issues = <String>[];
    final msg = _msg;

    // 読めない計画・重複 ID は「静かに消える」ため必ず報告する
    final scan = _scanImplPlans;
    if (scan != null && msg != null) {
      final result = await scan(projectDir);
      if (result.unreadable.isNotEmpty) {
        issues.add(msg.implScanUnreadable(
            result.unreadable.length, _sample(result.unreadable)));
      }
      if (result.duplicates.isNotEmpty) {
        issues.add(msg.implScanDuplicates(
            result.duplicates.length, _sample(result.duplicates.keys)));
      }
    }

    final detect = _detectMisplacedPlans;
    if (detect != null && msg != null) {
      final misplaced = await detect(projectDir);
      if (misplaced.isNotEmpty) {
        issues.add(
            msg.implPlansMisplaced(misplaced.length, _sample(misplaced.keys)));
      }
    }

    // 凍結後の書き換えは遷移時に止まるが、遷移しないまま放置されると
    // 誰も気づかないので、ここで報告する
    final drifted = _driftedImplPlans;
    if (drifted != null && msg != null) {
      final ids = await drifted(projectDir);
      if (ids.isNotEmpty) {
        issues.add(msg.implPlansDrifted(ids.length, _sample(ids)));
      }
    }

    final withPlan = _featuresWithImplPlan;
    if (withPlan == null || msg == null) return issues;
    final plan = await _planRepo.read(projectDir);
    if (plan == null) return issues;
    final planned = await withPlan(projectDir);
    if (planned == null) return issues; // ゲート無効時は診断しない
    final missing = [
      for (final feature in plan.features)
        if (!planned.contains(feature.name) &&
            _dirExists('$projectDir/lib/features/'
                '${feature.permission == "direct" ? "" : "${feature.permission}/"}'
                '${feature.name}'))
          feature.name,
    ];
    if (missing.isNotEmpty) {
      issues.add(msg.implPlanMissingForCode(missing.length, _sample(missing)));
    }
    return issues;
  }

  /// 一覧が長くなりすぎないよう先頭数件だけ見せる。
  static String _sample(Iterable<String> values) {
    final list = values.toList();
    final head = list.take(3).join(', ');
    return list.length > 3 ? '$head ほか' : head;
  }

  /// 生成済みスキルが古いバージョンのまま残っていないか。
  ///
  /// `claude init` は既存ファイルを上書きしないため、CLI を上げても
  /// `.claude/skills/` の内容は古いまま残る。AI が古い手順(v1.6.x の
  /// `new → done → archive`)に従い続けるので、明示的に案内する。
  Future<List<String>> _diagnoseGeneratedSkills(String projectDir) async {
    final path = '$projectDir/.claude/skills/utakata-impl-flow/SKILL.md';
    if (!_fileExists(path)) return const [];
    final content = await _readFile(path);
    if (content == null) return const [];
    // v1.7.0 のスキルは必ずレーンと start コマンドに触れている。
    // v1.8.0 のスキルはさらに note(記録の追記)に触れている。
    if (content.contains('impl start') &&
        content.contains('レーン') &&
        content.contains('impl note')) {
      return const [];
    }
    final msg = _msg;
    return [
      msg?.staleGeneratedSkill('utakata-impl-flow') ??
          '.claude/skills/utakata-impl-flow/SKILL.md が古いバージョンのままです。'
              '`utakata claude init --force` で再生成してください。',
    ];
  }

  /// `records.agent_write`(v1.6.0)の設定と、生成済み
  /// `.claude/settings.json` の乖離を検出する。
  ///
  /// `claude init` は既存 settings.json を上書きしないため、設定だけ変えても
  /// 実際の許可は変わらない。この取りこぼしは気づきにくいので明示的に警告する。
  Future<List<String>> _diagnoseRecordsPolicy(String projectDir) async {
    final config = await _configRepo?.read(projectDir);
    if (config == null) return const [];
    final issues = <String>[];

    if (config.recordsAgentWrite == 'full') {
      issues.add('records.agent_write: full が設定されています。AI が '
          'doc/records/ を直接編集できます(クライアント案件では非推奨。'
          '追記だけ許すなら append を使ってください)。');
    }

    final settingsPath = '$projectDir/.claude/settings.json';
    if (!_fileExists(settingsPath)) return issues;
    final settings = await _readFile(settingsPath);
    if (settings == null) return issues;

    // utakata が生成した settings.json でなければ乖離を判定しない
    // (手書きの設定に「--force で再生成せよ」と言うと壊してしまう)。
    final isGenerated = settings.contains('utakata status --brief') ||
        settings.contains('doc/preview/**');
    if (!isGenerated) return issues;

    final denied = settings.contains('"Write(doc/records/**)"');
    final allowsCli = settings.contains('Bash(utakata log add');
    final expectedDenied = config.recordsAgentWrite != 'full';
    final expectedAllowsCli = config.recordsAgentWrite != 'none';

    if (denied != expectedDenied || allowsCli != expectedAllowsCli) {
      issues.add('.claude/settings.json が records.agent_write '
          '(${config.recordsAgentWrite})と一致していません。'
          '`utakata claude init --force` で再生成してください。');
    }
    return issues;
  }

  /// 旧レイアウト・実案件 doc/ 構成物を新レイアウトへ移行する。
  Future<List<MigrationAction>> migrate(String projectDir, {bool dryRun = true}) async {
    final actions = <MigrationAction>[];

    // 1. feature_request.yaml → plan.yaml
    if (!_fileExists('$projectDir/doc/specs/plan.yaml') &&
        _fileExists('$projectDir/AI/specs/feature_request.yaml')) {
      actions.add(const MigrationAction(
          'AI/specs/feature_request.yaml → doc/specs/plan.yaml(schema:1 へ変換)'));
      if (!dryRun) {
        final plan = await _planRepo.read(projectDir);
        if (plan != null) await _planRepo.write(projectDir, plan);
      }
    }

    // 2. 導出可能な生成物の削除
    for (final path in [
      'AI/specs/plan_architecture.yaml',
      'AI/snapshots',
    ]) {
      final full = '$projectDir/$path';
      if (_fileExists(full) || _dirExists(full)) {
        actions.add(MigrationAction('$path → 削除(導出可能な生成物のため)'));
        if (!dryRun) {
          if (_dirExists(full)) {
            await _deleteDir(full);
          } else {
            await _deleteFile(full);
          }
        }
      }
    }

    // 3. AI/logs/conversation_log.md → doc/impl/research/ (内容があれば) or 削除
    final logPath = '$projectDir/AI/logs/conversation_log.md';
    if (_fileExists(logPath)) {
      final content = await _readFile(logPath);
      final hasContent = content != null && content.trim().length > 200;
      // テンプレートの雛形(見出しのみ)は 200 文字未満に収まらないため、
      // 実質的な会話履歴が追記されているかの簡易判定として長さを使う。
      if (hasContent) {
        actions.add(const MigrationAction(
            'AI/logs/conversation_log.md → doc/impl/research/conversation_log.md(内容ありのため移設)'));
        if (!dryRun) {
          await _movePath(logPath, '$projectDir/doc/impl/research/conversation_log.md');
        }
      } else {
        actions.add(const MigrationAction('AI/logs/conversation_log.md → 削除(空テンプレートのため)'));
        if (!dryRun) await _deleteFile(logPath);
      }
    }

    // 4. 実案件 doc/log/raw/*.md → doc/records/log/legacy/
    final rawDir = '$projectDir/doc/log/raw';
    if (_dirExists(rawDir)) {
      actions.add(const MigrationAction('doc/log/raw/** → doc/records/log/legacy/(凍結移動)'));
      if (!dryRun) {
        await _movePath(rawDir, '$projectDir/doc/records/log/legacy');
      }
    }

    // 5. doc/log/impl/*.md → doc/impl/(front matter 付与は将来の impl コマンドに委ねる)
    final implDir = '$projectDir/doc/log/impl';
    if (_dirExists(implDir)) {
      actions.add(const MigrationAction(
          'doc/log/impl/** → doc/impl/(実装計画書。frontmatter 付与は手動 or 将来の impl 移行コマンドで実施)'));
      if (!dryRun) {
        await _movePath(implDir, '$projectDir/doc/impl');
      }
    }

    // 6. doc/log/post_contract_summary_*.md → doc/impl/research/
    final logDir = '$projectDir/doc/log';
    if (_dirExists(logDir)) {
      final summaryFiles =
          _listEntries(logDir).where((f) => f.startsWith('post_contract_summary_')).toList();
      for (final file in summaryFiles) {
        actions.add(MigrationAction('doc/log/$file → doc/impl/research/$file'));
        if (!dryRun) {
          await _movePath('$logDir/$file', '$projectDir/doc/impl/research/$file');
        }
      }
    }

    // 7. doc/案件整理サマリー.md → doc/summary.md(リネームのみ。§10 相当のマーカー化・
    //    合意の agreements.jsonl への個別移行は人間の確認が前提のため自動化しない)
    const legacySummaryName = '案件整理サマリー.md';
    final legacySummaryPath = '$projectDir/doc/$legacySummaryName';
    if (_fileExists(legacySummaryPath) && !_fileExists('$projectDir/doc/summary.md')) {
      actions.add(MigrationAction(
        'doc/$legacySummaryName → doc/summary.md(リネームのみ。'
        '合意ログの agreements.jsonl への個別移行は `agree add --from <legacy>` で人間が確認しながら実施)',
      ));
      if (!dryRun) {
        await _movePath(legacySummaryPath, '$projectDir/doc/summary.md');
      }
    }

    // 8. doc/guides/{store,payment,infrastructure,testing,troubleshooting} → ~/.utakata/knowledge/
    //    doc/guides/project/** → doc/knowledge/
    final guidesDir = '$projectDir/doc/guides';
    if (_dirExists(guidesDir)) {
      for (final entry in _listEntries(guidesDir)) {
        if (entry == 'project') {
          actions.add(const MigrationAction('doc/guides/project/** → doc/knowledge/(案件固有ナレッジ)'));
          if (!dryRun) {
            await _movePath('$guidesDir/project', '$projectDir/doc/knowledge');
          }
        } else {
          actions.add(MigrationAction(
              'doc/guides/$entry/** → ~/.utakata/knowledge/$entry/(案件非依存ナレッジ。要手動確認)',
              automated: false));
        }
      }
    }

    return actions;
  }
}
