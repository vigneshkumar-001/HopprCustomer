// TutorialService_widgets.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:hopper/Core/Utility/app_showcase_key.dart';

class TutorialService {
  static bool _isShown = false;
  static bool _isActive = false;
  static TutorialCoachMark? _tutorial;

  static bool get isActive => _isActive;
  static bool get isPending => _tutorial != null && !_isShown;

  /// Show main tab tutorial
  static Future<void> showTutorial(
      BuildContext context, {
        required ShowcaseKeys keys,
      }) async {
    // Single-flight: prevent showing/creating the tutorial twice.
    if (_isShown || _tutorial != null) return;

    final prefs = await SharedPreferences.getInstance();
    final isFirstTime = prefs.getBool("tutorialShown") ?? true;
    if (!isFirstTime) return;

    _tutorial = TutorialCoachMark(
      targets: _createTargets(keys),
      colorShadow: Colors.black.withOpacity(0.5),
      opacityShadow: 0.5,
      textSkip: "Skip",
      paddingFocus: 8,
      onSkip: () {
        SharedPreferences.getInstance().then((prefs) async {
          await prefs.setBool("tutorialShown", false);
          _isShown = true;
          _isActive = false;
          _tutorial = null;
        });
        return true;
      },
      onFinish: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool("tutorialShown", false);
        _isShown = true;
        _isActive = false;
        _tutorial = null;
        return true;
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only show when targets exist in the tree (prevents instant hide).
      if (!_areTargetsReady(keys)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_areTargetsReady(keys)) {
            _isActive = true;
            _tutorial?.show(context: context);
          }
        });
        return;
      }
      _isActive = true;
      _tutorial?.show(context: context);
    });
  }

  /// Show profile-specific tutorial
  static Future<void> showProfileTutorial(
      BuildContext context, {
        required ShowcaseKeys keys,
      }) async {
    // Single-flight: prevent showing/creating the tutorial twice.
    if (_isShown || _tutorial != null) return;

    final prefs = await SharedPreferences.getInstance();
    final isFirstTime = prefs.getBool("profileTutorialShown") ?? true;
    if (!isFirstTime) return;

    _tutorial = TutorialCoachMark(
      targets: _profileTargets(keys),
      colorShadow: Colors.black.withOpacity(0.5),
      opacityShadow: 0.5,
      textSkip: "Skip",
      paddingFocus: 8,

      onSkip: () {
        SharedPreferences.getInstance().then((prefs) async {
          await prefs.setBool("tutorialShown", false);
          _isShown = true;
          _isActive = false;
          _tutorial = null;
        });
        return true;
      },
      onFinish: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool("tutorialShown", false);
        _isShown = true;
        _isActive = false;
        _tutorial = null;
        return true;
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_areProfileTargetsReady(keys)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_areProfileTargetsReady(keys)) {
            _isActive = true;
            _tutorial?.show(context: context);
          }
        });
        return;
      }
      _isActive = true;
      _tutorial?.show(context: context);
    });
  }

  static bool _areTargetsReady(ShowcaseKeys keys) {
    return keys.homeTab.currentContext != null &&
        keys.rideTab.currentContext != null &&
        keys.walletTab.currentContext != null &&
        keys.packageTab.currentContext != null &&
        keys.profileTabBottom.currentContext != null;
  }

  static bool _areProfileTargetsReady(ShowcaseKeys keys) {
    return keys.profileEditButton.currentContext != null &&
        keys.profileImage.currentContext != null;
  }

  // -------- Targets (now use instance keys) --------
  static List<TargetFocus> _profileTargets(ShowcaseKeys keys) {
    return [
      TargetFocus(
        identify: "profileEditButton",
        keyTarget: keys.profileEditButton,
        shape: ShapeLightFocus.RRect,
        radius: 8,
        enableOverlayTab: true,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => _buildCard(
              title: "Edit Profile",
              description: "Tap here to edit your profile details",
              controller: controller,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "profileImage",
        keyTarget: keys.profileImage,
        shape: ShapeLightFocus.Circle,
        enableOverlayTab: true,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => _buildCard(
              title: "Profile Image",
              description: "Tap here to change your profile picture",
              controller: controller,
            ),
          ),
        ],
      ),
    ];
  }

  static List<TargetFocus> _createTargets(ShowcaseKeys keys) {
    return [
      TargetFocus(
        identify: "homeTab",
        keyTarget: keys.homeTab,
        shape: ShapeLightFocus.Circle,
        enableOverlayTab: false,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => _buildCard(
              title: "Home Tab",
              description: "Tap here to go to Home screen",
              controller: controller,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "rideTab",
        keyTarget: keys.rideTab,
        shape: ShapeLightFocus.Circle,
        enableOverlayTab: false,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => _buildCard(
              title: "Ride Tab",
              description: "Tap here to book or view rides",
              controller: controller,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "walletTab",
        keyTarget: keys.walletTab,
        shape: ShapeLightFocus.Circle,
        enableOverlayTab: false,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => _buildCard(
              title: "Wallet Tab",
              description: "Check your wallet balance and transactions",
              controller: controller,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "packageTab",
        keyTarget: keys.packageTab,
        shape: ShapeLightFocus.Circle,
        enableOverlayTab: false,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => _buildCard(
              title: "Package Tab",
              description: "View your packages here",
              controller: controller,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "profileTab",
        keyTarget: keys.profileTabBottom,
        shape: ShapeLightFocus.Circle,
        enableOverlayTab: false,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => _buildCard(
              title: "Profile Tab",
              description: "Edit your profile and settings",
              controller: controller,
            ),
          ),
        ],
      ),
    ];
  }

  /// Overlay card
  static Widget _buildCard({
    required String title,
    required String description,
    required TutorialCoachMarkController controller,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.deepPurpleAccent,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.deepPurpleAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              controller.next();
              await Future.delayed(const Duration(milliseconds: 50));
            },
            child: const Text("Next"),
          ),
        ],
      ),
    );
  }
}



