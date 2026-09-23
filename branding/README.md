# Kurumsal kimlik varlıkları

Tek kaynak: `Dedem-Mekatronik-Kurumsal-Kimlik-Rehberi.pdf` (DEDEM Mekatronik Kurumsal Kimlik Rehberi).

## Logo dosyaları nasıl üretildi

Rehberde logo vektör olarak bulunuyor; ayrı bir SVG/PNG dosyası yok. Logo **yeniden çizilmedi**:

1. Rehberin 12. sayfası ("Logotype Farklı Zeminlerde Kullanımı") Apache PDFBox ile 600 DPI render edildi.
2. Soldaki resmi **"%100 black — yazı: beyaz, işareti: cmyk"** varyasyonu kırpıldı.
3. Panelin siyah zemini (`#000204`) "color-to-alpha" ile şeffaflığa çevrildi; logonun pikselleri değiştirilmedi.

Betik: `tool/branding/generate_assets.ps1`.

| Dosya | İçerik |
|-------|--------|
| `logo_vertical_white.png` | Dikey logo (işaret + DEDEM MEKATRONİK), beyaz yazı, 1383×1081 |
| `mark.png` | Logonun küre işareti, 585×585 |

Üretilen uygulama varlıkları:

- `assets/branding/logo_vertical_white.png`, `assets/branding/mark.png` (Flutter)
- `android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png` (adaptive icon ön katmanı)
- `android/app/src/main/res/drawable-nodpi/splash_icon.png` (Android 12+ splash)
- `android/app/src/main/res/drawable-nodpi/splash_logo.png` (Android 8–11 splash)

## Kullanım kuralları (rehberden)

- Bu varyasyon **yalnızca koyu (kurumsal siyah) zeminde** kullanılır. Açık zeminde kürenin gölgeli kenarları bozulur;
  açık zemin için rehberdeki siyah yazılı varyasyon gerekir.
- Logo bozulmaz, rengi/yazı tipi/perspektifi değiştirilmez (sayfa 13).
- Logo çevresinde "x" (harf yüksekliği) kadar güvenli alan bırakılır (sayfa 09).

## Yapılacaklar

- [ ] Pazarlamadan resmi **SVG/PNG logo dosyalarını** (özellikle yatay form ve şeffaf zeminli sürümler) almak;
      gelince bu dosyalar render yerine kullanılmalı.
- [ ] **Tek renkli (monochrome) logo** varsa Android 13+ temalı ikon katmanı eklemek.
- [ ] Üst çubukta ve launcher ikonunda logonun yalnızca küre işaretinin kullanılmasını pazarlamaya onaylatmak
      (rehber yalnızca tam logo formlarını gösteriyor; dar alanda tam logo okunamayacak kadar küçülüyor).
