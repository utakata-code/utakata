// utakata_arch_lib のローカルチェックアウトから lib/src/0_templates/architectures/
// へ同梱テンプレートを同期する(実装計画 D1: Single Source of Truth は arch_lib)。
//
// 実行: dart run tool/sync_arch_lib.dart <path-to-utakata_arch_lib>
//
// 変換はこのスクリプトだけが行い、CLI 実行時コードには入れない:
//   - `_starter`(独自アーキテクチャ雛形)は同梱しない
//   - **slim 同梱(v1.4.0 / Issue #15)**: 実行時に必須の
//     `arch_definition.yaml` と `skills/` のみを同梱する。読み物
//     (layers/ principles/ dependencies/)は同梱せず、参照時に
//     公式 utakata_arch_lib からフェッチする(既定ナレッジリポジトリ)
//   - arch_definition.yaml の detail_content_path をパッケージ内解決用の
//     フルパス(architectures/<id>/...)へ書き換える
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/sync_arch_lib.dart <path-to-utakata_arch_lib>');
    exit(64);
  }

  final archLibDir = Directory('${args.first}/arches');
  if (!archLibDir.existsSync()) {
    stderr.writeln('not an arch_lib checkout (missing arches/): ${args.first}');
    exit(66);
  }

  final targetRoot = Directory('lib/src/0_templates/architectures');
  if (!targetRoot.parent.existsSync()) {
    stderr.writeln('run from packages/utakata_code (missing lib/src/0_templates)');
    exit(66);
  }

  var synced = 0;
  for (final entry in archLibDir.listSync().whereType<Directory>()) {
    final id = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (id.startsWith('_') || id.startsWith('.')) continue;

    final target = Directory('${targetRoot.path}/$id');
    if (target.existsSync()) target.deleteSync(recursive: true);
    _copyTree(entry, target, archId: id);
    synced++;
    stdout.writeln('synced: $id');
  }

  if (synced == 0) {
    stderr.writeln('no architectures found under ${archLibDir.path}');
    exit(65);
  }
  stdout.writeln('next: dart run tool/generate_bundled_assets.dart '
      '(AOT 用の埋め込み版を更新する)');
}

/// slim 同梱の対象: このトップレベル配下のみ同梱する。
/// dependencies/ は機械可読な *.yaml(バージョン + 配置宣言)のみ同梱し、
/// *.md(読み物)は従来どおりオンデマンド取得に委ねる。
const _bundledTopLevel = {'arch_definition.yaml', 'skills', 'dependencies'};

void _copyTree(Directory from, Directory to, {required String archId}) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(recursive: true)) {
    final relative = entity.path.substring(from.path.length + 1);
    final parts = relative.split(Platform.pathSeparator);
    if (parts.any((s) => s.startsWith('.git'))) {
      continue;
    }
    if (!_bundledTopLevel.contains(parts.first)) continue;
    if (parts.first == 'dependencies' &&
        entity is File &&
        !relative.endsWith('.yaml')) {
      continue;
    }
    final targetPath = '${to.path}/$relative';
    if (entity is Directory) {
      Directory(targetPath).createSync(recursive: true);
    } else if (entity is File) {
      File(targetPath).parent.createSync(recursive: true);
      if (relative == 'arch_definition.yaml') {
        final content = entity.readAsStringSync().replaceAll(
              RegExp(r'detail_content_path:\s*"(?!architectures/)'),
              'detail_content_path: "architectures/$archId/',
            );
        File(targetPath).writeAsStringSync(content);
      } else {
        entity.copySync(targetPath);
      }
    }
  }
}
