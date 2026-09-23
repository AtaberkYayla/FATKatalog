# FATKatalog

Makine etiketlerindeki QR kodları okutup kayıtları **proje numarasına göre** Excel (.xlsx) dosyalarında toplayan mobil uygulama (Flutter, şimdilik yalnızca Android). FAT (Factory Acceptance Test) sırasında etiket bilgilerini elle kâğıda, sonra bilgisayara ve Excel'e yazma sürecinin yerini alır.

## Temel kurallar (kesin)

- **Veritabanı YOK.** sqflite, drift, Hive, Isar vb. kullanılmayacak. Kalıcı veri yalnızca dosyalarda tutulur.
- **Excel kütüphanesi YOK.** `excel`, `syncfusion_flutter_xlsio` vb. eklenmeyecek. .xlsx dosyası projedeki kendi `XlsxWriter` sınıfımızla üretilecek (zip için yalnızca `archive` paketi).
- **İnternet gerekmez.** Uygulama tamamen çevrimdışı çalışır; `INTERNET` izni release manifestinde istenmez.
- Kullanıcı arayüzü metinleri **Türkçe**; kod, sınıf ve değişken adları **İngilizce**.
- Kullanıcıya sorulan tek izin: `CAMERA`. (`VIBRATE` kurulumda otomatik verilen normal izindir.)

## Teknoloji

