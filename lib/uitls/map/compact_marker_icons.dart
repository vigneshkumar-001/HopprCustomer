import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class CompactMarkerIcons {
  static final Map<String, BitmapDescriptor> _cache =
      <String, BitmapDescriptor>{};

  static Future<BitmapDescriptor> assetPin({
    required String assetPath,
    double widthDp = 22,
    double? dpr,
  }) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final key = 'asset|$assetPath|$widthDp|$resolvedDpr';
    final cached = _cache[key];
    if (cached != null) return cached;

    final targetPx = (widthDp * resolvedDpr).round().clamp(18, 180);
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: targetPx,
    );
    final frame = await codec.getNextFrame();
    final bytes = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    _cache[key] = icon;
    return icon;
  }

  static Future<BitmapDescriptor> labeledPin({
    required String label,
    required String assetPath,
    double bubbleWidthDp = 170,
    double bubbleHeightDp = 46,
    double pinWidthDp = 22,
    double fontSizeDp = 13,
    TextAlign textAlign = TextAlign.center,
    double? dpr,
  }) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final key =
        'label|$label|$assetPath|$bubbleWidthDp|$bubbleHeightDp|$pinWidthDp|$fontSizeDp|$resolvedDpr';
    final cached = _cache[key];
    if (cached != null) return cached;

    final w = (bubbleWidthDp * resolvedDpr).round().clamp(140, 1400);
    final h = (bubbleHeightDp * resolvedDpr).round().clamp(36, 600);
    final pinW = (pinWidthDp * resolvedDpr).round().clamp(18, 260);
    final pad = (10 * resolvedDpr).round().clamp(8, 90);
    final radius = (14 * resolvedDpr).round().clamp(10, 120);
    final gap = (4 * resolvedDpr).round().clamp(2, 40);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(radius.toDouble()),
    );

    canvas.drawShadow(
      Path()..addRRect(rrect),
      Colors.black.withOpacity(0.18),
      8 * resolvedDpr,
      false,
    );
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFFE5E7EB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (1.0 * resolvedDpr).clamp(1.0, 3.0),
    );

    final textPara = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: textAlign,
        maxLines: 2,
        ellipsis: '...',
      ),
    )..pushStyle(
      ui.TextStyle(
        color: Colors.black,
        fontSize: (fontSizeDp * resolvedDpr).clamp(12.0, 60.0),
        fontWeight: FontWeight.w800,
      ),
    );
    textPara.addText(label);
    final paragraph = textPara.build();
    paragraph.layout(ui.ParagraphConstraints(width: (w - pad * 2).toDouble()));

    final double textX;
    switch (textAlign) {
      case TextAlign.left:
      case TextAlign.start:
        textX = pad.toDouble();
        break;
      case TextAlign.right:
      case TextAlign.end:
        textX = (w - pad - paragraph.maxIntrinsicWidth).clamp(
          0,
          w.toDouble(),
        );
        break;
      default:
        textX = ((w - paragraph.maxIntrinsicWidth) / 2).clamp(0, w.toDouble());
    }

    canvas.drawParagraph(
      paragraph,
      Offset(textX, (h - paragraph.height) / 2),
    );

    // pin image (keep aspect ratio; don't force square)
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: pinW,
    );
    final frame = await codec.getNextFrame();
    final img = frame.image;

    final pinH = (pinW * (img.height / img.width)).round().clamp(18, 520);
    final totalH = h + pinH + gap;

    final dst = Rect.fromLTWH(
      ((w - pinW) / 2).toDouble(),
      (h + gap).toDouble(),
      pinW.toDouble(),
      pinH.toDouble(),
    );
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(w, totalH);
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    _cache[key] = icon;
    return icon;
  }

  /// Vehicle-style icon: asset centered inside a circular badge.
  /// Uses dp sizing and caches by (asset + size + dpr).
  static Future<BitmapDescriptor> assetCircleBadge({
    required String assetPath,
    double diameterDp = 28,
    double? dpr,
    double imageScale = 0.56,
  }) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final key = 'badge|$assetPath|$diameterDp|$imageScale|$resolvedDpr';
    final cached = _cache[key];
    if (cached != null) return cached;

    final targetPx = (diameterDp * resolvedDpr).round().clamp(18, 220);
    final sourceWidthPx =
        (targetPx * imageScale).round().clamp(14, targetPx);

    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: sourceWidthPx,
    );
    final frame = await codec.getNextFrame();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(targetPx.toDouble(), targetPx.toDouble());
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = targetPx / 2;

    canvas.drawCircle(center, radius * 0.88, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius * 0.88,
      Paint()
        ..color = const Color(0xFFE5E7EB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (targetPx * 0.06).clamp(1.0, 6.0),
    );

    final img = frame.image;
    final dst = Rect.fromCenter(
      center: center,
      width: img.width.toDouble(),
      height: img.height.toDouble(),
    );
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );

    final rendered = await recorder.endRecording().toImage(targetPx, targetPx);
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    _cache[key] = icon;
    return icon;
  }
}
