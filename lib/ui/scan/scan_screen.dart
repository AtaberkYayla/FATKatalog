import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../platform/native_bridge.dart';
import '../theme/colors.dart';
import 'result_card.dart';
import 'scan_controller.dart';

/// Okutma ekranı: tam ekran kamera, nişan çerçevesi, fener ve son sonuç kartı.
///
/// Kamera iznini `mobile_scanner` ilk başlatmada ister; reddedilirse açıklama,
/// tekrar deneme ve ayarlara gitme seçenekleri gösterilir.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.controller});

  final ScanController controller;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  final _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_camera.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_camera.value.hasCameraPermission) {
      // İzin penceresi de uygulamayı "inactive" yapar; o sırada kameraya
      // dokunma. Kullanıcı ayarlardan izin verip dönmüş olabilir.
      if (state == AppLifecycleState.resumed) unawaited(_retryIfGranted());
      return;
    }
    // Arka plandayken kamerayı bırak; fener de kapanır.
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_camera.start());
      case AppLifecycleState.inactive:
        unawaited(_camera.stop());
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        break;
    }
  }

  bool get _permissionDenied =>
      _camera.value.error?.errorCode == MobileScannerErrorCode.permissionDenied;

  Future<void> _retryIfGranted() async {
    if (_permissionDenied && await NativeBridge.hasCameraPermission()) {
      await _camera.start();
    }
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        unawaited(widget.controller.onDetected(raw));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _camera,
      builder: (context, _, _) {
        if (_permissionDenied) {
          return _PermissionRequest(
            onRetry: () => unawaited(_camera.start()),
            onOpenSettings: () => unawaited(NativeBridge.openAppSettings()),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) => _scanner(constraints.biggest),
        );
      },
    );
  }

  Widget _scanner(Size size) {
    final side = size.shortestSide * 0.7;
    // Kart için alttan yer bırak; çerçeve biraz yukarıda dursun.
    final window = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.4),
      width: side,
      height: side,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _camera,
          // Yalnızca çerçevedeki QR okunur; yan yana etiketler karışmaz.
          scanWindow: window,
          onDetect: _onDetect,
          errorBuilder: (context, error) => _CameraError(error: error),
        ),
        IgnorePointer(
          child: CustomPaint(painter: _ViewfinderPainter(window)),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: window.bottom + 16,
          child: const Text(
            'QR kodu çerçevenin içine getirin',
            textAlign: TextAlign.center,
            style: TextStyle(color: viewfinderFrame, fontSize: 16),
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: _TorchButton(camera: _camera),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final last = widget.controller.last;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: last == null
                    ? const SizedBox.shrink()
                    : ResultCard(key: ObjectKey(last), outcome: last),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.camera});

  final MobileScannerController camera;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: camera,
      builder: (context, state, _) {
        final torch = state.torchState;
        if (!state.isInitialized || torch == TorchState.unavailable) {
          return const SizedBox.shrink();
        }
        final on = torch == TorchState.on;
        return IconButton.filled(
          iconSize: 28,
          tooltip: on ? 'Feneri kapat' : 'Feneri aç',
          style: IconButton.styleFrom(
            backgroundColor: on ? viewfinderFrame : scrimDark,
            foregroundColor: on ? dedemBlack : viewfinderFrame,
            fixedSize: const Size(56, 56),
          ),
          icon: Icon(on ? Icons.flashlight_on : Icons.flashlight_off),
          onPressed: () => unawaited(camera.toggleTorch()),
        );
      },
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(window, const Radius.circular(16));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(frame),
      ),
      Paint()..color = scrimDark,
    );

    // Köşe işaretleri
    final paint = Paint()
      ..color = viewfinderFrame
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const len = 36.0;
    const r = 16.0;
    final l = window.left, t = window.top, rt = window.right, b = window.bottom;
    canvas
      ..drawPath(
          Path()
            ..moveTo(l, t + len)
            ..lineTo(l, t + r)
            ..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))
            ..lineTo(l + len, t),
          paint)
      ..drawPath(
          Path()
            ..moveTo(rt - len, t)
            ..lineTo(rt - r, t)
            ..arcToPoint(Offset(rt, t + r), radius: const Radius.circular(r))
            ..lineTo(rt, t + len),
          paint)
      ..drawPath(
          Path()
            ..moveTo(rt, b - len)
            ..lineTo(rt, b - r)
            ..arcToPoint(Offset(rt - r, b), radius: const Radius.circular(r))
            ..lineTo(rt - len, b),
          paint)
      ..drawPath(
          Path()
            ..moveTo(l + len, b)
            ..lineTo(l + r, b)
            ..arcToPoint(Offset(l, b - r), radius: const Radius.circular(r))
            ..lineTo(l, b - len),
          paint);
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.window != window;
}

class _PermissionRequest extends StatelessWidget {
  const _PermissionRequest({
    required this.onRetry,
    required this.onOpenSettings,
  });

  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 64),
            const SizedBox(height: 16),
            Text('Kamera izni gerekli',
                style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Etiketlerdeki QR kodlarını okutmak için kamera izni gerekiyor. '
              'Görüntüler kaydedilmez, cihaz dışına gönderilmez.\n\n'
              'İzin penceresi artık çıkmıyorsa izni uygulama ayarlarından '
              'açabilirsiniz.',
              style: text.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.photo_camera),
              label: const Text('İzin ver'),
              onPressed: onRetry,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('Ayarlara git'),
              onPressed: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: dedemBlack,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Kamera başlatılamadı.\n'
            '${error.errorDetails?.message ?? error.errorCode.name}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: dedemWhite, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
