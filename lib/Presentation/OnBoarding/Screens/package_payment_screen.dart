import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/package_map_confrim_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/payment_success_sheet.dart';
import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
import 'package:hopper/Presentation/wallet/controller/wallet_controller.dart';
import 'package:hopper/webview_page.dart';

/// Parcel booking-time payment screen. Reuses the SAME visual building blocks
/// as the car-ride PaymentScreen (PackageContainer tiles, AppButtons,
/// PaymentWebView, PaymentSuccessSheet, and the same generic gateway-init
/// endpoints) — but every API call goes through PackageController's own
/// payParcelBooking(), never driverSearchController or /paymentBooking.
/// The sender pays at booking time here, before pickup — see
/// isParcelPaymentSatisfied() in the backend for the full business rule.
///
/// The whole screen is driven by ONE centralized state
/// (`packageController.parcelPaymentUiState`, [ParcelPaymentUiState]) instead
/// of per-tile loading booleans — see the state's doc comment for the full
/// list. That state also decides the single bottom action button's label,
/// enablement, and loading spinner; tiles only ever *select* a method, they
/// never trigger a network call directly.
class PackagePaymentScreen extends StatefulWidget {
  final String bookingId;
  final double amount;
  final AddressModel senderData;
  final AddressModel receiverData;
  final String discountCode;

  const PackagePaymentScreen({
    super.key,
    required this.bookingId,
    required this.amount,
    required this.senderData,
    required this.receiverData,
    this.discountCode = '',
  });

  @override
  State<PackagePaymentScreen> createState() => _PackagePaymentScreenState();
}

class _PackagePaymentScreenState extends State<PackagePaymentScreen> {
  final PackageController packageController = Get.put(PackageController());
  final WalletController walletController = Get.put(WalletController());

  /// One-shot guard so a retry after a failed dispatch (payment already
  /// settled) never re-dispatches a courier a second time. Screen-lifecycle
  /// scoped — a fresh screen instance (new booking) always starts false.
  // An accepted asynchronous search, not a driver-found flag.
  bool _dispatchStarted = false;

  @override
  void initState() {
    super.initState();
    packageController.resetParcelPaymentFlow();
    walletController.getWalletBalance();
  }

  @override
  void dispose() {
    packageController.resetParcelPaymentFlow();
    super.dispose();
  }

  bool _isBusy(ParcelPaymentUiState state) =>
      state == ParcelPaymentUiState.confirmingCash ||
      state == ParcelPaymentUiState.initializingOnlinePayment ||
      state == ParcelPaymentUiState.awaitingPayment ||
      state == ParcelPaymentUiState.verifyingPayment ||
      state == ParcelPaymentUiState.dispatching ||
      state == ParcelPaymentUiState.success;

  String _bottomActionLabel(ParcelPaymentUiState state, String? method) {
    switch (state) {
      case ParcelPaymentUiState.idle:
        return 'Select a payment method';
      case ParcelPaymentUiState.methodSelected:
        switch (method) {
          case 'PAYSTACK':
            return 'Pay with Paystack';
          case 'FLUTTERWAVE':
            return 'Pay with Flutterwave';
          case 'WALLET':
            return 'Pay from Wallet';
          case 'CASH':
            return 'Confirm Cash Payment';
          default:
            return 'Continue';
        }
      case ParcelPaymentUiState.confirmingCash:
        return 'Confirming Cash Payment…';
      case ParcelPaymentUiState.initializingOnlinePayment:
        return 'Setting up payment…';
      case ParcelPaymentUiState.awaitingPayment:
        return 'Waiting for payment…';
      case ParcelPaymentUiState.verifyingPayment:
        return 'Verifying payment…';
      case ParcelPaymentUiState.dispatching:
        return 'Finding a courier…';
      case ParcelPaymentUiState.success:
        return 'Payment confirmed';
      case ParcelPaymentUiState.failed:
        return 'Try Again';
    }
  }

  void _selectMethod(String method) {
    final state = packageController.parcelPaymentUiState.value;
    // Locks method selection once a payment is actually in flight — matches
    // the "one correct bottom action" requirement (a tile tap can never race
    // an in-flight charge/dispatch).
    if (state != ParcelPaymentUiState.idle &&
        state != ParcelPaymentUiState.methodSelected &&
        state != ParcelPaymentUiState.failed) {
      return;
    }
    packageController.parcelPaymentStatusMessage.value = '';
    packageController.selectedParcelPaymentMethod.value = method;
    packageController.parcelPaymentUiState.value = ParcelPaymentUiState.methodSelected;
  }

