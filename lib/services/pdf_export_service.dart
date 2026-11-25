import 'dart:typed_data';
import 'dart:ui' as ui;
import '../constants/incident_constants.dart';
import '../constants/periods.dart';
import '../models/models.dart';
import '../providers/teacher_provider.dart';
import '../utils/day_utils.dart';
import '../utils/labels.dart';
import 'evaluation_repository.dart';
import 'pdf_canvas.dart';

/// Contexte administratif commun à tous les PDF.
class PdfContext {
  final TeacherProfile teacher;
  final String yearName;
  final String directorLabel; // « مدير المتوسطة » …
  final String cycleWord; // « متوسطة » …
  const PdfContext({
    required this.teacher,
    required this.yearName,
    required this.directorLabel,
    required this.cycleWord,
  });

  String get school => teacher.school.isEmpty ? 'Lycée / Collège' : teacher.school;
  String get teacherName => teacher.fullName.isEmpty ? "Professeur d'EPS" : teacher.fullName;
}

/// Génération des PDF : mises en page calquées sur les PDF réels de l'application d'origine
/// (déclaration d'accident, bilan trimestriel, emploi du temps, liste des dispensés).
/// Le dessin utilise le moteur de texte de Flutter (voir pdf_canvas.dart).
class PdfExportService {
  static const String _appName = 'مساعد التربية البدنية والرياضية';
  static const double _l = 30, _r = 565, _w = 535;
  static const ui.Color _headFill = ui.Color(0xFFECEFF1);
  static const ui.Color _bar = ui.Color(0xFFF3F3F3);

  // ───────────── éléments communs ─────────────

  static void _topHeader(PageCanvas c, PdfContext ctx, {required String line2, String? line3, required double right}) {
    c.text('الجمهورية الجزائرية الديمقراطية الشعبية', right - 300, 20, 300, size: 9.5, bold: true);
    c.text(line2, right - 300, 32, 300, size: 9.5, bold: true);
    if (line3 != null) c.text(line3, right - 300, 44, 300, size: 8.5, color: kGrey);
    c.text('السنة الدراسية : ${ctx.yearName}', _l, 20, 260, size: 10, bold: true, align: ui.TextAlign.left);
    c.text('المؤسسة : ${ctx.school}', _l, 33, 260, size: 9.5, bold: true, align: ui.TextAlign.left, fit: true);
    c.text('التاريخ : ${stampNow()}', _l, 46, 260, size: 8.5, color: kGrey, align: ui.TextAlign.left);
    c.line(_l, 66, right, 66, color: const ui.Color(0xFF263238), sw: 1.4);
  }

  static void _sigBox(PageCanvas c, double x, double y, double w, double h, String title, String bottom, {String? middle}) {
    c.rect(x, y, w, h, stroke: kLine, sw: 0.9, r: 6);
    c.text(title, x + 6, y + 5, w - 12, size: 8.5, bold: true);
    if (middle != null) c.text(middle, x + 6, y + 19, w - 12, size: 8.5);
    c.text(bottom, x + 6, y + h - 14, w - 12, size: 7.5, color: kGrey);
  }

  static void _row(
    PageCanvas c,
    double y,
    double h,
    List<double> widths,
    List<String> cells, {
    double right = _r,
    ui.Color? fill,
    bool bold = false,
    double size = 8.5,
    List<ui.Color?>? colors,
    List<bool>? bolds,
    List<ui.TextAlign>? aligns,
  }) {
    var x = right;
    for (var i = 0; i < widths.length; i++) {
      x -= widths[i];
      c.rect(x, y, widths[i], h, fill: fill, stroke: kLine, sw: 0.6);
      c.textBox(
        cells[i], x, y, widths[i], h,
        size: size,
        bold: bolds != null ? bolds[i] : bold,
        color: (colors != null ? colors[i] : null) ?? kInk,
        align: aligns != null ? aligns[i] : ui.TextAlign.center,
      );
    }
  }

  static String _appr(double a) =>
      a >= 16 ? 'Très Bien' : a >= 14 ? 'Bien' : a >= 12 ? 'Assez Bien' : a >= 10 ? 'Passable' : 'Insuffisant';

  // ───────────── Déclaration d'accident (modèle de l'application) ─────────────

