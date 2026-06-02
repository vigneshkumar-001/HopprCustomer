import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Presentation/Authentication/controller/otp_controller.dart';
import 'package:hopper/Presentation/Authentication/screens/post_otp_routing_screen.dart';

class OtpProcessingScreen extends StatefulWidget {
  final String mobileNumber;
  final String countryCode;
  final String otp;

  const OtpProcessingScreen({
    super.key,
    required this.mobileNumber,
    required this.countryCode,
    required this.otp,
  });

  @override
  State<OtpProcessingScreen> createState() => _OtpProcessingScreenState();
}

class _OtpProcessingScreenState extends State<OtpProcessingScreen> {
  late final OtpController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = Get.find<OtpController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verify();
    });
  }

  Future<void> _verify() async {
    if (_started || !mounted) return;
    _started = true;

    await _controller.otpVerify(
      mobileNumber: widget.mobileNumber,
      context: context,
      countryCode: widget.countryCode,
      otp: widget.otp,
      onSuccess: () async {
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const PostOtpRoutingScreen(),
            transitionDuration: const Duration(milliseconds: 220),
            reverseTransitionDuration: const Duration(milliseconds: 180),
            transitionsBuilder: (_, animation, __, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              );
              return FadeTransition(opacity: curved, child: child);
            },
          ),
        );
      },
      onError: (_) {
        if (!mounted) return;
        Navigator.of(context).pop('otp_error');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppLoader.appLoader(),
              const SizedBox(height: 16),
              const Text(
                'Verifying OTP...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
