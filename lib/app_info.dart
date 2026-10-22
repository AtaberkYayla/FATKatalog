/// Bir sürümde neyin değiştiği.
class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.date,
    required this.changes,
  });

  /// pubspec.yaml'daki `version:` satırının nokta öncesi kısmı, ör. `1.2.0`.
  final String version;

  /// `dd.MM.yyyy`
  final String date;

  final List<String> changes;
}

/// Sürüm geçmişi, yeniden eskiye.
///
/// **Yeni sürüm çıkarırken:** pubspec.yaml'daki `version:` satırını artır
/// (`1.2.0+4` → sürüm adı + versionCode; versionCode **asla azalmamalı**,
/// azalırsa telefonlara güncelleme kurulamaz) ve buraya en üste bir madde ekle.
/// Uygulamadaki "Hakkında → Yenilikler" listesi buradan okunur, böylece sahadaki
/// kullanıcı da hangi sürümde ne değiştiğini görür.
const releaseNotes = <ReleaseNote>[
  ReleaseNote(
    version: '1.5.0',
    date: '22.10.2026',
    changes: [
      'Arşiv: sevkiyatı biten projenin listesi, Proje Detayı\'ndaki arşiv '
          'simgesinden ya da Projeler listesinde projeye uzun basarak arşive '
          'alınır. Ana listeden kalkar, aynı proje no için yeni liste boş '
          'başlar. Arşiv sekmesinde "8900 (13.10.2026-15:41)" olarak saklanır; '
          'açıp bakabilir, Excel olarak indirip paylaşabilir ya da silebilirsiniz.',
      'Arşive alınan ürünlerin seri numaraları serbest kalır, yeni listede '
          'tekrar okutulabilir.',
    ],
  ),
  ReleaseNote(
    version: '1.4.0',
    date: '13.10.2026',
    changes: [
      'Manuel ekle: etiketi olmayan malzemeler elle eklenebilir. Okut '
          'ekranındaki "Manuel ekle" düğmesinden ya da Proje Detayı\'ndaki '
          'üst çubuk simgesinden açılır. Proje No ve Seri No zorunludur; '
          'diğer alanlar boş bırakılabilir.',
    ],
  ),
  ReleaseNote(
    version: '1.3.0',
    date: '07.10.2026',
    changes: [
      'Palet ölçüsü: palet atarken Palet No\'nun altına palet genişliği ve '
          'uzunluğu (mm) girilir. Excel çıktısında Palet No ile Okutma '
          'Zamanı arasında "Palet Ölçüsü (mm)" sütununda Genişlik x Uzunluk '
          'olarak görünür.',
    ],
  ),
  ReleaseNote(
    version: '1.2.0',
    date: '23.09.2026',
    changes: [
      'Tümünü Excel olarak indir: bütün projelerin kayıtları tek bir Excel '
          'dosyasına indirilir veya paylaşılır.',
      'Excel dosyasından yükle: indirdiğiniz bir Excel dosyasındaki kayıtlar '
          'geri alınır. Tek projenin dosyası da olur, tüm projeler dosyası da. '
          'Kayıtlar mevcutlarla birleştirilir, hiçbir kayıt silinmez — iki '
          'telefonun verisini birleştirmek için de kullanılabilir.',
      'Excel\'de doldurulan palet no telefona geçer: zaten kayıtlı bir ürünün '
          'yalnızca boş alanları dosyadan tamamlanır, dolu alanın üstüne '
          'yazılmaz.',
      'Kayıt dosyaları sütun adlarına göre okunuyor: ileride yeni sütun '
          'eklensin veya sıra değişsin, eski kayıtlar kaybolmaz.',
      'Hakkında ekranına sürüm geçmişi eklendi.',
    ],
  ),
  ReleaseNote(
    version: '1.1.0',
    date: '22.09.2026',
    changes: [
      'Palet No: kayıtlara palet atanabiliyor, listede palete göre sıralama '
          've Excel çıktısında Palet No sütunu.',
    ],
  ),
  ReleaseNote(
    version: '1.0.0',
    date: '22.09.2026',
    changes: [
      'İlk sürüm: QR okutma, proje listesi, Excel olarak indirme ve paylaşma.',
    ],
  ),
];
