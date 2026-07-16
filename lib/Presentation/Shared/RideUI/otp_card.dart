// Shared Ride UI — OTP card.
//
// Deliberately dark "vault" card (per design direction: security-sensitive
// content stays dark/branded even though the rest of the UI is light).
// Large digit boxes, not default PIN-field boxes. Generic: caller supplies
// the already-authorized code (or null while unavailable) and copy —
// nothing here knows whether this is a pickup, delivery, or ride OTP.

import 'package:flutter/material.dart';
import 'ride_ui_theme.dart';

class OtpCard extends StatefulWidget {
  final String title;
  final String? code;
  final String helperText;
  final bool verified;
  final String verifiedText;

  const OtpCard({
    super.key,
    required this.title,
    required this.code,
    required this.helperText,
    this.verified = false,
    this.verifiedText = 'Verified',
  });

  @override
  State<OtpCard> createState() => _OtpCardState();
}

class _OtpCardState extends State<OtpCard> {
  // Starts collapsed — the OTP is security-sensitive (handed to the
  // courier in person), so it shouldn't sit fully exposed on screen by
  // default. Tapping the card reveals the big digit boxes; tapping again
  // hides them.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final code = widget.code;
    final helperText = widget.helperText;
    final verified = widget.verified;
    final verifiedText = widget.verifiedText;
    if (verified) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF9EE),
          borderRadius: BorderRadius.circular(RideUI.radiusCard),
          border: Border.all(color: const Color(0xFFBBE8CB)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.verified_rounded,
              size: 20,
              color: RideUI.brandGreen,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                verifiedText,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: RideUI.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final digits = (code ?? '').split('');
    final hasCode = digits.isNotEmpty;
    final expanded = _expanded && hasCode;

    return AnimatedContainer(
      duration: RideUI.motionBase,
      curve: RideUI.motionCurve,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: RideUI.vault,
        borderRadius: BorderRadius.circular(RideUI.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap:
                hasCode ? () => setState(() => _expanded = !_expanded) : null,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: RideUI.vaultField,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    size: 16,
                    color: RideUI.vaultTextPrimary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: RideUI.vaultTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (hasCode) ...[
                  Text(
                    expanded ? 'Hide' : 'Tap to view',
                    style: const TextStyle(
                      color: RideUI.vaultTextSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    duration: RideUI.motionBase,
                    turns: expanded ? 0.5 : 0,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: RideUI.vaultTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!hasCode) ...[
            const SizedBox(height: 14),
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: RideUI.vaultTextSecondary,
              ),
            ),
          ] else ...[
            AnimatedSize(
              duration: RideUI.motionBase,
              curve: RideUI.motionCurve,
              alignment: Alignment.topCenter,
              child:
                  expanded
                      ? Column(
                        children: [
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < digits.length; i++) ...[
                                if (i != 0) const SizedBox(width: 8),
                                Container(
                                  width: 44,
                                  height: 52,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: RideUI.vaultField,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: RideUI.vaultFieldBorder,
                                    ),
                                  ),
                                  child: Text(
                                    digits[i],
                                    style: const TextStyle(
                                      color: RideUI.vaultTextPrimary,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      )
                      : const SizedBox(width: double.infinity, height: 0),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            helperText,
            style: const TextStyle(
              color: RideUI.vaultTextSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
