// controllers/network_controller.dart

import 'dart:async';
import 'package:get/get.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkController extends GetxController {
  var isConnected = true.obs;
  var isTryingAgain = false.obs; // ✅ for loader state
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void onInit() {
    super.onInit();
    _initConnectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectionStatus,
    );
  }

  /// Initialize connectivity once on startup
  Future<void> _initConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _updateConnectionStatus(result);
  }

  /// Called whenever connection changes
  void _updateConnectionStatus(List<ConnectivityResult> result) {
    // If any of the connection types is not "none", we're connected
    isConnected.value = result.any(
      (type) =>
          type == ConnectivityResult.mobile ||
          type == ConnectivityResult.wifi ||
          type == ConnectivityResult.ethernet,
    );
  }

  Future<void> checkConnectionNow() async {
    final result = await _connectivity.checkConnectivity();
    _updateConnectionStatus(result);
  }

  Future<void> tryReconnect() async {
    isTryingAgain.value = true;

    await Future.delayed(Duration(seconds: 4));
    await checkConnectionNow();

    if (isConnected.value) {
      Get.closeAllSnackbars();
      Get.snackbar(
        "Online",
        "You're back online!",
        snackPosition: SnackPosition.TOP,
        backgroundColor: Get.theme.colorScheme.secondary,
        colorText: Get.theme.colorScheme.onSecondary,
      );
    } else {
      Get.closeAllSnackbars();
      Get.snackbar(
        "Still offline",
        "Please check your internet connection.",
        snackPosition: SnackPosition.TOP,
        backgroundColor: Get.theme.colorScheme.error,
        colorText: Get.theme.colorScheme.onError,
      );
    }

    isTryingAgain.value = false;
  }

  @override
  void onClose() {
    _connectivitySubscription.cancel();
    super.onClose();
  }
}
