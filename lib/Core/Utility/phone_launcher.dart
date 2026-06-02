import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

String sanitizePhoneNumber(String rawNumber) {
  final trimmed = rawNumber.trim();
  final hasPlus = trimmed.startsWith('+');
  final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.isEmpty) return '';
  return hasPlus ? '+$digitsOnly' : digitsOnly;
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
