import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// `package:yaml_edit` を用いた YAML の外科的編集を担うデータソース。
///
/// 自作シリアライザ([YamlDataSource.serialize])と異なり、既存ファイルの
/// コメント・書式を保持したまま特定ノードだけを更新できる。機械が
/// 人間の書いた YAML(plan.yaml 等)に書き込む唯一の正規経路とする(P4)。
class YamlEditDataSource {
  const YamlEditDataSource();

  /// 新規 YAML ドキュメントを Map からレンダリングする(新規作成時のみ使用。
  /// 既存ファイルの更新には [appendToList] を使うこと)。
  String render(Map<String, dynamic> data) {
    final editor = YamlEditor('');
    editor.update([], data);
    return editor.toString();
  }

  /// 既存 YAML 文字列の `path` が指すリストへ、コメント・書式を保持したまま
  /// 1件追記する。リストが存在しない場合は新規作成する。
  String appendToList(
    String yamlContent,
    List<Object> path,
    Object value,
  ) {
    final editor = YamlEditor(yamlContent);
    final current = _navigate(editor.parseAt([]), path);
    if (current is YamlList) {
      editor.appendToList(path, value);
    } else {
      editor.update(path, [value]);
    }
    return editor.toString();
  }

  /// `path` が指すノードを value で置き換える(存在しなければ作成する)。
  /// コメント・書式は保持される。
  ///
  /// `yaml_edit` の `update` は中間ノードを自動生成しない(存在しないパスは
  /// 例外)ため、欠けている中間 Map をここで先に作ってから更新する。
  String setAt(String yamlContent, List<Object> path, Object value) {
    final editor = YamlEditor(yamlContent);
    for (var i = 1; i < path.length; i++) {
      final parentPath = path.sublist(0, i);
      if (_navigate(editor.parseAt([]), parentPath) == null) {
        editor.update(parentPath, <String, dynamic>{});
      }
    }
    editor.update(path, value);
    return editor.toString();
  }

  /// `mapPath` が指すマップへ、まだ無いキー [key] を末尾に足す
  /// (Issue #28)。
  ///
  /// `yaml_edit` 2.2.4 は既存キーがアルファベット順に並んでいると新しいキーを
  /// その順の位置へ差し込み、差し込み先が list 要素の先頭キー(`- name:` の行)
  /// だと前の要素の末尾に入ってしまう。block 形式のマップでは位置を
  /// `yaml_edit` に決めさせず、「最後の値の行の次」に自前で差し込む。
  ///
  /// 差し込んだ後に読み直し、ドキュメント全体が「元の内容 + このキー」と
  /// 一致することを確かめる。一致しなければ [YamlAppendException] を投げる
  /// (呼び出し側は何も書かないこと)。block 形式でない(flow / 空)マップは
  /// 従来どおり `yaml_edit` に任せる。
  String appendKeyToBlockMap(
    String yamlContent,
    List<Object> mapPath,
    String key,
    Object value,
  ) {
    final editor = YamlEditor(yamlContent);
    final root = editor.parseAt([]);
    final map = _navigate(root, mapPath);
    if (map is! YamlMap) {
      throw YamlAppendException('map not found at $mapPath');
    }
    if (map.containsKey(key)) {
      throw YamlAppendException('key "$key" already exists at $mapPath');
    }
    if (map.style != CollectionStyle.BLOCK || map.nodes.isEmpty) {
      editor.update([...mapPath, key], value);
      return editor.toString();
    }

    final lineEnding = yamlContent.contains('\r\n') ? '\r\n' : '\n';

    // 差し込む位置: 最後の値(とその行末コメント)の行の次の行頭
    // 字下げは最初のキーの桁にそろえる
    final indent = (map.nodes.keys.first as YamlNode).span.start.column;
    final lastEnd = _contentEnd(map);

    var insertAt = -1;
    if (lastEnd > 0 && yamlContent[lastEnd - 1] == '\n') {
      // block scalar(`|` など)は値の範囲が改行まで含む
      insertAt = lastEnd;
    } else {
      final nl = yamlContent.indexOf('\n', lastEnd);
      if (nl >= 0) insertAt = nl + 1;
    }

    final snippetLines = _renderEntry(key, value)
        .map((line) => line.isEmpty ? line : '${' ' * indent}$line')
        .toList();
    if (insertAt >= 0) {
      final before = yamlContent.substring(0, insertAt);
      final after = yamlContent.substring(insertAt);
      final updated =
          '$before${snippetLines.join(lineEnding)}$lineEnding$after';
      _verifyAppended(root, updated, mapPath, key, value);
      return updated;
    }
    // 末尾に改行が無いファイル: 改行を補って足し、末尾は元どおり改行なしにする
    final updated = '$yamlContent$lineEnding${snippetLines.join(lineEnding)}';
    _verifyAppended(root, updated, mapPath, key, value);
    return updated;
  }

