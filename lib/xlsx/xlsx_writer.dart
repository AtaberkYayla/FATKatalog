import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';

/// Başlık satırı renkleri, 32 bit ARGB (ör. `0xFF1A1A1A`).
class XlsxHeaderStyle {
  const XlsxHeaderStyle({required this.fillArgb, required this.fontArgb});

  final int fillArgb;
  final int fontArgb;
}

/// Tek sayfalık, minimal bir .xlsx (SpreadsheetML) üretir. Excel kütüphanesi
/// kullanmaz; yalnızca zip için `archive` paketine dayanır.
///
/// - Tüm hücreler metin (`inlineStr` + `@` sayı biçimi): `06/2026` tarihe,
///   `601107999` sayıya dönüşmez, baştaki sıfırlar korunur.
/// - Başlık satırı kalın, renkli zeminli, dondurulmuş ve otomatik filtreli.
class XlsxWriter {
  XlsxWriter._();

  static const _nsMain =
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _nsRel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const _nsPkgRel =
      'http://schemas.openxmlformats.org/package/2006/relationships';
  static const _xmlDecl =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

  // styles.xml içindeki cellXfs indeksleri
  static const _styleText = 1;
  static const _styleHeader = 2;

  static const _minColWidth = 10;
  static const _maxColWidth = 50;

