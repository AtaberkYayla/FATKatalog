import 'package:flutter/material.dart';

import '../../app_info.dart';
import '../../platform/native_bridge.dart';
import '../theme/colors.dart';

// Logo görselleri DEDEM Mekatronik Kurumsal Kimlik Rehberi'ndeki resmi
// "%100 siyah zemin, beyaz yazı" varyasyonundan alınmıştır (branding/README.md).
// Bu varyasyon YALNIZCA siyah (dedemBlack) zemin üzerinde kullanılır.

const _markAsset = 'assets/branding/mark.png';
const _verticalLogoAsset = 'assets/branding/logo_vertical_white.png';

/// Logonun küre işareti; üst çubuk gibi dar alanlar için.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        _markAsset,
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'DEDEM Mekatronik',
      );
}

/// Üst çubuk başlığı: logo işareti + "FATKatalog".
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(size: 32),
        const SizedBox(width: 12),
        // Rehberdeki logo formlarında işaret ile yazı arasındaki kırmızı çizgi.
        Container(width: 2, height: 24, color: dedemRed),
        const SizedBox(width: 12),
        const Text('FATKatalog', style: TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class AboutButton extends StatelessWidget {
  const AboutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Hakkında',
      icon: const Icon(Icons.info_outline),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const _AboutDialog(),
      ),
    );
  }
}

class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      titlePadding: EdgeInsets.zero,
      title: ColoredBox(
        color: dedemBlack,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Image.asset(
              _verticalLogoAsset,
              width: 180,
              semanticLabel: 'DEDEM Mekatronik',
            ),
          ),
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('FATKatalog',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            FutureBuilder<String>(
              future: NativeBridge.appVersion(),
              builder: (context, snapshot) => Text(
                'Sürüm ${snapshot.data ?? '…'}',
                style: text.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'DEDEM Mekatronik – fabrika içi kullanım içindir',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: 20),
            const _ReleaseNotes(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

/// Sürüm geçmişi (lib/app_info.dart): en son sürüm açık, öncekiler katlanmış.
class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Yenilikler',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final note in releaseNotes)
          _NoteSection(note: note, expanded: note == releaseNotes.first),
      ],
    );
  }
}

class _NoteSection extends StatelessWidget {
  const _NoteSection({required this.note, required this.expanded});

  final ReleaseNote note;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final change in note.changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $change', style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
    final title = Text(
      '${note.version}  ·  ${note.date}',
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
    );

    if (expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 6), body],
      );
    }
    return Theme(
      // Katlanmış bölümlerin çevresindeki ayırıcı çizgileri kaldır.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: title,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [body],
      ),
    );
  }
}
