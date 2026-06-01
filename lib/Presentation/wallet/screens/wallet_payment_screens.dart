import 'package:flutter/material.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/pay_pall_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
import 'package:hopper/Presentation/wallet/controller/wallet_controller.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/webview_page.dart';
import 'package:url_launcher/url_launcher.dart';

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
import 'dart:convert';
import 'package:get/get.dart';

class WalletPaymentScreens extends StatefulWidget {
  final String? clientSecret;
  final String? transactionId;
  final String? publishableKey;
  final int? amount;

  const WalletPaymentScreens({
    super.key,

    this.amount,
    required this.publishableKey,
    required this.transactionId,
    required this.clientSecret,
  });

  @override
  State<WalletPaymentScreens> createState() => _WalletPaymentScreensState();
}

class _WalletPaymentScreensState extends State<WalletPaymentScreens> {
  final DriverSearchController driverSearchController =
      DriverSearchController();
  final WalletController Controller = Get.put(WalletController());

  bool _isLoading = false;
  bool payPalLoading = false;
  bool payStackLoading = false;
  Map<String, dynamic>? paymentIntentData;
  Future<void> makePayment() async {
    try {
      paymentIntentData = await createPaymentIntent(widget.amount) ?? {};

      if (paymentIntentData == null ||
          paymentIntentData!['clientSecret'] == null) {
        AppLogger.log.e('❌ Payment intent data invalid: $paymentIntentData');
        return;
      }

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntentData!['clientSecret'],
          style: ThemeMode.light,
          merchantDisplayName: 'Hoppr',
        ),
      );

