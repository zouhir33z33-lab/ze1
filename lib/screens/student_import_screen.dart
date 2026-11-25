import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/core_providers.dart';
import '../providers/students_provider.dart';
import '../themes/app_colors.dart';
import '../widgets/app_bottom_sheet.dart';

/// Import d'une classe entière depuis un tableau Excel/CSV : détection automatique des
/// colonnes (modifiable), aperçu, saut des doublons, puis insertion en une seule fois.
class StudentImportScreen extends ConsumerStatefulWidget {
  final SchoolClass schoolClass;
  final String fileName;
  final List<List<String>> rows;
  const StudentImportScreen({
    super.key,
    required this.schoolClass,
    required this.fileName,
    required this.rows,
  });

  @override
  ConsumerState<StudentImportScreen> createState() => _StudentImportScreenState();
}

class _Parsed {
  final List<Student> students;
  final int duplicates;
  final int empty;
  const _Parsed(this.students, this.duplicates, this.empty);
}

class _StudentImportScreenState extends ConsumerState<StudentImportScreen> {
  bool _header = true;
  bool _fullName = false; // nom + prénom dans une seule colonne
  int? _last, _first, _full, _gender, _number;
  bool _skipDup = true;
  bool _busy = false;

  int get _width => widget.rows.isEmpty ? 0 : widget.rows.first.length;