  static Future<Uint8List> incidentPdf({
    required IncidentReport report,
    required String studentName,
    required String gender, // 'M' | 'F' | ''
    required String className,
    required String level,
    required PdfContext ctx,
  }) async {
    String or(String? v, String d) => (v == null || v.trim().isEmpty) ? d : v.trim();
    final evac = choiceOf(kEvacuations, report.evacuationType)?.ar ?? report.evacuationType;
    final loc = choiceOf(kLocations, report.location)?.ar ?? report.location;
    final sex = gender == 'F' ? 'أنثى' : (gender == 'M' ? 'ذكر' : '—');
    final injury = report.injuryType == 'ENTORSE'
        ? 'التواء'
        : (choiceOf(kInjuryTypes, report.injuryType)?.ar ?? report.injuryType);

    final pages = PdfPages();
    final c = pages.newPage();

    c.text('الجمهورية الجزائرية الديمقراطية الشعبية', 265, 20, 300, size: 9.5, bold: true);
    c.text('وزارة التربية الوطنية', 265, 32, 300, size: 9.5, bold: true);
    c.text('المؤسسة : ${ctx.teacher.school.isEmpty ? 'Établissement Scolaire' : ctx.teacher.school}', 265, 44, 300, size: 10, bold: true, fit: true);
    c.text('المادة : التربية البدنية والرياضية', 265, 58, 300, size: 8, color: kGrey);
    c.text('السنة الدراسية : ${ctx.yearName}', _l, 20, 240, size: 10, bold: true, align: ui.TextAlign.left);
    c.rect(_l, 36, 118, 15, fill: const ui.Color(0xFFFFEBEE), stroke: kRed, sw: 1, r: 6);
    c.textBox('تصريح إداري عاجل بحادث', _l, 36, 118, 15, size: 7.5, bold: true, color: kRed);
    c.line(_l, 76, _r, 76, color: const ui.Color(0xFF263238), sw: 1.6);

    c.rect(197, 88, 200, 36, fill: _headFill, stroke: const ui.Color(0xFF607D8B), sw: 1.4, r: 8);
    c.textBox('تصريح بحادث مدرسي بدني', 197, 90, 200, 21, size: 14, bold: true);
    c.textBox('استمارة حادث خلال حصة التربية البدنية والرياضية', 197, 109, 200, 12, size: 7.5, color: kGrey);

    void section(double y, String title, double bodyH, ui.Color headFill, ui.Color border, {ui.Color titleColor = kInk}) {
      c.rect(_l, y, _w, 18 + bodyH, stroke: border, sw: 1, r: 6);
      c.rect(_l + 0.6, y + 0.6, _w - 1.2, 17, fill: headFill, r: 5);
      c.text(title, _l + 8, y + 4, _w - 16, size: 9, bold: true, color: titleColor, fit: true);
    }

    const colW = 178.3;
    double cx(int i) => _r - (i + 1) * colW;
    void cell(int col, double y, String label, String value, {ui.Color? valueColor, bool boldValue = false}) {
      c.rich([Seg('$label : ', bold: true), Seg(value, bold: boldValue, color: valueColor)],
          cx(col) + 2, y, colW - 6, size: 8.8, fit: true);
    }

    // 1
    section(134, '1. هوية التلميذ المصاب وإطار الحصة', 62, const ui.Color(0xFFCFD8DC), const ui.Color(0xFF607D8B));
    cell(0, 160, 'اللقب والاسم', studentName, valueColor: kBlue, boldValue: true);
    cell(1, 160, 'القسم', '$className ($level)');
    cell(2, 160, 'الجنس', sex);
    cell(0, 178, 'تاريخ الحادث', report.incidentDate);
    cell(1, 178, 'التوقيت الدقيق', report.incidentTime);
    cell(2, 178, 'مكان الحادث', loc);
    cell(0, 196, 'النشاط الرياضي الممارس', or(report.activity, 'غير محدد'));
    cell(1, 196, 'الأستاذ المسؤول', ctx.teacherName);

    // 2
    section(222, '2. طبيعة الإصابة وموقع الضرر الجسدي', 34, const ui.Color(0xFFFFEBEE), const ui.Color(0xFFE57373), titleColor: const ui.Color(0xFFB71C1C));
    c.rich([Seg('طبيعة الإصابة : ', bold: true), Seg(injury, bold: true, color: kRed)], _r - 262, 248, 258, size: 9, fit: true);
    c.rich([Seg('موضع الإصابة في الجسم : ', bold: true), Seg(or(report.injuryLocation, 'غير محدد'), bold: true, color: kRed)], _l + 4, 248, 258, size: 9, fit: true);

    // 3
    section(282, '3. الظروف المفصلة للحادث (وقائع موضوعية)', 64, const ui.Color(0xFFEEEEEE), const ui.Color(0xFFBDBDBD));
    c.text(or(report.circumstances, kDefaultCircumstances), _l + 10, 312, _w - 20, size: 9.5, lineHeight: 1.3);

    // 4
    section(354, '4. الإسعافات الأولية وتدابير التوجيه والإجلاء', 52, const ui.Color(0xFFE8F5E9), const ui.Color(0xFF66BB6A), titleColor: const ui.Color(0xFF1B5E20));
    final h1 = c.rich([Seg('الإسعافات الأولية الفورية : ', bold: true), Seg(or(report.firstAidGiven, 'إجراءات الحماية والراحة'))],
        _l + 10, 380, _w - 20, size: 8.8, lineHeight: 1.25);
    final y2 = 380 + h1 + 5;
    c.rich([Seg('التكفل / التوجيه : ', bold: true), Seg(evac)], _r - 330, y2, 320, size: 8.8, fit: true);
    c.rich([
      const Seg('إشعار الأولياء : ', bold: true),
      report.parentContacted
          ? const Seg('نعم (تم إشعارهم فوراً)', bold: true, color: kGreen)
          : const Seg('لا / في الانتظار', bold: true, color: kOrange),
    ], _l + 6, y2, 190, size: 8.8, fit: true);

    // 5
    section(418, '5. شهود الحادث وملاحظات تكميلية', 46, const ui.Color(0xFFEEEEEE), const ui.Color(0xFFBDBDBD));
    c.rich([const Seg('التلاميذ الشهود : ', bold: true), Seg(or(report.witnessStudents, 'لا يوجد شهود مسجلون'))],
        _l + 10, 444, _w - 20, size: 9, fit: true);
    if ((report.notes ?? '').trim().isNotEmpty) {
      c.rich([const Seg('ملاحظات إضافية : ', bold: true), Seg(report.notes!.trim())], _l + 10, 460, _w - 20, size: 9, fit: true);
    }

    const sw = 172.0;
    final sy = 690.0;
    _sigBox(c, _r - sw, sy, sw, 84, 'أستاذ(ة) التربية البدنية والرياضية المصرح :', 'التاريخ والإمضاء :', middle: ctx.teacherName);
    _sigBox(c, _r - 2 * sw - 9.5, sy, sw, 84, 'قاعة التمريض / وحدة الكشف (UDS) :', 'الختم والتأشيرة الطبية :');
    _sigBox(c, _l, sy, sw, 84, 'مدير المؤسسة :', 'الإمضاء والختم الرسمي :');
    c.text('تم استخراج الوثيقة بواسطة $_appName • حرر في 3 نسخ أصلية (الإدارة، الأستاذ، الملف الطبي)', _l, 806, _w,
        size: 7, color: kGrey, align: ui.TextAlign.center);

    await pages.add(c);
    return pages.build();
  }

