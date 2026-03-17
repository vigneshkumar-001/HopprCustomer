import 'dart:io';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/api/dataSource/apiDataSource.dart';
import 'package:hopper/Presentation/Drawer/models/profile_response.dart';
import 'package:country_picker/country_picker.dart';

class ProfleCotroller extends GetxController {
  RxBool isEditing = false.obs;
  RxBool isLoading = false.obs;

  TextEditingController nameController = TextEditingController();
  TextEditingController dobController = TextEditingController();
  TextEditingController genderController = TextEditingController();
  TextEditingController emailController = TextEditingController();

  final TextEditingController emergencyController = TextEditingController();

  ApiDataSource apiDataSource = ApiDataSource();
  Rxn<UserModel> user = Rxn<UserModel>();
  RxString frontImageUrl = ''.obs;
  String mobileNumber = " ";
  RxString code = " ".obs;
  final RxString selectedCountryCode = ''.obs;
  final RxString selectedCountryFlag = ''.obs;
  final RxString errorText = ''.obs;

  RxString userName = " ".obs;
  RxString userId = "".obs;
  RxString profileImagePath = "".obs;
  final Rx<Country?> selectedCountry = Rx<Country?>(null);

  void setSelectedCountry(Country country) {
    selectedCountry.value = country;
  }

  String? _safeParseDate(String input) {
    try {
      final formats = [
        "dd-MMMM-yyyy", // 2-October-2003
        "dd/MM/yyyy", // 02/10/2003
        "yyyy-MM-dd", // 1988-03-02
        "dd-MM-yyyy", // 02-10-2003
      ];

      for (var format in formats) {
        try {
          final parsed = DateFormat(format).parseStrict(input);
          return DateFormat("yyyy-MM-dd").format(parsed);
        } catch (_) {}
      }

      final parsed = DateTime.tryParse(input);
      if (parsed != null) {
        return DateFormat("yyyy-MM-dd").format(parsed);
      }

      return null;
    } catch (e) {
      AppLogger.log.e("Date parsing failed: $e");
      return null;
    }
  }

  void toggleEdit() {
    isEditing.value = !isEditing.value;
  }

  void setProfileImage(String path) {
    profileImagePath.value = path;
  }

  /*  Future<void> saveData(GlobalKey<FormState> formKey) async {
    if (!formKey.currentState!.validate()) return;

    isLoading.value = true;

    String firstName = nameController.text.split(" ").first;
    String lastName =
    nameController.text.split(" ").length > 1
        ? nameController.text.split(" ").last
        : "";

    String dateOfBirth = dobController.text;
    String gender = genderController.text;
    String email = emailController.text;
    String profileImage = profileImagePath.value;

    String? result = await submitProfileData(
      frontImageFile: ,
      firstName: firstName,
      lastName: lastName,
      dateOfBirth: dateOfBirth,
      gender: gender,
      email: email,
      profileImage: profileImage,
    );

    if (result != null) {
      userName.value = nameController.text;
      isEditing.value = false;
      Get.snackbar("Success", "Profile updated successfully");
    }

    isLoading.value = false;
  }*/

  Future<void> saveData(GlobalKey<FormState> formKey) async {
    if (!formKey.currentState!.validate()) return;

    isLoading.value = true;

    String firstName = nameController.text;
    String lastName =
        nameController.text.split(" ").length > 1
            ? nameController.text.split(" ").last
            : "";

    String dateOfBirth = "";
    if (dobController.text.isNotEmpty) {
      dateOfBirth = _safeParseDate(dobController.text) ?? "";
    }

    String gender = genderController.text;
    String email = emailController.text;
    String emergencyNumber = emergencyController.text;
    String countryCode = selectedCountryCode.value;

    File? frontImageFile;
    if (profileImagePath.value.isNotEmpty &&
        !profileImagePath.value.startsWith("http")) {
      final file = File(profileImagePath.value);
      if (file.existsSync()) {
        frontImageFile = file;
      } else {
        AppLogger.log.e(
          "⛔ Local image file does not exist: ${profileImagePath.value}",
        );
      }
    }

    String? result = await submitProfileData(
      countryCode: countryCode,
      firstName: firstName,
      lastName: lastName,
      dateOfBirth: dateOfBirth,
      gender: gender,
      email: email,
      emergencyNumber: emergencyNumber,
      frontImageFile: frontImageFile,
      profileImage: profileImagePath.value,
    );

    if (result != null) {
      userName.value = nameController.text;
      isEditing.value = false;
      Get.snackbar(
        "Success",
        "Profile updated successfully",
        backgroundColor: Colors.green,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP, // or TOP
        margin: const EdgeInsets.all(10),
        borderRadius: 8,
        duration: const Duration(seconds: 3),
      );
    }

    isLoading.value = false;
  }

