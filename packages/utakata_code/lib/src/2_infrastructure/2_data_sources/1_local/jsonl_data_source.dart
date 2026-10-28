import 'dart:convert';
import 'dart:io';

/// JSONL(1行=1レコード)の追記専用データソース。
///
/// 追記は末尾への1行書き込みのみ(O(1))。破損行(前回クラッシュ等)は
/// 読み込み時に検出し、`.corrupt` へ退避してスキップする(握りつぶさない)。
class JsonlDataSource {
  const JsonlDataSource();

  /// 1レコードを末尾に追記する(ファイルが無ければ作成)。
  Future<void> append(String path, Map<String, dynamic> record) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final sink = file.openWrite(mode: FileMode.append);
    sink.writeln(jsonEncode(record));
    await sink.flush();
    await sink.close();
  }

  /// 全レコードを読み出す。ファイルが無ければ空リスト。
  ///
  /// 破損した行(JSON として parse できない行)は `<path>.corrupt` へ
  /// 追記退避し、結果には含めない。
  Future<List<Map<String, dynamic>>> readAll(String path) async =>
      (await readAllDetailed(path)).rows.map((row) => row.record).toList();

  /// [readAll] と同じだが、各レコードの行番号(1始まり)と、
  /// 読めなかった行の一覧も返す(呼び出し側が警告を出せるように)。
  ///
  /// 破損行の `.corrupt` への退避は [readAll] と同じく行う。
  Future<JsonlReadResult> readAllDetailed(String path) async {
    final file = File(path);
    if (!file.existsSync()) return const JsonlReadResult([], []);

    final lines = await file.readAsLines();
    final records = <JsonlRow>[];
    final corrupt = <JsonlCorruptLine>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) {
          records.add(JsonlRow(i + 1, decoded));
        } else {
          corrupt.add(JsonlCorruptLine(i + 1, line));
        }
      } on FormatException {
        corrupt.add(JsonlCorruptLine(i + 1, line));
      }
    }

    if (corrupt.isNotEmpty) {
      // readAll は繰り返し呼ばれるため、既に退避済みの行は書かない
      // (同じ破損行が読むたびに積み上がって肥大するのを防ぐ)。
      final corruptFile = File('$path.corrupt');
      final alreadySaved = corruptFile.existsSync()
          ? (await corruptFile.readAsLines()).toSet()
          : <String>{};
      final newLines = corrupt
          .map((c) => c.raw)
          .where((line) => !alreadySaved.contains(line))
          .toList();
      if (newLines.isNotEmpty) {
        final sink = corruptFile.openWrite(mode: FileMode.append);
        for (final line in newLines) {
          sink.writeln(line);
        }
        await sink.flush();
        await sink.close();
      }
    }

    return JsonlReadResult(records, corrupt);
  }

  bool exists(String path) => File(path).existsSync();
}

/// JSONL の1レコードと、その行番号(1始まり)。
final class JsonlRow {
  final int line;
  final Map<String, dynamic> record;

  const JsonlRow(this.line, this.record);
}

/// JSON として読めなかった行。
final class JsonlCorruptLine {
  final int line;
  final String raw;

  const JsonlCorruptLine(this.line, this.raw);
}

final class JsonlReadResult {
  final List<JsonlRow> rows;
  final List<JsonlCorruptLine> corrupt;

  const JsonlReadResult(this.rows, this.corrupt);
}
