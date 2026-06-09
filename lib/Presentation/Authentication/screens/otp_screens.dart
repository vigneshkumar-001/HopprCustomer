import 'dart:async';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Presentation/Authentication/controller/otp_controller.dart';
import 'package:hopper/Presentation/Authentication/screens/otp_processing_screen.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:get/get.dart';
import 'package:smart_auth/smart_auth.dart';

class OtpScreens extends StatefulWidget {
  final String? countyCode;
  final String? mobileNumber;
  const OtpScreens({super.key, this.countyCode, this.mobileNumber});

  @override
  State<OtpScreens> createState() => _OtpScreensState();
}

class _OtpScreensState extends State<OtpScreens> {
  final formKey = GlobalKey<FormState>();
  TextEditingController otp = TextEditingController(text: "");
  bool isButtonDisabled = false;
  String verifyCode = '';
  StreamController<ErrorAnimationType>? errorController;
  String? otpError;
  late Timer _timer;
  int _start = 30;
  final OtpController otpController = Get.put(OtpController());
  bool _navigating = false;

  Future<void> _hideKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
  }

  Future<void> _startOtpVerification() async {
    if (_navigating) return;
    if (otp.text.length != 4) {
      errorController?.add(ErrorAnimationType.shake);
      setState(() {
        otpError = 'Please enter a valid 4-digit OTP';
      });
      return;
    }
    if (mounted) {
      setState(() {
        otpError = null;
        _navigating = true;
      });
    }
    await _hideKeyboard();
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (_, __, ___) => OtpProcessingScreen(
              mobileNumber: widget.mobileNumber ?? '',
              countryCode: widget.countyCode ?? '',
              otp: otp.text,
            ),
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 160),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
    if (!mounted) return;
    setState(() => _navigating = false);
  }

  @override
  void initState() {
    super.initState();

    _startTimer();
    // Auto-read the incoming OTP SMS, fill the boxes, and continue.
    _listenForOtp();
  }

  Future<void> _listenForOtp() async {
    try {
      final res = await SmartAuth.instance.getSmsWithUserConsentApi();
      if (!mounted || !res.hasData) return;
      final code =
          (res.requireData.code ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      if (code.length < 4) return;

      otp.text = code.substring(0, 4);
      if (mounted) setState(() => otpError = null);

      // Small pause so the filled boxes are visible, then auto-verify.
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) _startOtpVerification();
    } catch (_) {
      // Auto-read unavailable / cancelled — user can type manually.
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    try {
      SmartAuth.instance.removeUserConsentApiListener();
    } catch (_) {}
    otp.dispose();
    super.dispose();
  }

  void _resendOtp() {
    _timer.cancel(); // Cancel any running timer
    _sendOtp(); // Send the OTP first
    setState(() {
      _start = 30; // Restart the timer
    });
    _startTimer(); // Start countdown
  }

  void _sendOtp() {
    otpController.resend(
      code: widget.countyCode ?? '',
      mobileNumber: widget.mobileNumber ?? '',
    );
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_start > 0) {
        setState(() {
          _start--;
        });
      } else {
        _timer.cancel();
      }
    });
  }

  final FocusNode otpFocusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Obx(
          () =>
              otpController.isLoading.value
                  ? Center(child: AppLoader.appLoader())
                  : Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 20,
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,

                                  children: [
                                    AppButtons.backButton(context: context),
                                    SizedBox(height: 25),
                                    CustomTextFields.textWithStyles700(
                                      AppTexts.otpText,
                                      text1:
                                          ' ${widget.countyCode} ${widget.mobileNumber}',
                                    ),
                                    SizedBox(height: 30),

                                    Form(
                                      key: formKey,
                                      child: PinCodeTextField(
                                        focusNode: otpFocusNode,
                                        onCompleted: (value) {
                                          FocusScope.of(context).unfocus();
                                        },

                                        autoFocus: otp.text.isEmpty,

                                        appContext: context,
                                        // pastedTextStyle: TextStyle(
                                        //   color: Colors.green.shade600,
                                        //   fontWeight: FontWeight.bold,
                                        // ),
                                        length: 4,

                                        // obscureText: true,
                                        // obscuringCharacter: '*',
                                        // obscuringWidget: const FlutterLogo(size: 24,),
                                        blinkWhenObscuring: true,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        autoDisposeControllers: false,
                                        animationType: AnimationType.fade,

                                        // validator: (v) {
                                        //   if (v == null || v.length != 4)
                                        //     return 'Enter valid 4-digit OTP';
                                        //   return null;
                                        // },
                                        pinTheme: PinTheme(
                                          shape: PinCodeFieldShape.box,
                                          borderRadius: BorderRadius.circular(
                                            5.sp,
                                          ),
                                          fieldHeight: 48.sp,
                                          fieldWidth: 48.sp,
                                          selectedColor: AppColors.commonBlack,
                                          activeColor: AppColors.containerColor,
                                          activeFillColor:
                                              AppColors.containerColor,
                                          inactiveColor:
                                              AppColors.containerColor,
                                          selectedFillColor:
                                              AppColors.containerColor,
                                          fieldOuterPadding:
                                              EdgeInsets.symmetric(
                                                horizontal: 5,
                                              ),
                                          inactiveFillColor:
                                              AppColors.containerColor,
                                        ),
                                        cursorColor: Colors.black,
                                        animationDuration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        enableActiveFill: true,
                                        errorAnimationController:
                                            errorController,
                                        controller: otp,
                                        keyboardType: TextInputType.number,
                                        boxShadows: const [
                                          BoxShadow(
                                            offset: Offset(0, 1),
                                            color: Colors.black12,
                                            blurRadius: 5,
                                          ),
                                        ],
                                        // validator: (value) {
                                        //   if (value == null || value.length != 4) {
                                        //     return 'Please enter a valid 4-digit OTP';
                                        //   }
                                        //   return null;
                                        // },
                                        // onCompleted: (value) async {},
                                        onChanged: (value) {
                                          debugPrint(value);

                                          verifyCode = value;
                                          if (value.length == 4 &&
                                              otpError != null) {
                                            setState(() {
                                              otpError = null;
                                            });
                                          }
                                        },
                                        beforeTextPaste: (text) {
                                          debugPrint("Allowing to paste $text");
                                          return true;
                                        },
                                      ),
                                    ),
                                    if (otpError != null)
                                      Text(
                                        otpError!,
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    SizedBox(height: 20),

                                    _start > 0
                                        ? Text(
                                          '${AppTexts.youWillGetCodeBySmsIn} (00:${_start.toString().padLeft(2, '0')})',
                                        )
                                        : GestureDetector(
                                          onTap: _resendOtp,
                                          child: Text(
                                            AppTexts.resendCode,
                                            style: TextStyle(
                                              color: AppColors.resendBlue,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                  ],
                                ),
                              ),
                            ),
                            AppButtons.button(
                              onTap: () {
                                _startOtpVerification();

                                // if (otp.text.length != 4) {
                                //   errorController?.add(ErrorAnimationType.shake);
                                //   setState(() {
                                //     otpError = 'Please enter a valid 4-digit OTP';
                                //     isButtonDisabled = false;
                                //   });
                                //   return;
                                // }
                              },
                              text: AppTexts.verify,
                            ),
                          ],
                        ),
                      ),
                      if (_navigating)
                        Positioned.fill(
                          child: AbsorbPointer(
                            absorbing: true,
                            child: Container(
                              color: Colors.white54,
                              alignment: Alignment.center,
                              child: AppLoader.appLoader(),
                            ),
                          ),
                        ),
                    ],
                  ),
        ),
      ),
    );
  }
}
