import 'package:path/path.dart' as p;

import '../1_entities/plan/plan_intent.dart';
import '../1_entities/structure/expected_structure.dart';
import '../2_repositories/architecture_repository.dart';
import '../services/expected_structure_builder.dart';
import 'architecture_definition_entity_resolver.dart';

/// check が必須と判定するファイル([ExpectedStructureBuilder] の
/// requiredFiles)を、存在しないものだけ**空ファイルとして生成する**
/// ユースケース(Issue #19)。
///
/// `apply`(plan.yaml 全体)と `feature add`(1 feature。Issue #34)の両方から
/// 使う。check と同一の導出を使うので、生成したものと check の期待値が
/// 食い違わない。既存ファイルは一切上書きしない。
class CreateRequiredFilesUsecase {
  final ArchitectureRepository _archRepo;
  final bool Function(String path) _fileExists;
  final Future<void> Function(String path, String content) _writeFile;

  const CreateRequiredFilesUsecase({
    required ArchitectureRepository archRepo,
    required bool Function(String path) fileExists,
    required Future<void> Function(String path, String content) writeFile,
  })  : _archRepo = archRepo,
        _fileExists = fileExists,
        _writeFile = writeFile;

  /// [plan] の全 feature の必須ファイルを生成する。
  /// 生成した(dry-run 時は生成予定の)プロジェクト相対パスを返す。
  ///
  /// [skipPathPrefixes] で始まる feature のファイルは作らない
  /// (実装計画ゲートで止めた feature 用)。
  Future<List<String>> execute(
    String projectDir,
    PlanIntent plan, {
    bool dryRun = false,
    List<String> skipPathPrefixes = const [],
  }) async {
    final architecturesById = await resolveArchitectures(plan, _archRepo);
    final expected = ExpectedStructureBuilder.build(plan, architecturesById);

    final relativePaths = <String>[];
    _collectRequiredFiles(expected.topLevel, 'lib/features', relativePaths);

    final created = <String>[];
    for (final relative in relativePaths) {
      if (skipPathPrefixes.any((prefix) => relative.startsWith('$prefix/'))) {
        continue;
      }
      final absolute = p.join(projectDir, relative);
      if (_fileExists(absolute)) continue;
      if (!dryRun) await _writeFile(absolute, '');
      created.add(relative);
    }
    created.sort();
    return created;
  }

  /// [plan] のうち [featureName] の feature だけの必須ファイルを生成する
  /// (Issue #34: `feature add`)。plan に無ければ何もせず空を返す。
  Future<List<String>> executeForFeature(
    String projectDir,
    PlanIntent plan,
    String featureName, {
    bool dryRun = false,
  }) async {
    final features =
        plan.features.where((f) => f.name == featureName).toList();
    if (features.isEmpty) return const [];
    return execute(
      projectDir,
      PlanIntent(
        schema: plan.schema,
        defaultArchitectureId: plan.defaultArchitectureId,
        features: features,
      ),
      dryRun: dryRun,
    );
  }

  static void _collectRequiredFiles(
    Map<String, ExpectedDir> dirs,
    String pathPrefix,
    List<String> out,
  ) {
    for (final entry in dirs.entries) {
      final dir = entry.value;
      // 不要と宣言された層([] 宣言)のファイルは生成しない
      if (!dir.required) continue;
      final dirPath = '$pathPrefix/${entry.key}';
      for (final file in dir.requiredFiles) {
        out.add('$dirPath/$file');
      }
      _collectRequiredFiles(dir.children, dirPath, out);
    }
  }
}
