import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Receiver Tracking + WhatsApp Share MVP.
///
/// Important: this app NEVER auto-sends a WhatsApp message. `openWhatsAppChat`
/// only opens WhatsApp with the receiver's chat pre-filled — the sender still
/// has to tap WhatsApp's own Send button. That is a WhatsApp platform
/// guarantee of the `wa.me` deep link (it fills the compose box, nothing
/// more), not something this app enforces — do not add any flow that types
/// into WhatsApp's UI or posts to a WhatsApp API on the sender's behalf.

/// Loose validity check on an already-normalized E.164 Nigerian number. The
/// backend (`normalizeNigerianPhone` in twilio.service.ts) is the sole source
/// of truth for normalization — this only guards against showing a WhatsApp
/// button for a missing/malformed number.
bool isValidNormalizedNigerianPhone(String? phone) {
  final p = (phone ?? '').trim();
  return RegExp(r'^\+234\d{10}$').hasMatch(p);
}

/// Opens WhatsApp with [phone] (already-normalized E.164, e.g. `+2348012345678`)
/// and [message] pre-filled in the compose box. Tries the native app first,
/// then falls back to WhatsApp Web/browser — both are inherent to how `wa.me`
/// links resolve, not something this app orchestrates. Returns false (never
/// throws) if nothing could be launched, so callers can fall back to the
/// generic share sheet.
Future<bool> openWhatsAppChat({
  required String phone,
  required String message,
}) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return false;
  final encoded = Uri.encodeComponent(message);

  final candidates = <Uri>[
    Uri.parse('https://wa.me/$digits?text=$encoded'),
    Uri.parse('whatsapp://send?phone=$digits&text=$encoded'),
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
      debugPrint('WhatsApp launch fallback failed for $uri');
    }
  }

  return false;
}

/// Generic platform share sheet fallback (WhatsApp not installed / no
/// handler available) — the receiver's tracking message, shareable to any
/// app the sender picks, including WhatsApp's own share target.
Future<void> shareParcelMessage(String message) async {
  try {
    await SharePlus.instance.share(ShareParams(text: message));
  } catch (_) {}
}

/// Copies [text] to the clipboard. Never throws — callers show their own
/// success/error toast based on the returned bool.
Future<bool> copyToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}