// import 'package:flutter/material.dart';
// import 'package:hopper/Core/Utility/app_showcase_key.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
// import 'package:flutter/material.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
//
// class TutorialService {
//   static bool _isShown = false;
//   static TutorialCoachMark? _tutorial;
//
//   /// Show main tab tutorial
//   static Future<void> showTutorial(BuildContext context) async {
//     if (_isShown) return;
//
//     final prefs = await SharedPreferences.getInstance();
//     final isFirstTime = prefs.getBool("tutorialShown") ?? true;
//     if (!isFirstTime) return;
//
//     _tutorial = TutorialCoachMark(
//       targets: _createTargets(),
//       colorShadow: Colors.black.withOpacity(0.5),
//       opacityShadow: 0.5,
//       textSkip: "Skip",
//       paddingFocus: 8,
//       onSkip: () {
//         SharedPreferences.getInstance().then((prefs) async {
//           await prefs.setBool("tutorialShown", false);
//           _isShown = true;
//           _tutorial = null;
//         });
//
//         return true;
//         // SharedPreferences.getInstance().then((prefs) {
//         //   prefs.setBool("tutorialShown", false);
//         //   _isShown = true;
//         // });
//         return true; // <-- must return a bool
//       },
//       onFinish: () async {
//         final prefs = await SharedPreferences.getInstance();
//         await prefs.setBool("tutorialShown", false);
//         _isShown = true;
//         _tutorial = null;
//         return true;
//       },
//     );
//
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _tutorial?.show(context: context);
//     });
//   }
//
//   /// Show profile-specific tutorial
//   static Future<void> showProfileTutorial(BuildContext context) async {
//     if (_isShown) return;
//
//     final prefs = await SharedPreferences.getInstance();
//     final isFirstTime = prefs.getBool("profileTutorialShown") ?? true;
//     if (!isFirstTime) return;
//
//     _tutorial = TutorialCoachMark(
//       targets: _profileTargets(),
//       colorShadow: Colors.black.withOpacity(0.5),
//       opacityShadow: 0.5,
//       textSkip: "Skip",
//       paddingFocus: 8,
//       onSkip: () {
//         SharedPreferences.getInstance().then((prefs) {
//           prefs.setBool("profileTutorialShown", false);
//           _tutorial = null;
//           _isShown = true;
//         });
//         return true;
//       },
//       onFinish: () async {
//         final prefs = await SharedPreferences.getInstance();
//         await prefs.setBool("profileTutorialShown", false);
//         _isShown = true;
//         _tutorial = null;
//         return true;
//       },
//     );
//
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _tutorial?.show(context: context);
//     });
//   }
//
//
//   static List<TargetFocus> _profileTargets() {
//     return [
//       TargetFocus(
//         identify: "profileEditButton",
//         keyTarget: ShowcaseKeys.profileEditButton,
//         shape: ShapeLightFocus.RRect,
//         radius: 8,
//         enableOverlayTab: true,
//         contents: [
//           TargetContent(
//             align: ContentAlign.bottom,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Edit Profile",
//                   description: "Tap here to edit your profile details",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//       TargetFocus(
//         identify: "profileImage",
//         keyTarget: ShowcaseKeys.profileImage,
//         shape: ShapeLightFocus.Circle,
//         enableOverlayTab: true,
//         contents: [
//           TargetContent(
//             align: ContentAlign.bottom,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Profile Image",
//                   description: "Tap here to change your profile picture",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//     ];
//   }
//
//   /// Targets for main tabs
//   static List<TargetFocus> _createTargets() {
//     return [
//       TargetFocus(
//         identify: "homeTab",
//         keyTarget: ShowcaseKeys.homeTab,
//         shape: ShapeLightFocus.Circle,
//         enableOverlayTab: false,
//         contents: [
//           TargetContent(
//             align: ContentAlign.top,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Home Tab",
//                   description: "Tap here to go to Home screen",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//       TargetFocus(
//         identify: "rideTab",
//         keyTarget: ShowcaseKeys.rideTab,
//         shape: ShapeLightFocus.Circle,
//         enableOverlayTab: false,
//         contents: [
//           TargetContent(
//             align: ContentAlign.top,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Ride Tab",
//                   description: "Tap here to book or view rides",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//       TargetFocus(
//         identify: "walletTab",
//         keyTarget: ShowcaseKeys.walletTab,
//         shape: ShapeLightFocus.Circle,
//         enableOverlayTab: false,
//         contents: [
//           TargetContent(
//             align: ContentAlign.top,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Wallet Tab",
//                   description: "Check your wallet balance and transactions",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//       TargetFocus(
//         identify: "packageTab",
//         keyTarget: ShowcaseKeys.packageTab,
//         shape: ShapeLightFocus.Circle,
//         enableOverlayTab: false,
//         contents: [
//           TargetContent(
//             align: ContentAlign.top,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Package Tab",
//                   description: "View your packages here",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//       TargetFocus(
//         identify: "profileTab",
//         keyTarget: ShowcaseKeys.profileTabBottom,
//         shape: ShapeLightFocus.Circle,
//         enableOverlayTab: false,
//         contents: [
//           TargetContent(
//             align: ContentAlign.top,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Profile Tab",
//                   description: "Edit your profile and settings",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//     ];
//   }
//
//   /// Overlay card
//   static Widget _buildCard({
//     required String title,
//     required String description,
//     required TutorialCoachMarkController controller,
//   }) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       margin: const EdgeInsets.symmetric(horizontal: 24),
//       decoration: BoxDecoration(
//         color: Colors.deepPurpleAccent,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.4),
//             blurRadius: 12,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Text(
//             title,
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 20,
//               fontWeight: FontWeight.bold,
//               letterSpacing: 0.5,
//             ),
//           ),
//           const SizedBox(height: 8),
//           Text(
//             description,
//             style: const TextStyle(color: Colors.white70, fontSize: 15),
//             textAlign: TextAlign.center,
//           ),
//           const SizedBox(height: 12),
//           ElevatedButton(
//             style: ElevatedButton.styleFrom(
//               backgroundColor: Colors.white,
//               foregroundColor: Colors.deepPurpleAccent,
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(8),
//               ),
//             ),
//             onPressed: () async {
//               controller.next();
//               await Future.delayed(
//                 const Duration(milliseconds: 50),
//               ); // ensures previous highlight removed
//             },
//             child: const Text("Next"),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// /*class TutorialService {
//   static bool _isShown = false;
//   static TutorialCoachMark? _tutorial;
//
//   static Future<void> showTutorial(BuildContext context) async {
//     if (_isShown) return;
//
//     final prefs = await SharedPreferences.getInstance();
//     final isFirstTime = prefs.getBool("tutorialShown") ?? true;
//     if (!isFirstTime) return;
//
//     _tutorial = TutorialCoachMark(
//       targets: _createTargets(),
//       colorShadow: Colors.black.withOpacity(0.5), // lighter
//       opacityShadow: 0.5, // also lighter
//
//       textSkip: "Skip",
//       paddingFocus: 8,
//
//       onSkip: () {
//         // SharedPreferences.getInstance().then((prefs) {
//         //   prefs.setBool("tutorialShown", false);
//         //   _isShown = true;
//         // });
//         return true; // <-- must return a bool
//       },
//       onFinish: () {
//          SharedPreferences.getInstance().then((prefs) {
//            prefs.setBool("tutorialShown", false);
//            _isShown = true;
//          });
//         return true; // <-- must return a bool
//       },
//     );
//
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _tutorial?.show(context: context);
//     });
//   }
//
//   static Future<void> showProfileTutorial(BuildContext context) async {
//     if (_isShown) return;
//
//     final prefs = await SharedPreferences.getInstance();
//     final isFirstTime = prefs.getBool("profileTutorialShown") ?? true;
//     if (!isFirstTime) return;
//
//     _tutorial = TutorialCoachMark(
//       targets: _profileTargets(), // ✅ Only profile targets
//       colorShadow: Colors.black.withOpacity(0.5), // lighter
//       opacityShadow: 0.5, // also lighter
//
//       textSkip: "Skip",
//       paddingFocus: 8,
//
//       onSkip: () {
//          SharedPreferences.getInstance().then((prefs) {
//            prefs.setBool("tutorialShown", false);
//            _isShown = true;
//          });
//         return true; // <-- must return a bool
//       },
//       onFinish: () {
//           SharedPreferences.getInstance().then((prefs) {
//             prefs.setBool("tutorialShown", false);
//             _isShown = true;
//           });
//         return true; // <-- must return a bool
//       },
//     );
//
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _tutorial?.show(context: context);
//     });
//   }
//
//   static List<TargetFocus> _profileTargets() {
//     return [
//       // Profile Edit Button
//       TargetFocus(
//         identify: "profileEditButton",
//         keyTarget: ShowcaseKeys.profileEditButton,
//         shape: ShapeLightFocus.RRect,
//         radius: 8,
//         enableOverlayTab: true,
//         contents: [
//           TargetContent(
//             align: ContentAlign.bottom,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Edit Profile",
//                   description: "Tap here to edit your profile details",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//
//       // Profile Image
//       TargetFocus(
//         identify: "profileImage",
//         keyTarget: ShowcaseKeys.profileImage,
//         shape: ShapeLightFocus.Circle,
//         enableOverlayTab: true,
//         contents: [
//           TargetContent(
//             align: ContentAlign.bottom,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Profile Image",
//                   description: "Tap here to change your profile picture",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//     ];
//   }
//
//   static List<TargetFocus> _createTargets() {
//     return [
//       // Book Ride
//       // TargetFocus(
//       //   identify: "bookRide",
//       //   keyTarget: ShowcaseKeys.bookButton,
//       //   shape: ShapeLightFocus.RRect,
//       //   radius: 12,
//       //   enableOverlayTab: true,
//       //   contents: [
//       //     TargetContent(
//       //       align: ContentAlign.bottom,
//       //       builder:
//       //           (context, controller) => _buildCard(
//       //             title: "Book Ride",
//       //             description: "Tap here to book a ride with the best drivers",
//       //             controller: controller,
//       //           ),
//       //     ),
//       //   ],
//       // ),
//       //
//       // // Courier
//       // TargetFocus(
//       //   identify: "Courier",
//       //   keyTarget: ShowcaseKeys.courierTab,
//       //   shape: ShapeLightFocus.RRect,
//       //   radius: 12,
//       //   enableOverlayTab: true,
//       //   contents: [
//       //     TargetContent(
//       //       align: ContentAlign.bottom,
//       //       builder:
//       //           (context, controller) => _buildCard(
//       //             title: "Courier",
//       //             description: "Tap here to parcel with the best drivers",
//       //             controller: controller,
//       //           ),
//       //     ),
//       //   ],
//       // ),
//
//       // Home Tab
//       TargetFocus(
//         identify: "homeTab",
//         keyTarget: ShowcaseKeys.homeTab,
//         shape: ShapeLightFocus.Circle,
//         enableOverlayTab: true,
//         contents: [
//           TargetContent(
//             align: ContentAlign.top,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Home Tab",
//                   description: "Tap here to go to Home screen",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//
//       // Ride Tab
//       TargetFocus(
//         identify: "rideTab",
//         keyTarget: ShowcaseKeys.rideTab,
//         shape: ShapeLightFocus.Circle,
//         enableOverlayTab: true,
//         contents: [
//           TargetContent(
//             align: ContentAlign.top,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Ride Tab",
//                   description: "Tap here to book or view rides",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//
//       // Wallet Tab
//       TargetFocus(
//         identify: "walletTab",
//         keyTarget: ShowcaseKeys.walletTab,
//         shape: ShapeLightFocus.Circle,
//         enableOverlayTab: true,
//         contents: [
//           TargetContent(
//             align: ContentAlign.top,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Wallet Tab",
//                   description: "Check your wallet balance and transactions",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//
//       // Package Tab
//       TargetFocus(
//         identify: "packageTab",
//         keyTarget: ShowcaseKeys.packageTab,
//         shape: ShapeLightFocus.Circle,
//         enableOverlayTab: true,
//         contents: [
//           TargetContent(
//             align: ContentAlign.top,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Package Tab",
//                   description: "View your packages here",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//
//       // Profile Tab
//       TargetFocus(
//         identify: "profileTab",
//         keyTarget: ShowcaseKeys.profileTabBottom,
//         shape: ShapeLightFocus.Circle,
//         enableOverlayTab: true,
//         contents: [
//           TargetContent(
//             align: ContentAlign.top,
//             builder:
//                 (context, controller) => _buildCard(
//                   title: "Profile Tab",
//                   description: "Edit your profile and settings",
//                   controller: controller,
//                 ),
//           ),
//         ],
//       ),
//     ];
//   }
//
//   /// Overlay Card
//   static Widget _buildCard({
//     required String title,
//     required String description,
//     required TutorialCoachMarkController controller,
//   }) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       margin: const EdgeInsets.symmetric(horizontal: 24),
//       decoration: BoxDecoration(
//         color: Colors.deepPurpleAccent,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.4),
//             blurRadius: 12,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Text(
//             title,
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 20,
//               fontWeight: FontWeight.bold,
//               letterSpacing: 0.5,
//             ),
//           ),
//           const SizedBox(height: 8),
//           Text(
//             description,
//             style: const TextStyle(color: Colors.white70, fontSize: 15),
//             textAlign: TextAlign.center,
//           ),
//           const SizedBox(height: 12),
//           ElevatedButton(
//             style: ElevatedButton.styleFrom(
//               backgroundColor: Colors.white,
//               foregroundColor: Colors.deepPurpleAccent,
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(8),
//               ),
//             ),
//             onPressed: controller.next,
//             child: const Text("Next"),
//           ),
//         ],
//       ),
//     );
//   }
// }*/
//
// // import 'package:flutter/material.dart';
// // import 'package:hopper/Core/Utility/app_showcase_key.dart';
// // import 'package:shared_preferences/shared_preferences.dart';
// // import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
// //
// // class TutorialService {
// //   static bool _isShown = false;
// //   static TutorialCoachMark? _tutorial;
// //
// //   static Future<void> showTutorial(BuildContext context) async {
// //     if (_isShown) return;
// //
// //     final prefs = await SharedPreferences.getInstance();
// //     final isFirstTime = prefs.getBool("tutorialShown") ?? true;
// //     if (!isFirstTime) return;
// //
// //     _tutorial = TutorialCoachMark(
// //       targets: _createTargets(),
// //       colorShadow: Colors.black.withOpacity(0.7),
// //       textSkip: "Skip",
// //       paddingFocus: 8,
// //       opacityShadow: 0.85,
// //       onSkip: () {
// //         // SharedPreferences.getInstance().then((prefs) {
// //         //   prefs.setBool("tutorialShown", false);
// //         //   _isShown = true;
// //         // });
// //         return true; // <-- must return a bool
// //       },
// //       onFinish: () {
// //         // SharedPreferences.getInstance().then((prefs) {
// //         //   prefs.setBool("tutorialShown", false);
// //         //   _isShown = true;
// //         // });
// //         return true; // <-- must return a bool
// //       },
// //     );
// //
// //     WidgetsBinding.instance.addPostFrameCallback((_) {
// //       _tutorial?.show(context: context);
// //     });
// //   }
// //
// //   static List<TargetFocus> _createTargets() {
// //     return [
// //       // 1️⃣ Book Ride button first
// //       TargetFocus(
// //         identify: "bookRide",
// //         keyTarget: ShowcaseKeys.bookButton,
// //         shape: ShapeLightFocus.RRect,
// //         radius: 12,
// //         enableOverlayTab: true,
// //         contents: [
// //           TargetContent(
// //             align: ContentAlign.bottom,
// //             builder:
// //                 (context, controller) => _buildCard(
// //                   title: "Book Ride",
// //                   description: "Tap here to book a ride with the best drivers",
// //                   controller: controller,
// //                 ),
// //           ),
// //         ],
// //       ),
// //
// //       TargetFocus(
// //         identify: "Courier",
// //         keyTarget: ShowcaseKeys.courierTab,
// //         shape: ShapeLightFocus.RRect,
// //         radius: 12,
// //         enableOverlayTab: true,
// //         contents: [
// //           TargetContent(
// //             align: ContentAlign.bottom,
// //             builder:
// //                 (context, controller) => _buildCard(
// //                   title: "Courier",
// //                   description: "Tap here to Parcel  with the best drivers",
// //                   controller: controller,
// //                 ),
// //           ),
// //         ],
// //       ),
// //
// //       TargetFocus(
// //         identify: "homeTab",
// //         keyTarget: ShowcaseKeys.homeTab,
// //         shape: ShapeLightFocus.Circle,
// //         enableOverlayTab: true,
// //         contents: [
// //           TargetContent(
// //             align: ContentAlign.top,
// //             builder:
// //                 (context, controller) => _buildCard(
// //                   title: "Home Tab",
// //                   description: "Tap here to go to Home screen",
// //                   controller: controller,
// //                 ),
// //           ),
// //         ],
// //       ),
// //
// //       TargetFocus(
// //         identify: "rideTab",
// //         keyTarget: ShowcaseKeys.rideTab,
// //         shape: ShapeLightFocus.Circle,
// //         enableOverlayTab: true,
// //         contents: [
// //           TargetContent(
// //             align: ContentAlign.top,
// //             builder:
// //                 (context, controller) => _buildCard(
// //                   title: "Ride Tab",
// //                   description: "Tap here to book or view rides",
// //                   controller: controller,
// //                 ),
// //           ),
// //         ],
// //       ),
// //
// //       // 4️⃣ Wallet tab
// //       TargetFocus(
// //         identify: "walletTab",
// //         keyTarget: ShowcaseKeys.walletTab,
// //         shape: ShapeLightFocus.Circle,
// //         enableOverlayTab: true,
// //         contents: [
// //           TargetContent(
// //             align: ContentAlign.top,
// //             builder:
// //                 (context, controller) => _buildCard(
// //                   title: "Wallet Tab",
// //                   description: "Check your wallet balance and transactions",
// //                   controller: controller,
// //                 ),
// //           ),
// //         ],
// //       ),
// //
// //       // 5️⃣ Package tab
// //       TargetFocus(
// //         identify: "packageTab",
// //         keyTarget: ShowcaseKeys.packageTab,
// //         shape: ShapeLightFocus.Circle,
// //         enableOverlayTab: true,
// //         contents: [
// //           TargetContent(
// //             align: ContentAlign.top,
// //             builder:
// //                 (context, controller) => _buildCard(
// //                   title: "Package Tab",
// //                   description: "View your packages here",
// //                   controller: controller,
// //                 ),
// //           ),
// //         ],
// //       ),
// //
// //       // 6️⃣ Profile tab
// //       TargetFocus(
// //         identify: "profileTab",
// //         keyTarget: ShowcaseKeys.profileTabBottom,
// //         shape: ShapeLightFocus.Circle,
// //         enableOverlayTab: true,
// //         contents: [
// //           TargetContent(
// //             align: ContentAlign.top,
// //             builder:
// //                 (context, controller) => _buildCard(
// //                   title: "Profile Tab",
// //                   description: "Edit your profile and settings",
// //                   controller: controller,
// //                 ),
// //           ),
// //         ],
// //       ),
// //
// //       TargetFocus(
// //         identify: "profileEditButton",
// //         keyTarget: ShowcaseKeys.profileEditButton,
// //         shape: ShapeLightFocus.RRect,
// //         radius: 8,
// //         enableOverlayTab: true,
// //         contents: [
// //           TargetContent(
// //             align: ContentAlign.bottom,
// //             builder:
// //                 (context, controller) => _buildCard(
// //                   title: "Edit Profile",
// //                   description: "Tap here to edit your profile details",
// //                   controller: controller,
// //                 ),
// //           ),
// //         ],
// //       ),
// //
// //       TargetFocus(
// //         identify: "profileImage",
// //         keyTarget: ShowcaseKeys.profileImage,
// //         shape: ShapeLightFocus.Circle,
// //         enableOverlayTab: true,
// //         contents: [
// //           TargetContent(
// //             align: ContentAlign.bottom,
// //             builder:
// //                 (context, controller) => _buildCard(
// //                   title: "Profile Image",
// //                   description: "Tap here to change your profile picture",
// //                   controller: controller,
// //                 ),
// //           ),
// //         ],
// //       ),
// //     ];
// //   }
// //
// //   /// Beautiful card overlay
// //   static Widget _buildCard({
// //     required String title,
// //     required String description,
// //     required TutorialCoachMarkController controller,
// //   }) {
// //     return Container(
// //       padding: const EdgeInsets.all(16),
// //       margin: const EdgeInsets.symmetric(horizontal: 24),
// //       decoration: BoxDecoration(
// //         color: Colors.deepPurpleAccent,
// //         borderRadius: BorderRadius.circular(16),
// //         boxShadow: [
// //           BoxShadow(
// //             color: Colors.black.withOpacity(0.4),
// //             blurRadius: 12,
// //             offset: const Offset(0, 4),
// //           ),
// //         ],
// //       ),
// //       child: Column(
// //         mainAxisSize: MainAxisSize.min,
// //         children: [
// //           Text(
// //             title,
// //             style: const TextStyle(
// //               color: Colors.white,
// //               fontSize: 20,
// //               fontWeight: FontWeight.bold,
// //               letterSpacing: 0.5,
// //             ),
// //           ),
// //           const SizedBox(height: 8),
// //           Text(
// //             description,
// //             style: const TextStyle(color: Colors.white70, fontSize: 15),
// //             textAlign: TextAlign.center,
// //           ),
// //           const SizedBox(height: 12),
// //           ElevatedButton(
// //             style: ElevatedButton.styleFrom(
// //               backgroundColor: Colors.white,
// //               foregroundColor: Colors.deepPurpleAccent,
// //               shape: RoundedRectangleBorder(
// //                 borderRadius: BorderRadius.circular(8),
// //               ),
// //             ),
// //             onPressed: controller.next,
// //             child: const Text("Next"),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// // }
