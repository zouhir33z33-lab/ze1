import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

/// Dessin de pages PDF avec le moteur de texte de Flutter (forme des lettres arabes,
/// sens RTL et texte mixte arabe/latin parfaitement gérés), puis assemblage en PDF.
/// Chaque page est dessinée en points (A4 = 595 × 842) et intégrée comme image haute
/// résolution : aucune dépendance au WebView ni à une bibliothèque de formes arabes.
const double kA4W = 595.28;
const double kA4H = 841.89;

const ui.Color kInk = ui.Color(0xFF111111);
const ui.Color kGrey = ui.Color(0xFF666666);
const ui.Color kLine = ui.Color(0xFF777777);
const ui.Color kBlue = ui.Color(0xFF0D47A1);
const ui.Color kRed = ui.Color(0xFFC62828);
const ui.Color kGreen = ui.Color(0xFF2E7D32);
const ui.Color kOrange = ui.Color(0xFFEF6C00);
const ui.Color kTeal = ui.Color(0xFF00695C);

/// Segment de texte riche (gras / couleur).
class Seg {
  final String t;
  final bool bold;
  final ui.Color? color;
  const Seg(this.t, {this.bold = false, this.color});
}

class PageCanvas {
  final double width;
  final double height;
  final double scale;
  late final ui.PictureRecorder _rec;
  late final ui.Canvas canvas;

  PageCanvas({this.width = kA4W, this.height = kA4H, this.scale = 3.0}) {
    _rec = ui.PictureRecorder();
    canvas = ui.Canvas(_rec);
    canvas.scale(scale);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width, height),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
  }

  // ───────────── formes ─────────────

  void rect(double x, double y, double w, double h,
      {ui.Color? fill, ui.Color? stroke, double sw = 0.8, double r = 0}) {
    final rr = ui.RRect.fromRectAndRadius(ui.Rect.fromLTWH(x, y, w, h), ui.Radius.circular(r));
    if (fill != null) canvas.drawRRect(rr, ui.Paint()..color = fill);
    if (stroke != null) {
      canvas.drawRRect(
        rr,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = sw
          ..color = stroke,
      );
    }
  }

  void line(double x1, double y1, double x2, double y2, {ui.Color color = kLine, double sw = 0.8}) {
    canvas.drawLine(
      ui.Offset(x1, y1),
      ui.Offset(x2, y2),
      ui.Paint()
        ..color = color
        ..strokeWidth = sw,
    );
  }

  // ───────────── texte ─────────────

  static final RegExp _arabic = RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');

  /// Sens du texte : RTL s'il contient de l'arabe, sinon LTR (dates, heures, nombres, français).
  ui.TextDirection _dirFor(String s, ui.TextDirection? forced) =>
      forced ?? (_arabic.hasMatch(s) ? ui.TextDirection.rtl : ui.TextDirection.ltr);

  TextStyle _style(double size, bool bold, ui.Color color, double lineHeight) => TextStyle(
        fontFamily: 'Arial',
        fontSize: size,
        fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
        color: color,
        height: lineHeight,
      );

  /// Paragraphe dans la boîte [x, y, w]. Retourne la hauteur utilisée.
  /// [fit] = une seule ligne, police réduite si nécessaire pour tenir dans la largeur.
  double text(
    String s,
    double x,
    double y,
    double w, {
    double size = 10,
    bool bold = false,
    ui.Color color = kInk,
    ui.TextAlign align = ui.TextAlign.right,
    double lineHeight = 1.25,
    bool fit = false,
    ui.TextDirection? dir,
  }) {
    return rich([Seg(s, bold: bold, color: color)], x, y, w,
        size: size, align: align, lineHeight: lineHeight, fit: fit, dir: dir);
  }

  double rich(
    List<Seg> segs,
    double x,
    double y,
    double w, {
    double size = 10,
    ui.TextAlign align = ui.TextAlign.right,
    double lineHeight = 1.25,
    bool fit = false,
    ui.TextDirection? dir,
  }) {
    final direction = _dirFor(segs.map((e) => e.t).join(), dir);
    var fs = size;
    late TextPainter tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(
          style: _style(fs, false, kInk, lineHeight),
          children: [
            for (final s in segs)
              TextSpan(text: s.t, style: _style(fs, s.bold, s.color ?? kInk, lineHeight)),
          ],
        ),
        textDirection: direction,
        textAlign: align,
        maxLines: fit ? 1 : null,
      )..layout(minWidth: w, maxWidth: w);
      if (!fit || !tp.didExceedMaxLines || fs <= 5) break;
      fs -= 0.5;
    }
    tp.paint(canvas, ui.Offset(x, y));
    return tp.height;
  }

  /// Texte centré verticalement dans une boîte de hauteur [h] (une ligne, ajusté en largeur).
  void textBox(
    String s,
    double x,
    double y,
    double w,
    double h, {
    double size = 9,
    bool bold = false,
    ui.Color color = kInk,
    ui.TextAlign align = ui.TextAlign.center,
    double pad = 3,
  }) {
    var fs = size;
    late TextPainter tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(text: s, style: _style(fs, bold, color, 1.1)),
        textDirection: _dirFor(s, null),
        textAlign: align,
        maxLines: 1,
      )..layout(minWidth: w - 2 * pad, maxWidth: w - 2 * pad);
      if (!tp.didExceedMaxLines || fs <= 5) break;
      fs -= 0.5;
    }
    tp.paint(canvas, ui.Offset(x + pad, y + (h - tp.height) / 2));
  }

  Future<Uint8List> toPng() async {
    final pic = _rec.endRecording();
    final img = await pic.toImage((width * scale).round(), (height * scale).round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}

/// Assemble des pages dessinées en un document PDF.
class PdfPages {
  final bool landscape;
  final List<Uint8List> _pngs = [];
  PdfPages({this.landscape = false});

  PageCanvas newPage() => landscape ? PageCanvas(width: kA4H, height: kA4W) : PageCanvas();

  Future<void> add(PageCanvas p) async => _pngs.add(await p.toPng());

  Future<Uint8List> build() async {
    final doc = pw.Document();
    final fmt = landscape ? pdf.PdfPageFormat.a4.landscape : pdf.PdfPageFormat.a4;
    for (final png in _pngs) {
      final image = pw.MemoryImage(png);
      doc.addPage(
        pw.Page(
          pageFormat: fmt,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
        ),
      );
    }
    return doc.save();
  }
}
