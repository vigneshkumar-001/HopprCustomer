// app_showcase_key.dart
import 'package:flutter/material.dart';

/// Instance-scoped keys container. Create ONE per bottom-nav (or screen group)
/// and pass it down where needed.
class ShowcaseKeys {
  // Common actions
  final GlobalKey bookButton = GlobalKey();
  final GlobalKey courierTab = GlobalKey();
  final GlobalKey profileTab = GlobalKey();
  final GlobalKey walletIcon = GlobalKey();

  // BottomNavigationBar tabs
  final GlobalKey homeTab = GlobalKey();
  final GlobalKey rideTab = GlobalKey();
  final GlobalKey walletTab = GlobalKey();
  final GlobalKey packageTab = GlobalKey();
  final GlobalKey profileTabBottom = GlobalKey();

  // Profile
  final GlobalKey profileEditButton = GlobalKey();
  final GlobalKey profileImage = GlobalKey();

  ShowcaseKeys();
}
