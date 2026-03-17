import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

class LocationGateController extends GetxController
    with WidgetsBindingObserver {
  final RxBool isReady = false.obs;

  StreamSubscription<ServiceStatus>? _serviceSub;
  bool _dialogOpen = false;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);

    _serviceSub = Geolocator.getServiceStatusStream().listen((status) async {
      if (status == ServiceStatus.disabled) {
        isReady.value = false;
        _showEnableServiceDialog();
      } else {
        await _checkAndGate();
      }
    });

    _checkAndGate();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceSub?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user comes back from Settings
    if (state == AppLifecycleState.resumed) {
      _checkAndGate();
    }
  }

  Future<void> checkNow() async {
    await _checkAndGate();
  }

  Future<void> _checkAndGate() async {
    isReady.value = false;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showEnableServiceDialog();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _showPermissionDeniedDialog();
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      _showPermissionPermanentlyDeniedDialog();
      return;
    }

    // ✅ All good -> close any open popup and allow app
    _forceClosePopup();
    isReady.value = true;
  }

  void _forceClosePopup() {
    _dialogOpen = false;
    if (Get.isDialogOpen == true) {
      Get.back(closeOverlays: true); // ✅ important
    }
  }

  void _showEnableServiceDialog() {
    if (_dialogOpen) return;
    _dialogOpen = true;

    Get.dialog(
      barrierDismissible: false,
      PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text("Enable Location"),
          content: const Text(
            "GPS is turned OFF. Location is mandatory to use this app.",
          ),
          actions: [
            TextButton(
              onPressed: () async {
                // ✅ open location settings
                await Geolocator.openLocationSettings();
                // do not close dialog here; it will close on resume when check passes
              },
              child: const Text("Open Settings"),
            ),
            TextButton(
              onPressed: () async {
                await _checkAndGate();
              },
              child: const Text("Retry"),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      _dialogOpen = false;
    });
  }

  void _showPermissionDeniedDialog() {
    if (_dialogOpen) return;
    _dialogOpen = true;

    Get.dialog(
      barrierDismissible: false,
      PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text("Location Permission Required"),
          content: const Text("Please allow location permission to continue."),
          actions: [
            TextButton(
              onPressed: () async => _checkAndGate(),
              child: const Text("Retry"),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      _dialogOpen = false;
    });
  }

  void _showPermissionPermanentlyDeniedDialog() {
    if (_dialogOpen) return;
    _dialogOpen = true;

    Get.dialog(
      barrierDismissible: false,
      PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text("Permission Needed"),
          content: const Text(
            "Location permission is permanently denied. Enable it from Settings.",
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Geolocator.openAppSettings();
              },
              child: const Text("Open Settings"),
            ),
            TextButton(
              onPressed: () async => _checkAndGate(),
              child: const Text("Retry"),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      _dialogOpen = false;
    });
  }
}
