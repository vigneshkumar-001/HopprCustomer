// common_bottom_navigation.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_showcase_key.dart';
import 'package:hopper/Presentation/BookRide/Screens/search_screen.dart';
import 'package:hopper/Presentation/Drawer/screens/settings_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/home_screens.dart';
 
import 'package:hopper/Presentation/OnBoarding/Screens/package_screens.dart';
import 'package:hopper/Presentation/wallet/screens/wallet_screens.dart';
import 'package:hopper/TutorialService_widgets.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';

class CommonBottomNavigation extends StatefulWidget {
  final int initialIndex;
  const CommonBottomNavigation({super.key, this.initialIndex = 0});

  @override
  CommonBottomNavigationState createState() => CommonBottomNavigationState();
}

class CommonBottomNavigationState extends State<CommonBottomNavigation> {
  int _selectedIndex = 0;

  /// Instance-scoped showcase keys (fixes duplicate GlobalKey crash)
  late final ShowcaseKeys showcaseKeys;

  Future<void> _forceHideKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    showcaseKeys = ShowcaseKeys(); // <-- NEW: create per-instance keys
    _selectedIndex = widget.initialIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Prevent "keyboard flash" on first Home load (which also breaks tutorial overlay positioning).
      await _forceHideKeyboard();
      await Future.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      await _forceHideKeyboard();

      if (!mounted) return;
      if (MediaQuery.of(context).viewInsets.bottom > 0) return;
      // Give one more frame for layout to stabilize before showing coach marks.
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;