  Future<String?> submitProfileData({
    required String firstName,
    required String lastName,
    required String dateOfBirth,
    required String gender,
    required String email,
    required String emergencyNumber,
    required String countryCode,
    File? frontImageFile,
    required String profileImage,
    BuildContext? context,
  }) async
  {
    try {
      isLoading.value = true;
      String? frontImageUrl;

      if (frontImageFile != null) {
        final frontResult = await apiDataSource.userProfileUpload(
          imageFile: frontImageFile,
        );

        frontImageUrl = frontResult.fold((failure) {
          AppLogger.log.e("Front Upload Failed: ${failure.message}");
          return null;
        }, (success) => success.message);

        if (frontImageUrl == null) {
          isLoading.value = false;
          return null;
        }
      } else {
        frontImageUrl =
            this.frontImageUrl.value.isNotEmpty
                ? this.frontImageUrl.value
                : profileImage;
      }

      final results = await apiDataSource.submitProfileData(
        firstName: firstName,
        lastName: lastName,
        dateOfBirth: dateOfBirth,
        gender: gender,
        email: email,
        profileImage: frontImageUrl,
        emergencyNumber: emergencyNumber, // ✅ added
        countryCode: countryCode, // ✅ added
      );

      return results.fold(
        (failure) {
          isLoading.value = false;
          AppToasts.customToast(context!, failure.message);
          AppLogger.log.e("Failure: $failure");

          return null;
        },
        (response) {
          getProfileData();
          isLoading.value = false;
          AppLogger.log.i("Success: ${response.message}");
          return response.message;
        },
      );
    } catch (e) {
      isLoading.value = false;
      AppLogger.log.e(e);
      return null;
    }
  }

  /* Future<void> submitProfileData({
    required String firstName,
    required String lastName,
    required String dateOfBirth,
    required String gender,
    required String email,
    File? frontImageFile,
    required String profileImage,
  }) async {
    try {
      isLoading.value = true;
      String? frontImageUrl;

      if (frontImageFile != null) {
        final frontResult = await apiDataSource.userProfileUpload(
          imageFile: frontImageFile,
        );

        frontImageUrl = frontResult.fold((failure) {
          // CustomSnackBar.showError("Front Upload Failed: ${failure.message}");
          return null;
        }, (success) => success.message);

        if (frontImageUrl == null) {
          isLoading.value = false;
          return;
        }
      } else {
        // Use existing URL if no new file
        frontImageUrl = this.frontImageUrl.value;
      }

      final results = await apiDataSource.submitProfileData(
        firstName: firstName,
        lastName: lastName,
        dateOfBirth: dateOfBirth,
        gender: gender,
        email: email,
        profileImage: frontImageUrl,
      );

      return results.fold(
            (failure) {
          isLoading.value = false;
          AppLogger.log.e("Failure: $failure");
          return null;
        },
            (response) {
          isLoading.value = false;
          AppLogger.log.i("Success: ${response.message}");
          return response.message;
        },
      );
    } catch (e) {
      isLoading.value = false;
      AppLogger.log.e(e);
      return null;
    }
  }*/

  Future<String?> getProfileData() async {
    try {
      isLoading.value = true;
      final results = await apiDataSource.getProfileData();

      return results.fold(
        (failure) {
          isLoading.value = false;
          AppLogger.log.e("Failure: $failure");
          return null;
        },
        (response) {
          isLoading.value = false;
          AppLogger.log.i("Success: ${response.message}");

          user.value = response.data; // Save entire profile reactively

          nameController.text = "${response.data.firstName}";
          dobController.text =
              response.data.dateOfBirth != null
                  ? formatDob(response.data.dateOfBirth.toString()!)
                  : "";
          genderController.text = response.data.gender ?? "";
          emailController.text = response.data.email ?? "";
          profileImagePath.value = response.data.profileImage ?? "";
          userName.value = "${response.data.firstName}  ";
          mobileNumber = response.data.phone ?? "";
          userId.value = response.data.id ?? "";
          code.value = response.data.countryCode ?? "";

          return response.message;
        },
      );
    } catch (e) {
      isLoading.value = false;
      AppLogger.log.e(e);
      return null;
    }
  }

  String formatDob(String dob) {
    try {
      final parsedDate = DateTime.parse(dob);
      return DateFormat("d MMMM yyyy").format(parsedDate); // 5 March 2000
    } catch (e) {
      return dob;
    }
  }
}



