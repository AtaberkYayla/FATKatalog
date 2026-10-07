/// Palet ölçüsü (mm): `Genişlik x Uzunluk`. CSV ve Excel'de tek metin olarak
/// tutulur, ör. `800 x 1200`.
class PalletSize {
  const PalletSize(this.width, this.length);

  final String width;
  final String length;

  static final _digits = RegExp(r'^\d+$');
  static final _separator = RegExp(r'\s*[xX×]\s*');

  /// `800 x 1200`; ikisi de boşsa boş metin.
  String get text => width.isEmpty && length.isEmpty ? '' : '$width x $length';

  /// Ya ikisi de boş (ölçü girilmemiş) ya da ikisi de sayı.
  bool get isValid =>
      (width.isEmpty && length.isEmpty) ||
      (_digits.hasMatch(width) && _digits.hasMatch(length));

  /// `800 x 1200`, `800x1200`, `800×1200` biçimlerini çözer. Çözülemezse
  /// (ör. elle başka bir şey yazılmış) `null`.
  static PalletSize? tryParse(String text) {
    final parts = text.trim().split(_separator);
    if (parts.length != 2) return null;
    final size = PalletSize(parts[0], parts[1]);
    return size.isValid && size.width.isNotEmpty ? size : null;
  }
}
