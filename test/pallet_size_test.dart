import 'package:fatkatalog/model/pallet_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('metin Genişlik x Uzunluk biçiminde', () {
    expect(const PalletSize('800', '1200').text, '800 x 1200');
    expect(const PalletSize('', '').text, '');
  });

  test('ya ikisi de boş ya ikisi de sayı geçerlidir', () {
    expect(const PalletSize('', '').isValid, isTrue);
    expect(const PalletSize('800', '1200').isValid, isTrue);
    expect(const PalletSize('800', '').isValid, isFalse);
    expect(const PalletSize('', '1200').isValid, isFalse);
    expect(const PalletSize('80a', '1200').isValid, isFalse);
  });

  test('farklı yazımlar çözülür', () {
    for (final raw in ['800 x 1200', '800x1200', ' 800 X 1200 ', '800×1200']) {
      final size = PalletSize.tryParse(raw);
      expect(size?.width, '800', reason: raw);
      expect(size?.length, '1200', reason: raw);
    }
  });

  test('çözülemeyen metin null döner', () {
    for (final raw in ['', '800', '800 x', 'x 1200', 'a x b', '1 x 2 x 3']) {
      expect(PalletSize.tryParse(raw), isNull, reason: raw);
    }
  });
}