  /// [node] の中身が実際に終わる位置(offset)。
  ///
  /// block 形式のコレクションの範囲は次のトークン(次の `- name:` 等)の
  /// 直前まで伸びることがあるため、末端のスカラーまでたどって求める。
  static int _contentEnd(YamlNode node) {
    if (node is YamlMap &&
        node.style == CollectionStyle.BLOCK &&
        node.nodes.isNotEmpty) {
      var end = 0;
      for (final value in node.nodes.values) {
        final e = _contentEnd(value);
        if (e > end) end = e;
      }
      return end;
    }
    if (node is YamlList &&
        node.style == CollectionStyle.BLOCK &&
        node.nodes.isNotEmpty) {
      return _contentEnd(node.nodes.last);
    }
    return node.span.end.offset;
  }

  /// `{key: value}` を block 形式で描画し、行の一覧で返す(字下げなし)。
  List<String> _renderEntry(String key, Object value) {
    final editor = YamlEditor('');
    editor.update([], {key: value});
    final lines = editor.toString().split('\n');
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  /// 書き換え後の内容を読み直し、元のドキュメントに [key] だけが足された
  /// 状態と一致するかを確かめる。
  void _verifyAppended(
    YamlNode originalRoot,
    String updated,
    List<Object> mapPath,
    String key,
    Object value,
  ) {
    final Object? actual;
    try {
      actual = _toPlain(loadYaml(updated));
    } on Exception catch (e) {
      throw YamlAppendException('result is not valid YAML: $e');
    }
    final expected = _toPlain(originalRoot);
    final target = _navigate(expected, mapPath);
    if (target is! Map) {
      throw YamlAppendException('map not found at $mapPath');
    }
    target[key] = _toPlain(value);
    if (!_deepEquals(expected, actual)) {
      throw YamlAppendException(
          'appending "$key" at $mapPath would change other content');
    }
  }

  static Object? _toPlain(Object? node) {
    if (node is YamlScalar) return node.value;
    if (node is Map) {
      return <Object?, Object?>{
        for (final e in node.entries) _toPlain(e.key): _toPlain(e.value),
      };
    }
    if (node is List) return [for (final e in node) _toPlain(e)];
    return node;
  }

  static bool _deepEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_deepEquals(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// `path` が指すノードが存在するか(値が null の場合も false)。
  bool hasNode(String yamlContent, List<Object> path) =>
      _navigate(YamlEditor(yamlContent).parseAt([]), path) != null;

  /// `mapPath` が指すマップに [key] があるか(値が null でも true)。
  bool hasKey(String yamlContent, List<Object> mapPath, String key) {
    final map = _navigate(YamlEditor(yamlContent).parseAt([]), mapPath);
    return map is YamlMap && map.containsKey(key);
  }

  /// `path` が指すノードの値(無ければ null)。
  Object? valueAt(String yamlContent, List<Object> path) =>
      _navigate(YamlEditor(yamlContent).parseAt([]), path);

  /// `path` が指すリストから、値が [value] と一致する最初の要素を削除する。
  /// 見つからない場合は元の内容をそのまま返す。
  String removeFromList(String yamlContent, List<Object> path, Object value) {
    final editor = YamlEditor(yamlContent);
    final current = _navigate(editor.parseAt([]), path);
    if (current is! YamlList) return yamlContent;
    for (var i = 0; i < current.length; i++) {
      if (current[i] == value) {
        editor.remove([...path, i]);
        return editor.toString();
      }
    }
    return yamlContent;
  }

  /// `features:` 配列内で `name` が一致する feature のインデックスを返す。
  /// 見つからなければ -1。
  int indexOfFeature(String yamlContent, String featureName) {
    final root = YamlEditor(yamlContent).parseAt([]);
    if (root is! YamlMap) return -1;
    final features = root['features'];
    if (features is! YamlList) return -1;
    for (var i = 0; i < features.length; i++) {
      final f = features[i];
      if (f is YamlMap && f['name'] == featureName) return i;
    }
    return -1;
  }

  dynamic _navigate(dynamic node, List<Object> path) {
    var current = node;
    for (final key in path) {
      if (current is Map && key is String) {
        current = current[key];
      } else if (current is List && key is int) {
        if (key < 0 || key >= current.length) return null;
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }
}

/// [YamlEditDataSource.appendKeyToBlockMap] が安全に追記できなかったときの例外。
/// 投げられた場合、呼び出し側はファイルを書き換えてはならない。
final class YamlAppendException implements Exception {
  final String message;
  const YamlAppendException(this.message);

  @override
  String toString() => 'YamlAppendException: $message';
}