  // ───────────── Bilan trimestriel ─────────────

  static Future<Uint8List> termReportPdf({
    required SchoolClass cls,
    required Term term,
    required TermSummary summary,
    required PdfContext ctx,
  }) async {
    const perPage = 24;
    final n = summary.students.length;
    final pageCount = n == 0 ? 1 : (n + perPage - 1) ~/ perPage;
    final termAr = kTermNamesAr[(term.termNumber - 1).clamp(0, 2)];
    final avgTxt = summary.classAverage == null ? 'N/A' : summary.classAverage!.toStringAsFixed(2);
    final passTxt = summary.passRate == null ? 'N/A' : '${summary.passRate!.toStringAsFixed(1)}%';
    const widths = <double>[52, 175, 25, 45, 55, 50, 50, 83];
    final pages = PdfPages();

    for (var p = 0; p < pageCount; p++) {
      final c = pages.newPage();
      _topHeader(c, ctx, line2: 'وزارة التربية الوطنية - التربية البدنية والرياضية', right: _r);
      c.text('الحصيلة الرسمية لاختتام الفصل الدراسي • $termAr', _l, 80, _w, size: 13.5, bold: true, align: ui.TextAlign.center);

      c.rect(_l, 106, _w, 22, fill: _bar, stroke: const ui.Color(0xFFDDDDDD), r: 6);
      const cw = 178.3;
      c.textBox('القسم : ${cls.name} (${cls.level})', _r - cw, 106, cw, 22, size: 9.5, bold: true, align: ui.TextAlign.right);
      c.textBox('الأستاذ : ${ctx.teacherName}', _r - 2 * cw, 106, cw, 22, size: 9.5, bold: true);
      c.textBox('التعداد : $n تلميذ', _l, 106, cw, 22, size: 9.5, bold: true, align: ui.TextAlign.left);

      c.rect(_l, 136, _w, 44, fill: _headFill, stroke: const ui.Color(0xFFB0BEC5), r: 8);
      const kw = _w / 4;
      final kpi = <(String, String, ui.Color)>[
        ('${summary.sessions}', 'الحصص المنجزة', kInk),
        ('${summary.evaluations}', 'التقييمات المنجزة', kInk),
        (avgTxt, 'معدل القسم', kBlue),
        (passTxt, 'نسبة النجاح', kGreen),
      ];
      for (var i = 0; i < 4; i++) {
        final x = _r - (i + 1) * kw;
        c.textBox(kpi[i].$1, x, 140, kw, 22, size: 14, bold: true, color: kpi[i].$3);
        c.textBox(kpi[i].$2, x, 160, kw, 14, size: 8, color: kGrey);
        if (i < 3) c.line(x, 144, x, 172, color: const ui.Color(0xFFB0BEC5));
      }

      _row(c, 190, 20, widths,
          ['الرقم', 'اللقب والاسم', 'ج', 'الغياب', 'المواظبة', 'التقييم', 'المعدل', 'التقدير'],
          fill: _headFill, bold: true, size: 8.5);
      final from = p * perPage;
      final to = (from + perPage) > n ? n : from + perPage;
      var y = 210.0;
      for (var i = from; i < to; i++) {
        final st = summary.students[i];
        _row(
          c, y, 20, widths,
          [
            st.student.studentNumber ?? '',
            st.student.fullName,
            st.student.gender == 'F' ? 'أ' : 'ذ',
            '${st.absences}',
            '${(st.presencePct ?? 100).toStringAsFixed(0)}%',
            '${st.gradedEvals}',
            st.average == null ? '-' : st.average!.toStringAsFixed(2),
            st.average == null ? 'N/A' : _appr(st.average!),
          ],
          size: 8,
          bolds: const [false, true, false, false, false, false, false, true],
          colors: [null, null, null, st.absences > 0 ? kRed : null, null, null, null, null],
          aligns: const [
            ui.TextAlign.center, ui.TextAlign.right, ui.TextAlign.center, ui.TextAlign.center,
            ui.TextAlign.center, ui.TextAlign.center, ui.TextAlign.center, ui.TextAlign.center,
          ],
        );
        y += 20;
      }
      if (p == pageCount - 1) {
        _sigBox(c, _r - 262, 722, 262, 64, 'أستاذ(ة) التربية البدنية والرياضية :', 'الإمضاء والختم');
        _sigBox(c, _l, 722, 262, 64, '${ctx.directorLabel} :', 'التأشيرة، الختم والتاريخ');
      }
      c.text('الصفحة ${p + 1} / $pageCount', _l, 806, 120, size: 7.5, bold: true, color: kGrey, align: ui.TextAlign.left);
      c.text('تطبيق $_appName • الحصيلة الرسمية لاختتام الفصل', 150, 806, 295, size: 7, color: kGrey, align: ui.TextAlign.center);
      await pages.add(c);
    }
    return pages.build();
  }

