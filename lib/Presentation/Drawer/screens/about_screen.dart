import 'package:flutter/material.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // Brand accent (Hoppr red).
  static const Color _accent = Color(0xFFE53935);

  // NOTE: confirm the Terms URL with the team — only the Privacy URL was
  // present in the app; the Terms URL follows the same path pattern.
  static const String _termsUrl =
      'https://next.fenizotechnologies.com/hoppr/Terms-and-Conditions/';
  static const String _privacyUrl =
      'https://next.fenizotechnologies.com/hoppr/Privacy-Policy/';
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.hopper.customer.hopper';

  Future<void> _openUrl(
    BuildContext context,
    String url, {
    bool external = false,
  }) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(
        uri,
        mode: external
            ? LaunchMode.externalApplication
            : LaunchMode.inAppWebView,
      );
      if (ok) return;
    } catch (_) {}
    // Fallback to the external browser/app.
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open the link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          children: [
            // ---- Header ----
            Container(
              color: Colors.white,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 16, 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back, color: _accent),
                        ),
                        const SizedBox(width: 2),
                        const Text(
                          'About',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: const Color(0xFFEDEFF3)),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  const SizedBox(height: 28),

                  // ---- Logo ----
                  Center(
                    child: Image.asset(
                      AppImages.hopprLogo,
                      width: 210,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 90,
                        child: Center(
                          child: Icon(
                            Icons.directions_car_rounded,
                            size: 56,
                            color: _accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Center(
                    child: Text(
                      'Version 1.0.0',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),

                  // ---- Links card ----
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.black.withOpacity(0.05)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _aboutItem(
                          icon: Icons.description_outlined,
                          title: 'Terms & Conditions',
                          onTap: () => _openUrl(context, _termsUrl),
                        ),
                        _divider(),
                        _aboutItem(
                          icon: Icons.privacy_tip_outlined,
                          title: 'Privacy Policy',
                          onTap: () => _openUrl(context, _privacyUrl),
                        ),
                        _divider(),
                        _aboutItem(
                          icon: Icons.star_outline_rounded,
                          title: 'Rate us on Play Store',
                          onTap: () =>
                              _openUrl(context, _playStoreUrl, external: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(
    height: 1,
    thickness: 1,
    indent: 56,
    endIndent: 16,
    color: Color(0xFFEFF1F4),
  );

  Widget _aboutItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: _accent, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
