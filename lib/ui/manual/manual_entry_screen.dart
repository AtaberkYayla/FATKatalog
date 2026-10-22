import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../model/parse_result.dart';
import '../../parser/manual_entry_validator.dart';
import '../../platform/native_bridge.dart';
import '../../storage/project_repository.dart';
import '../theme/colors.dart';

/// Etiketsiz malzemeleri elle ekleme formu.
///
/// Proje No ve Seri No (kimlik alanları) zorunludur; biri boşsa kayıt
/// oluşturulmaz. Kayıttan sonra form açık kalır, Proje No korunur; arka arkaya
/// birkaç malzeme eklenebilir.
class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({
    super.key,
    required this.repository,
    this.initialProjectNo = '',
    this.onAdded,
  });

  final ProjectRepository repository;

  /// Kayıt eklenince proje no'suyla çağrılır.
  final void Function(String projectNo)? onAdded;

  /// Proje Detayı'ndan açılırsa o projenin no'su hazır gelir.
  final String initialProjectNo;

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  late final _projectNo = TextEditingController(text: widget.initialProjectNo);
  final _workOrderNo = TextEditingController();
  final _erpProductNo = TextEditingController();
  final _serialNo = TextEditingController();
  final _productionDate = TextEditingController();
  final _positionNo = TextEditingController();
  final _serialFocus = FocusNode();

  var _busy = false;
  String? _error;
  String? _lastAdded;

  List<TextEditingController> get _all => [
        _projectNo,
        _workOrderNo,
        _erpProductNo,
        _serialNo,
        _productionDate,
        _positionNo,
      ];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    _serialFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final result = ManualEntryValidator.validate(
      projectNo: _projectNo.text,
      workOrderNo: _workOrderNo.text,
      erpProductNo: _erpProductNo.text,
      serialNo: _serialNo.text,
      productionDate: _productionDate.text,
      positionNo: _positionNo.text,
    );
    switch (result) {
      case ParseError(:final reason):
        setState(() => _error = reason);
        unawaited(NativeBridge.feedback(FeedbackKind.error));
      case ParseSuccess(:final record):
        setState(() {
          _busy = true;
          _error = null;
        });
        try {
          final added = await widget.repository.add(record);
          if (!mounted) return;
          switch (added) {
            case Added(:final entry):
              unawaited(NativeBridge.feedback(FeedbackKind.success));
              widget.onAdded?.call(entry.record.projectNo);
              setState(() {
                _lastAdded =
                    '${entry.record.projectNo} projesine eklendi · ${entry.record.serialNo}';
                // Proje No kalır, geri kalanı sıradaki malzeme için temizlenir.
                for (final c in _all.skip(1)) {
                  c.clear();
                }
              });
              // Sıradaki malzeme için imleç Seri No'da.
              _serialFocus.requestFocus();
            case Duplicate(:final serialNo, :final existingProjectNo):
              unawaited(NativeBridge.feedback(FeedbackKind.warning));
              setState(() => _error =
                  '$serialNo zaten $existingProjectNo projesinde kayıtlı');
          }
        } on FileSystemException catch (e) {
          setState(() =>
              _error = 'Kayıt yazılamadı: ${e.osError?.message ?? e.message}');
        } finally {
          if (mounted) setState(() => _busy = false);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Manuel ekle')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Etiketi olmayan malzemeler için. Proje No ve Seri No zorunlu; '
              'bildiğiniz diğer alanları doldurun.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _field(
              _projectNo,
              'Proje No *',
              keyboardType: TextInputType.number,
              formatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              autofocus: widget.initialProjectNo.isEmpty,
            ),
            _field(_workOrderNo, 'İş Emri No',
                capitalization: TextCapitalization.characters),
            _field(
              _erpProductNo,
              'Erp Ürün No',
              keyboardType: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            _field(
              _serialNo,
              'Seri No *',
              focusNode: _serialFocus,
              // Proje No hazır geldiyse imleç doğrudan Seri No'da başlar.
              autofocus: widget.initialProjectNo.isNotEmpty,
              capitalization: TextCapitalization.characters,
            ),
            _field(
              _productionDate,
              'Üretim Yılı',
              helper: 'AA/YYYY, ör. 06/2026',
              keyboardType: TextInputType.datetime,
            ),
            _field(
              _positionNo,
              'Poz No',
              capitalization: TextCapitalization.characters,
              action: TextInputAction.done,
              onSubmitted: _submit,
            ),
            if (_error != null)
              _StatusBox(
                color: statusError,
                icon: Icons.error,
                text: _error!,
              ),
            if (_lastAdded != null && _error == null)
              _StatusBox(
                color: statusSuccess,
                icon: Icons.check_circle,
                text: _lastAdded!,
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Ekle'),
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? helper,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    TextCapitalization capitalization = TextCapitalization.none,
    TextInputAction action = TextInputAction.next,
    VoidCallback? onSubmitted,
    FocusNode? focusNode,
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        textCapitalization: capitalization,
        textInputAction: action,
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _StatusBox extends StatelessWidget {
  const _StatusBox({
    required this.color,
    required this.icon,
    required this.text,
  });

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: onStatus),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: onStatus,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
