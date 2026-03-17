import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

Future<File?> compressImage(
    File file, {
      int quality = 70,
      int minWidth = 1080,
      int minHeight = 1080,
    }) async {
  try {
    // Safety checks
    final exists = await file.exists();
    debugPrint("Compress input exists: $exists | path: ${file.path}");
    if (!exists) return null;

    final dir = await getTemporaryDirectory();
    final targetPath = p.join(
      dir.path,
      'selfie_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    // ✅ More reliable path: compress to bytes, then write
    final Uint8List? bytes = await FlutterImageCompress.compressWithFile(
      file.path,
      quality: quality,
      minWidth: minWidth,
      minHeight: minHeight,
      format: CompressFormat.jpeg,
    );

    if (bytes == null) {
      debugPrint("❌ compressWithFile returned NULL");
      return null;
    }

    final outFile = File(targetPath);
    await outFile.writeAsBytes(bytes, flush: true);

    debugPrint("✅ Compressed saved: ${outFile.path} | bytes: ${outFile.lengthSync()}");
    return outFile;
  } catch (e) {
    debugPrint("Image compress error: $e");
    return null;
  }
}
void printImageSize(File file, {String label = ''}) {
  final int bytes = file.lengthSync();
  final double kb = bytes / 1024;
  final double mb = kb / 1024;

  debugPrint('$label size: $bytes bytes | ${kb.toStringAsFixed(2)} KB | ${mb.toStringAsFixed(2)} MB');
}
