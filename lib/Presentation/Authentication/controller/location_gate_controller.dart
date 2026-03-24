import 'dart:async';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:hopper/Core/Consents/app_colors.dart';

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

    // Defer first gate check until after first frame so dialogs have a Navigator.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndGate();
    });
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
      Get.back(); // close only this dialog
    }
  }

  Widget _locationBlockDialog({
    required String title,
    required String message,
    required String primaryText,
    required VoidCallback onPrimary,
    String? secondaryText,
    VoidCallback? onSecondary,
    IconData icon = Icons.location_on_rounded,
  }) {
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.commonWhite,
                AppColors.chatBlueColor.withOpacity(0.12),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.red.shade600, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.commonBlack,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.commonBlack,
                    foregroundColor: AppColors.commonWhite,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onPrimary,
                  child: Text(
                    primaryText,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (secondaryText != null && onSecondary != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onSecondary,
                    child: Text(
                      secondaryText,
                      style: const TextStyle(
                        color: AppColors.commonBlack,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showEnableServiceDialog() {
    if (_dialogOpen) return;
    _dialogOpen = true;

    void open() {
      Get.dialog(
        barrierDismissible: false,
        _locationBlockDialog(
          title: 'Turn on Location',
          message:
              'Please enable GPS/Location services. This app is location-based and needs your location to work.',
          primaryText: 'Open Settings',
          onPrimary: () async {
            await Geolocator.openLocationSettings();
          },
          secondaryText: 'Retry',
          onSecondary: () async {
            await _checkAndGate();
          },
          icon: Icons.gps_off_rounded,
        ),
      ).whenComplete(() {
        _dialogOpen = false;
      });
    }

    if (Get.context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => open());
    } else {
      open();
    }
  }

  void _showPermissionDeniedDialog() {
    if (_dialogOpen) return;
    _dialogOpen = true;

    void open() {
      Get.dialog(
        barrierDismissible: false,
        _locationBlockDialog(
          title: 'Allow Location Permission',
          message:
              'Please allow location permission to continue. We use location to provide nearby services and accurate pickup.',
          primaryText: 'Retry',
          onPrimary: () async => _checkAndGate(),
          icon: Icons.my_location_rounded,
        ),
      ).whenComplete(() {
        _dialogOpen = false;
      });
    }

    if (Get.context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => open());
    } else {
      open();
    }
  }

  void _showPermissionPermanentlyDeniedDialog() {
    if (_dialogOpen) return;
    _dialogOpen = true;

    void open() {
      Get.dialog(
        barrierDismissible: false,
        _locationBlockDialog(
          title: 'Enable Permission in Settings',
          message:
              'Location permission is permanently denied. Please enable it from Settings to continue.',
          primaryText: 'Open Settings',
          onPrimary: () async {
            await Geolocator.openAppSettings();
          },
          secondaryText: 'Retry',
          onSecondary: () async => _checkAndGate(),
          icon: Icons.settings_rounded,
        ),
      ).whenComplete(() {
        _dialogOpen = false;
      });
    }

    if (Get.context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => open());
    } else {
      open();
    }
  }
}