- Flutter (stable), Dart 3, Material 3
- QR okuma: `mobile_scanner` (Android'de CameraX + **bundled** ML Kit), yalnızca `BarcodeFormat.qrCode`
- Kamera izni: `mobile_scanner` kendisi ister; izin durumu ve "Ayarlara git" platform kanalıyla (`permission_handler` compileSdk 37 istediği için kullanılmıyor)
- Dosya konumu: `path_provider` (`getApplicationSupportDirectory()` = Android `filesDir`)
- Zip: `archive`
- Paylaşım: `share_plus`
- Android'e özgü işler (bip sesi, titreşim, `MediaStore` ile indirme) küçük bir platform kanalıyla (`com.dedem.fatkatalog/native`) `MainActivity.kt` içinde yapılır.
- State yönetimi: ek paket yok; `ChangeNotifier` + `ListenableBuilder`.
- Android: minSdk 26, target/compileSdk Flutter'ın varsayılanı (güncel kararlı)
- Paket adı / applicationId: `com.dedem.fatkatalog`, Dart paket adı: `fatkatalog`

## QR içerik formatı

Örnek (eski etiket, 5 alan / yeni etiket, 6 alan):

```
8835*P2-00180700*601107999*DDM261062*06/2026
8835*P2-00180700*601107999*DDM261062*06/2026*<Poz No>
```

Alanlar `*` ile ayrılır, sırası sabittir:

| # | Alan | Örnek | Doğrulama |
|---|------|-------|-----------|
| 1 | Proje No | `8835` | `^\d{4}$` — **katalog anahtarı** |
| 2 | İş Emri No | `P2-00180700` | boş olamaz |
| 3 | Erp Ürün No | `601107999` | `^\d+$` |
| 4 | Seri No | `DDM261062` | boş olamaz, **benzersiz** |
| 5 | Üretim Yılı | `06/2026` | `^\d{2}/\d{4}$`, ay 01–12 |
| 6 | Poz No | — | yalnızca yeni etiketlerde; biçim henüz bilinmiyor, doğrulanmaz, boş olabilir |

- Her alan `trim()` edilir.
- Alan sayısı 5 veya 6 değilse ya da doğrulama başarısızsa kayıt **yapılmaz**, kullanıcıya hangi alanın hatalı olduğu gösterilir. 5 alanlı eski etiketlerde Poz No boş kaydedilir.
- Ayrıştırma saf bir fonksiyon olmalı: `QrParser.parse(String raw) → ParseResult` (`ParseSuccess(LabelRecord)` / `ParseError(reason)`). Flutter bağımlılığı olmamalı ki unit test edilebilsin.

## Veri saklama

Uygulamanın iç depolaması altında:

```
<applicationSupportDirectory>/projects/
  8835.csv     ← asıl kayıt (kaynak veri)
  8835.xlsx    ← her kayıttan sonra CSV'den yeniden üretilir
  8840.csv
  8840.xlsx
```

- **CSV kaynak veridir**, .xlsx ondan türetilir. Liste ekranları CSV'den yüklenen veriyi gösterir.
- CSV: UTF-8, ayırıcı `;`, ilk satır başlık. Alanlarda `;`, `"` veya satır sonu varsa standart CSV kaçışı uygulanır.
- Sütunlar (CSV ve Excel aynı sırada):
  `Proje No; İş Emri No; Erp Ürün No; Seri No; Üretim Yılı; Poz No; Palet No; Okutma Zamanı`
- Palet No QR'dan gelmez; okutmadan sonra Proje Detayı'nda atanır, atanmamışsa boş.
- **CSV, sütun sırasına değil başlık adlarına göre okunur.** Tanınmayan sütun yok sayılır, eksik sütun boş kabul edilir; hiçbir satır sütun sayısı yüzünden düşürülmez. Böylece yeni sürümün yazdığı dosya eski sürümde de açılır ve **sütun eklemek eski kayıtları kaybettirmez**. Palet No sütunu olmayan eski (7 sütunlu) CSV'ler bu sayede kendiliğinden okunur; o projede ilk yazmada yeni biçime geçer. Başlık tanınmazsa (bozuk dosya) sütun sırasına göre okumaya düşülür.
- Biçim değiştirirken kural: **CSV sütunları yalnızca sona eklenir**, var olan sütun adı değiştirilmez veya kaldırılmaz. Görünüm değişiklikleri .xlsx tarafında yapılır; .xlsx her zaman CSV'den yeniden üretildiği için kayıtları etkilemez.
- Okutma Zamanı formatı: `dd.MM.yyyy HH:mm:ss` (cihaz saat dilimi).
- **Atomik yazma:** her değişiklikte önce aynı klasörde geçici dosyaya yazılır (`flush: true`), sonra `rename` ile asıl dosyanın yerine taşınır. Uygulama yazma sırasında kapanırsa dosya yarım kalmamalı.
- Tüm dosya işlemleri tek bir `ProjectRepository` üzerinden ve bir kilitle (Future zinciri) sıralı yapılır (aynı anda iki yazma olmasın).

### Tekrar kontrolü

- Seri No **tüm projeler genelinde** benzersizdir. Aynı seri no tekrar okutulursa kayıt yapılmaz, "DDM261062 zaten 8835 projesinde kayıtlı" gibi uyarı verilir.
- Başlangıçta tüm CSV'lerden seri no → proje no eşlemesi belleğe alınır (`Map`), her kayıtta güncellenir.

## XlsxWriter

.xlsx bir zip arşividir. `archive` paketinin `ZipEncoder`'ı ile şu dosyalar üretilir:

```
[Content_Types].xml
_rels/.rels
xl/workbook.xml
xl/_rels/workbook.xml.rels
xl/styles.xml
xl/worksheets/sheet1.xml
```

- `sharedStrings.xml` kullanılmaz; hücreler `t="inlineStr"` ile yazılır.
- **Tüm hücreler metin** olarak yazılır (ayrıca `@` / numFmtId 49 biçimi). Böylece Excel `06/2026`'yı tarihe, `601107999`'u sayıya çevirmez ve baştaki sıfırlar kaybolmaz.
- XML özel karakterleri (`& < > " '`) kaçışlanır, XML'de geçersiz kontrol karakterleri atılır.
- Sayfa adı = proje no (ör. `8835`).
- Başlık satırı kalın (styles.xml'de bir kalın font + bir cellXfs girdisi).
- Başlık satırı dondurulur (`<pane ySplit="1" ... state="frozen"/>`).
- Sütun genişlikleri içeriğe göre, alt/üst sınırlı (`<cols>`).
- Başlık satırında `autoFilter`.
- API: `XlsxWriter.encode(sheetName, header, rows, headerStyle) → List<int>` (bayt dizisi; dosyaya atomik yazma repository'nin işi).
- Üretilen dosya Microsoft Excel, LibreOffice ve Google Sheets'te hatasız açılmalı.

## Ekranlar

### 1. Okutma (açılış ekranı)
- Tam ekran kamera önizlemesi, ortada nişan çerçevesi.
- QR algılanınca ayrıştır → doğrula → tekrar kontrolü → kaydet.
- Aynı ham içerik 3 sn içinde tekrar algılanırsa yok say (sürekli okuma spam'ini önler).
- Başarılı kayıt: kısa titreşim + bip, altta yeşil kart: "8835 projesine eklendi · DDM261062".
- Hata / tekrar: uzun titreşim, kırmızı veya turuncu kart ile sebep.
- Son okutulan kaydın özeti ekranda kalır.
- Kamera izni reddedilirse açıklama + tekrar isteme / ayarlara git butonu.
- Fener (flash) aç/kapa butonu — FAT alanı karanlık olabilir.

### 2. Projeler
- `projects/` klasöründeki CSV'lerden liste: "8835 · 12 ürün · son okutma 22.09.2026 10:50".
- Varsayılan sıralama: son okutma zamanına göre (yeniden eskiye).
- Üstte proje no ile arama.

### 3. Proje Detayı
- O projenin kayıtları tablo/liste olarak.
- Sıralama seçeneği: Okutma zamanı (varsayılan) / Seri No / Palet No (paletsizler sonda).
- Her kayıtta atanmışsa palet etiketi görünür; özet satırı: "12 ürün · 8 paletli".
- **Çoklu seçim:** kayda uzun basınca seçim modu açılır, seçim modunda dokunmak seçimi değiştirir; geri tuşu seçimi kapatır. Menüde "Tümünü seç", "Paleti olmayanları seç", "Seçimi temizle".
- **Palet ata** (seçim modu): palet no girilir; projede kullanılmış paletler tek dokunuşla seçilebilir; mevcut paleti değişecek kayıt sayısı uyarı olarak gösterilir; "Paleti kaldır" boş palet atar.
- **Sil** (seçim modu, onay diyaloğu ile). Silme sonrası CSV ve xlsx yeniden yazılır, tekrar kontrol haritası güncellenir. Projenin tüm kayıtları silinirse proje dosyaları da silinir.
- **"Excel olarak indir"** butonu:
  - Android 10+ : `MediaStore.Downloads` ile `Download/FATKatalog/` altına kaydet (platform kanalı).
  - Android 8–9 : izin istemeden sistemin "Farklı kaydet" penceresi (`ACTION_CREATE_DOCUMENT`).
  - Dosya adı: `8835_22-09-2026.xlsx` (proje no + indirme tarihi, gün-ay-yıl).
- **"Paylaş"** butonu: `share_plus` (WhatsApp, e-posta vb.). MIME: `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`.

Alt navigasyon: Okut · Projeler.

## İçe / dışa aktarma

Uygulamanın iç depolaması yalnızca **uygulama kaldırılırsa** veya "Verileri temizle" denirse silinir; normal sürüm güncellemesi veriye dokunmaz. Buna rağmen kaldırmayı gerektiren durumlar olabilir (imza anahtarı değişikliği, telefon değişimi, sürüm düşürme). İndirilen Excel dosyası, verinin uygulama dışındaki kopyasıdır.

**Kullanıcıya ayrı bir "yedek dosyası" kavramı gösterilmez** — fabrikadaki kullanıcı için fazla ayrıntı. Her gün indirdiği Excel dosyasının aynısı geri de yüklenebilir.

Projeler sekmesinin üst çubuğundaki menü (`lib/ui/projects/backup_menu.dart`):

- **Tümünü Excel olarak indir** → bütün projeler tek sayfada, `Download/FATKatalog/FATKatalog_tum_projeler_23-09-2026.xlsx`.
- **Tümünü paylaş** → aynı dosya `share_plus` ile (WhatsApp, e-posta).
- **Excel dosyasından yükle** → sistem dosya seçicisi (`ACTION_OPEN_DOCUMENT`, platform kanalı; ek paket yok).

Proje Detayı'ndaki tek proje için "Excel olarak indir" / "Paylaş" aynen kalır.

Kurallar:

- İçe aktarma **iki düzeni de kabul eder**: tek projenin Excel'i (`8835_23-09-2026.xlsx`) ve tüm projeler dosyası. İkisi de aynı sütunları taşır; Proje No bir sütun olduğu için projeler dosyadan ayrıştırılır, ayrı bir koda gerek yoktur.
- Dosya türü **içeriğe bakarak** ayrılır (zip imzası `PK\x03\x04`), uzantıya değil: paylaşım yoluyla gelen dosyanın uzantısı güvenilmez. CSV de kabul edilir (eski dosyalar, elle düzenlenmiş dosyalar) ama arayüzde adı geçmez.
- Okuma `lib/xlsx/xlsx_reader.dart` ile yapılır — `XlsxWriter` gibi Excel kütüphanesi kullanmaz, yalnızca `archive`. Kendi yazdığımız `inlineStr` hücreleri, Excel'de açılıp kaydedilmiş dosyaların `sharedStrings` hücreleri ve düz sayı hücrelerinin üçünü de okur; atlanmış boş hücreleri sütun harfinden bulur (yoksa sütunlar kayar).
- İçe aktarma **birleştirir, asla silmez**: eksik kayıtlar eklenir; seri no zaten kayıtlıysa o kaydın yalnızca **boş** alanları dosyadan tamamlanır, **dolu bir alanın üstüne asla yazılmaz**. Böylece ofiste Excel'de doldurulan Palet No telefona geçer, ama telefondaki hiçbir bilgi kaybolmaz. Proje No ve Seri No kaydın kimliğidir, değişmez; okutma zamanı da kaydın kendi zamanı kalır, dosyadan alınmaz.
- Seri no dosyada **başka bir projede** görünüyorsa kayda hiç dokunulmaz (dosya ile telefon çelişiyordur).
- Değişiklik olmayan projenin dosyaları yeniden yazılmaz.
- Sonuç sayıyla bildirilir: "12 kayıt eklendi · 9 kayıt güncellendi · 30 kayıt zaten vardı · 3 satır okunamadı".
- Başlık satırında Seri No yoksa dosya reddedilir ("Bu dosya bir FATKatalog kayıt dosyası değil"), hiçbir şey yazılmaz.

## Sürümleme

- Sürüm `pubspec.yaml` içindeki `version: 1.2.0+4` satırında; `+` sonrası Android `versionCode`.
- **`versionCode` asla azaltılmaz.** Daha düşük numaralı bir APK kurulu sürümün üzerine kurulamaz; kullanıcı uygulamayı kaldırmak zorunda kalır ve kayıtları silinir.
- Her sürümde `lib/app_info.dart` içindeki `releaseNotes` listesine en üste bir madde eklenir. Uygulamada "Hakkında → Yenilikler" bu listeden gelir, böylece sahadaki kullanıcı da hangi sürümde ne değiştiğini görür.
- **İmza anahtarı sabit kalmalı.** Farklı anahtarla imzalanmış APK kurulu sürümün üzerine kurulamaz (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`) ve kaldırma tüm kayıtları siler. Release yapılandırması hâlâ debug anahtarını kullanıyor; gerçek keystore'a geçiş, sahadaki telefonlar yedeklerini aldıktan sonra yapılacak (aşağıya bkz.).

## Kurumsal kimlik (DEDEM Mekatronik)

Uygulama DEDEM Mekatronik'in fabrika içi kullanımı içindir. Görünümü kurumsal kimliğe uygun olmalı.

### Varlık dosyaları
Tek kaynak: `branding/Dedem-Mekatronik-Kurumsal-Kimlik-Rehberi.pdf`. Ayrıntılar ve üretim adımları `branding/README.md`'de.

```
branding/
  Dedem-Mekatronik-Kurumsal-Kimlik-Rehberi.pdf  ← resmi rehber
  logo_vertical_white.png  ← rehber s.12 "%100 black" varyasyonu, şeffaf zemin
  mark.png                 ← aynı varyasyonun küre işareti
  colors.md                ← resmi renk kodları (HEX)
tool/branding/generate_assets.ps1  ← uygulama varlıklarını bu kaynaktan üretir
```

- Logo **uydurulmaz, yeniden çizilmez, AI ile üretilmez**; yalnızca rehberdeki / `branding/` içindeki resmi logo kullanılır.
- Mevcut logo varyasyonu (beyaz yazı) **yalnızca kurumsal siyah zeminde** kullanılır.
- Pazarlamadan resmi SVG/PNG dosyaları gelirse render edilmiş PNG'lerin yerine onlar kullanılır.

### Uygulama ikonu
- Resmi logodan **adaptive icon** üret (`android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`, foreground + background katmanı). minSdk 26 olduğu için eski PNG yoğunlukları gerekmez.
- Android 13+ temalı ikon için `monochrome` katmanı ekle (`logo_mono` varsa ondan).
- Logo güvenli alan (safe zone, 66dp çember) içinde kalmalı, kırpılmamalı.
- Resmi PNG logo gelince `flutter_launcher_icons` da kullanılabilir.

### Açılış ekranı (Splash)
- Android yerel splash teması (`android/app/src/main/res/values*/styles.xml`, API 31+ için `windowSplashScreen*`): arka plan kurumsal ana renk (veya etiketteki gibi siyah), ortada logo.

### Tema renkleri
- Renkler `branding/colors.md`'den alınır ve `lib/ui/theme/colors.dart` içinde tek yerde tanımlanır (`dedemBlack` #1D1D1B, `dedemRed` #E30613, `dedemWhite`, `dedemSilver`, `dedemGray`, `dedemSilverC`). Dart kodunda başka yerde sabit renk kodu yazılmaz. (İkon/splash için Android `res/values/colors.xml` aynı değerleri taşır.)
- Kullanım: üst çubuk / splash / ikon zemini / Excel başlığı **siyah**; butonlar ve vurgular **kırmızı**. Yazı tipi **Roboto**.
- `ColorScheme` açık/koyu için bu renklerden elle kurulur. **Dynamic color (Material You) kullanılmaz**; aksi halde telefonun duvar kağıdı renkleri kurumsal renklerin yerine geçer.
- Başarı (yeşil), uyarı (turuncu) ve hata (kırmızı) renkleri kurumsal renklerden bağımsız, net ve okunaklı kalmalı; okutma geri bildirimi fabrika ortamında bir bakışta anlaşılmalı.
- Kontrast en az WCAG AA seviyesinde olmalı (atölye ışığında okunabilirlik).

### Uygulama içinde logo
- Üst çubukta (AppBar) küçük logo + "FATKatalog" başlığı.
- "Hakkında" diyaloğu: logo, uygulama sürümü, "DEDEM Mekatronik – fabrika içi kullanım içindir".

### Excel çıktısı
- Başlık satırı arka planı kurumsal ana renk, yazısı `OnPrimary` rengi (styles.xml'de bir `fill` girdisi). Excel'e logo gömülmez; dosya sade kalır.

## Klasör yapısı

```
lib/
├── main.dart, app.dart, app_info.dart (sürüm notları)
├── model/        label_record.dart, parse_result.dart
├── parser/       qr_parser.dart
├── storage/      project_repository.dart, csv_codec.dart, timestamp.dart
├── xlsx/         xlsx_writer.dart, xlsx_reader.dart
├── platform/     native_bridge.dart (bip, titreşim, MediaStore, dosya seçme)
├── export/       export_manager.dart (tek proje), backup_manager.dart (tümü + içe aktarma)
└── ui/
    ├── scan/
    ├── projects/
    ├── detail/
    ├── widgets/
    └── theme/
```

`model/`, `parser/`, `storage/` ve `xlsx/` Flutter'a bağımlı olmamalı (yalnızca `dart:io` / saf Dart).

## Testler

`test/` altında unit testler (`flutter test`):

- `qr_parser_test.dart`: geçerli örnek, eksik alan, fazla alan, 3/5 haneli proje no, boşluklu girdi, hatalı tarih.
- `csv_codec_test.dart`: `;` ve `"` içeren alanların gidiş-dönüşü.
- `xlsx_writer_test.dart`: üretilen zip'in beklenen tüm girdileri içermesi, XML'lerin parse edilebilmesi (`xml` dev bağımlılığı), özel karakter kaçışı, `06/2026` değerinin metin hücresi olarak kalması.
- `xlsx_reader_test.dart`: `XlsxWriter` ile yazılan dosyanın birebir geri okunması, `06/2026` ve baştaki sıfırın korunması, özel karakterler, Excel'in kaydettiği biçim (`sharedStrings` + atlanmış boş hücreler), zip olmayan dosyanın reddi.
- `project_repository_test.dart` (geçici klasörle): ekleme, tekrar reddi, silme, projelere göre gruplama, palet atama, eski/bilinmeyen sütunlu dosya okuma, dışa aktarma ve içe aktarma (indirilen proje Excel'inin geri yüklenmesi, boş klasöre geri yükleme, birleştirme, bozuk satır sayımı, yanlış dosyanın reddi).

Test verisi:

```
8835*P2-00180700*601107999*DDM261062*06/2026
8835*P2-00180701*601108000*DDM261063*06/2026
8840*P2-00190100*601109500*DDM261101*07/2026
```

## Derleme

```bash
flutter pub get
flutter test
flutter build apk --debug
# APK: build/app/outputs/flutter-apk/app-debug.apk
```

### İmza anahtarı (dikkat)

`android/app/build.gradle.kts` içindeki release bloğu hâlâ **debug anahtarıyla** imzalıyor. Sahadaki telefonlarda kurulu APK'lar bu anahtarla imzalandığı için `~/.android/debug.keystore` fiilen üretim anahtarıdır: kaybolursa güncelleme yayınlanamaz, telefonlar uygulamayı kaldırmak zorunda kalır ve **tüm kayıtlar silinir**. Bu dosya kurumsal bir yerde yedeklenmeli (repoya **konmaz**).

Gerçek keystore'a geçiş sırası:

1. Yedekleme özelliğini içeren sürüm (1.2.0) mevcut anahtarla dağıtılır — normal güncelleme, veri kaybı yok.
2. Sahadaki herkes "Yedek al" ile yedeğini alır ve dosyayı telefon dışına çıkarır.
3. Gerçek keystore üretilir, `key.properties` ile bağlanır (repoya konmaz, yedeklenir).
4. Yeni imzalı sürüm kurulurken telefonlarda bir kereliğine kaldır/kur gerekir; ardından yedek "Yedekten geri yükle" ile içeri alınır.

## Geliştirme sırası

1. Proje iskeleti, alt navigasyon, tema.
2. `QrParser` + testleri.
3. `CsvCodec` + `ProjectRepository` (atomik yazma, tekrar kontrolü) + testleri.
4. `XlsxWriter` + testleri; üretilen örnek dosyayı Excel'de elle doğrula.
5. Kamera + ML Kit okutma ekranı, izin akışı, titreşim/bip, fener.
6. Projeler ve Proje Detayı ekranları.
7. İndirme (MediaStore) ve paylaşım.
8. Hata durumları ve son rötuşlar.

Her adımda derlemenin ve testlerin geçtiğinden emin ol, sonra sonrakine geç.

## Kapsam dışı (şimdilik)

- iOS derlemesi (Flutter sayesinde ileride eklenebilir; `mobile_scanner` iOS'u destekler, platform kanalının iOS tarafı yazılmalı)
- Sunucu / SharePoint senkronizasyonu
- Kullanıcı girişi, okutan kişi bilgisi
- FAT sonucu (geçti/kaldı) ve not alanı
- Etikette olup QR'da olmayan bilgiler (gerilim, güç, ağırlık) — ileride ERP kodu üzerinden eşleme tablosuyla eklenebilir

## Açık sorular

- Poz No'nun biçimi (örnek değer) öğrenilince doğrulama kuralı eklenebilir.
