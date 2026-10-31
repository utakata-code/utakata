import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:utakata/src/1_domain/3_usecases/show_doc_usecase.dart';
import 'package:utakata/src/2_infrastructure/2_data_sources/1_local/filesystem_data_source.dart';
import 'package:utakata/src/bundled_assets.g.dart';

import '../tool/generate_bundled_assets.dart' as gen;

Future<String> _packageRoot() async {
  // CWD は並列スイートが chdir するので使わない(version_test.dart と同じ)。
  final libUri = await Isolate.resolvePackageUri(Uri.parse('package:utakata/'));
  return Directory.fromUri(libUri!).parent.path;
}

void main() {
  test('bundled_assets.g.dart が同梱ファイルと一致している', () async {
    final root = await _packageRoot();
    final actual = File(p.join(root, gen.outputPath)).readAsStringSync();
    expect(
      actual == gen.renderBundledAssets(root),
      isTrue,
      reason: 'lib/src/bundled_assets.g.dart is stale — '
          'run `dart run tool/generate_bundled_assets.dart`',
    );
    expect(bundledAssets, gen.collectBundledAssets(root));
  });

  test('doc show の全トピックが埋め込まれている', () {
    for (final path in ShowDocUsecase.topics.values) {
      expect(bundledAssets.containsKey(path), isTrue, reason: path);
    }
  });

  group('extractBundledAssets', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('utakata_bundled_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('パッケージルートと同じ並びで書き出し、一時ディレクトリを残さない', () {
      final target = p.join(tmp.path, 'bundled-x');
      FilesystemDataSource.extractBundledAssets(target);
      for (final entry in bundledAssets.entries) {
        final file = File(p.joinAll([target, ...entry.key.split('/')]));
        expect(file.readAsStringSync(), entry.value, reason: entry.key);
      }
      expect(tmp.listSync().map((e) => p.basename(e.path)), ['bundled-x']);
    });

    test('既にあれば上書きしない', () {
      final target = p.join(tmp.path, 'bundled-x');
      Directory(target).createSync();
      FilesystemDataSource.extractBundledAssets(target);
      expect(Directory(target).listSync(), isEmpty);
    });
  });
}
