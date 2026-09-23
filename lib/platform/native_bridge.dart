import 'package:flutter/services.dart';

enum FeedbackKind { success, warning, error }

/// Android'e özgü işler için platform kanalı (bkz. android/.../MainActivity.kt).
class NativeBridge {
  NativeBridge._();

  static const _channel = MethodChannel('com.dedem.fatkatalog/native');

  /// Başarı: kısa titreşim + bip. Uyarı/hata: uzun titreşim.
  static Future<void> feedback(FeedbackKind kind) async {
    try {
      await _channel.invokeMethod('feedback', kind.name);
    } on PlatformException {
      // Geri bildirim olmasa da okutma devam etmeli.
    }
  }

  /// Kamera izni verilmiş mi (istemeden yalnızca kontrol eder).
  static Future<bool> hasCameraPermission() async =>
      await _channel.invokeMethod<bool>('hasCameraPermission') ?? false;

  /// Uygulamanın sistem ayarları sayfasını açar (izni elle vermek için).
  static Future<void> openAppSettings() =>
      _channel.invokeMethod<void>('openAppSettings');

  /// Uygulama sürümü (Android `versionName`).
  static Future<String> appVersion() async {
    try {
      return await _channel.invokeMethod<String>('appVersion') ?? '?';
    } on PlatformException {
      return '?';
    }
  }

  /// Dosyayı `Download/FATKatalog/` altına kaydeder (Android 10+: MediaStore,
  /// Android 8–9: sistemin "Farklı kaydet" penceresi).
  ///
  /// Kaydedilen konumun okunabilir açıklamasını, kullanıcı vazgeçerse `null`
  /// döndürür.
  static Future<String?> saveToDownloads({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) =>
      _channel.invokeMethod<String>('saveToDownloads', {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'mimeType': mimeType,
      });

  /// Sistemin dosya seçicisini açar; seçilen dosyanın uygulama önbelleğine
  /// alınmış kopyasının yolunu, kullanıcı vazgeçerse `null` döndürür.
  static Future<String?> pickFile() => _channel.invokeMethod<String>('pickFile');
}
