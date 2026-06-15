import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class CompactMarkerIcons {
  static final Map<String, BitmapDescriptor> _cache =
      <String, BitmapDescriptor>{};

  static Future<ui.Rect?> _opaqueBounds(ui.Image image) async {
    const int alphaThreshold = 12;
    ByteData? bd;
    try {
      bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } catch (_) {
      bd = null;
    }
    if (bd == null) return null;
    final bytes = bd.buffer.asUint8List();
    final w = image.width;
    final h = image.height;
    int minX = w, minY = h, maxX = -1, maxY = -1;

    for (int y = 0; y < h; y++) {
      final rowOffset = y * w * 4;
      for (int x = 0; x < w; x++) {
        final a = bytes[rowOffset + x * 4 + 3];
        if (a > alphaThreshold) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (maxX < 0 || maxY < 0) return null;
    minX = (minX - 1).clamp(0, w - 1);
    minY = (minY - 1).clamp(0, h - 1);
    maxX = (maxX + 1).clamp(0, w - 1);
    maxY = (maxY + 1).clamp(0, h - 1);
    return ui.Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );
  }

  /// Render an asset as a crisp marker icon without any badge/circle behind it.
  ///
  /// - Crops transparent padding (tight bounds)
  /// - Scales with `devicePixelRatio`
  /// - Contain-fit into the target square (no stretching)
  static Future<BitmapDescriptor> assetContained({
    required String assetPath,
    double sizeDp = 28,
    double? dpr,
  }) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final key = 'contain|$assetPath|$sizeDp|$resolvedDpr';
    final cached = _cache[key];
    if (cached != null) return cached;

    final targetPx = (sizeDp * resolvedDpr).round().clamp(18, 420);

    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final src = frame.image;

    final srcRect = (await _opaqueBounds(src)) ??
        Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble());

    final cropW = srcRect.width;
    final cropH = srcRect.height;

    final scale = (cropW <= 1 || cropH <= 1)
        ? 1.0
        : (targetPx / math.max(cropW, cropH));

    // Contain within the square while preserving aspect ratio.
    final dstW = cropW * scale;
    final dstH = cropH * scale;
    final dx = (targetPx - dstW) / 2.0;
    final dy = (targetPx - dstH) / 2.0;
    final dstRect = Rect.fromLTWH(dx, dy, dstW, dstH);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, targetPx.toDouble(), targetPx.toDouble()),
    );
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;
    canvas.drawImageRect(
      src,
      srcRect,
      dstRect,
      paint,
    );
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(targetPx, targetPx);
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    _cache[key] = icon;
    return icon;
  }

  static Future<BitmapDescriptor> assetPin({
    required String assetPath,
    double widthDp = 22,
    Color? tint,
    double? dpr,
  }) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final key = 'asset|$assetPath|$widthDp|${tint?.value}|$resolvedDpr';
    final cached = _cache[key];
    if (cached != null) return cached;

    final targetPx = (widthDp * resolvedDpr).round().clamp(18, 180);
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: targetPx,
    );
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final iw = img.width;
    final ih = img.height;

    // Draw through a canvas so an optional tint (srcIn) can recolor a solid
    // silhouette pin — pickup vs drop in different colours from one asset.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, iw.toDouble(), ih.toDouble()),
    );
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, iw.toDouble(), ih.toDouble()),
      Rect.fromLTWH(0, 0, iw.toDouble(), ih.toDouble()),
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high
        ..colorFilter =
            tint != null ? ColorFilter.mode(tint, BlendMode.srcIn) : null,
    );
    final rendered = await recorder.endRecording().toImage(iw, ih);
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
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
    Color? tint,
    double? dpr,
  }) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final key =
        'label|$label|$assetPath|$bubbleWidthDp|$bubbleHeightDp|$pinWidthDp|$fontSizeDp|${tint?.value}|$resolvedDpr';
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
      Paint()
        ..filterQuality = FilterQuality.high
        ..colorFilter =
            tint != null ? ColorFilter.mode(tint, BlendMode.srcIn) : null,
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
