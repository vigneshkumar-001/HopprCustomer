import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/api/dataSource/apiDataSource.dart';
import 'package:hopper/Presentation/OnBoarding/models/ride_receipt_response.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Post-payment success bottom sheet — shared by the car-ride and parcel
/// payment flows. Fetches the same booking-agnostic receipt endpoint
/// (keyed only by bookingId), so it works unmodified for either booking type.
class PaymentSuccessSheet extends StatefulWidget {
  final String bookingId;
  final String paymentMethod;
  final String fallbackSummary;
  final VoidCallback onContinue;
  final Future<void> Function() onFallbackDownload;
  final String headline;
  final String subheadline;

  const PaymentSuccessSheet({
    super.key,
    required this.bookingId,
    required this.paymentMethod,
    required this.fallbackSummary,
    required this.onContinue,
    required this.onFallbackDownload,
    this.headline = 'Payment Successful',
    this.subheadline =
        'Your payment is confirmed. Review or share the trip summary before rating.',
  });

  @override
  State<PaymentSuccessSheet> createState() => _PaymentSuccessSheetState();
}

class _PaymentSuccessSheetState extends State<PaymentSuccessSheet> {
  RideReceiptResponse? _receipt;
  bool _loading = true;
  bool _pdfBuilding = false;

  @override
  void initState() {
    super.initState();
    _fetchReceipt();
  }

  Future<void> _fetchReceipt() async {
    if (widget.bookingId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final res =
        await ApiDataSource().getRideReceipt(bookingId: widget.bookingId);
    if (!mounted) return;
    res.fold(
      (_) => setState(() => _loading = false),
      (r) => setState(() {
        _receipt = r.success ? r : null;
        _loading = false;
      }),
    );
  }

  // Backend text when available, else the local summary — so Copy / Share always
  // produce something useful.
  String get _shareText =>
      (_receipt?.hasText ?? false) ? _receipt!.text : widget.fallbackSummary;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _shareText));
    if (!mounted) return;
    AppToasts.showSuccess(context, 'Receipt copied');
  }

  // Share the openable receipt link when the backend provides one (recipient can
  // view + Save as PDF in the browser), else fall back to the text summary.
  void _share() {
    final url = _receipt?.downloadUrl ?? '';
    if (url.isNotEmpty) {
      Share.share('$_shareText\n\nView receipt: $url');
    } else {
      Share.share(_shareText);
    }
  }

  Future<void> _download() async {
    // Preferred path: backend-provided ready-to-open receipt link. Opens the
    // styled receipt in the device browser (which has its own "Save as PDF").
    // No PDF packages / building needed.
    final url = _receipt?.downloadUrl ?? '';
    if (url.isNotEmpty) {
      try {
        final ok = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (ok) return;
      } catch (_) {
        // fall through to the local PDF/text export below
      }
    }

    // Fallback (older backend, no downloadUrl): build the PDF locally from the
    // receipt HTML; if even that is missing, use the local text export.
    final html = _receipt?.html ?? '';
    if (html.trim().isEmpty) {
      await widget.onFallbackDownload();
      return;
    }
    setState(() => _pdfBuilding = true);
    try {
      final bytes = await Printing.convertHtml(
        format: PdfPageFormat.a4,
        html: html,
      );
      final safeId =
          widget.bookingId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Hoppr_Receipt_$safeId.pdf',
      );
    } catch (_) {
      if (mounted) AppToasts.showError(context, 'Failed to build receipt PDF');
    } finally {
      if (mounted) setState(() => _pdfBuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final busy = _pdfBuilding; // disable every action while the PDF builds
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D5DD),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Center(
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.black,
                  child: Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  widget.headline,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  widget.subheadline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF667085), fontSize: 13),
                ),
              ),
              const SizedBox(height: 18),
              _receiptCard(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: AppButtons.button(
                      onTap: busy ? null : _share,
                      text: 'Share',
                      buttonColor: Colors.white,
                      textColor: Colors.black,
                      hasBorder: true,
                      borderColor: const Color(0xFFD0D5DD),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButtons.button(
                      onTap: busy ? null : _copy,
                      text: 'Copy',
                      buttonColor: Colors.white,
                      textColor: Colors.black,
                      hasBorder: true,
                      borderColor: const Color(0xFFD0D5DD),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: AppButtons.button(
                      onTap: busy ? null : _download,
                      isLoading: _pdfBuilding,
                      text: 'Download',
                      buttonColor: Colors.white,
                      textColor: Colors.black,
                      hasBorder: true,
                      borderColor: const Color(0xFFD0D5DD),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButtons.button(
                      onTap: busy ? null : widget.onContinue,
                      text: 'Continue',
                      buttonColor: AppColors.commonBlack,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: _loading
          ? const SizedBox(
              height: 96,
              child: Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : (_receipt?.data != null
              ? _structuredCard(_receipt!.data!)
              : _fallbackCard()),
    );
  }

  Widget _structuredCard(ReceiptData d) {
    final method = d.paymentMethod.trim().isNotEmpty
        ? d.paymentMethod
        : widget.paymentMethod;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.receipt_long_rounded,
              size: 18,
              color: Color(0xFF101828),
            ),
            const SizedBox(width: 8),
            const Text(
              'Hoppr Receipt',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            if (d.status.trim().isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F6EC),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  d.status,
                  style: const TextStyle(
                    color: Color(0xFF067647),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (d.bookingId.isNotEmpty) _kv('Booking ID', d.bookingId),
        if (d.rideDate.isNotEmpty) _kv('Date', d.rideDate),
        _kv('Amount', d.formattedTotal),
        if (method.trim().isNotEmpty) _kv('Payment', method),
        if (d.driverName.isNotEmpty) _kv('Driver', d.driverWithRating),
      ],
    );
  }

  Widget _fallbackCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF98A2B3)),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Receipt not available yet',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF667085),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          widget.fallbackSummary,
          style: const TextStyle(
            height: 1.5,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