  // ───────────── Relevé de notes ─────────────

  static Future<Uint8List> gradeSheetPdf({
    required SchoolClass cls,
    required Term term,
    required List<EvaluationRow> evals,
    required Map<int, Map<int, double?>> matrix,
    required TermSummary summary,
    required PdfContext ctx,
  }) async {
    final landscape = evals.length > 5;
    final pages = PdfPages(landscape: landscape);
    final pw = landscape ? kA4H : kA4W;
    final right = pw - 30;
    final width = right - 30;
    final perPage = landscape ? 15 : 24;
    final n = summary.students.length;
    final pageCount = n == 0 ? 1 : (n + perPage - 1) ~/ perPage;
    const fixed = <double>[52, 150];
    const avgW = 60.0;
    final evalW = evals.isEmpty ? 0.0 : (width - 52 - 150 - avgW) / evals.length;
    final widths = <double>[...fixed, for (var i = 0; i < evals.length; i++) evalW, avgW];
    final termAr = kTermNamesAr[(term.termNumber - 1).clamp(0, 2)];

    for (var p = 0; p < pageCount; p++) {
      final c = pages.newPage();
      _topHeader(c, ctx, line2: 'وزارة التربية الوطنية - التربية البدنية والرياضية', right: right);
      c.text('كشف النقاط • $termAr', 30, 80, width, size: 13.5, bold: true, align: ui.TextAlign.center);
      c.rect(30, 106, width, 22, fill: _bar, stroke: const ui.Color(0xFFDDDDDD), r: 6);
      c.textBox('القسم : ${cls.name} (${cls.level})', right - 220, 106, 220, 22, size: 9.5, bold: true, align: ui.TextAlign.right);
      c.textBox('التعداد : $n تلميذ', 30, 106, 200, 22, size: 9.5, bold: true, align: ui.TextAlign.left);

      _row(c, 140, 28, widths,
          [
            'الرقم', 'اللقب والاسم',
            for (final r in evals) '${r.evaluation.title} /${r.evaluation.maxScore.toStringAsFixed(0)}',
            'المعدل /20',
          ],
          right: right, fill: _headFill, bold: true, size: 7.5);
      final from = p * perPage;
      final to = (from + perPage) > n ? n : from + perPage;
      var y = 168.0;
      for (var i = from; i < to; i++) {
        final st = summary.students[i];
        _row(
          c, y, 20, widths,
          [
            st.student.studentNumber ?? '',
            st.student.fullName,
            for (final r in evals)
              (matrix[r.evaluation.id]?[st.student.id])?.toStringAsFixed(2) ?? '-',
            st.average == null ? '-' : st.average!.toStringAsFixed(2),
          ],
          right: right,
          size: 8,
          bolds: [false, true, for (var k = 0; k < evals.length; k++) false, true],
          aligns: [ui.TextAlign.center, ui.TextAlign.right, for (var k = 0; k < evals.length; k++) ui.TextAlign.center, ui.TextAlign.center],
        );
        y += 20;
      }
      if (p == pageCount - 1) {
        final sy = (landscape ? kA4W : kA4H) - 120;
        _sigBox(c, right - 262, sy, 262, 64, 'أستاذ(ة) التربية البدنية والرياضية :', 'الإمضاء والختم');
        _sigBox(c, 30, sy, 262, 64, '${ctx.directorLabel} :', 'التأشيرة، الختم والتاريخ');
      }
      c.text('الصفحة ${p + 1} / $pageCount', 30, (landscape ? kA4W : kA4H) - 36, 120, size: 7.5, bold: true, color: kGrey, align: ui.TextAlign.left);
      await pages.add(c);
    }
    return pages.build();
  }

