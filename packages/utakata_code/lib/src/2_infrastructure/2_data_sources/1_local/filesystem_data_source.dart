import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../1_domain/1_entities/structure/structure_node.dart';
import '../../../bundled_assets.g.dart';
import '../../../version.g.dart';

/// ファイルシステム操作を担うデータソース
///
/// dart:io を直接使用する。Domain 層はこのクラスに依存しない。
class FilesystemDataSource {
  const FilesystemDataSource();

  /// ファイルを読み込む。存在しない場合は null を返す
  Future<String?> readFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  /// ファイルに書き込む（ディレクトリが存在しない場合は作成する）
  Future<void> writeFile(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  /// ディレクトリを作成する（存在する場合は何もしない）
  Future<void> ensureDir(String path) async {
    await Directory(path).create(recursive: true);
  }

  /// ファイルを削除する(存在しなければ何もしない)
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  /// ディレクトリを再帰的に削除する(存在しなければ何もしない)
  Future<void> deleteDir(String path) async {
    final dir = Directory(path);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// ファイル/ディレクトリを移動する(移動先の親ディレクトリは自動作成)
  /// [from] を [to] へ移動する。
  ///
  /// [overwrite] が false(既定)で移動先が既に存在する場合は
  /// [FileSystemException] を投げる — rename は宛先を黙って上書きするため、
  /// 素のまま使うと同名ファイルの中身が警告なしに消える。
  Future<void> movePath(String from, String to, {bool overwrite = false}) async {
    if (!overwrite && entityExists(to)) {
      throw FileSystemException('move destination already exists', to);
    }
    final toParent = Directory(p.dirname(to));
    await toParent.create(recursive: true);
    if (Directory(from).existsSync()) {
      await Directory(from).rename(to);
    } else if (File(from).existsSync()) {
      await File(from).rename(to);
    }
  }

  /// ディレクトリ直下のエントリ名(ファイル・ディレクトリ)一覧を返す
  List<String> listEntries(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];
    return dir.listSync().map((e) => p.basename(e.path)).toList()..sort();
  }

  /// [dirPath] 配下を再帰的に走査し、ファイル名が [fileName] に一致する
  /// ファイルの相対パス一覧を返す(doctor の残存 GUIDE.md 検出などに使う)。
  List<String> listFilesNamed(String dirPath, String fileName) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => p.basename(f.path) == fileName)
        .map((f) => p.relative(f.path, from: dirPath))
        .toList()
      ..sort();
  }

  /// パスに何らかのエンティティ(ファイル・ディレクトリ・リンク)が存在するか。
  ///
  /// 「無ければ作る」系の存在ガードはこちらを使う — [fileExists] は
  /// 同パスがディレクトリだと false を返すため、後続の書き込みが
  /// 生の FileSystemException でクラッシュしてしまう。
  bool entityExists(String path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

  /// [dirPath] 配下の [suffix] で終わるファイルを再帰列挙する(dirPath 相対)。
  List<String> listFilesWithSuffix(String dirPath, String suffix) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(suffix))
        .map((f) => p.relative(f.path, from: dirPath))
        .toList()
      ..sort();
  }

  /// ファイルが存在するか確認する
  bool fileExists(String path) => File(path).existsSync();

  /// ディレクトリが存在するか確認する
  bool dirExists(String path) => Directory(path).existsSync();

  /// ディレクトリ配下のファイル・ディレクトリを再帰的にスキャンする
  ///
  /// .dart ファイル（.g.dart / .freezed.dart を除く）のみを対象とする
  Map<String, dynamic> scanDartFiles(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return {};
    return _scanDir(dir);
  }

  Map<String, dynamic> _scanDir(Directory dir) {
    final result = <String, dynamic>{};
    final entities = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));

    for (final entity in entities) {
      final name = p.basename(entity.path);
      if (name.startsWith('.') || name == '.gitkeep') continue;

      if (entity is Directory) {
        result[name] = _scanDir(entity);
      } else if (entity is File) {
        final isDartFile = name.endsWith('.dart');
        final isGenerated =
            name.endsWith('.g.dart') || name.endsWith('.freezed.dart');
        if (isDartFile && !isGenerated) {
          final files = result['__files__'] as List<String>? ?? [];
          files.add(name);
          result['__files__'] = files;
        }
      }
    }
    return result;
  }

  /// ディレクトリ配下を再帰的にスキャンし、正準構造モデル
  /// ([StructureDirNode] / [StructureFileNode])のツリーを返す。
  ///
  /// `scanDartFiles`(Map ベースの旧表現)の後継。ファイル種別
  /// (source / generated)の判定は [StructureFileNode.kindOf] に一元化する。
  StructureDirNode scanStructureTree(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return StructureDirNode.empty;
    return _scanStructureDir(dir);
  }

  StructureDirNode _scanStructureDir(Directory dir) {
    final children = <String, StructureNode>{};
    final entities = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));

    for (final entity in entities) {
      final name = p.basename(entity.path);
      if (name.startsWith('.') || name == '.gitkeep') continue;

      if (entity is Directory) {
        children[name] = _scanStructureDir(entity);
      } else if (entity is File && name.endsWith('.dart')) {
        children[name] = StructureFileNode(StructureFileNode.kindOf(name));
      }
    }
    return StructureDirNode(children);
  }

  /// ディレクトリ配下の .dart ファイルを再帰的にフラットリストで返す
  ///
  /// .g.dart / .freezed.dart / .template.dart は除外する。
  /// (命名規則の検証など、ツリー構造ではなくファイル単位の走査が必要な用途向け)
  List<String> listDartFilesRecursive(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((path) => path.endsWith('.dart'))
        .where((path) => !path.endsWith('.freezed.dart'))
        .where((path) => !path.endsWith('.g.dart'))
        .where((path) => !path.endsWith('.template.dart'))
        .toList()
      ..sort();
  }

  /// パッケージに同梱されたテンプレートディレクトリのパスを返す
  ///
  /// パッケージルートは [_packageRoot] の順で決める。例外は投げない —
  /// どこにも無ければ存在しないパスを返し、呼び出し側(bin/utakata.dart の
  /// 既定ナレッジへのフォールバック等)が存在確認で判断する。
  Future<String> resolvePackageTemplatePath(String relativePath) async {
    final root = await _packageRoot();
    return p.join(root, 'lib', 'src', '0_templates', relativePath);
  }

  /// パッケージルート直下のファイル(`doc/*.md` 等)の絶対パスを解決する。
  /// 見つからなければ null。
  Future<String?> resolvePackageFilePath(String relativePath) async {
    final path = p.join(await _packageRoot(), relativePath);
    return File(path).existsSync() ? path : null;
  }

  /// 環境変数でパッケージルートを差し替えるときの名前。
  /// パッケージルートと同じ並び(`lib/src/0_templates`, `doc`)のディレクトリを指す。
  static const assetsDirEnv = 'UTAKATA_ASSETS_DIR';

  static Future<String>? _packageRootCache;

  /// 同梱ファイルを読むためのパッケージルート(Issue #36):
  ///   ① 環境変数 [assetsDirEnv]
  ///   ② `Isolate.resolvePackageUri`(dart run / pub global activate)
  ///   ③ 埋め込み済みの [bundledAssets] を `~/.utakata/cache/bundled-<版>/`
  ///      へ一度だけ書き出したもの(`dart compile exe` の実行ファイル向け)
  Future<String> _packageRoot() => _packageRootCache ??= _computePackageRoot();

  static Future<String> _computePackageRoot() async {
    final override = Platform.environment[assetsDirEnv];
    if (override != null && override.isNotEmpty) return p.absolute(override);

    try {
      final libUri =
          await Isolate.resolvePackageUri(Uri.parse('package:utakata/'));
      if (libUri != null) {
        final root = Directory.fromUri(libUri).parent.path;
        if (Directory(p.join(root, 'lib', 'src', '0_templates')).existsSync()) {
          return root;
        }
      }
    } on Object {
      // AOT 等で解決できない場合は埋め込み版へ
    }

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    final target =
        p.join(home, '.utakata', 'cache', 'bundled-$packageVersion');
    try {
      extractBundledAssets(target);
    } on FileSystemException {
      // 書き出せなくても投げない(存在しないパスとして扱われる)
    }
    return target;
  }

  /// [bundledAssets] を [targetDir] に書き出す。既にあれば何もしない。
  ///
  /// 途中で落ちても中途半端なディレクトリを残さないよう、隣の一時
  /// ディレクトリに書いてから rename する。並行実行で先を越された場合は
  /// 一時ディレクトリを捨てて相手の結果を使う。
  static void extractBundledAssets(String targetDir) {
    if (Directory(targetDir).existsSync()) return;
    final parent = Directory(p.dirname(targetDir))..createSync(recursive: true);
    final temp = parent.createTempSync('${p.basename(targetDir)}.tmp-');
    try {
      for (final entry in bundledAssets.entries) {
        final file = File(p.joinAll([temp.path, ...entry.key.split('/')]));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(entry.value);
      }
      temp.renameSync(targetDir);
    } on FileSystemException {
      if (!Directory(targetDir).existsSync()) rethrow;
    } finally {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    }
  }
}
