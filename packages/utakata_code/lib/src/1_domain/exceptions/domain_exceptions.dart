library;

/// utakata ドメイン層の例外クラス群
///
/// 例外メッセージは言語非依存の英語で記述する。
/// ユーザー向けの多言語メッセージは CliMessages 経由で Command 層が担う。
sealed class UtakataDomainException implements Exception {
  final String message;
  const UtakataDomainException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// 指定したアーキテクチャが存在しない
final class ArchitectureNotFoundException extends UtakataDomainException {
  const ArchitectureNotFoundException(String architectureId)
      : super('Architecture "$architectureId" not found.');
}

/// feature_request.yaml が存在しない
final class FeatureRequestNotFoundException extends UtakataDomainException {
  const FeatureRequestNotFoundException(String path)
      : super('feature_request.yaml not found: $path');
}

/// flutter コマンドが見つからない
///
/// FLUTTER_PATH / FLUTTER_ROOT 環境変数、または PATH 上に
/// flutter 実行ファイルが存在しない場合にスローされる。
final class FlutterNotFoundException extends UtakataDomainException {
  const FlutterNotFoundException()
      : super(
          'flutter command not found. '
          'Set FLUTTER_PATH environment variable to the full path.',
        );
}

/// 合意 ID の形が正しくない(`AGR-` + 4桁以上の数字でない。改行混入など。#33)。
final class InvalidAgreementIdException extends UtakataDomainException {
  final String id;

  InvalidAgreementIdException(this.id)
      : super('Invalid agreement ID: ${quoteRecordId(id)} (expected AGR-NNNN).');
}

/// 合意 ID の形は正しいが、agreements.jsonl に記録が無い(#33)。
final class AgreementNotFoundException extends UtakataDomainException {
  final String id;

  AgreementNotFoundException(this.id)
      : super('Agreement ${quoteRecordId(id)} not found '
            '(check with `utakata agree list`).');
}

/// 改行などの制御文字をエスケープして1行で見せる(不正な ID の表示用)。
String quoteRecordId(String raw) {
  final escaped = raw
      .replaceAll(r'\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}

/// YAML 解析に失敗した
final class YamlParseException extends UtakataDomainException {
  const YamlParseException(String path)
      : super('Failed to parse YAML: $path');
}
