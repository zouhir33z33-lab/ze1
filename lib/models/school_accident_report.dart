/// Données du formulaire « تقرير عن حادث مدرسي » (modèle de rapport destiné à la direction).
enum SportKind { none, physical, collective }

class SchoolAccidentReport {
  String institution;
  String wilaya;
  DateTime date;
  String mrName;
  String job;
  String signer; // « أنا الممضي أسفله الأستاذ ... »
  String hour;
  String className;
  String student;
  String birthDate;
  SportKind kind;
  String anyText; // « أي (...) »
  String place;
  String level; // « على مستوى ... »
  String intervention;
  String cause;
  List<String> witnesses;

  SchoolAccidentReport({
    this.institution = '',
    this.wilaya = '',
    DateTime? date,
    this.mrName = '',
    this.job = '',
    this.signer = '',
    this.hour = '',
    this.className = '',
    this.student = '',
    this.birthDate = '',
    this.kind = SportKind.none,
    this.anyText = '',
    this.place = '',
    this.level = '',
    this.intervention = '',
    this.cause = '',
    List<String>? witnesses,
  })  : date = date ?? DateTime.now(),
        witnesses = witnesses ?? ['', '', ''];
}

/// Fonctions proposées dans le formulaire (neuf choix).
const List<String> kReportJobs = [
  'أستاذ التعليم الإبتدائي قسم أول',
  'أستاذ التعليم الإبتدائي قسم ثان',
  'أستاذ مميز في التعليم إبتدائي',
  'أستاذ التعليم المتوسط قسم أول',
  'أستاذ التعليم المتوسط قسم ثان',
  'أستاذ مميز في التعليم المتوسط',
  'أستاذ التعليم الثانوي قسم أول',
  'أستاذ التعليم الثانوي قسم ثان',
  'أستاذ مميز في التعليم الثانوي',
];
