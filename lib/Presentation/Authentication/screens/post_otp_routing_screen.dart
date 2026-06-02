import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Presentation/Authentication/controller/location_gate_controller.dart';
import 'package:hopper/Presentation/Authentication/screens/permission_screens.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';

class PostOtpRoutingScreen extends StatefulWidget {
  const PostOtpRoutingScreen({super.key});

  @override
  State<PostOtpRoutingScreen> createState() => _PostOtpRoutingScreenState();
}

class _PostOtpRoutingScreenState extends State<PostOtpRoutingScreen> {
  bool _navigated = false;

  Future<void> _hideKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveNext();
    });
  }

  Future<void> _resolveNext() async {
    if (_navigated || !mounted) return;

    final gate = Get.find<LocationGateController>();
    await gate.checkNow();
    if (!mounted || _navigated) return;

    await _hideKeyboard();
    if (!mounted || _navigated) return;

    final Widget next =
        gate.isReady.value
            ? const CommonBottomNavigation()
            : const PermissionScreens();

    _navigated = true;
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => next,
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
                'Signing you in...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