      await displayPaymentSheet();
    } catch (e, s) {
      AppLogger.log.e('❌ Stripe init failed: $e');
      AppLogger.log.e('Stack: $s');
    }
  }

  Future<void> displayPaymentSheet() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) {
      AppLogger.log.e('⚠️ Token not found');
      return;
    }

    try {
      // Present Stripe payment sheet
      await Stripe.instance.presentPaymentSheet();

      // Extract fields from backend response
      final transactionId = paymentIntentData?['transactionId'];
      final clientSecret = paymentIntentData?['clientSecret'];
      final paymentIntentId =
          clientSecret != null && clientSecret.contains('_secret')
              ? clientSecret.split('_secret').first
              : clientSecret;

      final customerId = paymentIntentData?['customer'];

      // Validate required fields
      if (transactionId == null ||
          paymentIntentId == null ||
          customerId == null) {
        AppLogger.log.e('❌ Missing required field(s) for wallet confirmation');
        return;
      }

      final body = jsonEncode({
        "transactionId": transactionId,
        "paymentIntentId": paymentIntentId,
        "customerId": customerId,
      });

      // Confirm payment on backend
      final response = await http.post(
        Uri.parse(ApiConsents.addToWalletResponse),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: body,
      );

      AppLogger.log.i('Confirm Payment Response: ${response.body}');

      if (response.statusCode == 200) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await Controller.getWalletBalance();

          AppLogger.log.i("✅ Payment successful");
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Payment Successful")));

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => CommonBottomNavigation(initialIndex: 2),
            ),
            (route) => false,
          );
        });
        AppLogger.log.i('✅ Payment confirmed successfully');
      } else {
        AppLogger.log.e(
          '❌ Failed to confirm payment response: ${response.body}',
        );
      }
    } catch (e, s) {
      AppLogger.log.e('❌ Error showing payment sheet: $e');
      AppLogger.log.e('Stack: $s');
    }
  }

  Color _borderFor(String method) {
    final isSelected = selectedPaymentMethod == method;
    return isSelected ? AppColors.resendBlue : AppColors.containerColor;
  }

  double _borderWidthFor(String method) {
    final isSelected = selectedPaymentMethod == method;
    return isSelected ? 2.0 : 1.0;
  }

  Future<Map<String, dynamic>?> createPaymentIntent(int? amount) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        AppLogger.log.e('⚠️ Token not found');
        return null;
      }

      final response = await http.post(
        Uri.parse(ApiConsents.addToWallet),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'amount': amount, 'method': "STRIPE"}),
      );

      AppLogger.log.i('Status code: ${response.statusCode}');
      AppLogger.log.i('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        AppLogger.log.i('Decoded payment intent response: $decoded');
        return decoded;
      } else {
        final decoded = jsonDecode(response.body);
        final message = decoded['message'] ?? 'Failed to create payment intent';

        // Show toast/snackbar/dialog with message
        AppLogger.log.e('❌ Payment failed: $message');
        AppToasts.showError(context,message); // or your own UI alert handler

        return null; // Don’t throw; handle gracefully
      }
    } catch (err) {
      AppLogger.log.e('err charging user: $err');
      return null;
    }
  }

  /*  Future<void> makePayment() async {
    try {
      await Stripe.instance.presentPaymentSheet();

      // confirm payment to your backend
      await confirmPayment(widget.transactionId ?? "");

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Controller.getWalletBalance();

        AppLogger.log.i("✅ Payment successful");
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Payment Successful")));

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => CommonBottomNavigation(initialIndex: 2),
          ),
          (route) => false,
        );
      });
    } catch (e) {
      AppLogger.log.e("❌ Stripe error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Payment Failed")));
    }
  }

  Future<void> confirmPayment(String transactionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final String url = ApiConsents.addToWalletResponse;

      // Extract the PaymentIntent ID (remove the _secret part)
      final clientSecret = widget.clientSecret ?? "";
      final paymentIntentId =
          clientSecret.contains("_secret")
              ? clientSecret.split("_secret").first
              : clientSecret;

      final response = await http.post(
        Uri.parse(url),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "transactionId": transactionId,
          "paymentIntentId": paymentIntentId,
        }),
      );

      AppLogger.log.i(
        "📩 Confirm Payment API response: ${response.statusCode}",
      );
      AppLogger.log.i("📩 Response body: ${response.body}");
    } catch (e) {
      AppLogger.log.e("❌ Error in confirmPayment: $e");
    }
  }*/

  Future<void> payPall() async {
    // Navigator.push(
    //   context,
    //   MaterialPageRoute(
    //     builder:
    //         (context) => PaypalWebviewPage(
    //           amount: widget.amount.toString() ?? '',
    //           bookingId: widget.bookingId ?? '',
    //         ),
    //   ),
    // );
  }

  bool flutterWaveLoading = false;
  Future<void> payWithFlutterWave() async {
    final prefs = await SharedPreferences.getInstance();

    String? email = prefs.getString('flutterwave_email');
    String? name = prefs.getString('flutterwave_name');
    String? phone = prefs.getString('flutterwave_phone');

    // If any field is empty, show bottom sheet to enter info
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

      // If user canceled bottom sheet, stop
      if (result != true) return;

      // After saving, read values again
      email = prefs.getString('flutterwave_email');
      name = prefs.getString('flutterwave_name');
      phone = prefs.getString('flutterwave_phone');
    }

    setState(() => flutterWaveLoading = true);

    try {
      String? token = prefs.getString('token');
      final response = await http.post(
        Uri.parse(
          'https://bk.myhoppr.com/api/flutterwave/wallet/initialize',
        ),
        headers: {
          "Content-Type": "application/json",
          if (token != null)
            "Authorization": "Bearer $token", // ✅ Add Bearer token
        },
        body: jsonEncode({
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
            MaterialPageRoute(
              builder: (_) => PaymentWebView(url: paymentLink, page: 'walet'),
            ),
          );

          if (result != null && result["status"] == "success") {
            AppToasts.showSuccess(context,'Payment Successful');
            AppLogger.log.i("Payment Successful: ${result["transaction_id"]}");

            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => CommonBottomNavigation(initialIndex: 2),
              ),
              (route) => false,
            );
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

  String? _emailError;
  String? _nameError;
  String? _phoneError;
  bool _isValidEmail(String email) {
    final e = email.trim();
    return RegExp(r'^[\w\.\-+]+@([\w\-]+\.)+[A-Za-z]{2,}$').hasMatch(e);
  }

  Future<bool?> _showUserInfoBottomSheet(
    BuildContext context,
    String? email,
    String? name,
    String? phone,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPhone = prefs.getString('phone'); // stored phone

    // ✅ Prefer passed phone, else savedPhone, else empty
    final initialPhone =
        (phone != null && phone.trim().isNotEmpty) ? phone : (savedPhone ?? "");

    final emailController = TextEditingController(text: email ?? "");
    final nameController = TextEditingController(text: name ?? "");
    final phoneController = TextEditingController(text: initialPhone);

    bool isValidEmail(String v) {
      return RegExp(
        r'^[\w\.\-+]+@([\w\-]+\.)+[A-Za-z]{2,}$',
      ).hasMatch(v.trim());
    }

    bool isValidPhone(String v) {
      return RegExp(r'^\+?\d{8,15}$').hasMatch(v.trim());
    }

    String? emailError;
    String? nameError;
    String? phoneError;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(25),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 25,
                ),
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
                    const SizedBox(height: 15),
                    const Text(
                      "Enter Payment Info",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 25),

                    // ✅ Email
                    _buildTextField(
                      emailController,
                      "Email",
                      Icons.email,
                      TextInputType.emailAddress,
                      errorText: emailError,
                      onChanged: (v) {
                        setModalState(() {
                          if (v.trim().isEmpty) {
                            emailError = "Email is required";
                          } else if (!isValidEmail(v)) {
                            emailError = "Enter a valid email";
                          } else {
                            emailError = null;
                          }
                        });
                      },
                    ),

                    const SizedBox(height: 15),

                    // ✅ Name
                    _buildTextField(
                      nameController,
                      "Name",
                      Icons.person,
                      TextInputType.name,
                      errorText: nameError,
                      onChanged: (v) {
                        setModalState(() {
                          nameError =
                              v.trim().isEmpty ? "Name is required" : null;
                        });
                      },
                    ),

                    const SizedBox(height: 15),

                    // ✅ Phone (prefilled from prefs and editable)
                    _buildTextField(
                      phoneController,
                      "Phone",
                      Icons.phone,
                      TextInputType.phone,
                      errorText: phoneError,
                      onChanged: (v) {
                        setModalState(() {
                          if (v.trim().isEmpty) {
                            phoneError = "Phone is required";
                          } else if (!isValidPhone(v)) {
                            phoneError = "Enter a valid phone number";
                          } else {
                            phoneError = null;
                          }
                        });
                      },
                    ),

                    const SizedBox(height: 25),

                    AppButtons.button(
                      onTap: () async {
                        final e = emailController.text.trim();
                        final n = nameController.text.trim();
                        final p = phoneController.text.trim();

                        setModalState(() {
                          emailError =
                              e.isEmpty
                                  ? "Email is required"
                                  : (!isValidEmail(e)
                                      ? "Enter a valid email"
                                      : null);

                          nameError = n.isEmpty ? "Name is required" : null;

                          phoneError =
                              p.isEmpty
                                  ? "Phone is required"
                                  : (!isValidPhone(p)
                                      ? "Enter a valid phone number"
                                      : null);
                        });

                        if (emailError != null ||
                            nameError != null ||
                            phoneError != null) {
                          return;
                        }

                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('flutterwave_email', e);
                        await prefs.setString('flutterwave_name', n);

                        // ✅ Save edited phone in both keys
                        await prefs.setString('flutterwave_phone', p);
                        await prefs.setString('phone', p);

                        Navigator.pop(context, true);
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
      },
    );
  }

  // Future<bool?> _showUserInfoBottomSheet(
  //   BuildContext context,
  //   String? email,
  //   String? name,
  //   String? phone,
  // ) async {
  //   final prefs = await SharedPreferences.getInstance();
  //   final savedPhone = prefs.getString('phone'); // ✅ this is your stored phone
  //   final emailController = TextEditingController(text: email);
  //   final nameController = TextEditingController(text: name);
  //   final phoneController = TextEditingController(text: phone);
  //
  //   bool isValidEmail(String v) {
  //     return RegExp(
  //       r'^[\w\.\-+]+@([\w\-]+\.)+[A-Za-z]{2,}$',
  //     ).hasMatch(v.trim());
  //   }
  //
  //   bool isValidPhone(String v) {
  //     return RegExp(r'^\+?\d{8,15}$').hasMatch(v.trim());
  //   }
  //
  //   String? emailError;
  //   String? nameError;
  //   String? phoneError;
  //
  //   return showModalBottomSheet<bool>(
  //     context: context,
  //     isScrollControlled: true,
  //     backgroundColor: Colors.transparent,
  //     builder: (context) {
  //       return StatefulBuilder(
  //         builder: (context, setModalState) {
  //           return Padding(
  //             padding: EdgeInsets.only(
  //               bottom: MediaQuery.of(context).viewInsets.bottom,
  //             ),
  //             child: Container(
  //               decoration: BoxDecoration(
  //                 color: Colors.white,
  //                 borderRadius: const BorderRadius.vertical(
  //                   top: Radius.circular(25),
  //                 ),
  //                 boxShadow: const [
  //                   BoxShadow(
  //                     color: Colors.black26,
  //                     blurRadius: 10,
  //                     offset: Offset(0, -4),
  //                   ),
  //                 ],
  //               ),
  //               padding: const EdgeInsets.symmetric(
  //                 horizontal: 20,
  //                 vertical: 25,
  //               ),
  //               child: Column(
  //                 mainAxisSize: MainAxisSize.min,
  //                 children: [
  //                   Container(
  //                     width: 50,
  //                     height: 5,
  //                     decoration: BoxDecoration(
  //                       color: Colors.grey[300],
  //                       borderRadius: BorderRadius.circular(10),
  //                     ),
  //                   ),
  //                   const SizedBox(height: 15),
  //                   const Text(
  //                     "Enter Payment Info",
  //                     style: TextStyle(
  //                       fontSize: 20,
  //                       fontWeight: FontWeight.bold,
  //                       color: Colors.black87,
  //                     ),
  //                   ),
  //                   const SizedBox(height: 25),
  //
  //                   // ✅ Email
  //                   _buildTextField(
  //                     emailController,
  //                     "Email",
  //                     Icons.email,
  //                     TextInputType.emailAddress,
  //                     errorText: emailError,
  //                     onChanged: (v) {
  //                       setModalState(() {
  //                         if (v.trim().isEmpty) {
  //                           emailError = "Email is required";
  //                         } else if (!isValidEmail(v)) {
  //                           emailError = "Enter a valid email";
  //                         } else {
  //                           emailError = null;
  //                         }
  //                       });
  //                     },
  //                   ),
  //
  //                   const SizedBox(height: 15),
  //
  //                   // ✅ Name
  //                   _buildTextField(
  //                     nameController,
  //                     "Name",
  //                     Icons.person,
  //                     TextInputType.name,
  //                     errorText: nameError,
  //                     onChanged: (v) {
  //                       setModalState(() {
  //                         nameError =
  //                             v.trim().isEmpty ? "Name is required" : null;
  //                       });
  //                     },
  //                   ),
  //
  //                   const SizedBox(height: 15),
  //
  //                   // ✅ Phone
  //                   _buildTextField(
  //                     phoneController,
  //                     "Phone",
  //                     Icons.phone,
  //                     TextInputType.phone,
  //                     errorText: phoneError,
  //                     onChanged: (v) {
  //                       setModalState(() {
  //                         if (v.trim().isEmpty) {
  //                           phoneError = "Phone is required";
  //                         } else if (!isValidPhone(v)) {
  //                           phoneError = "Enter a valid phone number";
  //                         } else {
  //                           phoneError = null;
  //                         }
  //                       });
  //                     },
  //                   ),
  //
  //                   const SizedBox(height: 25),
  //
  //                   AppButtons.button(
  //                     onTap: () async {
  //                       // final validation on save too
  //                       final e = emailController.text.trim();
  //                       final n = nameController.text.trim();
  //                       final p = phoneController.text.trim();
  //
  //                       setModalState(() {
  //                         emailError =
  //                             e.isEmpty
  //                                 ? "Email is required"
  //                                 : (!isValidEmail(e)
  //                                     ? "Enter a valid email"
  //                                     : null);
  //
  //                         nameError = n.isEmpty ? "Name is required" : null;
  //
  //                         phoneError =
  //                             p.isEmpty
  //                                 ? "Phone is required"
  //                                 : (!isValidPhone(p)
  //                                     ? "Enter a valid phone number"
  //                                     : null);
  //                       });
  //
  //                       if (emailError != null ||
  //                           nameError != null ||
  //                           phoneError != null) {
  //                         return;
  //                       }
  //
  //                       final prefs = await SharedPreferences.getInstance();
  //                       await prefs.setString('flutterwave_email', e);
  //                       await prefs.setString('flutterwave_name', n);
  //                       await prefs.setString('flutterwave_phone', p);
  //
  //                       Navigator.pop(context, true);
  //                     },
  //                     text: 'Save & Continue',
  //                   ),
  //
  //                   const SizedBox(height: 20),
  //                 ],
  //               ),
  //             ),
  //           );
  //         },
  //       );
  //     },
  //   );
  // }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon,
    TextInputType type, {
    String? errorText,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: AppColors.commonBlack),
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[700]),
        filled: true,
        fillColor: Colors.grey[100],
        errorText: errorText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 15,
        ),
      ),
    );
  }

  // Future<bool?> _showUserInfoBottomSheet(
  //   BuildContext context,
  //   String? email,
  //   String? name,
  //   String? phone,
  // )
  // {
  //   final _emailController = TextEditingController(text: email);
  //   final _nameController = TextEditingController(text: name);
  //   final _phoneController = TextEditingController(text: phone);
  //
  //   return showModalBottomSheet<bool>(
  //     context: context,
  //     isScrollControlled: true,
  //     backgroundColor: Colors.transparent, // Transparent to get rounded corners
  //     builder: (context) {
  //       return Padding(
  //         padding: EdgeInsets.only(
  //           bottom: MediaQuery.of(context).viewInsets.bottom,
  //         ),
  //         child: Container(
  //           decoration: BoxDecoration(
  //             color: Colors.white,
  //             borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
  //             boxShadow: [
  //               BoxShadow(
  //                 color: Colors.black26,
  //                 blurRadius: 10,
  //                 offset: Offset(0, -4),
  //               ),
  //             ],
  //           ),
  //           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
  //           child: Column(
  //             mainAxisSize: MainAxisSize.min,
  //             children: [
  //               Container(
  //                 width: 50,
  //                 height: 5,
  //                 decoration: BoxDecoration(
  //                   color: Colors.grey[300],
  //                   borderRadius: BorderRadius.circular(10),
  //                 ),
  //               ),
  //               SizedBox(height: 15),
  //               Text(
  //                 "Enter Payment Info",
  //                 style: TextStyle(
  //                   fontSize: 20,
  //                   fontWeight: FontWeight.bold,
  //                   color: Colors.black87,
  //                 ),
  //               ),
  //               SizedBox(height: 25),
  //               _buildTextField(
  //                 _emailController,
  //                 "Email",
  //                 Icons.email,
  //                 TextInputType.emailAddress,
  //                 errorText: _emailError,
  //                 onChanged: (v) {
  //                   setState(() {
  //                     if (v.trim().isEmpty) {
  //                       _emailError = "Email is required";
  //                     } else if (!_isValidEmail(v)) {
  //                       _emailError = "Enter a valid email";
  //                     } else {
  //                       _emailError = null;
  //                     }
  //                   });
  //                 },
  //               ),
  //               SizedBox(height: 15),
  //               _buildTextField(
  //                 onChanged: (v) {},
  //                 _nameController,
  //                 "Name",
  //                 Icons.person,
  //                 TextInputType.name,
  //               ),
  //               SizedBox(height: 15),
  //               _buildTextField(
  //                 onChanged: (v) {},
  //                 _phoneController,
  //                 "Phone",
  //                 Icons.phone,
  //                 TextInputType.phone,
  //               ),
  //               SizedBox(height: 25),
  //               AppButtons.button(
  //                 onTap: () async {
  //                   if (_emailController.text.isEmpty ||
  //                       _nameController.text.isEmpty ||
  //                       _phoneController.text.isEmpty) {
  //                     AppToasts.showError("All fields are required");
  //                     return;
  //                   }
  //
  //                   if (!_isValidEmail(_emailController.text)) {
  //                     AppToasts.showError("Please enter a valid email");
  //                     return;
  //                   }
  //                   final prefs = await SharedPreferences.getInstance();
  //                   await prefs.setString(
  //                     'flutterwave_email',
  //                     _emailController.text,
  //                   );
  //                   await prefs.setString(
  //                     'flutterwave_name',
  //                     _nameController.text,
  //                   );
  //                   await prefs.setString(
  //                     'flutterwave_phone',
  //                     _phoneController.text,
  //                   );
  //
  //                   Navigator.pop(context, true);
  //                 },
  //                 text: 'Save & Continue',
  //               ),
  //
  //               SizedBox(height: 20),
  //             ],
  //           ),
  //         ),
  //       );
  //     },
  //   );
  // }

  //
  // Widget _buildTextField(
  //   TextEditingController controller,
  //   String label,
  //   IconData icon,
  //   TextInputType type,
  // ) {
  //   return TextField(
  //     controller: controller,
  //     keyboardType: type,
  //     decoration: InputDecoration(
  //       prefixIcon: Icon(icon, color: AppColors.commonBlack),
  //       labelText: label,
  //       labelStyle: TextStyle(color: Colors.grey[700]),
  //       filled: true,
  //       fillColor: Colors.grey[100],
  //       border: OutlineInputBorder(
  //         borderRadius: BorderRadius.circular(15),
  //         borderSide: BorderSide.none,
  //       ),
  //       contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
  //     ),
  //   );
  // }

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
          'https://bk.myhoppr.com/api/paystack/wallet/initialize',
        ),
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token", 
        },
        body: jsonEncode({"amount": widget.amount, "email": email}),
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
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              // await Controller.getWalletBalance();

              AppLogger.log.i("✅ Payment successful");
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text("Payment Successful")));

              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => CommonBottomNavigation(initialIndex: 2),
                ),
                (route) => false,
              );
            });
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

  @override
  void initState() {
    super.initState();
  }

  String? selectedPaymentMethod;

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
                      SizedBox(width: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CustomTextFields.textWithStyles700(
                            'Hoppr',
                            fontSize: 20,
                          ),
                          CustomTextFields.textWithStylesSmall(
                            'Hoppr Trusted Business',
                          ),
                        ],
                      ),

                      Spacer(),
                      // Image.asset(AppImages.history, height: 20, width: 20),
                    ],
                  ),

                  const SizedBox(height: 30),

                  CustomTextFields.textWithStyles700(
                    'Recommended',
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
                      //             });
                      //
                      //             await payPall();
                      //
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
                      //       border: Border.all(color: AppColors.containerColor),
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
                      //
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
                        onTap:
                            flutterWaveLoading
                                ? null
                                : () async {
                                  setState(() {
                                    selectedPaymentMethod = "FLUTTERWAVE";
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
                            border: Border.all(
                              color: _borderFor("FLUTTERWAVE"),
                              width: _borderWidthFor("FLUTTERWAVE"),
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Image.asset(
                                AppImages.flutter_wave,
                                height: 24,
                                width: 40,
                              ),
                              SizedBox(width: 10),
                              CustomTextFields.textWithStylesSmall(
                                'Flutter Wave',
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap:
                            payStackLoading
                                ? null
                                : () async {
                                  setState(() {
                                    selectedPaymentMethod = "PAYSTACK";
                                    payStackLoading = true;
                                  });

                                  await payWithPayStack();

                                  setState(() => payStackLoading = false);
                                },
                        child: Container(
                          height: 50,
                          width: 170,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.commonWhite,
                            border: Border.all(
                              color: _borderFor("PAYSTACK"),
                              width: _borderWidthFor("PAYSTACK"),
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child:
                              payStackLoading
                                  ? Center(child: AppLoader.circularLoader())
                                  : Row(
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

                      // InkWell(
                      //   borderRadius: BorderRadius.circular(30),
                      //   onTap:
                      //       _isLoading
                      //           ? null
                      //           : () async {
                      //             setState(() {
                      //
                      //               selectedPaymentMethod = "Stripe";
                      //               _isLoading = true;
                      //             });
                      //
                      //             await makePayment();
                      //
                      //             setState(() {
                      //               _isLoading = false;
                      //             });
                      //           },
                      //   child: Container(
                      //     height: 50,
                      //     width: 170,
                      //     padding: EdgeInsets.all(10),
                      //     decoration: BoxDecoration(
                      //       color: AppColors.commonWhite,
                      //       border: Border.all(
                      //         color: _borderFor("STRIPE"),
                      //         width: _borderWidthFor("STRIPE"),
                      //       ),
                      //       borderRadius: BorderRadius.circular(10),
                      //     ),
                      //     child:
                      //         _isLoading
                      //             ? Center(child: AppLoader.circularLoader())
                      //             : Row(
                      //               children: [
                      //                 Image.asset(AppImages.stripe),
                      //                 SizedBox(width: 10),
                      //                 CustomTextFields.textWithStylesSmall(
                      //                   'Stripe',
                      //                   fontSize: 16,
                      //                   fontWeight: FontWeight.w500,
                      //                   colors: AppColors.commonBlack,
                      //                 ),
                      //               ],
                      //             ),
                      //   ),
                      // ),
                      // InkWell(
                      //   borderRadius: BorderRadius.circular(30),
                      //   onTap:
                      //       payStackLoading
                      //           ? null
                      //           : () async {
                      //             setState(() {
                      //               payStackLoading = true;
                      //               // selectedIndex = 4;
                      //             });
                      //             await payWithPayStack();
                      //             setState(() {
                      //               payStackLoading = false;
                      //             });
                      //           },
                      //   child: Container(
                      //     height: 50,
                      //     width: 170,
                      //     padding: EdgeInsets.all(10),
                      //     decoration: BoxDecoration(
                      //       color: AppColors.commonWhite,
                      //       border: Border.all(color: AppColors.containerColor),
                      //       borderRadius: BorderRadius.circular(10),
                      //     ),
                      //     child:
                      //         payStackLoading
                      //             ? Center(child: AppLoader.circularLoader())
                      //             : Row(
                      //               children: [
                      //                 Image.asset(AppImages.payStack),
                      //                 SizedBox(width: 10),
                      //                 CustomTextFields.textWithStylesSmall(
                      //                   'paystack',
                      //                   fontSize: 16,
                      //                   fontWeight: FontWeight.w500,
                      //                   colors: AppColors.commonBlack,
                      //                 ),
                      //               ],
                      //             ),
                      //   ),
                      // ),
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
                            (context) =>
                                PackageContainer.buildUnderDevelopmentDialog(
                                  context,
                                ),
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

                  /*   CustomTextFields.textWithStyles700('Wallets', fontSize: 16),
                  SizedBox(height: 15),
                  PackageContainer.customWalletContainer(
                    onTap: () {},
                    title: 'Hoppr Wallet',

                    leadingImagePath: AppImages.wallet,
                    trailing: CustomTextFields.textWithImage(
                      fontWeight: FontWeight.w600,
                      text: '0.0',
                      colors: AppColors.walletCurrencyColor,
                      imagePath: AppImages.nBlackCurrency,
                      imageColors: AppColors.walletCurrencyColor,
                    ),
                  ),*/
                  SizedBox(height: 15),
                  PackageContainer.customWalletContainer(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder:
                            (context) =>
                                PackageContainer.buildUnderDevelopmentDialog(
                                  context,
                                ),
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
                  Center(
                    child: CustomTextFields.textWithStylesSmall(
                      'Secured by (Payment Getway) Account & Terms',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: SizedBox(
          height: 100,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 5),
                    CustomTextFields.textWithImage(
                      text: widget.amount.toString() ?? '0',
                      fontSize: 25,
                      colors: AppColors.commonBlack,
                      fontWeight: FontWeight.w700,
                      imageSize: 23,
                      imagePath: AppImages.nBlackCurrency,
                    ),

                    // Row(
                    //   children: [
                    //     GestureDetector(
                    //       onTap: () {
                    //         // Handle view details tap here
                    //       },
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
                Expanded(
                  child: AppButtons.button(
                    onTap: () {
                      if (selectedPaymentMethod == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Please select a payment method"),
                          ),
                        );
                        return;
                      }
                    },
                    text: 'Continue',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