  /// .xlsx dosyasının baytlarını döndürür.
  static List<int> encode({
    required String sheetName,
    required List<String> header,
    required List<List<String>> rows,
    required XlsxHeaderStyle headerStyle,
  }) {
    final safeName = sanitizeSheetName(sheetName);
    final columnCount = [
      header.length,
      ...rows.map((r) => r.length),
      1,
    ].reduce(math.max);

    final parts = <String, String>{
      '[Content_Types].xml': _contentTypes(),
      '_rels/.rels': _rootRels(),
      'xl/workbook.xml': _workbook(safeName, columnCount, rows.length + 1),
      'xl/_rels/workbook.xml.rels': _workbookRels(),
      'xl/styles.xml': _styles(headerStyle),
      'xl/worksheets/sheet1.xml': _sheet(header, rows, columnCount),
    };

    final archive = Archive();
    parts.forEach((name, xml) {
      final bytes = utf8.encode(xml);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return ZipEncoder().encode(archive);
  }

  static String _contentTypes() => '$_xmlDecl'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '</Types>';

  static String _rootRels() => '$_xmlDecl'
      '<Relationships xmlns="$_nsPkgRel">'
      '<Relationship Id="rId1" Type="$_nsRel/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  static String _workbook(String sheetName, int columnCount, int rowCount) {
    // Excel otomatik filtre aralığını bu gizli tanımlı adla da takip eder.
    final quotedName = "'${sheetName.replaceAll("'", "''")}'";
    final filterRef =
        '$quotedName!\$A\$1:\$${columnName(columnCount - 1)}\$$rowCount';
    return '$_xmlDecl'
        '<workbook xmlns="$_nsMain" xmlns:r="$_nsRel">'
        '<sheets><sheet name="${escapeXml(sheetName)}" sheetId="1" r:id="rId1"/></sheets>'
        '<definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">'
        '${escapeXml(filterRef)}'
        '</definedName></definedNames>'
        '</workbook>';
  }

  static String _workbookRels() => '$_xmlDecl'
      '<Relationships xmlns="$_nsPkgRel">'
      '<Relationship Id="rId1" Type="$_nsRel/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="$_nsRel/styles" Target="styles.xml"/>'
      '</Relationships>';

  static String _styles(XlsxHeaderStyle style) => '$_xmlDecl'
      '<styleSheet xmlns="$_nsMain">'
      '<fonts count="2">'
      '<font><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
      '<font><b/><sz val="11"/><color rgb="${_argbHex(style.fontArgb)}"/><name val="Calibri"/><family val="2"/></font>'
      '</fonts>'
      '<fills count="3">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="${_argbHex(style.fillArgb)}"/><bgColor indexed="64"/></patternFill></fill>'
      '</fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="3">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="49" fontId="1" fillId="2" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';

  static String _sheet(
      List<String> header, List<List<String>> rows, int columnCount) {
    final ref = 'A1:${columnName(columnCount - 1)}${rows.length + 1}';
    final sb = StringBuffer()
      ..write(_xmlDecl)
      ..write('<worksheet xmlns="$_nsMain" xmlns:r="$_nsRel">')
      ..write('<dimension ref="$ref"/>')
      ..write('<sheetViews><sheetView workbookViewId="0">')
      ..write(
          '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>')
      ..write('<selection pane="bottomLeft" activeCell="A2" sqref="A2"/>')
      ..write('</sheetView></sheetViews>')
      ..write('<sheetFormatPr defaultRowHeight="15"/>')
      ..write('<cols>');
    for (var c = 0; c < columnCount; c++) {
      final width = _columnWidth(c, header, rows);
      sb.write('<col min="${c + 1}" max="${c + 1}" width="$width" customWidth="1"/>');
    }
    sb.write('</cols><sheetData>');
    _writeRow(sb, 1, header, _styleHeader);
    for (var r = 0; r < rows.length; r++) {
      _writeRow(sb, r + 2, rows[r], _styleText);
    }
    sb
      ..write('</sheetData>')
      ..write('<autoFilter ref="$ref"/>')
      ..write('</worksheet>');
    return sb.toString();
  }

  static void _writeRow(
      StringBuffer sb, int rowNumber, List<String> values, int style) {
    sb.write('<row r="$rowNumber">');
    for (var c = 0; c < values.length; c++) {
      final value = _stripInvalidXmlChars(values[c]);
      final space = value != value.trim() ? ' xml:space="preserve"' : '';
      sb.write('<c r="${columnName(c)}$rowNumber" s="$style" t="inlineStr">'
          '<is><t$space>${escapeXml(value)}</t></is></c>');
    }
    sb.write('</row>');
  }

  static int _columnWidth(
      int column, List<String> header, List<List<String>> rows) {
    var longest = column < header.length ? header[column].length : 0;
    for (final row in rows) {
      if (column < row.length) longest = math.max(longest, row[column].length);
    }
    return (longest + 3).clamp(_minColWidth, _maxColWidth);
  }

  /// 0 → A, 25 → Z, 26 → AA ...
  static String columnName(int index) {
    var n = index + 1;
    final chars = <int>[];
    while (n > 0) {
      final rem = (n - 1) % 26;
      chars.insert(0, 0x41 + rem);
      n = (n - 1) ~/ 26;
    }
    return String.fromCharCodes(chars);
  }

  /// Excel sayfa adı kuralları: en fazla 31 karakter, `[]:*?/\` yok, boş olamaz.
  static String sanitizeSheetName(String name) {
    var cleaned = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), '_');
    cleaned = cleaned.replaceAll(RegExp(r"^'+|'+$"), '');
    if (cleaned.length > 31) cleaned = cleaned.substring(0, 31);
    return cleaned.trim().isEmpty ? 'Sayfa1' : cleaned;
  }

  static String escapeXml(String s) {
    final sb = StringBuffer();
    for (final c in s.runes) {
      switch (c) {
        case 0x26:
          sb.write('&amp;');
        case 0x3C:
          sb.write('&lt;');
        case 0x3E:
          sb.write('&gt;');
        case 0x22:
          sb.write('&quot;');
        case 0x27:
          sb.write('&apos;');
        default:
          sb.writeCharCode(c);
      }
    }
    return sb.toString();
  }

  /// XML 1.0'da izin verilmeyen karakterleri atar (tab ve satır sonları kalır).
  static String _stripInvalidXmlChars(String s) {
    final sb = StringBuffer();
    for (final c in s.runes) {
      final valid = c == 0x09 ||
          c == 0x0A ||
          c == 0x0D ||
          (c >= 0x20 && c <= 0xD7FF) ||
          (c >= 0xE000 && c <= 0xFFFD) ||
          (c >= 0x10000 && c <= 0x10FFFF);
      if (valid) sb.writeCharCode(c);
    }
    return sb.toString();
  }

  static String _argbHex(int argb) =>
      (argb & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase();
}
