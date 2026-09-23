import 'package:flutter/material.dart';

import '../../xlsx/xlsx_writer.dart';
import 'colors.dart';

// Kurumsal kimlik: siyah zemin üzerinde logo (üst çubuk), etkileşimli öğelerde
// kurumsal kırmızı, yazı tipi Roboto.
//
// Dynamic color (Material You) bilinçli olarak kullanılmıyor: duvar kağıdı
// renkleri kurumsal renklerin yerine geçmemeli.

const _fontFamily = 'Roboto'; // kurumsal yazı tipi; Android'in sistem yazı tipi

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: dedemRed, // beyaz yazıyla 4.9:1
  onPrimary: dedemWhite,
  primaryContainer: neutralPage,
  onPrimaryContainer: dedemBlack,
  secondary: dedemBlack,
  onSecondary: dedemWhite,
  secondaryContainer: dedemSilverC,
  onSecondaryContainer: dedemBlack,
  surface: dedemWhite,
  onSurface: dedemBlack,
  onSurfaceVariant: dedemSilver, // beyaz zeminde 5.0:1
  surfaceContainerLowest: dedemWhite,
  surfaceContainerLow: neutralPage,
  surfaceContainer: neutralPage,
  surfaceContainerHigh: neutralPage,
  surfaceContainerHighest: dedemSilverC,
  outline: dedemGray,
  outlineVariant: dedemSilverC,
  error: statusError,
  onError: onStatus,
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: dedemRed,
  onPrimary: dedemWhite,
  primaryContainer: neutralDark3,
  onPrimaryContainer: dedemWhite,
  secondary: dedemSilverC,
  onSecondary: dedemBlack,
  secondaryContainer: neutralDark3,
  onSecondaryContainer: dedemWhite,
  surface: neutralDark1,
  onSurface: neutralPage,
  onSurfaceVariant: dedemSilverC,
  surfaceContainerLowest: neutralDark1,
  surfaceContainerLow: dedemBlack,
  surfaceContainer: dedemBlack,
  surfaceContainerHigh: neutralDark2,
  surfaceContainerHighest: neutralDark3,
  outline: dedemSilver,
  outlineVariant: neutralDark3,
  error: statusError,
  onError: onStatus,
);

ThemeData _build(ColorScheme scheme) => ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: _fontFamily,
      // Üst çubuk her iki temada da siyah: resmi logo varyasyonu siyah zemin
      // + beyaz yazı içindir.
      appBarTheme: const AppBarTheme(
        backgroundColor: dedemBlack,
        foregroundColor: dedemWhite,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: dedemRed.withValues(alpha: 0.16),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? dedemRed
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );

final lightTheme = _build(_lightScheme);
final darkTheme = _build(_darkScheme);

/// Excel başlık satırı: kurumsal siyah zemin + beyaz yazı.
final excelHeaderStyle = XlsxHeaderStyle(
  fillArgb: dedemBlack.toARGB32(),
  fontArgb: dedemWhite.toARGB32(),
);