  // ───────────── Emploi du temps hebdomadaire (A4 paysage) ─────────────

  static String _periodName(Period p) => switch (p.id) {
        'M1' => 'الفترة الصباحية 1',
        'M2' => 'الفترة الصباحية 2',
        'E1' => 'الفترة المسائية 1',
        _ => 'الفترة المسائية 2',
      };

  static Future<Uint8List> timetablePdf({
    required List<TimetableSlot> slots,
    required Map<int, SchoolClass> classes,
    required Map<int, PedagogicalSheet> sheets,
    required PdfContext ctx,
  }) async {
    final pages = PdfPages(landscape: true);
    final c = pages.newPage();
    const right = kA4H - 30; // 811.89
    const width = right - 30;
    final used = <int>{for (final s in slots) s.classId};
    final names = [for (final id in used) if (classes[id] != null) classes[id]!.name];

    c.text('الجمهورية الجزائرية الديمقراطية الشعبية', right - 300, 20, 300, size: 9.5, bold: true);
    c.text('وزارة التربية الوطنية', right - 300, 32, 300, size: 9.5, bold: true);
    c.text('مديرية التربية • مادة التربية البدنية والرياضية', right - 300, 44, 300, size: 8.5, color: kGrey);
    c.text('السنة الدراسية : ${ctx.yearName}', 30, 20, 280, size: 10, bold: true, align: ui.TextAlign.left);
    c.text('المؤسسة : ${ctx.school}', 30, 33, 280, size: 9.5, bold: true, align: ui.TextAlign.left, fit: true);
    c.text('تاريخ الإصدار : ${stampNow()}', 30, 46, 280, size: 8.5, color: kGrey, align: ui.TextAlign.left);
    c.line(30, 64, right, 64, color: const ui.Color(0xFF263238), sw: 1.2);
    c.text('جدول التوقيت الأسبوعي الرسمي لأستاذ التربية البدنية والرياضية', 30, 74, width, size: 13, bold: true, align: ui.TextAlign.center);

    c.rect(30, 98, width, 22, fill: _bar, stroke: const ui.Color(0xFFDDDDDD), r: 6);
    c.textBox('المادة : التربية البدنية والرياضية', right - 200, 98, 200, 22, size: 9, bold: true, align: ui.TextAlign.right);
    c.textBox('الأقسام المبرمجة : ${names.length} (${names.join('، ')})', 240, 98, (right - 205) - 240, 22, size: 8.5, bold: true, color: kBlue);
    c.textBox('الحجم الساعي : ${slots.length} حصص (${slots.length * 2} سا / أسبوع)', 30, 98, 200, 22, size: 9, bold: true, color: kGreen, align: ui.TextAlign.left);

    const days = [1, 2, 3, 4, 5];
    const timeW = 92.0;
    final dayW = (width - timeW) / days.length;
    final widths = <double>[timeW, for (var i = 0; i < days.length; i++) dayW];
    var y = 132.0;
    // en-tête
    var x = right;
    for (var i = 0; i < widths.length; i++) {
      x -= widths[i];
      c.rect(x, y, widths[i], 26, fill: const ui.Color(0xFF37474F), stroke: const ui.Color(0xFF37474F));
      if (i == 0) {
        c.textBox('التوقيت', x, y, widths[i], 26, size: 9, bold: true, color: const ui.Color(0xFFFFFFFF));
      } else {
        final d = days[i - 1];
        c.textBox(kDayNamesAr[d - 1], x, y + 1, widths[i], 14, size: 9, bold: true, color: const ui.Color(0xFFFFFFFF));
        c.textBox(kDayNamesFr[d - 1].toUpperCase(), x, y + 13, widths[i], 11, size: 7, color: const ui.Color(0xFFCFD8DC));
      }
    }
    y += 26;

    void periodRow(Period p) {
      const h = 62.0;
      var cx = right;
      for (var i = 0; i < widths.length; i++) {
        cx -= widths[i];
        if (i == 0) {
          c.rect(cx, y, widths[i], h, fill: _headFill, stroke: kLine, sw: 0.6);
          c.textBox(_periodName(p), cx, y + 16, widths[i], 14, size: 8.5, bold: true);
          c.textBox('${p.start} - ${p.end}', cx, y + 32, widths[i], 12, size: 8.5, color: kGrey);
          continue;
        }
        final d = days[i - 1];
        TimetableSlot? slot;
        for (final s in slots) {
          if (s.dayOfWeek == d && s.startTime == p.start && s.endTime == p.end) slot = s;
        }
        final cls = slot == null ? null : classes[slot.classId];
        c.rect(cx, y, widths[i], h, fill: cls == null ? null : const ui.Color(0xFFE3F2FD), stroke: kLine, sw: 0.6);
        if (cls == null) {
          c.textBox('-', cx, y, widths[i], h, size: 9, color: const ui.Color(0xFF999999));
        } else {
          var ty = y + 7;
          c.textBox(cls.name, cx, ty, widths[i], 16, size: 12.5, bold: true, color: kBlue);
          ty += 16;
          c.textBox(cls.level, cx, ty, widths[i], 11, size: 8.5, bold: true, color: const ui.Color(0xFF37474F));
          ty += 11;
          if ((slot!.fieldName ?? '').isNotEmpty) {
            c.textBox(slot.fieldName!, cx, ty, widths[i], 11, size: 8, color: kGrey);
            ty += 11;
          }
          final sheet = sheets[slot.defaultSheetId];
          if (sheet != null) c.textBox(sheet.title, cx, ty, widths[i], 11, size: 7.5, color: kTeal);
        }
      }
      y += h;
    }

    periodRow(kPeriods[0]);
    periodRow(kPeriods[1]);
    var lx = right;
    for (var i = 0; i < widths.length; i++) {
      lx -= widths[i];
      c.rect(lx, y, widths[i], 18, fill: const ui.Color(0xFFFFF8E1), stroke: kLine, sw: 0.6);
      c.textBox(i == 0 ? '$kLunchStart - $kLunchEnd' : 'فترة الاستراحة', lx, y, widths[i], 18,
          size: 8, bold: true, color: kOrange);
    }
    y += 18;
    periodRow(kPeriods[2]);
    periodRow(kPeriods[3]);

    y += 16;
    _sigBox(c, right - 262, y, 262, 70, 'أستاذ(ة) التربية البدنية والرياضية :', 'الإمضاء والتاريخ', middle: 'السيد(ة) ${ctx.teacherName}');
    _sigBox(c, 30, y, 262, 70, 'تأشيرة مدير المؤسسة :', '(الختم والإمضاء) ${ctx.directorLabel}');
    c.text('وثيقة مطابقة للتوقيت الرسمي لوزارة التربية الوطنية', 300, y + 22, 212, size: 8, color: kGrey, align: ui.TextAlign.center);
    c.text('${ctx.cycleWord} • $_appName', 300, y + 36, 212, size: 8, bold: true, align: ui.TextAlign.center);

    await pages.add(c);
    return pages.build();
  }

