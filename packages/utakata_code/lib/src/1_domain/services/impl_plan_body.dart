/// 実装計画書の**本文**を「計画」と「実施記録」に分ける純関数サービス(v1.8.0)。
///
/// 1.7.x までは frontmatter だけを機械管理し、本文は一切解釈しなかった。
/// その結果、1本の計画書が「計画 → 実施記録 → 追試 → 次ビルドの確認項目」と
/// 時系列で積み上がり、どこが計画でどこが記録か読めなくなった。
///
/// ここで越える一線は**最小**に留める: 本文を節構造として解析はせず、
/// マーカー行 [marker] を 1 つ探すだけ。マーカーより上が計画(凍結の対象)、
/// 下が記録(追記のみ)。マーカーの無い 1.7.x 以前のファイルは全体が計画で、
/// 最初の追記時に末尾へマーカーが足される。
abstract final class ImplPlanBody {
  /// 計画と記録の境界。HTML コメントなので Markdown の描画には現れない。
  static const marker = '<!-- utakata:log -->';

  /// マーカー直後に置く見出し(記録領域の中なので凍結の対象外)。
  static const logHeading = '## 実施記録';

  /// 本文を計画と記録に分ける。記録領域が無ければ `log` は null。
  static ({String plan, String? log}) split(String body) {
    final index = _markerIndex(body);
    if (index < 0) return (plan: body, log: null);
    final afterMarker = body.indexOf('\n', index);
    return (
      plan: body.substring(0, index),
      log: afterMarker < 0 ? '' : body.substring(afterMarker + 1),
    );
  }

  /// 記録領域に 1 件追記した本文を返す。領域が無ければ末尾に作る。
  static String appendEntry(String body, String entry) {
    final buffer = StringBuffer();
    if (_markerIndex(body) < 0) {
      buffer.write(body);
      if (body.isNotEmpty && !body.endsWith('\n')) buffer.write('\n');
      if (body.isNotEmpty) buffer.write('\n');
      buffer
        ..writeln(marker)
        ..writeln(logHeading)
        ..writeln();
    } else {
      buffer.write(body);
      if (!body.endsWith('\n')) buffer.write('\n');
    }
    buffer.writeln(entry);
    return buffer.toString();
  }

  /// 記録 1 件の書式: `- 2026-10-07 10:12 (actor) text`。
  /// 複数行の text は 2 スペース字下げで続ける(箇条書きの継続行)。
  static String formatEntry({
    required DateTime at,
    required String actor,
    required String text,
  }) {
    final stamp = '${at.year.toString().padLeft(4, '0')}-'
        '${at.month.toString().padLeft(2, '0')}-'
        '${at.day.toString().padLeft(2, '0')} '
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    final who = actor.trim().isEmpty ? '' : ' (${actor.trim()})';
    final lines = text.trim().split(RegExp(r'\r?\n'));
    final buffer = StringBuffer('- $stamp$who ${lines.first}');
    for (final line in lines.skip(1)) {
      buffer.write('\n  $line');
    }
    return buffer.toString();
  }

  /// 計画部分の指紋(凍結後の変更検知用、v1.8.0 #22)。
  ///
  /// 暗号学的な強度は要らない(改竄対策ではなく「変わったか」の検知)ので、
  /// 依存を増やさず FNV-1a 64bit を使う。改行コードと行末の空白、末尾の
  /// 空行は正規化してから計算する — エディタの自動整形で「変更あり」に
  /// ならないように。
  static String digest(String plan) {
    final normalized = plan
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .trimRight();
    // Dart の int は 64bit で乗算は自然に折り返すので、マスクは要らない
    var hash = 0xcbf29ce484222325;
    for (final unit in normalized.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    // 64bit の値は負になりうる(toUnsigned(64) では正に戻せない)ので、
    // 32bit ずつ符号なしで 16 進にする
    final hi = (hash >>> 32) & 0xFFFFFFFF;
    final lo = hash & 0xFFFFFFFF;
    return hi.toRadixString(16).padLeft(8, '0') +
        lo.toRadixString(16).padLeft(8, '0');
  }

  /// マーカー行の先頭位置(行頭にあるものだけを境界と見なす)。
  static int _markerIndex(String body) {
    var from = 0;
    while (true) {
      final index = body.indexOf(marker, from);
      if (index < 0) return -1;
      final atLineStart = index == 0 || body[index - 1] == '\n';
      if (atLineStart) return index;
      from = index + marker.length;
    }
  }
}