      TutorialService.showTutorial(context, keys: showcaseKeys);
    });
  }

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return HomeScreens();
      case 1:
        return BookRideSearchScreen(flag: 'bottomBar');
      case 2:
        return WalletScreen(flag: 'bottomBar');
      case 3:
        return PackageScreens();
      case 4:
        return SettingsScreen(flag: 'bottomBar');
      // case 4:
      //   return PaymentScreen(amount: 10, bookingId: '761255');
      default:
        return HomeScreens();
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return WillPopScope(
      onWillPop: () async => false,
      child: NoInternetOverlay(
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: Colors.white,
          body: _getScreen(_selectedIndex),
          bottomNavigationBar:
              isKeyboardVisible
                  ? null
                  : BottomNavigationBar(
                    backgroundColor: AppColors.commonWhite,
                    type: BottomNavigationBarType.fixed,
                    currentIndex: _selectedIndex,
                    onTap: _onItemTapped,
                    selectedItemColor: AppColors.commonBlack,
                    unselectedItemColor: const Color(0xFF93959F),
                    selectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                    ),
                    items: [
                      BottomNavigationBarItem(
                        icon: Container(
                          key: showcaseKeys.homeTab, // <-- instance key
                          child: Image.asset(
                            AppImages.bHome,
                            height: 30,
                            width: 30,
                            color:
                                _selectedIndex == 0
                                    ? AppColors.commonBlack
                                    : const Color(0xFF93959F),
                          ),
                        ),
                        label: 'Home',
                      ),
                      BottomNavigationBarItem(
                        icon: Container(
                          key: showcaseKeys.rideTab, // <-- instance key
                          child: Image.asset(
                            AppImages.bCar,
                            height: 30,
                            width: 30,
                            color:
                                _selectedIndex == 1
                                    ? AppColors.commonBlack
                                    : const Color(0xFF93959F),
                          ),
                        ),
                        label: 'Ride',
                      ),
                      BottomNavigationBarItem(
                        icon: Container(
                          key: showcaseKeys.walletTab, // <-- instance key
                          child: Image.asset(
                            AppImages.bWallet,
                            height: 30,
                            width: 30,
                            color:
                                _selectedIndex == 2
                                    ? AppColors.commonBlack
                                    : const Color(0xFF93959F),
                          ),
                        ),
                        label: 'Wallet',
                      ),
                      BottomNavigationBarItem(
                        icon: Container(
                          key: showcaseKeys.packageTab, // <-- instance key
                          child: Image.asset(
                            AppImages.bPackage,
                            height: 30,
                            width: 30,
                            color:
                                _selectedIndex == 3
                                    ? AppColors.commonBlack
                                    : const Color(0xFF93959F),
                          ),
                        ),
                        label: 'Package',
                      ),
                      BottomNavigationBarItem(
                        icon: Container(
                          key:
                              showcaseKeys.profileTabBottom, // <-- instance key
                          child: Image.asset(
                            AppImages.bProfile,
                            height: 30,
                            width: 30,
                            color:
                                _selectedIndex == 4
                                    ? AppColors.commonBlack
                                    : const Color(0xFF93959F),
                          ),
                        ),
                        label: 'Profile',
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:hopper/Core/Consents/app_colors.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/Core/Utility/app_showcase_key.dart';
// import 'package:hopper/Presentation/BookRide/Screens/book_map_screen.dart';
// import 'package:hopper/Presentation/BookRide/Screens/search_screen.dart';
// import 'package:hopper/Presentation/Drawer/screens/settings_screen.dart';
// import 'package:hopper/Presentation/OnBoarding/Screens/chat_screen.dart';
// import 'package:hopper/Presentation/OnBoarding/Screens/home_screens.dart';
// import 'package:hopper/Presentation/OnBoarding/Screens/package_screens.dart';
// import 'package:hopper/Presentation/OnBoarding/Screens/payment_screen.dart';
// import 'package:hopper/Presentation/wallet/screens/wallet_screens.dart';
// import 'package:hopper/TutorialService_widgets.dart';
// import 'package:hopper/dummy2.dart';
// import 'package:hopper/dummy_screen.dart';
// import 'package:hopper/uber_screen.dart';
// import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
//
// class CommonBottomNavigation extends StatefulWidget {
//   final int initialIndex;
//   const CommonBottomNavigation({super.key, this.initialIndex = 0});
//
//   @override
//   CommonBottomNavigationState createState() => CommonBottomNavigationState();
// }
//
// class CommonBottomNavigationState extends State<CommonBottomNavigation> {
//   int _selectedIndex = 0;
//
//   // final List<Widget> _screens = <Widget>[
//   //   HomeScreens(),
//   //   BookRideSearchScreen(),
//   //   PackageScreens(),
//   //   PackageScreens(),
//   //   ChatScreen(),
//   // ];
//
//  @override
//   void initState() {
//     super.initState();
//     _selectedIndex = widget.initialIndex;
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) return;
//       TutorialService.showTutorial(context);
//     });
//   }
//
//   Widget _getScreen(int index) {
//     switch (index) {
//       case 0:
//         return HomeScreens();
//       case 1:
//         return BookRideSearchScreen(flag: 'bottomBar');
//       case 2:
//         return WalletScreen(flag: 'bottomBar');
//
//       case 3:
//         return PackageScreens();
//       case 4:
//         return SettingsScreen(flag: 'bottomBar');
//       // case 4:
//       //   return PaymentScreen(amount: 12220, bookingId: '12346');
//       default:
//         return HomeScreens();
//     }
//   }
//
//   void _onItemTapped(int index) {
//     setState(() {
//       _selectedIndex = index;
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
//     return WillPopScope(
//       onWillPop: () async {
//         return false;
//       },
//       child: NoInternetOverlay(
//         child: Scaffold(
//           resizeToAvoidBottomInset: true,
//           backgroundColor: Colors.white,
//           body: _getScreen(_selectedIndex),
//           bottomNavigationBar:
//               isKeyboardVisible
//                   ? null
//                   : Builder(
//                     builder:
//                         (context) => BottomNavigationBar(
//                           backgroundColor: AppColors.commonWhite,
//                           type: BottomNavigationBarType.fixed,
//                           currentIndex: _selectedIndex,
//                           onTap: _onItemTapped,
//                           selectedItemColor: AppColors.commonBlack,
//                           unselectedItemColor: Color(0xFF93959F),
//                           selectedLabelStyle: const TextStyle(
//                             fontWeight: FontWeight.bold,
//                           ),
//                           unselectedLabelStyle: const TextStyle(
//                             fontWeight: FontWeight.w500,
//                           ),
//                           items: [
//                             BottomNavigationBarItem(
//                               icon: Container(
//                                 key: ShowcaseKeys.homeTab,
//                                 child: Image.asset(
//                                   AppImages.bHome,
//                                   height: 30,
//                                   width: 30,
//                                   color:
//                                       _selectedIndex == 0
//                                           ? AppColors.commonBlack
//                                           : Color(0xFF93959F),
//                                 ),
//                               ),
//                               label: 'Home',
//                             ),
//                             BottomNavigationBarItem(
//                               icon: Container(
//                                 key: ShowcaseKeys.rideTab,
//                                 child: Image.asset(
//                                   AppImages.bCar,
//                                   height: 30,
//                                   width: 30,
//                                   color:
//                                       _selectedIndex == 1
//                                           ? AppColors.commonBlack
//                                           : Color(0xFF93959F),
//                                 ),
//                               ),
//                               label: 'Ride',
//                             ),
//                             BottomNavigationBarItem(
//                               icon: Container(
//                                 key: ShowcaseKeys.walletTab,
//                                 child: Image.asset(
//                                   AppImages.bWallet,
//                                   height: 30,
//                                   width: 30,
//                                   color:
//                                       _selectedIndex == 2
//                                           ? AppColors.commonBlack
//                                           : Color(0xFF93959F),
//                                 ),
//                               ),
//                               label: 'Wallet',
//                             ),
//                             BottomNavigationBarItem(
//                               icon: Container(
//                                 key: ShowcaseKeys.packageTab,
//                                 child: Image.asset(
//                                   AppImages.bPackage,
//                                   height: 30,
//                                   width: 30,
//                                   color:
//                                       _selectedIndex == 3
//                                           ? AppColors.commonBlack
//                                           : Color(0xFF93959F),
//                                 ),
//                               ),
//                               label: 'Package',
//                             ),
//                             BottomNavigationBarItem(
//                               icon: Container(
//                                 key: ShowcaseKeys.profileTabBottom,
//                                 child: Image.asset(
//                                   AppImages.bProfile,
//                                   height: 30,
//                                   width: 30,
//                                   color:
//                                       _selectedIndex == 4
//                                           ? AppColors.commonBlack
//                                           : Color(0xFF93959F),
//                                 ),
//                               ),
//                               label: 'Profile',
//                             ),
//                           ],
//                         ),
//                   ),
//
//           // bottomNavigationBar:
//           //     isKeyboardVisible
//           //         ? null
//           //         : BottomNavigationBar(
//           //           backgroundColor: AppColors.commonWhite,
//           //           type: BottomNavigationBarType.fixed,
//           //           currentIndex: _selectedIndex,
//           //           onTap: _onItemTapped,
//           //
//           //           selectedItemColor: AppColors.commonBlack,
//           //           unselectedItemColor: Color(0xFF93959F),
//           //           selectedLabelStyle: const TextStyle(
//           //             fontWeight: FontWeight.bold,
//           //           ),
//           //           unselectedLabelStyle: const TextStyle(
//           //             fontWeight: FontWeight.w500,
//           //           ),
//           //
//           //           items: [
//           //             BottomNavigationBarItem(
//           //               icon: Container(
//           //                 key: ShowcaseKeys.homeTab,
//           //                 child: Image.asset(
//           //                   AppImages.bHome,
//           //                   height: 30,
//           //                   width: 30,
//           //                   color:
//           //                       _selectedIndex == 0
//           //                           ? AppColors.commonBlack
//           //                           : Color(0xFF93959F),
//           //                 ),
//           //               ),
//           //               label: 'Home',
//           //             ),
//           //             BottomNavigationBarItem(
//           //               icon: Container(
//           //                 key: ShowcaseKeys.rideTab,
//           //                 child: Image.asset(
//           //                   AppImages.bCar,
//           //                   height: 30,
//           //                   width: 30,
//           //                   color:
//           //                       _selectedIndex == 1
//           //                           ? AppColors.commonBlack
//           //                           : Color(0xFF93959F),
//           //                 ),
//           //               ),
//           //               label: 'Ride',
//           //             ),
//           //             BottomNavigationBarItem(
//           //               icon: Container(
//           //                 key: ShowcaseKeys.walletTab,
//           //                 child: Image.asset(
//           //                   AppImages.bWallet,
//           //                   height: 30,
//           //                   width: 30,
//           //                   color:
//           //                       _selectedIndex == 2
//           //                           ? AppColors.commonBlack
//           //                           : Color(0xFF93959F),
//           //                 ),
//           //               ),
//           //               label: 'Wallet',
//           //             ),
//           //             BottomNavigationBarItem(
//           //               icon: Container(
//           //                 key: ShowcaseKeys.packageTab,
//           //                 child: Image.asset(
//           //                   AppImages.bPackage,
//           //                   height: 30,
//           //                   width: 30,
//           //                   color:
//           //                       _selectedIndex == 3
//           //                           ? AppColors.commonBlack
//           //                           : Color(0xFF93959F),
//           //                 ),
//           //               ),
//           //               label: 'Package',
//           //             ),
//           //             BottomNavigationBarItem(
//           //               icon: Container(
//           //                 key: ShowcaseKeys.profileTabBottom,
//           //                 child: Image.asset(
//           //                   AppImages.bProfile,
//           //                   height: 30,
//           //                   width: 30,
//           //                   color:
//           //                       _selectedIndex == 4
//           //                           ? AppColors.commonBlack
//           //                           : Color(0xFF93959F),
//           //                 ),
//           //               ),
//           //               label: 'Profile',
//           //             ),
//           //           ],
//           //         ),
//         ),
//       ),
//     );
//   }
// }
