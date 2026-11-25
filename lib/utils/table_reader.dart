import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';

/// Lecture d'un tableau (feuille Excel .xlsx ou fichier CSV) en liste de lignes de texte.
/// Sans dépendance supplémentaire : un .xlsx est une archive ZIP de fichiers XML.
class TableReader {
  /// Lit un fichier .xlsx ou .csv. Lève [FormatException] si le format n'est pas pris en charge
  /// (message 'xls' pour l'ancien format binaire .xls).
  static Future<List<List<String>>> read(String path) async {
    final lower = path.toLowerCase();
    final bytes = await File(path).readAsBytes();
    if (lower.endsWith('.xlsx')) return _readXlsx(bytes);
    if (lower.endsWith('.csv') || lower.endsWith('.txt')) return _readCsv(bytes);
    if (lower.endsWith('.xls')) throw const FormatException('xls');
    throw const FormatException('unsupported');
  }

  // ───────────────────────── CSV ─────────────────────────

  static List<List<String>> _readCsv(List<int> bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final firstLine = text.split('\n').first;
    final counts = <String, int>{
      ',': ','.allMatches(firstLine).length,
      ';': ';'.allMatches(firstLine).length,
      '\t': '\t'.allMatches(firstLine).length,
    };
    final delim = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == delim) {
        row.add(cell.toString().trim());
        cell.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString().trim());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(c);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString().trim());
      rows.add(row);
    }
    return _clean(rows);
  }

  // ───────────────────────── XLSX ─────────────────────────

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
      .replaceAll('&amp;', '&');

  static String _textOf(String xml) {
    final buf = StringBuffer();
    for (final m in RegExp(r'<t(?:\s[^>]*)?>(.*?)</t>', dotAll: true).allMatches(xml)) {
      buf.write(_unescape(m.group(1)!));
    }
    return buf.toString();
  }

  static String? _file(Archive a, String name) {
    for (final f in a.files) {
      if (f.isFile && f.name == name) return utf8.decode(f.content as List<int>, allowMalformed: true);
    }
    return null;
  }

  static int _colIndex(String letters) {
    var n = 0;
    for (final c in letters.toUpperCase().codeUnits) {
      n = n * 26 + (c - 64);
    }
    return n - 1;
  }

  static List<List<String>> _readXlsx(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('unsupported');
    }

    // chaînes partagées
    final shared = <String>[];
    final ss = _file(archive, 'xl/sharedStrings.xml');
    if (ss != null) {
      for (final m in RegExp(r'<si(?:\s[^>]*)?>(.*?)</si>', dotAll: true).allMatches(ss)) {
        shared.add(_textOf(m.group(1)!));
      }
    }

    // styles de date : quels index de cellXfs sont des formats de date ?
    final dateStyle = <int>{};
    final styles = _file(archive, 'xl/styles.xml');
    if (styles != null) {
      final customDate = <int>{};
      for (final m in RegExp(r'<numFmt\s[^>]*numFmtId="(\d+)"[^>]*formatCode="([^"]*)"').allMatches(styles)) {
        final code = _unescape(m.group(2)!).toLowerCase().replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]|\\.'), '');
        if (code.contains('y') || (code.contains('d') && code.contains('m'))) {
          customDate.add(int.parse(m.group(1)!));
        }
      }
      final cx = RegExp(r'<cellXfs[^>]*>(.*?)</cellXfs>', dotAll: true).firstMatch(styles);
      if (cx != null) {
        var idx = 0;
        for (final m in RegExp(r'<xf\s[^>]*?/?>').allMatches(cx.group(1)!)) {
          final id = int.tryParse(RegExp(r'numFmtId="(\d+)"').firstMatch(m.group(0)!)?.group(1) ?? '0') ?? 0;
          if ((id >= 14 && id <= 22) || (id >= 45 && id <= 47) || customDate.contains(id)) {
            dateStyle.add(idx);
          }
          idx++;
        }
      }
    }

    // première feuille du classeur
    var sheetPath = 'xl/worksheets/sheet1.xml';
    final wb = _file(archive, 'xl/workbook.xml');
    final rels = _file(archive, 'xl/_rels/workbook.xml.rels');
    if (wb != null && rels != null) {
      final rid = RegExp(r'<sheet\s[^>]*r:id="([^"]+)"').firstMatch(wb)?.group(1);
      if (rid != null) {
        for (final m in RegExp(r'<Relationship\s[^>]*>').allMatches(rels)) {
          final tag = m.group(0)!;
          if (tag.contains('Id="$rid"')) {
            final target = RegExp(r'Target="([^"]+)"').firstMatch(tag)?.group(1);
            if (target != null) {
              sheetPath = target.startsWith('/') ? target.substring(1) : 'xl/$target';
            }
          }
        }
      }
    }
    final sheet = _file(archive, sheetPath) ?? _file(archive, 'xl/worksheets/sheet1.xml');
    if (sheet == null) throw const FormatException('unsupported');

    final rows = <List<String>>[];
    for (final rm in RegExp(r'<row\b[^>]*?(?:/>|>(.*?)</row>)', dotAll: true).allMatches(sheet)) {
      final inner = rm.group(1);
      if (inner == null) {
        rows.add(<String>[]);
        continue;
      }
      final cells = <int, String>{};
      var next = 0;
      for (final cm in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true).allMatches(inner)) {
        final attrs = cm.group(1) ?? '';
        final body = cm.group(2) ?? '';
        final ref = RegExp(r'\br="([A-Za-z]+)\d+"').firstMatch(attrs)?.group(1);
        final col = ref != null ? _colIndex(ref) : next;
        next = col + 1;
        final t = RegExp(r'\bt="([^"]*)"').firstMatch(attrs)?.group(1);
        final s = int.tryParse(RegExp(r'\bs="(\d+)"').firstMatch(attrs)?.group(1) ?? '');
        final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1);
        var value = '';
        if (t == 's') {
          final i = int.tryParse(v ?? '');
          value = (i != null && i < shared.length) ? shared[i] : '';
        } else if (t == 'inlineStr') {
          value = _textOf(body);
        } else if (t == 'str' || t == 'e') {
          value = _unescape(v ?? '');
        } else if (t == 'b') {
          value = v == '1' ? 'TRUE' : 'FALSE';
        } else if (v != null) {
          var raw = _unescape(v).trim();
          final numeric = double.tryParse(raw);
          if (numeric != null && s != null && dateStyle.contains(s)) {
            final d = DateTime(1899, 12, 30).add(Duration(days: numeric.floor()));
            raw = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          } else if (numeric != null && raw.toLowerCase().contains('e') && numeric.abs() < 1e17 && numeric == numeric.roundToDouble()) {
            raw = numeric.round().toString(); // 1.0010180111527E15 -> 1001018011152700
          } else if (numeric != null && raw.endsWith('.0')) {
            raw = raw.substring(0, raw.length - 2);
          }
          value = raw;
        }
        cells[col] = value.trim();
      }
      if (cells.isEmpty) {
        rows.add(<String>[]);
        continue;
      }
      final maxCol = cells.keys.reduce((a, b) => a > b ? a : b);
      rows.add([for (var i = 0; i <= maxCol; i++) cells[i] ?? '']);
    }
    return _clean(rows);
  }

  /// Supprime les lignes vides et uniformise le nombre de colonnes.
  static List<List<String>> _clean(List<List<String>> rows) {
    final nonEmpty = rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
    if (nonEmpty.isEmpty) return [];
    final width = nonEmpty.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    return [
      for (final r in nonEmpty) [...r, for (var i = r.length; i < width; i++) ''],
    ];
  }
}
