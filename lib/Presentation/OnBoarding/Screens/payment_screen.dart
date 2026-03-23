import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

import 'package:cached_network_image/cached_network_image.dart';

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
    final summary = _receiptSummary(paymentMethod, transactionId: transactionId);
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(999)))),
              const SizedBox(height: 18),
              const Center(child: CircleAvatar(radius: 28, backgroundColor: Colors.black, child: Icon(Icons.check_rounded, color: Colors.white, size: 30))),
              const SizedBox(height: 16),
              const Center(child: Text('Payment Successful', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              const SizedBox(height: 8),
              Center(child: Text('Your payment is confirmed. Review or share the trip summary before rating.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF667085), fontSize: 13))),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E7EB))),
                child: Text(summary, style: const TextStyle(height: 1.5, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: AppButtons.button(onTap: () => Share.share(summary), text: 'Share', buttonColor: Colors.white, textColor: Colors.black, hasBorder: true, borderColor: const Color(0xFFD0D5DD))),
                const SizedBox(width: 10),
                Expanded(child: AppButtons.button(onTap: () async { await Clipboard.setData(ClipboardData(text: summary)); AppToasts.showSuccess(context,'Receipt copied'); }, text: 'Copy', buttonColor: Colors.white, textColor: Colors.black, hasBorder: true, borderColor: const Color(0xFFD0D5DD))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: AppButtons.button(onTap: () async => _exportReceipt(summary), text: 'Download', buttonColor: Colors.white, textColor: Colors.black, hasBorder: true, borderColor: const Color(0xFFD0D5DD))),
                const SizedBox(width: 10),
                Expanded(child: AppButtons.button(onTap: () => Navigator.pop(sheetContext), text: 'Continue', buttonColor: AppColors.commonBlack)),
              ]),
            ],
          ),
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
                                      final bookingId = widget.bookingId ?? "";
                                      setModalState(() => isSubmittingRating = true);
                                      await driverSearchController.rateDriver(
                                        bookingId: bookingId,
                                        rating: selectedRating.toString(),
                                        context: sheetContext,
                                      );
                                      if (mounted) {
                                        setModalState(() => isSubmittingRating = false);
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
            'https://hoppr-face-two-dbe557472d7f.herokuapp.com/api/customer/confirm-stripe-payment-response',
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
          'https://hoppr-face-two-dbe557472d7f.herokuapp.com/api/customer/confirm-stripe-payment-intents',
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
          'https://hoppr-face-two-dbe557472d7f.herokuapp.com/api/flutterwave/initialize',
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
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PaymentWebView(url: paymentLink)),
          );

          if (result != null && result["status"] == "success") {
            AppToasts.showSuccess(context,'Payment Successful');
            AppLogger.log.i("Payment Successful: ${result["transactionId"]}");
            await _completePaymentFlow(paymentMethod: 'FlutterWave', transactionId: result['transactionId']?.toString());
          } else {
            AppToasts.showError(context,"Payment failed or cancelled");
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
          'https://hoppr-face-two-dbe557472d7f.herokuapp.com/api/paystack/init',
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
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PaymentWebView(url: paymentLink)),
          );

          if (result != null && result["status"] == "success") {
            AppToasts.showSuccess(context,'Payment Successful');
            AppLogger.log.i("Payment Successful: ${result["transactionId"]}");
            await _completePaymentFlow(paymentMethod: 'Paystack', transactionId: result['transactionId']?.toString());
          } else {
            AppToasts.showError(context,"Payment failed or cancelled");
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
                      InkWell(
                        onTap:
                            payPalLoading
                                ? null
                                : () async {
                                  setState(() {
                                    payPalLoading = true;
                                    selectedIndex = 0;
                                  });

                                  await payPall();

                                  setState(() {
                                    payPalLoading = false;
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
                                  selectedIndex == 0
                                      ? Colors.black
                                      : AppColors.containerColor,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child:
                              payPalLoading
                                  ? Center(child: AppLoader.circularLoader())
                                  : Row(
                                    children: [
                                      Image.asset(
                                        AppImages.payPall,
                                        height: 24,
                                        width: 24,
                                      ),
                                      SizedBox(width: 10),

                                      CustomTextFields.textWithStylesSmall(
                                        'PayPal',
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(30),
                        onTap:
                            _isLoading
                                ? null
                                : () async {
                                  setState(() {
                                    _isLoading = true;
                                    selectedIndex = 2;
                                  });

                                  await makePayment();

                                  setState(() {
                                    _isLoading = false;
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
                                  selectedIndex == 2
                                      ? Colors.black
                                      : AppColors.containerColor,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child:
                              _isLoading
                                  ? Center(child: AppLoader.circularLoader())
                                  : Row(
                                    children: [
                                      Image.asset(AppImages.stripe),
                                      SizedBox(width: 10),
                                      CustomTextFields.textWithStylesSmall(
                                        'Stripe',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        colors: AppColors.commonBlack,
                                      ),
                                    ],
                                  ),
                        ),
                      ),
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
                    ],
                  ),

                  SizedBox(height: 15),

                  CustomTextFields.textWithStyles700('Card', fontSize: 16),
                  SizedBox(height: 15),
                  PackageContainer.customWalletContainer(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder:
                            (context) => _buildUnderDevelopmentDialog(context),
                      );
                    },

                    title: 'Add a new card',
                    textColor: AppColors.resendBlue,
                    fontWeight: FontWeight.w400,
                    leadingImagePath: AppImages.borderAdd,
                    trailing: Image.asset(
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
                    'Update your location on the hoppr home ppage to select address from a different city',
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

                          final result = await packageController.paymentDetails(
                            bookingId: widget.bookingId ?? '',
                            paymentType: 'WALLET',
                            context: context,
                          );

                          // call ONCE after success (adjust according to your API’s success contract)
                          if (result ==
                              '' /* success per your current code */ ) {
                            await _completePaymentFlow(paymentMethod: 'Wallet');
                          }
                          return;
                        }

                        if (selectedIndex == 3) {
                          // COD
                          final result = await packageController.paymentDetails(
                            bookingId: widget.bookingId ?? '',
                            paymentType: 'COD',
                            context: context,
                          );
                          // show ONCE after success
                          if (result == '' /* success */ ) {
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





