import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../model/label_record.dart';
import '../../model/parse_result.dart';
import '../../parser/qr_parser.dart';
import '../../platform/native_bridge.dart';
import '../../storage/project_repository.dart';

sealed class ScanOutcome {
  const ScanOutcome();
}

final class ScanSaved extends ScanOutcome {
  const ScanSaved(this.entry);

  final ScanEntry entry;
}

final class ScanDuplicate extends ScanOutcome {
  const ScanDuplicate({required this.serialNo, required this.projectNo});

  final String serialNo;
  final String projectNo;
}

final class ScanInvalid extends ScanOutcome {
  const ScanInvalid({required this.reason, required this.raw});

  final String reason;
  final String raw;
}

final class ScanFailed extends ScanOutcome {
  const ScanFailed(this.message);

  final String message;
}

/// Okutma akışı: ayrıştır → doğrula → tekrar kontrolü → kaydet → geri bildirim.
///
/// Kamera ekranından bağımsız yaşar; sekme değişse de son sonuç korunur.
class ScanController extends ChangeNotifier {
  ScanController(this._repository);

  static const _repeatWindow = Duration(seconds: 3);

  final ProjectRepository _repository;

  String? _lastRaw;
  DateTime _lastSeenAt = DateTime.fromMillisecondsSinceEpoch(0);

  ScanOutcome? _last;

  /// Son okutmanın sonucu; ekranda kalıcı olarak gösterilir.
  ScanOutcome? get last => _last;

  Future<void> onDetected(String raw) async {
    final now = DateTime.now();
    final isRepeat =
        raw == _lastRaw && now.difference(_lastSeenAt) < _repeatWindow;
    // Etiket kadrajda kaldıkça süre uzar; aynı etiket tekrar tekrar işlenmez.
    _lastRaw = raw;
    _lastSeenAt = now;
    if (isRepeat) return;

    final outcome = await _process(raw);
    _last = outcome;
    notifyListeners();
    await NativeBridge.feedback(switch (outcome) {
      ScanSaved() => FeedbackKind.success,
      ScanDuplicate() => FeedbackKind.warning,
      ScanInvalid() || ScanFailed() => FeedbackKind.error,
    });
  }

  Future<ScanOutcome> _process(String raw) async {
    switch (QrParser.parse(raw)) {
      case ParseError(:final reason):
        return ScanInvalid(reason: reason, raw: raw);
      case ParseSuccess(:final record):
        try {
          return switch (await _repository.add(record)) {
            Added(:final entry) => ScanSaved(entry),
            Duplicate(:final serialNo, :final existingProjectNo) =>
              ScanDuplicate(serialNo: serialNo, projectNo: existingProjectNo),
          };
        } on FileSystemException catch (e) {
          return ScanFailed('Kayıt yazılamadı: ${e.osError?.message ?? e.message}');
        }
    }
  }
}
