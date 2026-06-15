import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

String sanitizePhoneNumber(String rawNumber) {
  final trimmed = rawNumber.trim();
  final hasPlus = trimmed.startsWith('+');
  final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.isEmpty) return '';
  return hasPlus ? '+$digitsOnly' : digitsOnly;
}

/// Opens the given Android app's Play Store page. Tries the Play Store app
/// first (`market://`) then falls back to the https store URL in the browser.
/// Never throws — returns false if nothing could be launched.
Future<bool> launchPlayStore(String packageName) async {
  final pkg = packageName.trim();
  if (pkg.isEmpty) return false;

  final candidates = <Uri>[
    Uri.parse('market://details?id=$pkg'),
    Uri.parse('https://play.google.com/store/apps/details?id=$pkg'),
  ];

  for (final uri in candidates) {
    try {
      final okExternal = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (okExternal) return true;
    } catch (_) {}

    try {
      final okDefault = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (okDefault) return true;
    } catch (_) {}

    if (kDebugMode) {
      debugPrint('Play Store launch fallback failed for $uri');
    }
  }

  return false;
}

Future<bool> launchPhoneDialer(String rawNumber) async {
  final normalized = sanitizePhoneNumber(rawNumber);
  if (normalized.isEmpty) return false;

  final candidates = <Uri>[
    Uri(scheme: 'tel', path: normalized),
    Uri.parse('tel:$normalized'),
    Uri.parse('tel://$normalized'),
  ];

  for (final uri in candidates) {
    try {
      final okExternal = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (okExternal) return true;
    } catch (_) {}

    try {
      final okDefault = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (okDefault) return true;
    } catch (_) {}

    if (kDebugMode) {
      debugPrint('Dialer launch fallback failed for $uri');
    }
  }

  return false;
}