  Future<void> _onBottomActionTap() async {
    final state = packageController.parcelPaymentUiState.value;
    final method = packageController.selectedParcelPaymentMethod.value;
    if (method == null) return;
    if (state != ParcelPaymentUiState.methodSelected && state != ParcelPaymentUiState.failed) {
      return;
    }
    packageController.parcelPaymentStatusMessage.value = '';
    switch (method) {
      case 'CASH':
        await _processCash();
        break;
      case 'WALLET':
        await _processWallet();
        break;
      case 'PAYSTACK':
        await _processOnlineGateway('PAYSTACK');
        break;
      case 'FLUTTERWAVE':
        await _processOnlineGateway('FLUTTERWAVE');
        break;
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    packageController.parcelPaymentUiState.value = ParcelPaymentUiState.failed;
    packageController.parcelPaymentStatusMessage.value = message;
    AppToasts.showError(context, message);
  }

  void _goToTracking() {
    if (!mounted) return;
    Get.offAll(
      () => PackageMapConfirmScreen(
        bookingId: widget.bookingId,
        discountCode: widget.discountCode,
        senderData: widget.senderData,
        receiverData: widget.receiverData,
      ),
    );
  }

  Future<void> _showSuccessSheet({
    required String paymentMethod,
    String? headline,
    String? subheadline,
    String? transactionId,
  }) async {
    final summary =
        'Hoppr Package Payment\nBooking: ${widget.bookingId}\nAmount: ${widget.amount.toStringAsFixed(2)}\nPayment: $paymentMethod'
        '${transactionId != null && transactionId.isNotEmpty ? '\nTransaction: $transactionId' : ''}';
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return PaymentSuccessSheet(
          bookingId: widget.bookingId,
          paymentMethod: paymentMethod,
          fallbackSummary: summary,
          onContinue: () => Navigator.pop(sheetContext),
          onFallbackDownload: () async {},
          headline: headline ?? 'Payment Successful',
          subheadline: subheadline ?? 'Your package payment is confirmed.',
        );
      },
    );
    _goToTracking();
  }

  /// Dispatches to nearby drivers — only ever called AFTER a payment plan
  /// has been confirmed (WALLET/CASH: right after `payParcelBooking`
  /// succeeds; PAYSTACK/FLUTTERWAVE: only after `_verifyOnlinePaymentSettled`
  /// server-confirms `parcelPaymentStatus == 'PAID'`). The backend
  /// independently enforces the same ordering (409 `dispatchEligible:false`),
  /// this is the client-side half of that guarantee.
  Future<bool> _dispatchDriverRequest() {
    return packageController.sendPackageDriverRequest(
      bookingId: widget.bookingId,
      discountCode: widget.discountCode,
      senderData: widget.senderData,
      receiverData: widget.receiverData,
    );
  }

  /// Starts dispatch once, confirms only the payment, then navigates to the
  /// authoritative searching screen. If dispatch fails post-payment (customer
  /// has already paid), surfaces a distinct retryable failure rather than a
  /// generic one, since re-tapping "Try Again" here must NOT re-charge.
  Future<void> _dispatchAndFinish({
    required String paymentMethodLabel,
    String? transactionId,
    bool showSheet = true,
    String? successToast,
  }) async {
    if (!_dispatchStarted) {
      packageController.parcelPaymentUiState.value = ParcelPaymentUiState.dispatching;
      final dispatched = await _dispatchDriverRequest();
      if (!mounted) return;
      if (!dispatched) {
        // Error already surfaced globally by the controller. Payment is
        // already settled/planned at this point — don't call it a payment
        // failure, and the next "Try Again" tap will skip straight back
        // here (payParcelBooking short-circuits as already-satisfied).
        packageController.parcelPaymentUiState.value = ParcelPaymentUiState.failed;
        packageController.parcelPaymentStatusMessage.value =
            'Payment confirmed, but we could not reach a courier yet. Tap Try Again.';
        return;
      }
      _dispatchStarted = true;
    }

    packageController.parcelPaymentUiState.value = ParcelPaymentUiState.success;
    if (showSheet) {
      await _showSuccessSheet(
        paymentMethod: paymentMethodLabel,
        transactionId: transactionId,
        headline: 'Payment confirmed',
        subheadline:
            'We are now searching for an available Bike courier. '
            'You will see the result on the next screen.',
      );
    } else {
      if (successToast != null && mounted) {
        AppToasts.showSuccess(context, successToast);
      }
      _goToTracking();
    }
  }

  Future<bool?> _showConfirmCashSheet() {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.resendBlue.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(Icons.payments_rounded, color: AppColors.resendBlue, size: 28),
                ),
                const SizedBox(height: 16),
                const Text('Confirm Cash Payment', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'You\'ll pay ₦${widget.amount.toStringAsFixed(0)} in cash to the courier at pickup. Continue?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700], height: 1.45),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: AppButtons.button(
                    onTap: () => Navigator.pop(sheetContext, true),
                    text: 'Confirm Cash Payment',
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: Text(
                      'Not yet',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _processCash() async {
    final confirmed = await _showConfirmCashSheet();
    if (!mounted) return;
    if (confirmed != true) {
      packageController.parcelPaymentUiState.value = ParcelPaymentUiState.methodSelected;
      return;
    }
    packageController.parcelPaymentUiState.value = ParcelPaymentUiState.confirmingCash;
    final data = await packageController.payParcelBooking(bookingId: widget.bookingId, paymentType: 'CASH');
    if (!mounted) return;
    if (data == null) {
      _fail(
        packageController.parcelPaymentError.value.isNotEmpty
            ? packageController.parcelPaymentError.value
            : 'Could not select cash payment',
      );
      return;
    }
    await _dispatchAndFinish(
      paymentMethodLabel: 'Cash on Delivery',
      showSheet: false,
      successToast: 'Cash on delivery selected — pay the courier at pickup',
    );
  }

  Future<void> _processWallet() async {
    packageController.parcelPaymentUiState.value = ParcelPaymentUiState.initializingOnlinePayment;
    final data = await packageController.payParcelBooking(bookingId: widget.bookingId, paymentType: 'WALLET');
    if (!mounted) return;
    if (data == null) {
      _fail(
        packageController.parcelPaymentError.value.isNotEmpty
            ? packageController.parcelPaymentError.value
            : 'Wallet payment failed',
      );
      return;
    }
    if (data['parcelPaymentStatus'] != 'PAID') {
      _fail('Wallet payment failed');
      return;
    }
    walletController.getWalletBalance();
    await _dispatchAndFinish(paymentMethodLabel: 'Hoppr Wallet');
  }

  Future<Map<String, String>?> _collectContactInfo({required bool needsNamePhone}) async {
    final prefs = await SharedPreferences.getInstance();
    String? email = prefs.getString('flutterwave_email');
    String? name = prefs.getString('flutterwave_name');
    String? phone = prefs.getString('flutterwave_phone');

    final missing =
        (email == null || email.trim().isEmpty) ||
        (needsNamePhone && ((name == null || name.trim().isEmpty) || (phone == null || phone.trim().isEmpty)));

    if (!missing) {
      return {'email': email, 'name': name ?? '', 'phone': phone ?? ''};
    }

    final result = await _showContactInfoSheet(email, name, phone, needsNamePhone);
    if (result != true) return null;

    email = prefs.getString('flutterwave_email');
    name = prefs.getString('flutterwave_name');
    phone = prefs.getString('flutterwave_phone');
    if (email == null || email.trim().isEmpty) return null;
    return {'email': email, 'name': name ?? '', 'phone': phone ?? ''};
  }

  Future<bool?> _showContactInfoSheet(String? email, String? name, String? phone, bool needsNamePhone) {
    final emailController = TextEditingController(text: email);
    final nameController = TextEditingController(text: name);
    final phoneController = TextEditingController(text: phone);

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(height: 15),
                const Text('Enter Payment Info', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 25),
                _contactField(emailController, 'Email', Icons.email, TextInputType.emailAddress),
                if (needsNamePhone) ...[
                  const SizedBox(height: 15),
                  _contactField(nameController, 'Name', Icons.person, TextInputType.name),
                  const SizedBox(height: 15),
                  _contactField(phoneController, 'Phone', Icons.phone, TextInputType.phone),
                ],
                const SizedBox(height: 25),
                AppButtons.button(
                  onTap: () async {
                    if (emailController.text.trim().isEmpty ||
                        (needsNamePhone &&
                            (nameController.text.trim().isEmpty || phoneController.text.trim().isEmpty))) {
                      AppToasts.showError(sheetContext, 'All fields are required');
                      return;
                    }
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('flutterwave_email', emailController.text.trim());
                    if (needsNamePhone) {
                      await prefs.setString('flutterwave_name', nameController.text.trim());
                      await prefs.setString('flutterwave_phone', phoneController.text.trim());
                    }
                    Navigator.pop(sheetContext, true);
                  },
                  text: 'Save & Continue',
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _contactField(TextEditingController controller, String label, IconData icon, TextInputType type) {
    return TextField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: AppColors.commonBlack),
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[700]),
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      ),
    );
  }

  /// Re-checks payment settlement server-side instead of trusting the
  /// WebView's client-side redirect alone — `payParcelBooking` is idempotent
  /// (it short-circuits to the settled status once the webhook has landed),
  /// so this is just a bounded poll of the same endpoint. The webhook is
  /// normally near-instant, but can lag the gateway's redirect by a beat.
  Future<bool> _verifyOnlinePaymentSettled(String paymentType) async {
    const maxAttempts = 4;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final data = await packageController.payParcelBooking(bookingId: widget.bookingId, paymentType: paymentType);
      if (data != null && data['parcelPaymentStatus'] == 'PAID') return true;
      if (attempt < maxAttempts - 1) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return false;
  }

  Future<void> _processOnlineGateway(String method) async {
    final needsNamePhone = method == 'FLUTTERWAVE';
    final contact = await _collectContactInfo(needsNamePhone: needsNamePhone);
    if (!mounted || contact == null) return;

    packageController.parcelPaymentUiState.value = ParcelPaymentUiState.initializingOnlinePayment;

    // Records intent server-side (dispatchEligible=true) — settlement still
    // happens later via the webhook, confirmed below in
    // _verifyOnlinePaymentSettled before we ever dispatch a courier.
    final intent = await packageController.payParcelBooking(bookingId: widget.bookingId, paymentType: method);
    if (!mounted) return;
    if (intent == null) {
      _fail(
        packageController.parcelPaymentError.value.isNotEmpty
            ? packageController.parcelPaymentError.value
            : 'Could not start payment',
      );
      return;
    }

    if (intent['parcelPaymentStatus'] == 'PAID') {
      // Idempotent re-entry (already settled from a previous attempt) — skip
      // straight to dispatch, no need to open the gateway checkout again.
      await _dispatchAndFinish(paymentMethodLabel: method == 'PAYSTACK' ? 'Paystack' : 'FlutterWave');
      return;
    }

    final Map<String, dynamic>? init;
    if (method == 'PAYSTACK') {
      init = await packageController.initParcelPaystackPayment(bookingId: widget.bookingId, email: contact['email']!);
    } else {
      init = await packageController.initParcelFlutterwavePayment(
        bookingId: widget.bookingId,
        amount: widget.amount,
        email: contact['email']!,
        name: contact['name'] ?? '',
        phone: contact['phone'] ?? '',
      );
    }
    if (!mounted) return;
    final checkoutUrl =
        method == 'PAYSTACK' ? (init?['authorization_url'] as String?) : (init?['paymentLink'] as String?);
    if (checkoutUrl == null || checkoutUrl.isEmpty) {
      _fail(
        packageController.parcelPaymentError.value.isNotEmpty
            ? packageController.parcelPaymentError.value
            : 'Failed to initialize payment',
      );
      return;
    }

    packageController.parcelPaymentUiState.value = ParcelPaymentUiState.awaitingPayment;
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentWebView(url: checkoutUrl)));
    if (!mounted) return;

    if (result == null || result['status'] != 'success') {
      _fail('Payment failed or cancelled');
      return;
    }

    packageController.parcelPaymentUiState.value = ParcelPaymentUiState.verifyingPayment;
    final settled = await _verifyOnlinePaymentSettled(method);
    if (!mounted) return;
    if (!settled) {
      _fail(
        'We received your payment but could not confirm it yet. Please '
        'check My Bookings shortly — you have not been charged twice.',
      );
      return;
    }

    await _dispatchAndFinish(
      paymentMethodLabel: method == 'PAYSTACK' ? 'Paystack' : 'FlutterWave',
      transactionId: result['transactionId']?.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final state = packageController.parcelPaymentUiState.value;
      final selected = packageController.selectedParcelPaymentMethod.value;
      final busy = _isBusy(state);
      final tilesEnabled = !busy;

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (busy) {
            AppToasts.showInfoGlobal('Please wait for the current step to finish', title: 'Please wait');
            return;
          }
          // Every entry point today pushes this screen with Get.to/Navigator.push
          // (pre-dispatch confirm flow, the home-screen resume path, and the
          // tracking screen's "Pay Online Instead" switch) — there is always a
          // live screen underneath to return to. Prefer a plain pop over
          // Get.offAll's full rebuild: for the "switch to online" entry point
          // specifically, force-rebuilding a brand-new PackageMapConfirmScreen
          // on back meant that screen briefly (or, if its own driver-restore
          // raced, persistently) re-showed "Finding a courier" even though a
          // courier was already assigned — going back to the SAME already-live
          // instance instead just can't regress into a stale UI. _goToTracking()
          // remains the fallback for the rare case nothing is left to pop to.
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
          _goToTracking();
        },
        child: Scaffold(
          body: SafeArea(
            child: Container(
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFFFFD), Color(0xFFF6F7FF)],
                ),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap:
                                busy
                                    ? null
                                    : () {
                                      Navigator.maybePop(context);
                                    },
                            child: Opacity(
                              opacity: busy ? 0.35 : 1,
                              child: Image.asset(AppImages.backImage, height: 20, width: 20),
                            ),
                          ),
                          CustomTextFields.textWithStyles700('Package Payment', fontSize: 20),
                          const Text(''),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CustomTextFields.textWithStylesSmall(
                        'Pay for your package delivery — your courier collects it once payment is confirmed.',
                        maxLines: 2,
                        fontSize: 12,
                      ),
                      const SizedBox(height: 24),

                      CustomTextFields.textWithStyles700('Online Payment', fontSize: 17),
                      const SizedBox(height: 15),
                      Opacity(
                        opacity: tilesEnabled ? 1 : 0.5,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(30),
                              onTap: tilesEnabled ? () => _selectMethod('PAYSTACK') : null,
                              child: Container(
                                height: 50,
                                width: 170,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.commonWhite,
                                  border: Border.all(
                                    color: selected == 'PAYSTACK' ? Colors.black : AppColors.containerColor,
                                    width: selected == 'PAYSTACK' ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Image.asset(AppImages.payStack),
                                    const SizedBox(width: 10),
                                    CustomTextFields.textWithStylesSmall(
                                      'paystack',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      colors: AppColors.commonBlack,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: tilesEnabled ? () => _selectMethod('FLUTTERWAVE') : null,
                              child: Container(
                                height: 50,
                                width: 170,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.commonWhite,
                                  border: Border.all(
                                    color: selected == 'FLUTTERWAVE' ? Colors.black : AppColors.containerColor,
                                    width: selected == 'FLUTTERWAVE' ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Image.asset(AppImages.flutter_wave, height: 24, width: 40),
                                      const SizedBox(width: 10),
                                      CustomTextFields.textWithStylesSmall(
                                        'Flutter wave',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        colors: AppColors.commonBlack,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),

                      CustomTextFields.textWithStyles700('Wallets', fontSize: 16),
                      const SizedBox(height: 15),
                      Opacity(
                        opacity: tilesEnabled ? 1 : 0.5,
                        child: Obx(() {
                          final balance = walletController.walletBalance.value?.customerWalletBalance.toString() ?? '0';
                          return PackageContainer.customWalletContainer(
                            borderColor: selected == 'WALLET' ? Colors.black : AppColors.containerColor,
                            onTap: tilesEnabled ? () => _selectMethod('WALLET') : () {},
                            title: 'Hoppr Wallet',
                            leadingImagePath: AppImages.wallet,
                            trailing: CustomTextFields.textWithImage(
                              fontWeight: FontWeight.w600,
                              text: balance,
                              colors: AppColors.walletCurrencyColor,
                              imagePath: AppImages.nBlackCurrency,
                              imageColors: AppColors.walletCurrencyColor,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 15),

                      Opacity(
                        opacity: tilesEnabled ? 1 : 0.5,
                        child: PackageContainer.customWalletContainer(
                          borderColor: selected == 'CASH' ? Colors.black : AppColors.containerColor,
                          onTap: tilesEnabled ? () => _selectMethod('CASH') : () {},
                          title: 'Cash Payment',
                          leadingImagePath: AppImages.cash,
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                            decoration: BoxDecoration(
                              color: AppColors.resendBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: CustomTextFields.textWithStyles600(
                              'Pay at pickup',
                              fontSize: 12,
                              color: AppColors.resendBlue,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      CustomTextFields.textWithStylesSmall(
                        'Cash is collected by the courier at pickup — the receiver at drop-off does not handle payment.',
                        maxLines: 2,
                        fontSize: 11,
                      ),
                      if (state == ParcelPaymentUiState.failed &&
                          packageController.parcelPaymentStatusMessage.value.isNotEmpty) ...[
                        const SizedBox(height: 15),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withOpacity(0.2)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  packageController.parcelPaymentStatusMessage.value,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.red,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CustomTextFields.textWithImage(
                        text: widget.amount.toStringAsFixed(0),
                        fontSize: 25,
                        colors: AppColors.commonBlack,
                        fontWeight: FontWeight.w700,
                        imageSize: 23,
                        imagePath: AppImages.nBlackCurrency,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: AppButtons.button(
                      isLoading: busy,
                      onTap: (!busy && selected != null) ? _onBottomActionTap : null,
                      text: _bottomActionLabel(state, selected),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
