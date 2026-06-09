import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_logger.dart';

import 'package:country_picker/country_picker.dart';
import 'package:hopper/Presentation/Authentication/screens/otp_screens.dart';
import 'package:hopper/api/dataSource/apiDataSource.dart';
import 'package:hopper/api/repository/api_consents.dart';

var getMobileNumber = '';
var countryCodes = '';
String selectedCountryFlag = '';
const String _prefsLoginCountryCode = 'login_country_code';
const String _prefsLoginCountryFlag = 'login_country_flag';
const String _defaultLoginCountryCode = '+234';
const String _defaultLoginCountryFlag = '🇳🇬';

class AuthController extends GetxController {
  // String mobileNumber = '';
  TextEditingController mobileNumber = TextEditingController();
  TextEditingController countryCodeController = TextEditingController();
  ApiDataSource apiDataSource = ApiDataSource();
  String accessToken = '';
  RxString selectedCountryCode = ''.obs;

  RxBool isLoading = false.obs;
  RxBool isGoogleLoading = false.obs;
  final errorText = ''.obs;

  @override
  void onInit() {
    super.onInit();
    initCountrySelection();
  }

  Future<void> initCountrySelection() async {
    // Set a safe default immediately so UI never shows mismatched flag/code.
    if (selectedCountryCode.value.isEmpty) {
      selectedCountryCode.value = _defaultLoginCountryCode;
      countryCodeController.text = _defaultLoginCountryCode;
    }
    if (selectedCountryFlag.isEmpty) {
      selectedCountryFlag = _defaultLoginCountryFlag;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final persistedCode = prefs.getString(_prefsLoginCountryCode) ?? '';
      final persistedFlag = prefs.getString(_prefsLoginCountryFlag) ?? '';

      if (persistedCode.trim().isNotEmpty) {
        selectedCountryCode.value = persistedCode.trim();
        countryCodeController.text = persistedCode.trim();
      }
      if (persistedFlag.trim().isNotEmpty) {
        selectedCountryFlag = persistedFlag.trim();
      }

      // Persist current selection so logout/login keeps both flag + code in sync.
      await prefs.setString(_prefsLoginCountryCode, selectedCountryCode.value);
      await prefs.setString(_prefsLoginCountryFlag, selectedCountryFlag);
    } catch (e) {
      AppLogger.log.e('Country init failed: $e');
    }
  }

  void setSelectedCountry(Country country) {
    final code = '+${country.phoneCode}';
    selectedCountryCode.value = code;
    countryCodeController.text = code;
    selectedCountryFlag = country.flagEmoji;

    SharedPreferences.getInstance().then((prefs) async {
      await prefs.setString(_prefsLoginCountryCode, code);
      await prefs.setString(_prefsLoginCountryFlag, selectedCountryFlag);
    });
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   mobileNumber.clear();
    // });
  }

  Future<String?> login({
    required String mobileNumber,
    required BuildContext context,
    required String countryCode,
  }) async {
    isLoading.value = true;
    try {
      final results = await apiDataSource.mobileNumberLogin(
        mobileNumber,
        countryCode,
      );
      results.fold(
        (failure) {
          // AppToasts.showErrorGlobal(failure.message, title: "Error");
          isLoading.value = false;
        },
        (response) {
          isLoading.value = false;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => OtpScreens(
                    countyCode: selectedCountryCode.value,
                    mobileNumber: mobileNumber,
                  ),
            ),
          );
        },
      );
    } catch (e) {
      isLoading.value = false;
      return '';
    }
    isLoading.value = false;
    return '';
  }



  Future<String?> getAppSettings() async {
    try {
      final results = await apiDataSource.getAppSettings();
      results.fold(
        (failure) {
          // AppToasts.showErrorGlobal(failure.message, title: "Error");
          isLoading.value = false;
        },
        (response) async {
          isLoading.value = false;
          AppLogger.log.i('App Setting ${response.sosNumber}');
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('sosNumber', response.sosNumber ?? '');
          await prefs.setString('gMapKey', response.gMapKey ?? '');
          // Use the backend key immediately for all Maps HTTP calls.
          ApiConsents.setDynamicMapsKey(response.gMapKey);
          AppLogger.log.i(response.toJson());
        },
      );
    } catch (e) {
      isLoading.value = false;
      AppLogger.log.e(e);
      return '';
    }
    isLoading.value = false;
    return '';
  }



  void clearState() {
    accessToken = '';
    // Keep selected country code/flag stable across logout/login.
  }
}