  // ───────────── détection automatique des colonnes ─────────────

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0640]'), '') // diacritiques arabes et tatweel
      .replaceAll('é', 'e').replaceAll('è', 'e').replaceAll('ê', 'e')
      .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه').replaceAll('ى', 'ي')
      .trim();

  static bool _has(String h, List<String> words) => words.any((w) => h.contains(w));

  @override
  void initState() {
    super.initState();
    _autoDetect();
  }

  void _autoDetect() {
    if (widget.rows.isEmpty) return;
    final head = widget.rows.first.map(_norm).toList();
    int? full, first, last, gender, number;
    for (var i = 0; i < head.length; i++) {
      final h = head[i];
      if (h.isEmpty) continue;
      if (full == null && (_has(h, ['اللقب والاسم', 'الاسم واللقب', 'الاسم الكامل', 'nom et prenom', 'nom prenom', 'full name', 'nom complet']))) {
        full = i;
      } else if (first == null && (_has(h, ['prenom', 'first', 'given', 'الاسم']) && !_has(h, ['لقب']))) {
        first = i;
      } else if (last == null && _has(h, ['لقب', 'nom', 'last', 'surname', 'famille'])) {
        last = i;
      } else if (gender == null && _has(h, ['جنس', 'sexe', 'genre', 'gender', 'sex'])) {
        gender = i;
      } else if (number == null && _has(h, ['رقم', 'تسجيل', 'matricule', 'n°', 'numero', 'num', 'id'])) {
        number = i;
      }
    }
    final detected = full != null || first != null || last != null;
    setState(() {
      _header = detected;
      if (full != null && first == null && last == null) {
        _fullName = true;
        _full = full;
      } else {
        _fullName = false;
        _last = last ?? (detected ? null : 0);
        _first = first ?? (detected ? null : (_width > 1 ? 1 : null));
      }
      _gender = gender;
      _number = number;
    });
  }

  // ───────────── construction de la liste à importer ─────────────

  static String? _gender2(String v) {
    final g = _norm(v);
    if (g.isEmpty) return null;
    const male = ['ذ', 'ذكر', 'm', 'g', 'garcon', 'male', 'homme', 'masculin', 'h'];
    const female = ['ا', 'انثي', 'انثى', 'f', 'fille', 'female', 'femme', 'feminin', 'اناث'];
    if (male.contains(g)) return 'M';
    if (female.contains(g)) return 'F';
    return null;
  }

  String _cell(List<String> r, int? c) => (c == null || c >= r.length) ? '' : r[c].trim();

  _Parsed _build() {
    final existing = ref.read(studentsProvider(widget.schoolClass.id!)).valueOrNull ?? const <Student>[];
    final seen = <String>{for (final s in existing) '${s.lastName.toLowerCase()}|${s.firstName.toLowerCase()}'};
    final out = <Student>[];
    var dup = 0, empty = 0;
    final start = _header ? 1 : 0;
    for (var i = start; i < widget.rows.length; i++) {
      final r = widget.rows[i];
      var last = '', first = '';
      if (_fullName) {
        final parts = _cell(r, _full).split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
        if (parts.isNotEmpty) {
          last = parts.first;
          first = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        }
      } else {
        last = _cell(r, _last);
        first = _cell(r, _first);
      }
      if (last.isEmpty && first.isEmpty) {
        empty++;
        continue;
      }
      if (last.isEmpty) {
        last = first;
        first = '';
      }
      final key = '${last.toLowerCase()}|${first.toLowerCase()}';
      if (_skipDup && seen.contains(key)) {
        dup++;
        continue;
      }
      seen.add(key);
      final numTxt = _cell(r, _number);
      out.add(Student(
        classId: widget.schoolClass.id!,
        firstName: first.isEmpty ? '-' : first,
        lastName: last,
        gender: _gender2(_cell(r, _gender)),
        studentNumber: numTxt.isEmpty ? null : numTxt,
      ));
    }
    return _Parsed(out, dup, empty);
  }

  String _colLabel(int i) {
    var n = i + 1;
    var letters = '';
    while (n > 0) {
      letters = String.fromCharCode(65 + (n - 1) % 26) + letters;
      n = (n - 1) ~/ 26;
    }
    final sample = widget.rows.isEmpty ? '' : widget.rows.first[i];
    final s = sample.length > 14 ? '${sample.substring(0, 14)}…' : sample;
    return '$letters${s.isEmpty ? '' : ' — $s'}';
  }

  Widget _dropdown(String label, int? value, ValueChanged<int?> onChanged, {bool required = false}) {
    final tr = ref.read(trProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<int?>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: [
          DropdownMenuItem<int?>(value: null, child: Text(required ? tr('imp_choose') : tr('imp_none'))),
          for (var i = 0; i < _width; i++) DropdownMenuItem<int?>(value: i, child: Text(_colLabel(i), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => onChanged(v)),
      ),
    );
  }

  Future<void> _import(List<Student> list) async {
    setState(() => _busy = true);
    final tr = ref.read(trProvider);
    final n = await ref.read(studentsProvider(widget.schoolClass.id!).notifier).addMany(list);
    if (!mounted) return;
    final ctx = context;
    Navigator.pop(ctx);
    showSuccessSnack(ctx, '${tr('imp_done')} : $n');
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    final parsed = _build();
    final canImport = parsed.students.isNotEmpty && !_busy;
    final dataRows = widget.rows.length - (_header ? 1 : 0);

    return Scaffold(
      appBar: AppBar(
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('imp_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Text(widget.schoolClass.name, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              border: Border.all(color: const Color(0xFF81C784)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.table_chart, color: AppColors.present),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.fileName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${widget.rows.length} ${tr('imp_rows')} • $_width ${tr('imp_cols')}',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            title: Text(tr('imp_header'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            value: _header,
            onChanged: (v) => setState(() => _header = v),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            title: Text(tr('imp_full_name'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(tr('imp_full_name_hint'), style: const TextStyle(fontSize: 11)),
            value: _fullName,
            onChanged: (v) => setState(() => _fullName = v),
          ),
          const SizedBox(height: 6),
          if (_fullName)
            _dropdown(tr('imp_col_full'), _full, (v) => _full = v, required: true)
          else ...[
            _dropdown(tr('imp_col_last'), _last, (v) => _last = v, required: true),
            _dropdown(tr('imp_col_first'), _first, (v) => _first = v),
          ],
          _dropdown(tr('imp_col_gender'), _gender, (v) => _gender = v),
          _dropdown(tr('imp_col_number'), _number, (v) => _number = v),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            title: Text(tr('imp_skip_dup'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            value: _skipDup,
            onChanged: (v) => setState(() => _skipDup = v),
          ),
          const Divider(height: 24),
          Text(tr('imp_preview'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            '${parsed.students.length} ${tr('imp_will')} • ${parsed.duplicates} ${tr('imp_dups')} • ${parsed.empty} ${tr('imp_empty')} (${dataRows < 0 ? 0 : dataRows} ${tr('imp_rows')})',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          if (parsed.students.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('imp_nothing'), style: const TextStyle(color: AppColors.absent)),
            )
          else
            for (var i = 0; i < parsed.students.length && i < 8; i++)
              Builder(builder: (_) {
                final s = parsed.students[i];
                final girl = s.gender == 'F';
                final tint = s.gender == null ? Colors.grey : (girl ? const Color(0xFFD81B60) : AppColors.primary);
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 15,
                      backgroundColor: tint.withOpacity(0.12),
                      child: Text(s.gender == null ? '?' : (girl ? 'F' : 'G'),
                          style: TextStyle(color: tint, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    title: Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: (s.studentNumber ?? '').isEmpty ? null : Text('N° ${s.studentNumber}'),
                  ),
                );
              }),
          if (parsed.students.length > 8)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('… +${parsed.students.length - 8}',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: FilledButton.icon(
            onPressed: canImport ? () => _import(parsed.students) : null,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.file_download_done),
            label: Text('${tr('imp_btn')} ${parsed.students.length}'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }
}