  // ───────────── Liste des élèves dispensés ─────────────

  static Future<Uint8List> exemptListPdf({
    required List<Map<String, Object?>> rows,
    required String levelLabel, // « Tous les niveaux » ou « 1AM »
    required PdfContext ctx,
  }) async {
    const perPage = 24;
    final n = rows.length;
    final pageCount = n == 0 ? 1 : (n + perPage - 1) ~/ perPage;
    final males = rows.where((r) => r['gender'] == 'M').length;
    final females = rows.where((r) => r['gender'] == 'F').length;
    const widths = <double>[30, 150, 35, 80, 90, 100, 50];
    final pages = PdfPages();

    for (var p = 0; p < pageCount; p++) {
      final c = pages.newPage();
      _topHeader(c, ctx, line2: 'وزارة التربية الوطنية', line3: 'المادة : التربية البدنية والرياضية', right: _r);
      c.text('السجل الرسمي للتلاميذ المعفيين من ممارسة التربية البدنية والرياضية', _l, 78, _w, size: 12.5, bold: true, align: ui.TextAlign.center);
      c.text('سجل الإعفاءات الطبية الرسمية - وزارة التربية الوطنية', _l, 96, _w, size: 8.5, color: kGrey, align: ui.TextAlign.center);

      c.rect(_l, 112, _w, 22, fill: _bar, stroke: const ui.Color(0xFFDDDDDD), r: 6);
      const cw = 178.3;
      c.textBox('التصنيف : $levelLabel', _r - cw, 112, cw, 22, size: 9, bold: true, align: ui.TextAlign.right);
      c.textBox('مجموع المعفين : $n تلميذ', _r - 2 * cw, 112, cw, 22, size: 9, bold: true);
      c.textBox('ذكور : $males • إناث : $females', _l, 112, cw, 22, size: 9, bold: true, align: ui.TextAlign.left);

      _row(c, 146, 22, widths,
          ['الرقم', 'اللقب والاسم', 'الجنس', 'القسم', 'رقم التسجيل', 'سبب الإعفاء / الشهادة', 'التأشيرة الطبية'],
          fill: _headFill, bold: true, size: 8);
      final from = p * perPage;
      final to = (from + perPage) > n ? n : from + perPage;
      var y = 168.0;
      for (var i = from; i < to; i++) {
        final r = rows[i];
        final reason = ((r['medical_reason'] as String?) ?? '').trim();
        _row(
          c, y, 22, widths,
          [
            '${i + 1}',
            '${r['last_name']} ${r['first_name']}',
            r['gender'] == 'F' ? 'أ' : 'ذ',
            '${r['class_name']}',
            '${r['student_number'] ?? ''}',
            reason.isEmpty ? "Dispensé(e) d'EPS" : reason,
            '',
          ],
          size: 8,
          bolds: const [false, true, false, false, false, false, false],
          colors: const [null, null, null, null, null, kBlue, null],
          aligns: const [
            ui.TextAlign.center, ui.TextAlign.right, ui.TextAlign.center, ui.TextAlign.center,
            ui.TextAlign.center, ui.TextAlign.center, ui.TextAlign.center,
          ],
        );
        y += 22;
      }
      if (p == pageCount - 1) {
        const sw = 172.0;
        _sigBox(c, _r - sw, 722, sw, 70, 'أستاذ(ة) التربية البدنية والرياضية :', 'الإمضاء والتاريخ');
        _sigBox(c, _r - 2 * sw - 9.5, 722, sw, 70, 'طبيب الصحة المدرسية (وحدة الكشف والمتابعة) :', 'الختم والتأشيرة الطبية');
        _sigBox(c, _l, 722, sw, 70, 'مدير المؤسسة :', 'الإمضاء والختم الرسمي');
      }
      c.text('الصفحة ${p + 1} / $pageCount', _l, 806, 120, size: 7.5, bold: true, color: kGrey, align: ui.TextAlign.left);
      await pages.add(c);
    }
    return pages.build();
  }

