import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/Drawer/controller/profle_cotroller.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/pay_pall_screen.dart';
import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
import 'package:hopper/Presentation/wallet/controller/wallet_controller.dart';
import 'package:hopper/webview_page.dart';

import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_logger.dart';

import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';

import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:hopper/api/dataSource/apiDataSource.dart';
import 'package:hopper/Presentation/OnBoarding/models/ride_receipt_response.dart';
import 'package:hopper/Presentation/OnBoarding/models/saved_card.dart';

class PaymentScreen extends StatefulWidget {
  final String? bookingId;
  final double? amount;
  final AddressModel? sender;
  final AddressModel? receiver;
  final String? driverName;
  final String? driverProfilePic;
  const PaymentScreen({
    super.key,
    this.bookingId,
    this.amount,
    this.sender,
    this.receiver,
    this.driverName,
    this.driverProfilePic,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  static const String _customerCompletedCashBookingKey =
      'customer_completed_cash_booking_id';
  int selectedIndex = 3;

  final DriverSearchController driverSearchController =
      Get.isRegistered<DriverSearchController>()
          ? Get.find<DriverSearchController>()
          : Get.put(DriverSearchController());
  final PackageController packageController = Get.put(PackageController());
  final WalletController walletController = Get.put(WalletController());


  final ProfleCotroller controller = Get.put(ProfleCotroller());
  bool _isRatingSheetOpen = false;

  bool _isLoading = false;
  bool payPalLoading = false;
  bool flutterWaveLoading = false;
  bool payStackLoading = false;

  // ── Paystack saved cards (one-tap "pay with card") ──────────────────────
  // Card numbers are entered on Paystack's hosted page only — never sent to
  // our API. We keep only the safe display fields returned by the backend.
  List<SavedCard> _savedCards = [];
  bool _cardsLoading = false;
  bool _addingCard = false;
  String? _busyCardId; // id of the card currently being charged / deleted

  Future<void> _markCustomerCashPaymentCompleted() async {
    final bookingId = (widget.bookingId ?? '').trim();
    if (bookingId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customerCompletedCashBookingKey, bookingId);
  }

  void _goToHomeAfterPayment() {
    if (!mounted) return;
    Get.offAll(() => const CommonBottomNavigation(initialIndex: 0));
  }

  String _receiptSummary(String paymentMethod, {String? transactionId}) {
    final booking = (widget.bookingId ?? '').trim();
    final amount =
        (widget.amount != null) ? widget.amount!.toStringAsFixed(2) : '';
    final driverName = (widget.driverName ?? '').trim();
    final tx = (transactionId ?? '').trim();

    final now = DateTime.now();
    final two = (int v) => v.toString().padLeft(2, '0');
    final dateStr =
        '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';

    final b = StringBuffer();
    b.writeln('Hoppr Receipt');
    b.writeln('Date: $dateStr');
    b.writeln('Booking ID: ${booking.isEmpty ? '-' : booking}');
    b.writeln('Amount: ${amount.isEmpty ? '-' : amount}');
    b.writeln('Payment: $paymentMethod');
    if (tx.isNotEmpty) b.writeln('Transaction: $tx');
    if (driverName.isNotEmpty) b.writeln('Driver: $driverName');
    return b.toString().trim();
  }

  String _redactPaymentUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }

  Future<File> _writeReceiptFile(String summary) async {
    final safeBooking =
        (widget.bookingId ?? 'ride').replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}hoppr_receipt_${safeBooking}_$ts.txt',
    );
    await file.writeAsString(summary);
    return file;
  }

  Future<void> _exportReceipt(String summary) async {
    try {
      final file = await _writeReceiptFile(summary);
      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        subject: 'Hoppr receipt',
        text: 'Hoppr receipt',
      );
    } catch (_) {
      if (!mounted) return;
      AppToasts.showError(context, 'Failed to export receipt');
    }
  }

  Future<void> _showPaymentSuccessSheet({required String paymentMethod, String? transactionId}) async {
    // Local summary is only a FALLBACK (used if the backend receipt can't be
    // fetched) — the card + buttons prefer the backend receipt's exact numbers.
    final summary = _receiptSummary(paymentMethod, transactionId: transactionId);
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _PaymentSuccessSheet(
          bookingId: (widget.bookingId ?? '').trim(),
          paymentMethod: paymentMethod,
          fallbackSummary: summary,
          onContinue: () => Navigator.pop(sheetContext),
          onFallbackDownload: () => _exportReceipt(summary),
        );
      },
    );
  }

  Future<void> _completePaymentFlow({required String paymentMethod, String? transactionId}) async {
    if (!mounted) return;
    await _showPaymentSuccessSheet(paymentMethod: paymentMethod, transactionId: transactionId);
    if (!mounted) return;
    await _showRatingBottomSheet(context);
  }

  Future<void> _showRatingBottomSheet(BuildContext pageContext) async {
    if (_isRatingSheetOpen) return;
    _isRatingSheetOpen = true;
    int selectedRating = 0;
    bool isSubmittingRating = false;

    await showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final user = controller.user.value;
            final fallbackName = user?.firstName.trim() ?? '';
            final riderName = (widget.driverName?.trim().isNotEmpty == true ? widget.driverName!.trim() : fallbackName.isNotEmpty ? fallbackName : 'Driver');
            final profilePic = (widget.driverProfilePic?.trim().isNotEmpty == true ? widget.driverProfilePic!.trim() : user?.profileImage ?? '');

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD0D5DD),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 22),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: CachedNetworkImage(
                          imageUrl: profilePic,
                          height: 72,
                          width: 72,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            height: 72,
                            width: 72,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF2F4F7),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            height: 72,
                            width: 72,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF2F4F7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Color(0xFF98A2B3),
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Trip Completed',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF101828),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Rate your experience with $riderName',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(5, (index) {
                          final active = index < selectedRating;
                          return GestureDetector(
                            onTap: () => setModalState(() => selectedRating = index + 1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: 54,
                              width: 54,
                              decoration: BoxDecoration(
                                color: active ? const Color(0xFFFFF4E5) : const Color(0xFFF5F6F8),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: active ? const Color(0xFFF59E0B) : const Color(0xFFE4E7EC),
                                ),
                              ),
                              child: Icon(
                                active ? Icons.star_rounded : Icons.star_border_rounded,
                                color: active ? const Color(0xFFF59E0B) : const Color(0xFF98A2B3),
                                size: 30,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: AppButtons.button(
                              borderColor: const Color(0xFFD0D5DD),
                              hasBorder: true,
                              buttonColor: Colors.white,
                              textColor: AppColors.commonBlack,
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _goToHomeAfterPayment();
                              },
                              text: 'Skip',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppButtons.button(
                              buttonColor: AppColors.commonBlack,
                              isLoading: isSubmittingRating || driverSearchController.isLoading.value,
                              onTap: (isSubmittingRating || driverSearchController.isLoading.value)
                                  ? null
                                  : () async {
                                      if (selectedRating <= 0) {
                                        AppToasts.showError(
                                          sheetContext,
                                          'Please select a rating',
                                        );
                                        return;
                                      }

                                      final bookingId = widget.bookingId ?? "";
                                      setModalState(() => isSubmittingRating = true);
                                      final result = await driverSearchController.rateDriver(
                                        bookingId: bookingId,
                                        rating: selectedRating.toString(),
                                        context: sheetContext,
                                      );
                                      if (!mounted) return;
                                      setModalState(() => isSubmittingRating = false);

                                      if (result == '') {
                                        if (Navigator.of(sheetContext).canPop()) {
                                          Navigator.pop(sheetContext);
                                        }
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          _goToHomeAfterPayment();
                                        });
                                      }
                                    },
                              text: 'Submit Rating',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    _isRatingSheetOpen = false;
  }

  Map<String, dynamic>? paymentIntentData;

  /*Future<void> makePayment() async {
    try {
      paymentIntentData = await createPaymentIntent('1000') ?? {};

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntentData!['clientSecret'],
          style: ThemeMode.light,
          customFlow: false,

          merchantDisplayName: 'Hoppr',
        ),
      );

      displayPaymentSheet();
    } catch (e) {
      AppLogger.log.i('Exception: $e');
    }
  }*/
  Future<void> payPall() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => PaypalWebviewPage(
              amount: widget.amount?.toString() ?? '',
              bookingId: widget.bookingId ?? '',
            ),
      ),
    );

    if (!mounted) return;
    if (result == true) {
      AppToasts.showSuccess(context,'Payment Successful');
      await _completePaymentFlow(paymentMethod: 'PayPal');
    } else if (result == false) {
      AppToasts.showError(context,'Payment failed or cancelled');
    }
  }

  Future<void> makePayment() async {
    try {
      final result = await createPaymentIntent('1500000');

      if (result == null || !result.containsKey('clientSecret')) {
        AppLogger.log.e("❌ Payment Intent is null or missing 'clientSecret'");
        return;
      }

      paymentIntentData = result;

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntentData!['clientSecret'],
          style: ThemeMode.light,
          customFlow: false,
          merchantDisplayName: 'Hoppr',
        ),
      );

      displayPaymentSheet();
    } catch (e) {
      AppLogger.log.e('💡 Exception in makePayment: $e');
    }
  }

  displayPaymentSheet() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');

    if (token == null) {
      AppLogger.log.i('⚠️ Token not found in shared preferences');
      return;
    }

    try {
      final String bookingId = widget.bookingId ?? '';
      await Stripe.instance.presentPaymentSheet();

      String? clientSecret = paymentIntentData?['clientSecret'];
      String? transactionId;

      if (clientSecret != null && clientSecret.contains('_secret')) {
        transactionId = clientSecret.split('_secret').first;
      }

      if (transactionId != null) {
        final response = await http.post(
          Uri.parse(
            'https://bk.myhoppr.com/api/customer/confirm-stripe-payment-response',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            "userBookingId": bookingId,
            "paymentIntentId": transactionId,
          }),
        );

        AppLogger.log.i('Confirm Payment Response: ${response.body}');
        if (response.statusCode == 200) {
          if (mounted) {
            await _completePaymentFlow(paymentMethod: 'Stripe', transactionId: transactionId);
          }
          AppLogger.log.i('✅ Payment response confirmed successfully');
        } else {
          AppLogger.log.i('❌ Failed to confirm payment response');
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Payment successful\nTransaction ID: $transactionId"),
        ),
      );

      AppLogger.log.i('✅ Payment successful. Transaction ID: $transactionId');
    } catch (e) {
      AppLogger.log.i('❌ Error during payment sheet presentation: $e');
    }
  }

  Future<Map<String, dynamic>?> createPaymentIntent(String amount) async {
    try {
      final String bookingId = widget.bookingId ?? '';
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');

      final response = await http.post(
        Uri.parse(
          'https://bk.myhoppr.com/api/customer/confirm-stripe-payment-intents',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'userBookingId': bookingId, 'amount': amount}),
      );

      AppLogger.log.i('Status code: ${response.statusCode}');
      AppLogger.log.i('Response body: ${response.body}');

      final decoded = jsonDecode(response.body);

      // 👇 Detect server-side validation error
      if (decoded is Map && decoded.containsKey('error')) {
        final errorMsg = decoded['error'] ?? 'Unknown error occurred';
        if (context.mounted) {
          AppToasts.showError(context,errorMsg.toString());
          // ScaffoldMessenger.of(context).showSnackBar(
          //   SnackBar(content: Text(errorMsg.toString())),
          // );
        }
        AppLogger.log.e('❌ Stripe payment error: $errorMsg');
        return null;
      }

      // 👇 Handle non-200 status codes
      if (response.statusCode != 200) {
        throw Exception('Failed to create payment intent');
      }

      AppLogger.log.i('✅ Decoded payment intent response: $decoded');
      return decoded;
    } catch (err) {
      AppLogger.log.e('❌ Error creating payment intent: $err');
      if (context.mounted) {
        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(content: Text('Error creating payment intent: $err')),
        // );
        AppToasts.showError(context,'$err');
      }
      return null;
    }
  }



  Future<void> payWithFlutterWave() async {
    final prefs = await SharedPreferences.getInstance();

    String? email = prefs.getString('flutterwave_email');
    String? name = prefs.getString('flutterwave_name');
    String? phone = prefs.getString('flutterwave_phone');

    if (email == null ||
        email.isNotEmpty ||
        name == null ||
        name.isEmpty ||
        phone == null ||
        phone.isEmpty) {
      final result = await _showUserInfoBottomSheet(
        context,
        email,
        name,
        phone,
      );

      if (result != true) return;

      email = prefs.getString('flutterwave_email');
      name = prefs.getString('flutterwave_name');
      phone = prefs.getString('flutterwave_phone');
    }

    setState(() => flutterWaveLoading = true);

    try {
      String? token = prefs.getString('token');
      final response = await http.post(
        Uri.parse(
          'https://bk.myhoppr.com/api/flutterwave/initialize',
        ),
        headers: {
          "Content-Type": "application/json",
          if (token != null)
            "Authorization": "Bearer $token", // ✅ Add Bearer token
        },
        body: jsonEncode({
          "userBookingId": widget.bookingId ?? '',
          "amount": widget.amount.toString(),
          "email": email,
          "name": name,
          "phone": phone,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final paymentLink = data['paymentLink'];

        if (paymentLink != null) {
          final startedAt = DateTime.now();
          if (kDebugMode) {
            AppLogger.log.i(
              '[PAY_FLOW] flutterwave openWeb url=${_redactPaymentUrl(paymentLink.toString())} bookingId=${widget.bookingId} amount=${widget.amount}',
            );
          }
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PaymentWebView(url: paymentLink)),
          );
          if (kDebugMode) {
            AppLogger.log.i(
              '[PAY_FLOW] flutterwave webResult elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds} result=$result',
            );
          }

          if (result != null && result["status"] == "success") {
            AppToasts.showSuccess(context,'Payment Successful');
            AppLogger.log.i("Payment Successful: ${result["transactionId"]}");
            await _completePaymentFlow(paymentMethod: 'FlutterWave', transactionId: result['transactionId']?.toString());
          } else {
            final code = (result is Map) ? result['errorCode'] : null;
            if (code == -2) {
              // -2 on Android WebView is typically host lookup / address unreachable.
              AppToasts.showError(
                context,
                "Network/DNS issue while opening payment page. Please check internet or try a different network and retry.",
              );
            } else {
              AppToasts.showError(context,"Payment failed or cancelled");
            }
          }
        } else {
          final errorMsg = data['message'] ?? "Failed to initialize payment";
          AppToasts.showError(context,errorMsg);
        }
      } else {
        final errorMsg = data['message'] ?? "Failed to initialize payment";
        AppToasts.showError(context,errorMsg);
        AppLogger.log.e(
          'Failed to initialize Flutterwave payment: ${response.body}',
        );
      }
    } catch (e) {
      AppToasts.showError(context,e.toString());
      AppLogger.log.e("Error during Flutterwave payment: $e");
    } finally {
      setState(() => flutterWaveLoading = false);
    }
  }

  Future<bool?> _showUserInfoBottomSheet(
    BuildContext context,
    String? email,
    String? name,
    String? phone,
  ) {
    final _emailController = TextEditingController(text: email);
    final _nameController = TextEditingController(text: name);
    final _phoneController = TextEditingController(text: phone);

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // Transparent to get rounded corners
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                SizedBox(height: 15),
                Text(
                  "Enter Payment Info",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 25),
                _buildTextField(
                  _emailController,
                  "Email",
                  Icons.email,
                  TextInputType.emailAddress,
                ),
                SizedBox(height: 15),
                _buildTextField(
                  _nameController,
                  "Name",
                  Icons.person,
                  TextInputType.name,
                ),
                SizedBox(height: 15),
                _buildTextField(
                  _phoneController,
                  "Phone",
                  Icons.phone,
                  TextInputType.phone,
                ),
                SizedBox(height: 25),
                AppButtons.button(
                  onTap: () async {
                    if (_emailController.text.isEmpty ||
                        _nameController.text.isEmpty ||
                        _phoneController.text.isEmpty) {
                      AppToasts.showError(context,"All fields are required");
                      return;
                    }

                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(
                      'flutterwave_email',
                      _emailController.text,
                    );
                    await prefs.setString(
                      'flutterwave_name',
                      _nameController.text,
                    );
                    await prefs.setString(
                      'flutterwave_phone',
                      _phoneController.text,
                    );

                    Navigator.pop(context, true);
                  },
                  text: 'Save & Continue',
                ),

                SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon,
    TextInputType type,
  ) {
    return TextField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: AppColors.commonBlack),
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[700]),
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      ),
    );
  }

  Future<void> payWithPayStack() async {
    final prefs = await SharedPreferences.getInstance();

    String? email = prefs.getString('flutterwave_email');
    String? name = prefs.getString('flutterwave_name');
    String? phone = prefs.getString('flutterwave_phone');

    if (email == null ||
        email.isNotEmpty ||
        name == null ||
        name.isEmpty ||
        phone == null ||
        phone.isEmpty) {
      final result = await _showUserInfoBottomSheet(
        context,
        email,
        name,
        phone,
      );

      if (result != true) return;

      email = prefs.getString('flutterwave_email');
      name = prefs.getString('flutterwave_name');
      phone = prefs.getString('flutterwave_phone');
    }

    setState(() => payStackLoading = true);

    try {
      String? token = prefs.getString('token');
      final response = await http.post(
        Uri.parse(
          'https://bk.myhoppr.com/api/paystack/init',
        ),
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "userBookingId": widget.bookingId ?? '',
          "email": email,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final paymentLink = data['authorization_url'];

        if (paymentLink != null) {
          final startedAt = DateTime.now();
          if (kDebugMode) {
            AppLogger.log.i(
              '[PAY_FLOW] paystack openWeb url=${_redactPaymentUrl(paymentLink.toString())} bookingId=${widget.bookingId} amount=${widget.amount}',
            );
          }
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PaymentWebView(url: paymentLink)),
          );
          if (kDebugMode) {
            AppLogger.log.i(
              '[PAY_FLOW] paystack webResult elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds} result=$result',
            );
          }

          if (result != null && result["status"] == "success") {
            AppToasts.showSuccess(context,'Payment Successful');
            AppLogger.log.i("Payment Successful: ${result["transactionId"]}");
            await _completePaymentFlow(paymentMethod: 'Paystack', transactionId: result['transactionId']?.toString());
          } else {
            final code = (result is Map) ? result['errorCode'] : null;
            if (code == -2) {
              AppToasts.showError(
                context,
                "Network/DNS issue while opening payment page. Please check internet or try a different network and retry.",
              );
            } else {
              AppToasts.showError(context,"Payment failed or cancelled");
            }
          }
        } else {
          final errorMsg = data['message'] ?? "Failed to initialize payment";
          AppToasts.showError(context,errorMsg);
        }
      } else {
        final errorMsg = data['message'] ?? "Failed to initialize payment";
        AppToasts.showError(context,errorMsg);
        AppLogger.log.e(
          'Failed to initialize Flutterwave payment: ${response.body}',
        );
      }
    } catch (e) {
      AppToasts.showError(context,e.toString());
      AppLogger.log.e("Error during Flutterwave payment: $e");
    } finally {
      setState(() => payStackLoading = false);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // Paystack saved cards. The card number is collected on Paystack's hosted
  // page only and never reaches our API. These calls mirror the existing
  // raw-http payment flows (payWithPayStack) to stay consistent and avoid
  // touching shared API infrastructure.
  // ════════════════════════════════════════════════════════════════════════
  static const String _cardsApiBase =
      'https://bk.myhoppr.com/api/customer/cards';

  Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/customer/cards -> data:[{ id, last4, cardType, bank, label }]
  Future<void> _loadSavedCards() async {
    if (!mounted) return;
    setState(() => _cardsLoading = true);
    try {
      final res = await http.get(
        Uri.parse(_cardsApiBase),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body is Map) ? body['data'] : null;
        final cards = <SavedCard>[];
        if (list is List) {
          for (final e in list) {
            if (e is Map<String, dynamic>) {
              final c = SavedCard.fromJson(e);
              if (c.isValid) cards.add(c);
            }
          }
        }
        if (mounted) setState(() => _savedCards = cards);
      }
    } catch (e) {
      AppLogger.log.e('Load saved cards failed: $e');
    } finally {
      if (mounted) setState(() => _cardsLoading = false);
    }
  }

  /// POST /api/customer/cards/init -> open Paystack page -> refresh on return.
  /// The verify charge (₦50) is credited back to the customer's wallet.
  Future<void> _addNewCard() async {
    if (_addingCard) return;
    setState(() => _addingCard = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('flutterwave_email');
      final res = await http.post(
        Uri.parse('$_cardsApiBase/init'),
        headers: await _authHeaders(),
        body: jsonEncode({
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        }),
      );
      final data = jsonDecode(res.body);
      final authUrl =
          (data is Map) ? data['authorization_url']?.toString() : null;
      if ((res.statusCode == 200 || res.statusCode == 201) &&
          authUrl != null &&
          authUrl.isNotEmpty) {
        final int before = _savedCards.length;
        if (!mounted) return;
        // Paystack collects the card and charges the small verify amount; on
        // return we always refresh (Paystack may not emit a standard signal).
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PaymentWebView(url: authUrl)),
        );
        await _loadSavedCards();
        walletController.getWalletBalance();
        if (!mounted) return;
        if (_savedCards.length > before) {
          AppToasts.showSuccess(
            context,
            'Card added · ₦50 was added to your wallet',
          );
        }
      } else {
        final msg = (data is Map ? data['message'] : null)?.toString() ??
            'Could not start card setup';
        if (mounted) AppToasts.showError(context, msg);
      }
    } catch (e) {
      AppLogger.log.e('Card init failed: $e');
      if (mounted) {
        AppToasts.showError(
          context,
          'Could not start card setup. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _addingCard = false);
    }
  }

  /// POST /api/customer/cards/charge -> { success, bookingStatus:"PAID" }.
  /// One tap, no card re-entry. On success shows the Payment Successful sheet.
  Future<void> _payWithSavedCard(SavedCard card) async {
    if (_busyCardId != null) return;
    final bookingId = (widget.bookingId ?? '').trim();
    if (bookingId.isEmpty) {
      AppToasts.showError(context, 'Missing booking reference');
      return;
    }
    setState(() => _busyCardId = card.id);
    bool success = false;
    try {
      final res = await http.post(
        Uri.parse('$_cardsApiBase/charge'),
        headers: await _authHeaders(),
        body: jsonEncode({'userBookingId': bookingId, 'cardId': card.id}),
      );
      final data = jsonDecode(res.body);
      final paid = (data is Map) &&
          (data['success'] == true ||
              data['bookingStatus']?.toString().toUpperCase() == 'PAID');
      if ((res.statusCode == 200 || res.statusCode == 201) && paid) {
        success = true;
      } else {
        final msg = (data is Map ? data['message'] : null)?.toString() ??
            'Card payment failed';
        if (mounted) AppToasts.showError(context, msg);
      }
    } catch (e) {
      AppLogger.log.e('Card charge failed: $e');
      if (mounted) {
        AppToasts.showError(context, 'Card payment failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busyCardId = null);
    }
    if (success && mounted) {
      await _completePaymentFlow(paymentMethod: 'Card');
    }
  }

  /// DELETE /api/customer/cards/{cardId}
  Future<void> _deleteSavedCard(SavedCard card) async {
    if (_busyCardId != null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove card'),
        content: Text('Remove ${card.display} from your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busyCardId = card.id);
    try {
      final res = await http.delete(
        Uri.parse('$_cardsApiBase/${Uri.encodeComponent(card.id)}'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 200 || res.statusCode == 204) {
        if (mounted) {
          setState(() => _savedCards.removeWhere((c) => c.id == card.id));
          AppToasts.showSuccess(context, 'Card removed');
        }
      } else {
        String msg = 'Could not remove card';
        try {
          final d = jsonDecode(res.body);
          if (d is Map && d['message'] != null) msg = d['message'].toString();
        } catch (_) {}
        if (mounted) AppToasts.showError(context, msg);
      }
    } catch (e) {
      AppLogger.log.e('Card delete failed: $e');
      if (mounted) {
        AppToasts.showError(context, 'Could not remove card. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busyCardId = null);
    }
  }

  Widget _buildSavedCardRow(SavedCard card) {
    final bool busy = _busyCardId == card.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.containerColor, width: 1),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Row(
          children: [
            const Icon(Icons.credit_card, size: 24, color: Colors.black87),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.display,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  if (card.bank.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        card.bank,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF667085),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              GestureDetector(
                onTap: () => _payWithSavedCard(card),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.commonBlack,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Pay',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _deleteSavedCard(card),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child:
                      Icon(Icons.delete_outline, size: 22, color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUnderDevelopmentDialog(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image.asset(
            //   AppImages.developing,
            //   width: 80,
            //   height: 80,
            //   fit: BoxFit.contain,
            // ),
            // const SizedBox(height: 16),
            Text(
              'Feature in Development',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.commonBlack,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This feature is currently under development.\nStay tuned for updates!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.greyDark,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            AppButtons.button(
              onTap: () {
                Navigator.pop(context);
              },
              text: 'OK',
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    walletController.getWalletBalance();
    controller.getProfileData();
    _loadSavedCards();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 25,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                        },
                        child: Image.asset(
                          AppImages.backImage,
                          height: 20,
                          width: 20,
                        ),
                      ),
                      CustomTextFields.textWithStyles700(
                        'Payment Method',
                        fontSize: 20,
                      ),
                      Text(''),
                      // Image.asset(AppImages.history, height: 20, width: 20),
                    ],
                  ),

                  const SizedBox(height: 30),

                  CustomTextFields.textWithStyles700(
                    'Online Payment',
                    fontSize: 17,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // InkWell(
                      //   onTap:
                      //       payPalLoading
                      //           ? null
                      //           : () async {
                      //             setState(() {
                      //               payPalLoading = true;
                      //               selectedIndex = 0;
                      //             });

                      //             await payPall();

                      //             setState(() {
                      //               payPalLoading = false;
                      //             });
                      //           },
                      //   child: Container(
                      //     height: 50,
                      //     width: 170,
                      //     padding: EdgeInsets.all(10),
                      //     decoration: BoxDecoration(
                      //       color: AppColors.commonWhite,
                      //       border: Border.all(
                      //         color:
                      //             selectedIndex == 0
                      //                 ? Colors.black
                      //                 : AppColors.containerColor,
                      //       ),
                      //       borderRadius: BorderRadius.circular(10),
                      //     ),
                      //     child:
                      //         payPalLoading
                      //             ? Center(child: AppLoader.circularLoader())
                      //             : Row(
                      //               children: [
                      //                 Image.asset(
                      //                   AppImages.payPall,
                      //                   height: 24,
                      //                   width: 24,
                      //                 ),
                      //                 SizedBox(width: 10),

                      //                 CustomTextFields.textWithStylesSmall(
                      //                   'PayPal',
                      //                   fontWeight: FontWeight.w500,
                      //                   fontSize: 16,
                      //                   colors: AppColors.commonBlack,
                      //                 ),
                      //               ],
                      //             ),
                      //   ),
                      // ),
 InkWell(
                        borderRadius: BorderRadius.circular(30),
                        onTap:
                            payStackLoading
                                ? null
                                : () async {
                                  setState(() {
                                    payStackLoading = true;
                                    selectedIndex = 4;
                                  });
                                  await payWithPayStack();
                                  setState(() {
                                    payStackLoading = false;
                                  });
                                },
                        child: Container(
                          height: 50,
                          width: 170,
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.commonWhite,
                            border: Border.all(
                              color:
                                  selectedIndex == 4
                                      ? Colors.black
                                      : AppColors.containerColor,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child:
                              payStackLoading
                                  ? Center(child: AppLoader.circularLoader())
                                  : Row(
                                    children: [
                                      Image.asset(AppImages.payStack),
                                      SizedBox(width: 10),
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
                        onTap:
                            flutterWaveLoading
                                ? null
                                : () async {
                                  setState(() {
                                    flutterWaveLoading = true;
                                  });

                                  await payWithFlutterWave();

                                  setState(() {
                                    flutterWaveLoading = false;
                                  });
                                },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 50,
                          width: 170,
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.commonWhite,
                            border: Border.all(color: AppColors.containerColor),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child:
                                flutterWaveLoading
                                    ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color:
                                            Colors
                                                .black, // you can change to AppColors.commonBlack
                                      ),
                                    )
                                    : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Image.asset(
                                          AppImages.flutter_wave,
                                          height: 24,
                                          width: 40,
                                        ),
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
                  SizedBox(height: 15),
                  // Row(
                  //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  //   children: [
                  //     // InkWell(
                  //     //   borderRadius: BorderRadius.circular(30),
                  //     //   onTap:
                  //     //       _isLoading
                  //     //           ? null
                  //     //           : () async {
                  //     //             setState(() {
                  //     //               _isLoading = true;
                  //     //               selectedIndex = 2;
                  //     //             });

                  //     //             await makePayment();

                  //     //             setState(() {
                  //     //               _isLoading = false;
                  //     //             });
                  //     //           },
                  //     //   child: Container(
                  //     //     height: 50,
                  //     //     width: 170,
                  //     //     padding: EdgeInsets.all(10),
                  //     //     decoration: BoxDecoration(
                  //     //       color: AppColors.commonWhite,
                  //     //       border: Border.all(
                  //     //         color:
                  //     //             selectedIndex == 2
                  //     //                 ? Colors.black
                  //     //                 : AppColors.containerColor,
                  //     //       ),
                  //     //       borderRadius: BorderRadius.circular(10),
                  //     //     ),
                  //     //     child:
                  //     //         _isLoading
                  //     //             ? Center(child: AppLoader.circularLoader())
                  //     //             : Row(
                  //     //               children: [
                  //     //                 Image.asset(AppImages.stripe),
                  //     //                 SizedBox(width: 10),
                  //     //                 CustomTextFields.textWithStylesSmall(
                  //     //                   'Stripe',
                  //     //                   fontSize: 16,
                  //     //                   fontWeight: FontWeight.w500,
                  //     //                   colors: AppColors.commonBlack,
                  //     //                 ),
                  //     //               ],
                  //     //             ),
                  //     //   ),
                  //     // ),
                   
                  //     InkWell(
                  //       borderRadius: BorderRadius.circular(30),
                  //       onTap:
                  //           payStackLoading
                  //               ? null
                  //               : () async {
                  //                 setState(() {
                  //                   payStackLoading = true;
                  //                   selectedIndex = 4;
                  //                 });
                  //                 await payWithPayStack();
                  //                 setState(() {
                  //                   payStackLoading = false;
                  //                 });
                  //               },
                  //       child: Container(
                  //         height: 50,
                  //         width: 170,
                  //         padding: EdgeInsets.all(10),
                  //         decoration: BoxDecoration(
                  //           color: AppColors.commonWhite,
                  //           border: Border.all(
                  //             color:
                  //                 selectedIndex == 4
                  //                     ? Colors.black
                  //                     : AppColors.containerColor,
                  //           ),
                  //           borderRadius: BorderRadius.circular(10),
                  //         ),
                  //         child:
                  //             payStackLoading
                  //                 ? Center(child: AppLoader.circularLoader())
                  //                 : Row(
                  //                   children: [
                  //                     Image.asset(AppImages.payStack),
                  //                     SizedBox(width: 10),
                  //                     CustomTextFields.textWithStylesSmall(
                  //                       'paystack',
                  //                       fontSize: 16,
                  //                       fontWeight: FontWeight.w500,
                  //                       colors: AppColors.commonBlack,
                  //                     ),
                  //                   ],
                  //                 ),
                  //       ),
                  //     ),
                  //   ],
                  // ),

                  // SizedBox(height: 15),

                  CustomTextFields.textWithStyles700('Card', fontSize: 16),
                  const SizedBox(height: 15),
                  if (_cardsLoading && _savedCards.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: AppLoader.circularLoader()),
                    ),
                  ..._savedCards.map(_buildSavedCardRow),
                  PackageContainer.customWalletContainer(
                    onTap: _addNewCard,
                    title: _addingCard
                        ? 'Opening secure card setup…'
                        : 'Add a new card',
                    textColor: AppColors.resendBlue,
                    fontWeight: FontWeight.w400,
                    leadingImagePath: AppImages.borderAdd,
                    trailing: _addingCard
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Image.asset(
                            AppImages.rightArrow,
                            color: AppColors.commonBlack,
                            width: 16,
                            height: 16,
                          ),
                  ),
                  SizedBox(height: 15),

                  CustomTextFields.textWithStyles700('Wallets', fontSize: 16),
                  SizedBox(height: 15),
                  Obx(() {
                    final balance =
                        walletController
                            .walletBalance
                            .value?.customerWalletBalance
                            .toString() ??
                        "0";


                    return PackageContainer.customWalletContainer(
                      borderColor:
                          selectedIndex == 1
                              ? Colors.black
                              : AppColors.containerColor,
                      onTap: () {
                        setState(() {
                          selectedIndex = 1;
                        });
                      },
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

                  SizedBox(height: 15),
                  PackageContainer.customWalletContainer(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder:
                            (context) => _buildUnderDevelopmentDialog(context),
                      );
                    },
                    title: 'Crypto',
                    leadingImagePath: AppImages.wallet,
                    trailing: Image.asset(
                      AppImages.rightArrow,
                      width: 16,
                      height: 16,
                    ),
                  ),
                  SizedBox(height: 15),
                  PackageContainer.customWalletContainer(
                    borderColor:
                        selectedIndex == 3
                            ? Colors.black
                            : AppColors.containerColor,
                    onTap: () {
                      setState(() {
                        selectedIndex = 3;
                      });
                    },
                    title: 'Cash Payment',
                    leadingImagePath: AppImages.cash,
                    trailing: Container(
                      padding: EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                      decoration: BoxDecoration(
                        color: AppColors.resendBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: CustomTextFields.textWithStyles600(
                        'Pay on delivery',
                        fontSize: 12,
                        color: AppColors.resendBlue,
                      ),
                    ),
                  ),
                  SizedBox(height: 15),
                  CustomTextFields.textWithStylesSmall(
                    'Update your location on the hoppr home page to select address from a different city',
                    maxLines: 2,fontSize: 11

                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      bottomNavigationBar: SafeArea(
        child: SizedBox(
          height: 120,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomTextFields.textWithImage(
                      text: widget.amount?.toString() ?? '280',
                      fontSize: 25,
                      colors: AppColors.commonBlack,
                      fontWeight: FontWeight.w700,
                      imageSize: 23,
                      imagePath: AppImages.nBlackCurrency,
                    ),
                    // const SizedBox(height: 4),
                    // Row(
                    //   children: [
                    //     GestureDetector(
                    //       onTap: () {},
                    //       child: CustomTextFields.textWithStylesSmall(
                    //         'View Details',
                    //       ),
                    //     ),
                    //     Icon(Icons.keyboard_arrow_down_outlined, size: 20),
                    //   ],
                    // ),
                  ],
                ),
                const SizedBox(width: 40),

                /*Expanded(
                  child: Obx(() {
                    return AppButtons.button(
                      onTap: () async {
                        if (selectedIndex == 1 || selectedIndex == 3) {
                          _showRatingBottomSheet(context);
                          print('Cash On Delivery or Hoppr Wallet selected');
                          final paymentType =
                              selectedIndex == 1 ? 'WALLET' : 'COD';

                          final result = await packageController.paymentDetails(
                            bookingId: widget.bookingId ?? '',
                            paymentType: paymentType,
                            context: context,
                          );

                          if (result == '') {
                            _showRatingBottomSheet(context);

                            // After rating, navigate home
                          } else {
                            // API failure
                            // ScaffoldMessenger.of(
                            //   context,
                            // ).showSnackBar(SnackBar(content: Text('')));
                          }
                        } else {
                          // Stripe / PayPal flow already handled separately
                          _showRatingBottomSheet(context);
                        }
                      },
                      isLoading: packageController.isButtonLoading.value,
                      text: 'Continue',
                    );
                  }),
                ),*/
                Expanded(
                  child: Obx(() {
                    return AppButtons.button(
                      onTap: () async {
                        final walletBalance =
                            double.tryParse(
                              walletController
                                      .walletBalance
                                      .value?.customerWalletBalance.toString() ??
                                  '0',
                            ) ??
                            0.0;
                        final rideAmount = widget.amount ?? 0.0;

                        if (selectedIndex == 1) {
                          // WALLET
                          if (walletBalance < rideAmount) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Insufficient wallet balance. Please add funds or choose another payment method.",
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          final success = await packageController.paymentDetails(
                            bookingId: widget.bookingId ?? '',
                            paymentType: 'WALLET',
                            context: context,
                          );

                          // call ONCE after success (adjust according to your API’s success contract)
                          if (success) {
                            await _completePaymentFlow(paymentMethod: 'Wallet');
                          }
                          return;
                        }

                        if (selectedIndex == 3) {
                          // COD
                          final success = await packageController.paymentDetails(
                            bookingId: widget.bookingId ?? '',
                            paymentType: 'COD',
                            context: context,
                          );
                          // show ONCE after success
                          if (success) {
                            await _markCustomerCashPaymentCompleted();
                            await _completePaymentFlow(paymentMethod: 'Cash on Delivery');
                          }
                          return;
                        }

                        // Stripe / PayPal flows:
                        // Don’t open the sheet here. Open it only after a confirmed success in their respective callbacks.
                        // For example, after Stripe success in displayPaymentSheet(), call:
                        // await _showRatingBottomSheet(context);

                        // final walletBalance =
                        //     double.tryParse(
                        //       walletController
                        //               .walletBalance
                        //               .value
                        //               ?.customerWalletBalance
                        //               ?.toString() ??
                        //           '0',
                        //     ) ??
                        //     0.0;
                        //
                        // final rideAmount = widget.amount ?? 0.0;
                        //
                        // if (selectedIndex == 1) {
                        //   // 🟡 WALLET SELECTED
                        //   if (walletBalance < rideAmount) {
                        //     // ❌ Not enough balance
                        //     ScaffoldMessenger.of(context).showSnackBar(
                        //       SnackBar(
                        //         content: Text(
                        //           "Insufficient wallet balance. Please add funds or choose another payment method.",
                        //         ),
                        //         backgroundColor: Colors.red,
                        //       ),
                        //     );
                        //     return;
                        //   }
                        //
                        //   _showRatingBottomSheet(context);
                        //   final result = await packageController.paymentDetails(
                        //     bookingId: widget.bookingId ?? '',
                        //     paymentType: 'WALLET',
                        //     context: context,
                        //   );
                        //
                        //   if (result == '') {
                        //     _showRatingBottomSheet(context);
                        //   } else {}
                        // } else if (selectedIndex == 3) {
                        //   // 💵 CASH ON DELIVERY
                        //   _showRatingBottomSheet(context);
                        //   final result = await packageController.paymentDetails(
                        //     bookingId: widget.bookingId ?? '',
                        //     paymentType: 'COD',
                        //     context: context,
                        //   );
                        // } else {
                        //   _showRatingBottomSheet(context);
                        // }
                      },
                      isLoading: packageController.isButtonLoading.value,
                      text: 'Continue',
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Payment Successful" sheet. Fetches the backend ride receipt (universal
/// endpoint — works for COD / Wallet / Paystack / Flutterwave) and drives the
/// card + Copy / Share / Download from it. Falls back to a locally-built summary
/// if the receipt isn't ready yet, and never crashes.
class _PaymentSuccessSheet extends StatefulWidget {
  final String bookingId;
  final String paymentMethod;
  final String fallbackSummary;
  final VoidCallback onContinue;
  final Future<void> Function() onFallbackDownload;

  const _PaymentSuccessSheet({
    required this.bookingId,
    required this.paymentMethod,
    required this.fallbackSummary,
    required this.onContinue,
    required this.onFallbackDownload,
  });

  @override
  State<_PaymentSuccessSheet> createState() => _PaymentSuccessSheetState();
}

class _PaymentSuccessSheetState extends State<_PaymentSuccessSheet> {
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
              const Center(
                child: Text(
                  'Payment Successful',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Your payment is confirmed. Review or share the trip summary before rating.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF667085), fontSize: 13),
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

// import 'dart:convert';
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:hopper/Core/Utility/app_toasts.dart';
// import 'package:hopper/Presentation/Drawer/controller/profle_cotroller.dart';
// import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';
// import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
// import 'package:hopper/Presentation/OnBoarding/Screens/pay_pall_screen.dart';
// import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
// import 'package:hopper/Presentation/wallet/controller/wallet_controller.dart';
// import 'package:hopper/webview_page.dart';

// import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:hopper/Core/Consents/app_colors.dart';
// import 'package:hopper/Core/Consents/app_logger.dart';

// import 'package:hopper/Core/Utility/app_buttons.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/Core/Utility/app_loader.dart';
// import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';

// import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
// import 'package:flutter_stripe/flutter_stripe.dart';
// import 'package:http/http.dart' as http;
// import 'package:get/get.dart';
// import 'package:share_plus/share_plus.dart';

// import 'package:cached_network_image/cached_network_image.dart';

// class PaymentScreen extends StatefulWidget {
//   final String? bookingId;
//   final double? amount;
//   final AddressModel? sender;
//   final AddressModel? receiver;
//   final String? driverName;
//   final String? driverProfilePic;
//   const PaymentScreen({
//     super.key,
//     this.bookingId,
//     this.amount,
//     this.sender,
//     this.receiver,
//     this.driverName,
//     this.driverProfilePic,
//   });

//   @override
//   State<PaymentScreen> createState() => _PaymentScreenState();
// }

// class _PaymentScreenState extends State<PaymentScreen> {
//   // Payment methods shown in production:
//   // - Flutterwave
//   // - Paystack
//   // - Hoppr Wallet
//   //
//   // Default to wallet to keep a predictable "Continue" flow.
//   int selectedIndex = 1;

//   final DriverSearchController driverSearchController =
//       Get.isRegistered<DriverSearchController>()
//           ? Get.find<DriverSearchController>()
//           : Get.put(DriverSearchController());
//   final PackageController packageController = Get.put(PackageController());
//   final WalletController walletController = Get.put(WalletController());


//   final ProfleCotroller controller = Get.put(ProfleCotroller());
//   bool _isRatingSheetOpen = false;

//   bool _isLoading = false;
//   bool payPalLoading = false;
//   bool flutterWaveLoading = false;
//   bool payStackLoading = false;

//   void _goToHomeAfterPayment() {
//     if (!mounted) return;
//     Get.offAll(() => const CommonBottomNavigation(initialIndex: 0));
//   }

//   String _receiptSummary(String paymentMethod, {String? transactionId}) {
//     final booking = (widget.bookingId ?? '').trim();
//     final amount =
//         (widget.amount != null) ? widget.amount!.toStringAsFixed(2) : '';
//     final driverName = (widget.driverName ?? '').trim();
//     final tx = (transactionId ?? '').trim();

//     final now = DateTime.now();
//     final two = (int v) => v.toString().padLeft(2, '0');
//     final dateStr =
//         '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';

//     final b = StringBuffer();
//     b.writeln('Hoppr Receipt');
//     b.writeln('Date: $dateStr');
//     b.writeln('Booking ID: ${booking.isEmpty ? '-' : booking}');
//     b.writeln('Amount: ${amount.isEmpty ? '-' : amount}');
//     b.writeln('Payment: $paymentMethod');
//     if (tx.isNotEmpty) b.writeln('Transaction: $tx');
//     if (driverName.isNotEmpty) b.writeln('Driver: $driverName');
//     return b.toString().trim();
//   }

//   Future<File> _writeReceiptFile(String summary) async {
//     final safeBooking =
//         (widget.bookingId ?? 'ride').replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
//     final ts = DateTime.now()
//         .toIso8601String()
//         .replaceAll(':', '-')
//         .replaceAll('.', '-');
//     final file = File(
//       '${Directory.systemTemp.path}${Platform.pathSeparator}hoppr_receipt_${safeBooking}_$ts.txt',
//     );
//     await file.writeAsString(summary);
//     return file;
//   }

//   Future<void> _exportReceipt(String summary) async {
//     try {
//       final file = await _writeReceiptFile(summary);
//       await Share.shareXFiles(
//         <XFile>[XFile(file.path)],
//         subject: 'Hoppr receipt',
//         text: 'Hoppr receipt',
//       );
//     } catch (_) {
//       if (!mounted) return;
//       AppToasts.showError(context, 'Failed to export receipt');
//     }
//   }

//   Future<void> _showPaymentSuccessSheet({required String paymentMethod, String? transactionId}) async {
//     final summary = _receiptSummary(paymentMethod, transactionId: transactionId);
//     await showModalBottomSheet(
//       context: context,
//       isDismissible: false,
//       enableDrag: false,
//       isScrollControlled: true,
//       backgroundColor: Colors.transparent,
//       builder: (sheetContext) {
//         final media = MediaQuery.of(sheetContext);
//         return SafeArea(
//           top: false,
//           child: Container(
//             constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
//             padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
//             decoration: const BoxDecoration(
//               color: Colors.white,
//               borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
//             ),
//             child: SingleChildScrollView(
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Center(
//                     child: Container(
//                       width: 48,
//                       height: 5,
//                       decoration: BoxDecoration(
//                         color: const Color(0xFFD0D5DD),
//                         borderRadius: BorderRadius.circular(999),
//                       ),
//                     ),
//                   ),
//                   const SizedBox(height: 18),
//                   const Center(
//                     child: CircleAvatar(
//                       radius: 28,
//                       backgroundColor: Colors.black,
//                       child: Icon(
//                         Icons.check_rounded,
//                         color: Colors.white,
//                         size: 30,
//                       ),
//                     ),
//                   ),
//                   const SizedBox(height: 16),
//                   const Center(
//                     child: Text(
//                       'Payment Successful',
//                       style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   const Center(
//                     child: Text(
//                       'Your payment is confirmed. Review or share the trip summary before rating.',
//                       textAlign: TextAlign.center,
//                       style: TextStyle(color: Color(0xFF667085), fontSize: 13),
//                     ),
//                   ),
//                   const SizedBox(height: 18),
//                   Container(
//                     width: double.infinity,
//                     padding: const EdgeInsets.all(14),
//                     decoration: BoxDecoration(
//                       color: const Color(0xFFF8FAFC),
//                       borderRadius: BorderRadius.circular(16),
//                       border: Border.all(color: const Color(0xFFE5E7EB)),
//                     ),
//                     child: Text(
//                       summary,
//                       style: const TextStyle(
//                         height: 1.5,
//                         fontSize: 13,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),
//                   ),
//                   const SizedBox(height: 14),
//                   Row(
//                     children: [
//                       Expanded(
//                         child: AppButtons.button(
//                           onTap: () => Share.share(summary),
//                           text: 'Share',
//                           buttonColor: Colors.white,
//                           textColor: Colors.black,
//                           hasBorder: true,
//                           borderColor: const Color(0xFFD0D5DD),
//                         ),
//                       ),
//                       const SizedBox(width: 10),
//                       Expanded(
//                         child: AppButtons.button(
//                           onTap: () async {
//                             await Clipboard.setData(ClipboardData(text: summary));
//                             AppToasts.showSuccess(context, 'Receipt copied');
//                           },
//                           text: 'Copy',
//                           buttonColor: Colors.white,
//                           textColor: Colors.black,
//                           hasBorder: true,
//                           borderColor: const Color(0xFFD0D5DD),
//                         ),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 10),
//                   Row(
//                     children: [
//                       Expanded(
//                         child: AppButtons.button(
//                           onTap: () async => _exportReceipt(summary),
//                           text: 'Download',
//                           buttonColor: Colors.white,
//                           textColor: Colors.black,
//                           hasBorder: true,
//                           borderColor: const Color(0xFFD0D5DD),
//                         ),
//                       ),
//                       const SizedBox(width: 10),
//                       Expanded(
//                         child: AppButtons.button(
//                           onTap: () => Navigator.pop(sheetContext),
//                           text: 'Continue',
//                           buttonColor: AppColors.commonBlack,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }

//   Future<void> _completePaymentFlow({required String paymentMethod, String? transactionId}) async {
//     if (!mounted) return;
//     await _showPaymentSuccessSheet(paymentMethod: paymentMethod, transactionId: transactionId);
//     if (!mounted) return;
//     await _showRatingBottomSheet(context);
//   }

//   Future<void> _showRatingBottomSheet(BuildContext pageContext) async {
//     if (_isRatingSheetOpen) return;
//     _isRatingSheetOpen = true;
//     int selectedRating = 0;
//     bool isSubmittingRating = false;

//     await showModalBottomSheet(
//       context: pageContext,
//       isScrollControlled: true,
//       isDismissible: false,
//       enableDrag: false,
//       backgroundColor: Colors.transparent,
//       builder: (sheetContext) {
//         return StatefulBuilder(
//           builder: (context, setModalState) {
//             final user = controller.user.value;
//             final fallbackName = user?.firstName.trim() ?? '';
//             final riderName = (widget.driverName?.trim().isNotEmpty == true ? widget.driverName!.trim() : fallbackName.isNotEmpty ? fallbackName : 'Driver');
//             final profilePic = (widget.driverProfilePic?.trim().isNotEmpty == true ? widget.driverProfilePic!.trim() : user?.profileImage ?? '');

//             return Container(
//               decoration: const BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
//               ),
//               child: SafeArea(
//                 top: false,
//                 child: SingleChildScrollView(
//                   padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
//                   child: Column(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       Container(
//                         width: 48,
//                         height: 5,
//                         decoration: BoxDecoration(
//                           color: const Color(0xFFD0D5DD),
//                           borderRadius: BorderRadius.circular(999),
//                         ),
//                       ),
//                       const SizedBox(height: 22),
//                       ClipRRect(
//                         borderRadius: BorderRadius.circular(999),
//                         child: CachedNetworkImage(
//                           imageUrl: profilePic,
//                           height: 72,
//                           width: 72,
//                           fit: BoxFit.cover,
//                           placeholder: (context, url) => Container(
//                             height: 72,
//                             width: 72,
//                             decoration: const BoxDecoration(
//                               color: Color(0xFFF2F4F7),
//                               shape: BoxShape.circle,
//                             ),
//                             child: const Center(
//                               child: SizedBox(
//                                 height: 18,
//                                 width: 18,
//                                 child: CircularProgressIndicator(strokeWidth: 2),
//                               ),
//                             ),
//                           ),
//                           errorWidget: (context, url, error) => Container(
//                             height: 72,
//                             width: 72,
//                             decoration: const BoxDecoration(
//                               color: Color(0xFFF2F4F7),
//                               shape: BoxShape.circle,
//                             ),
//                             child: const Icon(
//                               Icons.person,
//                               color: Color(0xFF98A2B3),
//                               size: 30,
//                             ),
//                           ),
//                         ),
//                       ),
//                       const SizedBox(height: 18),
//                       const Text(
//                         'Trip Completed',
//                         style: TextStyle(
//                           fontSize: 22,
//                           fontWeight: FontWeight.w700,
//                           color: Color(0xFF101828),
//                         ),
//                       ),
//                       const SizedBox(height: 8),
//                       Text(
//                         'Rate your experience with $riderName',
//                         textAlign: TextAlign.center,
//                         style: const TextStyle(
//                           fontSize: 14,
//                           height: 1.5,
//                           color: Color(0xFF667085),
//                           fontWeight: FontWeight.w500,
//                         ),
//                       ),
//                       const SizedBox(height: 24),
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                         children: List.generate(5, (index) {
//                           final active = index < selectedRating;
//                           return GestureDetector(
//                             onTap: () => setModalState(() => selectedRating = index + 1),
//                             child: AnimatedContainer(
//                               duration: const Duration(milliseconds: 180),
//                               height: 54,
//                               width: 54,
//                               decoration: BoxDecoration(
//                                 color: active ? const Color(0xFFFFF4E5) : const Color(0xFFF5F6F8),
//                                 borderRadius: BorderRadius.circular(16),
//                                 border: Border.all(
//                                   color: active ? const Color(0xFFF59E0B) : const Color(0xFFE4E7EC),
//                                 ),
//                               ),
//                               child: Icon(
//                                 active ? Icons.star_rounded : Icons.star_border_rounded,
//                                 color: active ? const Color(0xFFF59E0B) : const Color(0xFF98A2B3),
//                                 size: 30,
//                               ),
//                             ),
//                           );
//                         }),
//                       ),
//                       const SizedBox(height: 24),
//                       Row(
//                         children: [
//                           Expanded(
//                             child: AppButtons.button(
//                               borderColor: const Color(0xFFD0D5DD),
//                               hasBorder: true,
//                               buttonColor: Colors.white,
//                               textColor: AppColors.commonBlack,
//                               onTap: () {
//                                 Navigator.pop(sheetContext);
//                                 _goToHomeAfterPayment();
//                               },
//                               text: 'Skip',
//                             ),
//                           ),
//                           const SizedBox(width: 12),
//                           Expanded(
//                             child: AppButtons.button(
//                               buttonColor: AppColors.commonBlack,
//                               isLoading: isSubmittingRating || driverSearchController.isLoading.value,
//                               onTap: (isSubmittingRating || driverSearchController.isLoading.value)
//                                   ? null
//                                   : () async {
//                                       if (selectedRating == 0) {
//                                         ScaffoldMessenger.of(sheetContext)
//                                           ..hideCurrentSnackBar()
//                                           ..showSnackBar(
//                                             const SnackBar(
//                                               content: Text('Please select a rating'),
//                                             ),
//                                           );
//                                         return;
//                                       }
//                                       final bookingId = widget.bookingId ?? "";
//                                       setModalState(() => isSubmittingRating = true);
//                                       final result = await driverSearchController.rateDriver(
//                                         bookingId: bookingId,
//                                         rating: selectedRating.toString(),
//                                         context: sheetContext,
//                                       );
//                                       if (mounted) {
//                                         setModalState(() => isSubmittingRating = false);
//                                       }
//                                       if ((result ?? '').isEmpty) {
//                                         Navigator.pop(sheetContext);
//                                         _goToHomeAfterPayment();
//                                       }
//                                     },
//                               text: 'Submit Rating',
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             );
//           },
//         );
//       },
//     );

//     _isRatingSheetOpen = false;
//   }

//   Map<String, dynamic>? paymentIntentData;

//   /*Future<void> makePayment() async {
//     try {
//       paymentIntentData = await createPaymentIntent('1000') ?? {};

//       await Stripe.instance.initPaymentSheet(
//         paymentSheetParameters: SetupPaymentSheetParameters(
//           paymentIntentClientSecret: paymentIntentData!['clientSecret'],
//           style: ThemeMode.light,
//           customFlow: false,

//           merchantDisplayName: 'Hoppr',
//         ),
//       );

//       displayPaymentSheet();
//     } catch (e) {
//       AppLogger.log.i('Exception: $e');
//     }
//   }*/
//   Future<void> payPall() async {
//     final result = await Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder:
//             (context) => PaypalWebviewPage(
//               amount: widget.amount?.toString() ?? '',
//               bookingId: widget.bookingId ?? '',
//             ),
//       ),
//     );

//     if (!mounted) return;
//     if (result == true) {
//       AppToasts.showSuccess(context,'Payment Successful');
//       await _completePaymentFlow(paymentMethod: 'PayPal');
//     } else if (result == false) {
//       AppToasts.showError(context,'Payment failed or cancelled');
//     }
//   }

//   Future<void> makePayment() async {
//     try {
//       final result = await createPaymentIntent('1500000');

//       if (result == null || !result.containsKey('clientSecret')) {
//         AppLogger.log.e("❌ Payment Intent is null or missing 'clientSecret'");
//         return;
//       }

//       paymentIntentData = result;

//       await Stripe.instance.initPaymentSheet(
//         paymentSheetParameters: SetupPaymentSheetParameters(
//           paymentIntentClientSecret: paymentIntentData!['clientSecret'],
//           style: ThemeMode.light,
//           customFlow: false,
//           merchantDisplayName: 'Hoppr',
//         ),
//       );

//       displayPaymentSheet();
//     } catch (e) {
//       AppLogger.log.e('💡 Exception in makePayment: $e');
//     }
//   }

//   displayPaymentSheet() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     String? token = prefs.getString('token');

//     if (token == null) {
//       AppLogger.log.i('⚠️ Token not found in shared preferences');
//       return;
//     }

//     try {
//       final String bookingId = widget.bookingId ?? '';
//       await Stripe.instance.presentPaymentSheet();

//       String? clientSecret = paymentIntentData?['clientSecret'];
//       String? transactionId;

//       if (clientSecret != null && clientSecret.contains('_secret')) {
//         transactionId = clientSecret.split('_secret').first;
//       }

//       if (transactionId != null) {
//         final response = await http.post(
//           Uri.parse(
//             'https://bk.myhoppr.com/api/customer/confirm-stripe-payment-response',
//           ),
//           headers: {
//             'Content-Type': 'application/json',
//             'Authorization': 'Bearer $token',
//           },
//           body: jsonEncode({
//             "userBookingId": bookingId,
//             "paymentIntentId": transactionId,
//           }),
//         );

//         AppLogger.log.i('Confirm Payment Response: ${response.body}');
//         if (response.statusCode == 200) {
//           if (mounted) {
//             await _completePaymentFlow(paymentMethod: 'Stripe', transactionId: transactionId);
//           }
//           AppLogger.log.i('✅ Payment response confirmed successfully');
//         } else {
//           AppLogger.log.i('❌ Failed to confirm payment response');
//         }
//       }

//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text("Payment successful\nTransaction ID: $transactionId"),
//         ),
//       );

//       AppLogger.log.i('✅ Payment successful. Transaction ID: $transactionId');
//     } catch (e) {
//       AppLogger.log.i('❌ Error during payment sheet presentation: $e');
//     }
//   }

//   Future<Map<String, dynamic>?> createPaymentIntent(String amount) async {
//     try {
//       final String bookingId = widget.bookingId ?? '';
//       SharedPreferences prefs = await SharedPreferences.getInstance();
//       String? token = prefs.getString('token');

//       final response = await http.post(
//         Uri.parse(
//           'https://bk.myhoppr.com/api/customer/confirm-stripe-payment-intents',
//         ),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Bearer $token',
//         },
//         body: jsonEncode({'userBookingId': bookingId, 'amount': amount}),
//       );

//       AppLogger.log.i('Status code: ${response.statusCode}');
//       AppLogger.log.i('Response body: ${response.body}');

//       final decoded = jsonDecode(response.body);

//       // 👇 Detect server-side validation error
//       if (decoded is Map && decoded.containsKey('error')) {
//         final errorMsg = decoded['error'] ?? 'Unknown error occurred';
//         if (context.mounted) {
//           AppToasts.showError(context,errorMsg.toString());
//           // ScaffoldMessenger.of(context).showSnackBar(
//           //   SnackBar(content: Text(errorMsg.toString())),
//           // );
//         }
//         AppLogger.log.e('❌ Stripe payment error: $errorMsg');
//         return null;
//       }

//       // 👇 Handle non-200 status codes
//       if (response.statusCode != 200) {
//         throw Exception('Failed to create payment intent');
//       }

//       AppLogger.log.i('✅ Decoded payment intent response: $decoded');
//       return decoded;
//     } catch (err) {
//       AppLogger.log.e('❌ Error creating payment intent: $err');
//       if (context.mounted) {
//         // ScaffoldMessenger.of(context).showSnackBar(
//         //   SnackBar(content: Text('Error creating payment intent: $err')),
//         // );
//         AppToasts.showError(context,'$err');
//       }
//       return null;
//     }
//   }



//   Future<void> payWithFlutterWave() async {
//     final prefs = await SharedPreferences.getInstance();

//     String? email = prefs.getString('flutterwave_email');
//     String? name = prefs.getString('flutterwave_name');
//     String? phone = prefs.getString('flutterwave_phone');

//     if (email == null ||
//         email.isNotEmpty ||
//         name == null ||
//         name.isEmpty ||
//         phone == null ||
//         phone.isEmpty) {
//       final result = await _showUserInfoBottomSheet(
//         context,
//         email,
//         name,
//         phone,
//       );

//       if (result != true) return;

//       email = prefs.getString('flutterwave_email');
//       name = prefs.getString('flutterwave_name');
//       phone = prefs.getString('flutterwave_phone');
//     }

//     setState(() => flutterWaveLoading = true);

//     try {
//       String? token = prefs.getString('token');
//       final response = await http.post(
//         Uri.parse(
//           'https://bk.myhoppr.com/api/flutterwave/initialize',
//         ),
//         headers: {
//           "Content-Type": "application/json",
//           if (token != null)
//             "Authorization": "Bearer $token", // ✅ Add Bearer token
//         },
//         body: jsonEncode({
//           "userBookingId": widget.bookingId ?? '',
//           "amount": widget.amount.toString(),
//           "email": email,
//           "name": name,
//           "phone": phone,
//         }),
//       );

//       final data = jsonDecode(response.body);

//       if (response.statusCode == 200) {
//         final paymentLink = data['paymentLink'];

//         if (paymentLink != null) {
//           final result = await Navigator.push(
//             context,
//             MaterialPageRoute(builder: (_) => PaymentWebView(url: paymentLink)),
//           );

//           if (result != null && result["status"] == "success") {
//             AppToasts.showSuccess(context,'Payment Successful');
//             AppLogger.log.i("Payment Successful: ${result["transactionId"]}");
//             await _completePaymentFlow(paymentMethod: 'FlutterWave', transactionId: result['transactionId']?.toString());
//           } else {
//             AppToasts.showError(context,"Payment failed or cancelled");
//           }
//         } else {
//           final errorMsg = data['message'] ?? "Failed to initialize payment";
//           AppToasts.showError(context,errorMsg);
//         }
//       } else {
//         final errorMsg = data['message'] ?? "Failed to initialize payment";
//         AppToasts.showError(context,errorMsg);
//         AppLogger.log.e(
//           'Failed to initialize Flutterwave payment: ${response.body}',
//         );
//       }
//     } catch (e) {
//       AppToasts.showError(context,e.toString());
//       AppLogger.log.e("Error during Flutterwave payment: $e");
//     } finally {
//       setState(() => flutterWaveLoading = false);
//     }
//   }

//   Future<bool?> _showUserInfoBottomSheet(
//     BuildContext context,
//     String? email,
//     String? name,
//     String? phone,
//   ) {
//     final _emailController = TextEditingController(text: email);
//     final _nameController = TextEditingController(text: name);
//     final _phoneController = TextEditingController(text: phone);

//     return showModalBottomSheet<bool>(
//       context: context,
//       isScrollControlled: true,
//       backgroundColor: Colors.transparent, // Transparent to get rounded corners
//       builder: (context) {
//         return Padding(
//           padding: EdgeInsets.only(
//             bottom: MediaQuery.of(context).viewInsets.bottom,
//           ),
//           child: Container(
//             decoration: BoxDecoration(
//               color: Colors.white,
//               borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
//               boxShadow: [
//                 BoxShadow(
//                   color: Colors.black26,
//                   blurRadius: 10,
//                   offset: Offset(0, -4),
//                 ),
//               ],
//             ),
//             padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Container(
//                   width: 50,
//                   height: 5,
//                   decoration: BoxDecoration(
//                     color: Colors.grey[300],
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                 ),
//                 SizedBox(height: 15),
//                 Text(
//                   "Enter Payment Info",
//                   style: TextStyle(
//                     fontSize: 20,
//                     fontWeight: FontWeight.bold,
//                     color: Colors.black87,
//                   ),
//                 ),
//                 SizedBox(height: 25),
//                 _buildTextField(
//                   _emailController,
//                   "Email",
//                   Icons.email,
//                   TextInputType.emailAddress,
//                 ),
//                 SizedBox(height: 15),
//                 _buildTextField(
//                   _nameController,
//                   "Name",
//                   Icons.person,
//                   TextInputType.name,
//                 ),
//                 SizedBox(height: 15),
//                 _buildTextField(
//                   _phoneController,
//                   "Phone",
//                   Icons.phone,
//                   TextInputType.phone,
//                 ),
//                 SizedBox(height: 25),
//                 AppButtons.button(
//                   onTap: () async {
//                     if (_emailController.text.isEmpty ||
//                         _nameController.text.isEmpty ||
//                         _phoneController.text.isEmpty) {
//                       AppToasts.showError(context,"All fields are required");
//                       return;
//                     }

//                     final prefs = await SharedPreferences.getInstance();
//                     await prefs.setString(
//                       'flutterwave_email',
//                       _emailController.text,
//                     );
//                     await prefs.setString(
//                       'flutterwave_name',
//                       _nameController.text,
//                     );
//                     await prefs.setString(
//                       'flutterwave_phone',
//                       _phoneController.text,
//                     );

//                     Navigator.pop(context, true);
//                   },
//                   text: 'Save & Continue',
//                 ),

//                 SizedBox(height: 20),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildTextField(
//     TextEditingController controller,
//     String label,
//     IconData icon,
//     TextInputType type,
//   ) {
//     return TextField(
//       controller: controller,
//       keyboardType: type,
//       decoration: InputDecoration(
//         prefixIcon: Icon(icon, color: AppColors.commonBlack),
//         labelText: label,
//         labelStyle: TextStyle(color: Colors.grey[700]),
//         filled: true,
//         fillColor: Colors.grey[100],
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(15),
//           borderSide: BorderSide.none,
//         ),
//         contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
//       ),
//     );
//   }

//   Future<void> payWithPayStack() async {
//     final prefs = await SharedPreferences.getInstance();

//     String? email = prefs.getString('flutterwave_email');
//     String? name = prefs.getString('flutterwave_name');
//     String? phone = prefs.getString('flutterwave_phone');

//     if (email == null ||
//         email.isNotEmpty ||
//         name == null ||
//         name.isEmpty ||
//         phone == null ||
//         phone.isEmpty) {
//       final result = await _showUserInfoBottomSheet(
//         context,
//         email,
//         name,
//         phone,
//       );

//       if (result != true) return;

//       email = prefs.getString('flutterwave_email');
//       name = prefs.getString('flutterwave_name');
//       phone = prefs.getString('flutterwave_phone');
//     }

//     setState(() => payStackLoading = true);

//     try {
//       String? token = prefs.getString('token');
//       final response = await http.post(
//         Uri.parse(
//           'https://bk.myhoppr.com/api/paystack/init',
//         ),
//         headers: {
//           "Content-Type": "application/json",
//           if (token != null) "Authorization": "Bearer $token",
//         },
//         body: jsonEncode({
//           "userBookingId": widget.bookingId ?? '',
//           "email": email,
//         }),
//       );

//       final data = jsonDecode(response.body);

//       if (response.statusCode == 200) {
//         final paymentLink = data['authorization_url'];

//         if (paymentLink != null) {
//           final result = await Navigator.push(
//             context,
//             MaterialPageRoute(builder: (_) => PaymentWebView(url: paymentLink)),
//           );

//           if (result != null && result["status"] == "success") {
//             AppToasts.showSuccess(context,'Payment Successful');
//             AppLogger.log.i("Payment Successful: ${result["transactionId"]}");
//             await _completePaymentFlow(paymentMethod: 'Paystack', transactionId: result['transactionId']?.toString());
//           } else {
//             AppToasts.showError(context,"Payment failed or cancelled");
//           }
//         } else {
//           final errorMsg = data['message'] ?? "Failed to initialize payment";
//           AppToasts.showError(context,errorMsg);
//         }
//       } else {
//         final errorMsg = data['message'] ?? "Failed to initialize payment";
//         AppToasts.showError(context,errorMsg);
//         AppLogger.log.e(
//           'Failed to initialize Flutterwave payment: ${response.body}',
//         );
//       }
//     } catch (e) {
//       AppToasts.showError(context,e.toString());
//       AppLogger.log.e("Error during Flutterwave payment: $e");
//     } finally {
//       setState(() => payStackLoading = false);
//     }
//   }

//   Widget _buildUnderDevelopmentDialog(BuildContext context) {
//     return Dialog(
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//       backgroundColor: Colors.white,
//       child: Padding(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             // Image.asset(
//             //   AppImages.developing,
//             //   width: 80,
//             //   height: 80,
//             //   fit: BoxFit.contain,
//             // ),
//             // const SizedBox(height: 16),
//             Text(
//               'Feature in Development',
//               style: TextStyle(
//                 fontSize: 18,
//                 fontWeight: FontWeight.w600,
//                 color: AppColors.commonBlack,
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               'This feature is currently under development.\nStay tuned for updates!',
//               textAlign: TextAlign.center,
//               style: TextStyle(
//                 fontSize: 14,
//                 color: AppColors.greyDark,
//                 height: 1.4,
//               ),
//             ),
//             const SizedBox(height: 20),
//             AppButtons.button(
//               onTap: () {
//                 Navigator.pop(context);
//               },
//               text: 'OK',
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   @override
//   void initState() {
//     super.initState();
//     walletController.getWalletBalance();
//     controller.getProfileData();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: SafeArea(
//         child: Container(
//           height: double.infinity,
//           decoration: const BoxDecoration(
//             gradient: LinearGradient(
//               begin: Alignment.topCenter,
//               end: Alignment.bottomCenter,
//               colors: [Color(0xFFFFFFFD), Color(0xFFF6F7FF)],
//             ),
//           ),
//           child: SingleChildScrollView(
//             child: Padding(
//               padding: const EdgeInsets.symmetric(
//                 horizontal: 16.0,
//                 vertical: 25,
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     children: [
//                       GestureDetector(
//                         onTap: () {
//                           Navigator.pop(context);
//                         },
//                         child: Image.asset(
//                           AppImages.backImage,
//                           height: 20,
//                           width: 20,
//                         ),
//                       ),
//                       CustomTextFields.textWithStyles700(
//                         'Payment Method',
//                         fontSize: 20,
//                       ),
//                       Text(''),
//                       // Image.asset(AppImages.history, height: 20, width: 20),
//                     ],
//                   ),

//                   const SizedBox(height: 30),

//                   CustomTextFields.textWithStyles700(
//                     'Payment Options',
//                     fontSize: 17,
//                   ),
//                   const SizedBox(height: 20),
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     children: [
//                       InkWell(
//                         onTap:
//                             flutterWaveLoading
//                                 ? null
//                                 : () async {
//                                   setState(() {
//                                     selectedIndex = 0; // Flutterwave
//                                   });
//                                 },
//                         borderRadius: BorderRadius.circular(10),
//                         child: Container(
//                           height: 50,
//                           width: 170,
//                           padding: const EdgeInsets.all(10),
//                           decoration: BoxDecoration(
//                             color: AppColors.commonWhite,
//                             border: Border.all(
//                               color:
//                                   selectedIndex == 0
//                                       ? Colors.black
//                                       : AppColors.containerColor,
//                             ),
//                             borderRadius: BorderRadius.circular(10),
//                           ),
//                           child: Center(
//                             child:
//                                 flutterWaveLoading
//                                     ? const SizedBox(
//                                       height: 24,
//                                       width: 24,
//                                       child: CircularProgressIndicator(
//                                         strokeWidth: 2,
//                                         color: Colors.black,
//                                       ),
//                                     )
//                                     : Row(
//                                       mainAxisAlignment:
//                                           MainAxisAlignment.center,
//                                       children: [
//                                         Image.asset(
//                                           AppImages.flutter_wave,
//                                           height: 24,
//                                           width: 40,
//                                         ),
//                                         const SizedBox(width: 10),
//                                         CustomTextFields.textWithStylesSmall(
//                                           'Flutterwave',
//                                           fontSize: 16,
//                                           fontWeight: FontWeight.w500,
//                                           colors: AppColors.commonBlack,
//                                         ),
//                                       ],
//                                     ),
//                           ),
//                         ),
//                       ),

//                       InkWell(
//                         borderRadius: BorderRadius.circular(10),
//                         onTap:
//                             payStackLoading
//                                 ? null
//                                 : () async {
//                                   setState(() {
//                                     selectedIndex = 2; // Paystack
//                                   });
//                                 },
//                         child: Container(
//                           height: 50,
//                           width: 170,
//                           padding: const EdgeInsets.all(10),
//                           decoration: BoxDecoration(
//                             color: AppColors.commonWhite,
//                             border: Border.all(
//                               color:
//                                   selectedIndex == 2
//                                       ? Colors.black
//                                       : AppColors.containerColor,
//                             ),
//                             borderRadius: BorderRadius.circular(10),
//                           ),
//                           child:
//                               payStackLoading
//                                   ? Center(child: AppLoader.circularLoader())
//                                   : Row(
//                                     children: [
//                                       Image.asset(AppImages.payStack),
//                                       const SizedBox(width: 10),
//                                       CustomTextFields.textWithStylesSmall(
//                                         'Paystack',
//                                         fontSize: 16,
//                                         fontWeight: FontWeight.w500,
//                                         colors: AppColors.commonBlack,
//                                       ),
//                                     ],
//                                   ),
//                         ),
//                       ),
//                     ],
//                   ),

//                   const SizedBox(height: 15),

//                   CustomTextFields.textWithStyles700('Wallet', fontSize: 16),
//                   SizedBox(height: 15),
//                   Obx(() {
//                     final balance =
//                         walletController
//                             .walletBalance
//                             .value?.customerWalletBalance
//                             .toString() ??
//                         "0";


//                     return PackageContainer.customWalletContainer(
//                       borderColor:
//                           selectedIndex == 1
//                               ? Colors.black
//                               : AppColors.containerColor,
//                       onTap: () {
//                         setState(() {
//                           selectedIndex = 1;
//                         });
//                       },
//                       title: 'Hoppr Wallet',
//                       leadingImagePath: AppImages.wallet,
//                       trailing: CustomTextFields.textWithImage(
//                         fontWeight: FontWeight.w600,
//                         text: balance,
//                         colors: AppColors.walletCurrencyColor,
//                         imagePath: AppImages.nBlackCurrency,
//                         imageColors: AppColors.walletCurrencyColor,
//                       ),
//                     );
//                   }),

//                   const SizedBox(height: 15),

//                   CustomTextFields.textWithStyles700('Cash', fontSize: 16),
//                   const SizedBox(height: 15),
//                   PackageContainer.customWalletContainer(
//                     borderColor:
//                         selectedIndex == 3
//                             ? Colors.black
//                             : AppColors.containerColor,
//                     onTap: () {
//                       setState(() {
//                         selectedIndex = 3;
//                       });
//                     },
//                     title: 'Cash on Delivery',
//                     leadingImagePath: AppImages.cash,
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ),

//       bottomNavigationBar: SafeArea(
//         child: SizedBox(
//           height: 120,
//           child: Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
//             child: Row(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     CustomTextFields.textWithImage(
//                       text: widget.amount?.toString() ?? '280',
//                       fontSize: 25,
//                       colors: AppColors.commonBlack,
//                       fontWeight: FontWeight.w700,
//                       imageSize: 23,
//                       imagePath: AppImages.nBlackCurrency,
//                     ),
//                     // const SizedBox(height: 4),
//                     // Row(
//                     //   children: [
//                     //     GestureDetector(
//                     //       onTap: () {},
//                     //       child: CustomTextFields.textWithStylesSmall(
//                     //         'View Details',
//                     //       ),
//                     //     ),
//                     //     Icon(Icons.keyboard_arrow_down_outlined, size: 20),
//                     //   ],
//                     // ),
//                   ],
//                 ),
//                 const SizedBox(width: 40),

//                 /*Expanded(
//                   child: Obx(() {
//                     return AppButtons.button(
//                       onTap: () async {
//                         if (selectedIndex == 1 || selectedIndex == 3) {
//                           _showRatingBottomSheet(context);
//                           print('Cash On Delivery or Hoppr Wallet selected');
//                           final paymentType =
//                               selectedIndex == 1 ? 'WALLET' : 'COD';

//                           final result = await packageController.paymentDetails(
//                             bookingId: widget.bookingId ?? '',
//                             paymentType: paymentType,
//                             context: context,
//                           );

//                           if (result == '') {
//                             _showRatingBottomSheet(context);

//                             // After rating, navigate home
//                           } else {
//                             // API failure
//                             // ScaffoldMessenger.of(
//                             //   context,
//                             // ).showSnackBar(SnackBar(content: Text('')));
//                           }
//                         } else {
//                           // Stripe / PayPal flow already handled separately
//                           _showRatingBottomSheet(context);
//                         }
//                       },
//                       isLoading: packageController.isButtonLoading.value,
//                       text: 'Continue',
//                     );
//                   }),
//                 ),*/
//                 Expanded(
//                   child: Obx(() {
//                     final isBusy =
//                         packageController.isButtonLoading.value ||
//                         flutterWaveLoading ||
//                         payStackLoading;
//                     return AppButtons.button(
//                       onTap:
//                           isBusy
//                               ? null
//                               : () async {
//                         final walletBalance =
//                             double.tryParse(
//                               walletController
//                                       .walletBalance
//                                       .value?.customerWalletBalance.toString() ??
//                                   '0',
//                             ) ??
//                             0.0;
//                         final rideAmount = widget.amount ?? 0.0;

//                         if (selectedIndex == 0) {
//                           await payWithFlutterWave();
//                           return;
//                         }

//                         if (selectedIndex == 2) {
//                           await payWithPayStack();
//                           return;
//                         }

//                         if (selectedIndex == 1) {
//                           // WALLET
//                           if (walletBalance < rideAmount) {
//                             ScaffoldMessenger.of(context).showSnackBar(
//                               const SnackBar(
//                                 content: Text(
//                                   "Insufficient wallet balance. Please add funds or choose another payment method.",
//                                 ),
//                                 backgroundColor: Colors.red,
//                               ),
//                             );
//                             return;
//                           }

//                           final result = await packageController.paymentDetails(
//                             bookingId: widget.bookingId ?? '',
//                             paymentType: 'WALLET',
//                             context: context,
//                           );

//                           // call ONCE after success (adjust according to your API’s success contract)
//                           if (result ==
//                               '' /* success per your current code */ ) {
//                             await _completePaymentFlow(paymentMethod: 'Wallet');
//                           }
//                           return;
//                         }

//                         if (selectedIndex == 3) {
//                           // COD
//                           final result = await packageController.paymentDetails(
//                             bookingId: widget.bookingId ?? '',
//                             paymentType: 'COD',
//                             context: context,
//                           );
//                           // show ONCE after success
//                           if (result == '' /* success */ ) {
//                             await _completePaymentFlow(paymentMethod: 'Cash on Delivery');
//                           }
//                           return;
//                         }

//                         ScaffoldMessenger.of(context)
//                           ..hideCurrentSnackBar()
//                           ..showSnackBar(
//                             const SnackBar(
//                               content: Text('Please select a payment method'),
//                             ),
//                           );

//                         // Stripe / PayPal flows:
//                         // Don’t open the sheet here. Open it only after a confirmed success in their respective callbacks.
//                         // For example, after Stripe success in displayPaymentSheet(), call:
//                         // await _showRatingBottomSheet(context);

//                         // final walletBalance =
//                         //     double.tryParse(
//                         //       walletController
//                         //               .walletBalance
//                         //               .value
//                         //               ?.customerWalletBalance
//                         //               ?.toString() ??
//                         //           '0',
//                         //     ) ??
//                         //     0.0;
//                         //
//                         // final rideAmount = widget.amount ?? 0.0;
//                         //
//                         // if (selectedIndex == 1) {
//                         //   // 🟡 WALLET SELECTED
//                         //   if (walletBalance < rideAmount) {
//                         //     // ❌ Not enough balance
//                         //     ScaffoldMessenger.of(context).showSnackBar(
//                         //       SnackBar(
//                         //         content: Text(
//                         //           "Insufficient wallet balance. Please add funds or choose another payment method.",
//                         //         ),
//                         //         backgroundColor: Colors.red,
//                         //       ),
//                         //     );
//                         //     return;
//                         //   }
//                         //
//                         //   _showRatingBottomSheet(context);
//                         //   final result = await packageController.paymentDetails(
//                         //     bookingId: widget.bookingId ?? '',
//                         //     paymentType: 'WALLET',
//                         //     context: context,
//                         //   );
//                         //
//                         //   if (result == '') {
//                         //     _showRatingBottomSheet(context);
//                         //   } else {}
//                         // } else if (selectedIndex == 3) {
//                         //   // 💵 CASH ON DELIVERY
//                         //   _showRatingBottomSheet(context);
//                         //   final result = await packageController.paymentDetails(
//                         //     bookingId: widget.bookingId ?? '',
//                         //     paymentType: 'COD',
//                         //     context: context,
//                         //   );
//                         // } else {
//                         //   _showRatingBottomSheet(context);
//                         // }
//                       },
//                       isLoading: isBusy,
//                       text: 'Continue',
//                     );
//                   }),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }





