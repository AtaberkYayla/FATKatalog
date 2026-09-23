import 'label_record.dart';

sealed class ParseResult {
  const ParseResult();
}

final class ParseSuccess extends ParseResult {
  const ParseSuccess(this.record);

  final LabelRecord record;
}

final class ParseError extends ParseResult {
  const ParseError(this.reason);

  /// Kullanıcıya gösterilecek Türkçe açıklama.
  final String reason;
}
