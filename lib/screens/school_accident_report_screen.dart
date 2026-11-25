import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/incident_constants.dart';
import '../models/models.dart';
import '../providers/core_providers.dart';
import '../providers/teacher_provider.dart';
import '../services/incident_repository.dart';
import '../services/pdf_export_service.dart';
import '../themes/app_colors.dart';
import '../utils/day_utils.dart';
import '../widgets/export_sheet.dart';

/// Formulaire du « تقرير عن حادث مدرسي » : l'enseignant renseigne les champs puis exporte le
/// rapport (modèle officiel destiné à la direction) en PDF. Les informations stables
/// (établissement, wilaya, nom, fonction) sont mémorisées pour les prochains rapports.
class SchoolAccidentReportScreen extends ConsumerStatefulWidget {
  final IncidentRow? prefill;
  const SchoolAccidentReportScreen({super.key, this.prefill});

  @override
  ConsumerState<SchoolAccidentReportScreen> createState() => _SchoolAccidentReportScreenState();
}

class _SchoolAccidentReportScreenState extends ConsumerState<SchoolAccidentReportScreen> {
  static const _kInstitution = 'rep_institution';
  static const _kWilaya = 'rep_wilaya';
  static const _kMr = 'rep_mr';
  static const _kJob = 'rep_job';
  static const _kSigner = 'rep_signer';

  final _institution = TextEditingController();
  final _wilaya = TextEditingController();
  final _mr = TextEditingController();
  final _signer = TextEditingController();
  final _hour = TextEditingController();
  final _class = TextEditingController();
  final _student = TextEditingController();
  final _birth = TextEditingController();
  final _any = TextEditingController();
  final _place = TextEditingController();
  final _level = TextEditingController();
  final _intervention = TextEditingController();
  final _cause = TextEditingController();
  final _w = [TextEditingController(), TextEditingController(), TextEditingController()];
  DateTime _date = DateTime.now();
  String? _job;
  SportKind _kind = SportKind.none;

  List<TextEditingController> get _all =>
      [_institution, _wilaya, _mr, _signer, _hour, _class, _student, _birth, _any, _place, _level, _intervention, _cause, ..._w];

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPrefsProvider);
    final t = ref.read(teacherProvider).valueOrNull;
    _institution.text = prefs.getString(_kInstitution) ?? (t?.school ?? '');
    _wilaya.text = prefs.getString(_kWilaya) ?? '';
    _mr.text = prefs.getString(_kMr) ?? (t?.fullName ?? '');
    _signer.text = prefs.getString(_kSigner) ?? (t?.fullName ?? '');
    final savedJob = prefs.getString(_kJob);
    _job = kReportJobs.contains(savedJob) ? savedJob : null;

    final p = widget.prefill;
    if (p != null) {
      final r = p.report;
      _date = parseYmd(r.incidentDate);
      _hour.text = r.incidentTime;
      _class.text = p.className;
      _student.text = p.studentName;
      _place.text = choiceOf(kLocations, r.location)?.ar ?? r.location;
      _any.text = r.activity ?? '';
      _level.text = r.injuryLocation ?? '';
      _intervention.text = r.firstAidGiven ?? '';
      _cause.text = r.circumstances == kDefaultCircumstances ? '' : r.circumstances;
      final names = (r.witnessStudents ?? '').split(RegExp(r'[,،\n;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      for (var i = 0; i < 3 && i < names.length; i++) {
        _w[i].text = names[i];
      }
    }
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (p != null) setState(() => _date = p);
  }

  SchoolAccidentReport _build() => SchoolAccidentReport(
        institution: _institution.text,
        wilaya: _wilaya.text,
        date: _date,
        mrName: _mr.text,
        job: _job ?? '',
        signer: _signer.text,
        hour: _hour.text,
        className: _class.text,
        student: _student.text,
        birthDate: _birth.text,
        kind: _kind,
        anyText: _any.text,
        place: _place.text,
        level: _level.text,
        intervention: _intervention.text,
        cause: _cause.text,
        witnesses: [for (final c in _w) c.text],
      );

  Future<void> _export() async {
    final tr = ref.read(trProvider);
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString(_kInstitution, _institution.text.trim());
    await prefs.setString(_kWilaya, _wilaya.text.trim());
    await prefs.setString(_kMr, _mr.text.trim());
    await prefs.setString(_kSigner, _signer.text.trim());
    if (_job != null) await prefs.setString(_kJob, _job!);
    final report = _build();
    if (!mounted) return;
    final who = _student.text.trim().isEmpty ? 'eleve' : _student.text.trim().replaceAll(' ', '_');
    await showExportSheet(
      context,
      title: tr('sar_title'),
      subtitle: tr('export_official_sub'),
      fileName: 'Rapport_accident_${who}_${ymd(_date)}.pdf',
      buildPdf: () => PdfExportService.schoolAccidentReportPdf(report),
      labels: exportLabels(tr),
    );
  }

  Widget _field(TextEditingController c, String label, {int lines = 1, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  Widget _section(String title, IconData icon, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF4F7FB), borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
            ]),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    final d = '${two(_date.day)}/${two(_date.month)}/${_date.year}';
    return Scaffold(
      appBar: AppBar(title: Text(tr('sar_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          _section(tr('sar_sec_header'), Icons.account_balance, [
            _field(_institution, tr('sar_institution')),
            _field(_wilaya, tr('sar_wilaya')),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: tr('sar_date'),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: const Icon(Icons.calendar_month),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(d, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            _field(_mr, tr('sar_mr')),
            DropdownButtonFormField<String?>(
              value: _job,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr('sar_job'),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('—')),
                for (final j in kReportJobs) DropdownMenuItem<String?>(value: j, child: Text(j, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _job = v),
            ),
          ]),
          _section(tr('sar_sec_incident'), Icons.healing, [
            _field(_signer, tr('sar_signer')),
            _field(_hour, tr('sar_hour')),
            _field(_class, tr('sar_class')),
            _field(_student, tr('sar_student')),
            _field(_birth, tr('sar_birth')),
            Text(tr('sar_kind'), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: Text(tr('sar_physical')), selected: _kind == SportKind.physical,
                  onSelected: (_) => setState(() => _kind = _kind == SportKind.physical ? SportKind.none : SportKind.physical)),
              ChoiceChip(label: Text(tr('sar_collective')), selected: _kind == SportKind.collective,
                  onSelected: (_) => setState(() => _kind = _kind == SportKind.collective ? SportKind.none : SportKind.collective)),
            ]),
            const SizedBox(height: 10),
            _field(_any, tr('sar_any')),
            _field(_place, tr('sar_place')),
            _field(_level, tr('sar_level')),
            _field(_intervention, tr('sar_intervention')),
            _field(_cause, tr('sar_cause'), lines: 3),
          ]),
          _section(tr('sar_sec_witness'), Icons.groups, [
            for (var i = 0; i < 3; i++) _field(_w[i], '${tr('sar_witness')} ${i + 1}'),
          ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: FilledButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(tr('sar_export')),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.absent,
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
