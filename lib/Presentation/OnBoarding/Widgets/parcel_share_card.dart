// Receiver Tracking Share card.
//
// Mounted on the sender's package tracking screen once pickup is verified.
// Deliberately compact: just "Share Trip" (system share sheet with the
// tracking message) and "Copy Link" — no dedicated WhatsApp CTA/header, so
// the sender sees one simple pair of actions instead of a heavier card.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Core/Utility/whatsapp_share_helper.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';

class ParcelShareCard extends StatelessWidget {
  final PackageController packageController;

  const ParcelShareCard({super.key, required this.packageController});

  static const _ink = Color(0xFF111827);
  static const _grey = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final loading = packageController.shareDetailsLoading.value;
      final error = packageController.shareDetailsError.value;
      final data = packageController.shareDetails.value;

      if (data == null && loading) return _skeleton();
      if (data == null && error.isNotEmpty) return _errorCard(context);
      if (data == null) return const SizedBox.shrink();
      return _loadedCard(context, data);
    });
  }

  Widget _shell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _skeleton() {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(140, 16),
          const SizedBox(height: 10),
          bar(220, 12),
          const SizedBox(height: 16),
          bar(double.infinity, 48),
        ],
      ),
    );
  }

  Widget _errorCard(BuildContext context) {
    return _shell(
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: _grey, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Share details are unavailable right now.',
              style: TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final bookingId =
                  packageController.shareDetails.value?['publicPackageId']
                      ?.toString() ??
                  '';
              if (bookingId.isNotEmpty) {
                packageController.fetchParcelShareDetails(bookingId);
              }
            },
            child: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadedCard(BuildContext context, Map<String, dynamic> data) {
    final message = (data['message'] ?? '').toString();
    final trackingUrl = (data['trackingUrl'] ?? '').toString();

    return _shell(
      child: Row(
        children: [
          Expanded(
            child: _secondaryAction(
              icon: Icons.ios_share_rounded,
              label: 'Share Trip',
              onTap: message.isEmpty ? null : () => shareParcelMessage(message),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _secondaryAction(
              icon: Icons.link_rounded,
              label: 'Copy Link',
              onTap:
                  trackingUrl.isEmpty
                      ? null
                      : () => _handleCopyLink(context, trackingUrl),
            ),
          ),
        ],
      ),
    );
  }

  Widget _secondaryAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: _ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCopyLink(BuildContext context, String url) async {
    final ok = await copyToClipboard(url);
    if (!context.mounted) return;
    if (ok) {
      AppToasts.showSuccess(context, 'Tracking link copied');
    } else {
      AppToasts.showError(context, 'Could not copy the link');
    }
  }
}
