import 'dart:ui';

// Uygulamadaki TÜM renkler burada tanımlanır; Dart kodunda başka yerde sabit
// renk kodu yazılmaz. Kaynak: DEDEM Mekatronik Kurumsal Kimlik Rehberi,
// "Logotype Renk" sayfası (bkz. branding/colors.md). İkon ve splash için
// android/app/src/main/res/values/colors.xml aynı değerleri taşır.

// --- Resmi kurumsal renkler ---
const dedemBlack = Color(0xFF1D1D1B); // BLACK    CMYK 0/0/0/100
const dedemRed = Color(0xFFE30613); // RED      CMYK 0/100/100/0
const dedemWhite = Color(0xFFFFFFFF); // WHITE
const dedemSilver = Color(0xFF706F6F); // SILVER   CMYK 0/1/1/56
const dedemGray = Color(0xFF9D9D9C); // GRAY     CMYK 0/0/1/38
const dedemSilverC = Color(0xFFC6C6C6); // SILVER C CMYK 0/0/0/22

// --- Nötr zeminler (rehberin sayfa zemini ve koyu tema tonları) ---
const neutralPage = Color(0xFFF1F2F2);
const neutralDark1 = Color(0xFF121211);
const neutralDark2 = Color(0xFF2A2A28);
const neutralDark3 = Color(0xFF3A3A38);

// Okutma geri bildirimi: kurumsal renklerden bağımsız, beyaz yazıyla
// WCAG AA (>= 4.5:1). Hata kırmızısı, kurumsal kırmızıdan (butonlar)
// ayırt edilsin diye daha koyu ve her zaman ikonla birlikte kullanılır.
const statusSuccess = Color(0xFF1E7B34);
const statusWarning = Color(0xFFB45309);
const statusError = Color(0xFFB91C1C);
const onStatus = Color(0xFFFFFFFF);

// Kamera önizlemesi üzerindeki karartma ve nişan çerçevesi.
const scrimDark = Color(0x99000000);
const viewfinderFrame = Color(0xFFFFFFFF);