  // ───────────── « تقرير عن حادث مدرسي » (modèle destiné à la direction) ─────────────

  static Future<Uint8List> schoolAccidentReportPdf(SchoolAccidentReport r) async {
    String d(String v, int dots) => v.trim().isEmpty ? '.' * dots : v.trim();
    final dateStr = '${two(r.date.day)}/${two(r.date.month)}/${r.date.year}';
    final wilaya = r.wilaya.trim();
    const nb = '\u00A0';
    final pages = PdfPages();
    final c = pages.newPage();

    c.text('الجمهورية الجزائرية الديمقراطية الشعبية', _l, 34, _w, size: 13.5, bold: true, align: ui.TextAlign.center);
    c.text('وزارة التربية الوطنية', _l, 58, _w, size: 13.5, bold: true, align: ui.TextAlign.center);
    c.text('مديرية التربية لولاية ${wilaya.isEmpty ? '.........' : wilaya}', _l, 82, _w, size: 13.5, bold: true, align: ui.TextAlign.center);

    c.text(r.institution.trim().isEmpty ? 'متوسطة ............................' : r.institution.trim(),
        190, 118, 375, size: 13, bold: true, fit: true);
    c.text('${wilaya.isEmpty ? '..........' : wilaya} في: $dateStr', _l, 118, 160, size: 13, bold: true, align: ui.TextAlign.left, fit: true);
    c.text('السيد : ${d(r.mrName, 30)}', _l, 144, _w, size: 13, bold: true, fit: true);
    c.text('الوظيفة / ${r.job.trim().isEmpty ? '.........................' : r.job.trim()}', _l, 168, _w, size: 13, bold: true, fit: true);
    c.text('المادة / تربية بدنية ورياضية', _l, 192, _w, size: 13, bold: true);

    c.rect(206, 222, 183, 38, fill: const ui.Color(0xFFD9D9D9));
    c.textBox('تقرير عن حادث مدرسي', 206, 222, 183, 38, size: 20, bold: true);

    var y = 282.0;
    void para(List<Seg> segs, {double gap = 7, double size = 12.3}) {
      final h = c.rich(segs, _l, y, _w, size: size, lineHeight: 1.75);
      y += h + gap;
    }

    Seg b(String t) => Seg(t, bold: true);
    final physical = r.kind == SportKind.physical ? '×' : '$nb$nb';
    final collective = r.kind == SportKind.collective ? '×' : '$nb$nb';

    para([b('أنا الممضي أسفله الأستاذ '), b(d(r.signer, 36))]);
    para([b('في يوم: $dateStr ، وعلى الساعة: ${d(r.hour, 14)} مع قسم: ${d(r.className, 22)}')]);
    para([
      b('يأسفني أن أعلمكم عن إصابة التلميذ(ة) ${d(r.student, 32)} المزداد(ة) بتاريخ ${d(r.birthDate, 14)} '
          'وذلك أثناء أداء حصة التربية البدنية والرياضية، وبالضبط في حصة الميدان: '
          'البدني ( $physical )/الجماعي ( $collective ) أي(${d(r.anyText, 26)}).'),
    ]);
    para([
      b('وهذا بالتحديد على الساعة ${d(r.hour, 12)} وقد تلقى(ت) إصابة في مكان العمل ${d(r.place, 20)} '
          'على مستوى ${d(r.level, 22)} وكان تدخل الأستاذ بـ ${d(r.intervention, 30)}'),
    ], gap: 12);
    para([b('وعن سبب الإصابة فكان: ${d(r.cause, 60)}')]);
    para([b('وقمت أنا الأستاذ بإسعاف التلميذ، وقد بلغت الإدارة بذلك للقيام بالإجراءات اللازمة.')], gap: 10);

    c.text('التلاميذ الشهود مع الإمضاءات:', _l, y, _w, size: 13.5, bold: true);
    y += 30;
    for (var i = 0; i < 3; i++) {
      final w = i < r.witnesses.length ? r.witnesses[i] : '';
      c.text('${i + 1}- ${w.trim().isEmpty ? '.' * 62 : w.trim()}', _l, y, _w, size: 12.3, bold: true, fit: true);
      y += 28;
    }

    final sy = y + 24 > 760 ? y + 24 : 760.0;
    const tw = _w / 3;
    c.text('إمضاء الأستاذ(ة)', _r - tw, sy, tw, size: 12.3, bold: true, align: ui.TextAlign.center);
    c.text('إمضاء الناظر(ة)', _r - 2 * tw, sy, tw, size: 12.3, bold: true, align: ui.TextAlign.center);
    c.text('إمضاء المدير(ة)', _l, sy, tw, size: 12.3, bold: true, align: ui.TextAlign.center);

    await pages.add(c);
    return pages.build();
  }

