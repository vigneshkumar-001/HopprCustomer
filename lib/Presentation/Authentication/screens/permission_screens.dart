import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';

import '../controller/location_gate_controller.dart';

class PermissionScreens extends StatefulWidget {
  const PermissionScreens({super.key});

  @override
  State<PermissionScreens> createState() => _PermissionScreensState();
}

class _PermissionScreensState extends State<PermissionScreens> {
  bool isLoading = false;
  late final LocationGateController gate;
  late final Worker _readyWorker;

  @override
  void initState() {
    super.initState();
    gate = Get.find<LocationGateController>();

    // ✅ If already enabled -> auto navigate
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await gate.checkNow(); // controller will close dialogs + set isReady
      if (!mounted) return;
      if (gate.isReady.value) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CommonBottomNavigation()),
        );
      }
    });

    // ✅ If user enables from settings later -> auto navigate too
    _readyWorker = ever<bool>(gate.isReady, (ready) {
      if (ready && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CommonBottomNavigation()),
        );
      }
    });
  }

  @override
  void dispose() {
    _readyWorker.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    if (isLoading) return;
    setState(() => isLoading = true);

    await gate.checkNow();

    if (!mounted) return;
    setState(() => isLoading = false);

    if (gate.isReady.value) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CommonBottomNavigation()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppButtons.backButton(context: context),
                      Image.asset(AppImages.location),
                      CustomTextFields.textWithStyles700(
                        AppTexts.locationPermission,
                      ),
                      const SizedBox(height: 20),
                      CustomTextFields.textWithStylesSmall(
                        AppTexts.locationPermissionContent,
                      ),
                    ],
                  ),
                ),
              ),
              isLoading
                  ? AppLoader.appLoader()
                  : AppButtons.button(
                onTap: _onContinue,
                text: AppTexts.continues,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:hopper/Core/Consents/app_texts.dart';
// import 'package:hopper/Core/Utility/app_buttons.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/Core/Utility/app_loader.dart';
// import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
// import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
//
// import '../controller/location_gate_controller.dart';
//
// class PermissionScreens extends StatefulWidget {
//   const PermissionScreens({super.key});
//
//   @override
//   State<PermissionScreens> createState() => _PermissionScreensState();
// }
//
// class _PermissionScreensState extends State<PermissionScreens> {
//   bool isLoading = false;
//   late final LocationGateController gate;
//
//   @override
//   void initState() {
//     super.initState();
//     gate = Get.find<LocationGateController>();
//   }
//
//   Future<void> _onContinue() async {
//     if (isLoading) return;
//     setState(() => isLoading = true);
//
//     // ✅ This will show Android permission popup (requestPermission)
//     // ✅ If GPS is off -> controller shows its non-skippable dialog + opens settings
//     await gate.checkNow();
//
//     if (!mounted) return;
//     setState(() => isLoading = false);
//
//     // ✅ Only go next if location fully ready
//     if (gate.isReady.value) {
//       Navigator.pushReplacement(
//         context,
//         MaterialPageRoute(builder: (_) => const CommonBottomNavigation()),
//       );
//     }
//     // else do nothing (user must enable)
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: SafeArea(
//         child: Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
//           child: Column(
//             children: [
//               Expanded(
//                 child: SingleChildScrollView(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       AppButtons.backButton(context: context),
//                       Image.asset(AppImages.location),
//                       CustomTextFields.textWithStyles700(
//                         AppTexts.locationPermission,
//                       ),
//                       const SizedBox(height: 20),
//                       CustomTextFields.textWithStylesSmall(
//                         AppTexts.locationPermissionContent,
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//               isLoading
//                   ? AppLoader.appLoader()
//                   : AppButtons.button(
//                 onTap: _onContinue,
//                 text: AppTexts.continues,
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
//