  // ───────────── Exports tableur (lignes de texte) ─────────────


  static List<List<String>> timetableCsv(List<TimetableSlot> slots, Map<int, SchoolClass> classes) => [
        ['Jour', 'Début', 'Fin', 'Classe', 'Niveau', 'Terrain'],
        for (final s in slots)
          [
            kDayNamesFr[s.dayOfWeek - 1], s.startTime, s.endTime,
            classes[s.classId]?.name ?? '', classes[s.classId]?.level ?? '', s.fieldName ?? '',
          ],
      ];

  static List<List<String>> termCsv(SchoolClass cls, Term term, TermSummary summary) => [
        ['Classe', 'Trimestre', 'Matricule', 'Élève', 'Sexe', 'Absences', 'Présence %', 'Évaluations', 'Moyenne /20', 'Appréciation'],
        for (final st in summary.students)
          [
            cls.name, term.name, st.student.studentNumber ?? '', st.student.fullName,
            st.student.gender ?? '', '${st.absences}',
            (st.presencePct ?? 100).toStringAsFixed(0), '${st.gradedEvals}',
            st.average?.toStringAsFixed(2) ?? '', st.average == null ? '' : _appr(st.average!),
          ],
      ];

  static List<List<String>> gradeSheetCsv(
    SchoolClass cls,
    Term term,
    List<EvaluationRow> evals,
    Map<int, Map<int, double?>> matrix,
    TermSummary summary,
  ) =>
      [
        ['Classe', 'Trimestre', 'Matricule', 'Élève', ...evals.map((r) => r.evaluation.title), 'Moyenne /20'],
        for (final st in summary.students)
          [
            cls.name, term.name, st.student.studentNumber ?? '', st.student.fullName,
            for (final r in evals) matrix[r.evaluation.id]?[st.student.id]?.toStringAsFixed(2) ?? '',
            st.average?.toStringAsFixed(2) ?? '',
          ],
      ];

  static List<List<String>> exemptCsv(List<Map<String, Object?>> rows) => [
        ['Nom', 'Prénom', 'Sexe', 'Classe', 'Matricule', 'Motif'],
        for (final r in rows)
          [
            '${r['last_name']}', '${r['first_name']}', '${r['gender'] ?? ''}', '${r['class_name']}',
            '${r['student_number'] ?? ''}', '${r['medical_reason'] ?? "Dispensé(e) d'EPS"}',
          ],
      ];
}
