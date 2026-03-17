import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Presentation/Authentication/controller/authController.dart';
import 'package:hopper/Presentation/Authentication/screens/otp_screens.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:country_picker/country_picker.dart';
import 'package:get/get.dart';

class MobileScreens extends StatefulWidget {
  const MobileScreens({super.key});

  @override
  State<MobileScreens> createState() => _MobileScreensState();
}

class _MobileScreensState extends State<MobileScreens> {
  final AuthController controller = Get.put(AuthController());
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  void showCountrySelector(BuildContext context) {
    showCountryPicker(
      context: context,
      showSearch: true,
      showPhoneCode: true,
      searchAutofocus: true,
      countryListTheme: CountryListThemeData(
        flagSize: 22,
        backgroundColor: Colors.white,

        bottomSheetHeight: 600,
        //Optional. Sets the border radius for the bottomsheet.
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30.0),
          topRight: Radius.circular(30.0),
        ),
        searchTextStyle: TextStyle(color: Colors.black),
        //Optional. Styles the search field.
        inputDecoration: InputDecoration(
          hintText: 'Search',
          hintStyle: TextStyle(color: Colors.grey),
          prefixIcon: Icon(Icons.search, color: Colors.black),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),

          border: OutlineInputBorder(
            borderSide: BorderSide(
              color: const Color(0xFF8C98A8).withOpacity(0.2),
            ),
          ),
        ),
      ),
      // countryListTheme: CountryListThemeData(
      //   inputDecoration: InputDecoration(
      //     hintText: 'Search',
      //     hintStyle: TextStyle(color: Colors.grey),
      //     prefixIcon: Icon(Icons.search, color: Colors.black),
      //     enabledBorder: OutlineInputBorder(
      //       borderSide: BorderSide(color: Colors.black),
      //       borderRadius: BorderRadius.circular(8),
      //     ),
      //     focusedBorder: OutlineInputBorder(
      //       borderSide: BorderSide(color: Colors.black, width: 2),
      //       borderRadius: BorderRadius.circular(8),
      //     ),
      //     contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      //   ),
      //
      //   searchTextStyle: TextStyle(color: Colors.black),
      //   // Optional sheet styling
      //   borderRadius: BorderRadius.only(
      //     topLeft: Radius.circular(12),
      //     topRight: Radius.circular(12),
      //   ),
      // ),
      onSelect: (Country country) {
        controller.setSelectedCountry(country);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    controller.selectedCountryCode.value = '+234';
    controller.countryCodeController.text = '+234';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppButtons.backButton(context: context),
                        const SizedBox(height: 25),
                        CustomTextFields.textWithStyles700(
                          AppTexts.enterMobileNumberForVerification,
                        ),
                        const SizedBox(height: 15),
                        CustomTextFields.textWithStylesSmall(
                          maxLines: 3,
                          AppTexts.enterMobileNumberContent,
                        ),
                        const SizedBox(height: 20),

                        // Country Code & Mobile Number Input Row
                        Row(
                          children: [
                            // Country Selector
                            Expanded(
                              flex: 2,
                              child: GestureDetector(
                                onTap: () => showCountrySelector(context),
                                child: Obx(
                                  () => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.containerColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          selectedCountryFlag.isEmpty
                                              ? '🇳🇬'
                                              : selectedCountryFlag,
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          controller
                                                  .selectedCountryCode
                                                  .value
                                                  .isEmpty
                                              ? '+--'
                                              : controller
                                                  .selectedCountryCode
                                                  .value,
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        const Icon(Icons.arrow_drop_down),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),

                            // Mobile Number Field with Validation
                            Expanded(
                              flex: 4,
                              child: TextFormField(
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                onChanged: (value) {
                                  final code =
                                      controller.selectedCountryCode.value;

                                  if (value.isEmpty) {
                                    controller.errorText.value =
                                        'Please enter your Mobile Number';
                                  } else if (code == '+91' &&
                                      value.length != 10) {
                                    controller.errorText.value =
                                        'Indian numbers must be exactly 10 digits';
                                  } else if (code == '+234' &&
                                      value.length != 10) {
                                    controller.errorText.value =
                                        'Nigerian numbers must be exactly 10 digits';
                                  } else {
                                    controller.errorText.value = '';

                                    if (_formKey.currentState?.validate() ??
                                        false) {
                                      Future.delayed(
                                        Duration(milliseconds: 100),
                                        () {
                                          FocusScope.of(context).unfocus();
                                          final String mbl =
                                              controller.mobileNumber.text;
                                          controller.login(
                                            mobileNumber: mbl,
                                            context: context,
                                            countryCode: code,
                                          );
                                        },
                                      );
                                    }
                                  }

                                  // Trigger validation error UI
                                  _formKey.currentState?.validate();
                                },

                                //
                                // onChanged: (value) {
                                //   final code =
                                //       controller.selectedCountryCode.value;
                                //   if (value.isEmpty) {
                                //     controller.errorText.value =
                                //         'Please enter your Mobile Number';
                                //   } else if (code == '+91' &&
                                //       value.length != 10) {
                                //     controller.errorText.value =
                                //         'Indian numbers must be exactly 10 digits';
                                //   } else if (code == '+234' &&
                                //       value.length != 10) {
                                //     controller.errorText.value =
                                //         'Nigerian numbers must be exactly 10 digits';
                                //   } else {
                                //     controller.errorText.value = '';
                                //   }
                                //   _formKey.currentState?.validate();
                                // },
                                controller: controller.mobileNumber,
                                keyboardType: TextInputType.phone,
                                autofocus: true,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(10),
                                  FilteringTextInputFormatter.digitsOnly,
                                ],

                                // validator: (value) {
                                //   final code =
                                //       controller.selectedCountryCode.value;
                                //   if (value == null || value.isEmpty) {
                                //     return 'Please enter your Mobile Number';
                                //   } else if (code == '+91' &&
                                //       value.length != 10) {
                                //     return 'Indian numbers must be exactly 10 digits';
                                //   } else if (code == '+234' &&
                                //       value.length != 10) {
                                //     return 'Nigerian numbers must be exactly 10 digits';
                                //   }
                                //   return null;
                                // },
                                decoration: InputDecoration(
                                  hintText: 'Enter mobile number',
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 1,
                                    horizontal: 10,
                                  ),
                                  filled: true,
                                  fillColor: AppColors.containerColor,
                                  border: OutlineInputBorder(
                                    borderSide: BorderSide.none,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Obx(
                          () =>
                              controller.errorText.value.isNotEmpty
                                  ? Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      controller.errorText.value,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 10,
                                      ),
                                    ),
                                  )
                                  : const SizedBox(),
                        ),
                      ],
                    ),
                  ),
                ),
                Obx(() {
                  return controller.isLoading.value
                      ? AppLoader.appLoader()
                      : AppButtons.button(
                        onTap: () async {
                          final code = controller.selectedCountryCode.value;
                          final value = controller.mobileNumber.text.trim();

                          // Manual validation
                          if (value.isEmpty) {
                            controller.errorText.value =
                                'Please enter your Mobile Number';
                            return;
                          } else if (code == '+91' && value.length != 10) {
                            controller.errorText.value =
                                'Indian numbers must be exactly 10 digits';
                            return;
                          } else if (code == '+234' && value.length != 10) {
                            controller.errorText.value =
                                'Nigerian numbers must be exactly 10 digits';
                            return;
                          } else {
                            controller.errorText.value = '';
                          }
                          final String mbl = controller.mobileNumber.text;
                          controller.login(
                            mobileNumber: mbl,
                            context: context,
                            countryCode: code,
                          );
                          // Navigator.push(
                          //   context,
                          //   MaterialPageRoute(
                          //     builder:
                          //         (context) => OtpScreens(
                          //           countyCode: controller.selectedCountryCode.value,
                          //           mobileNumber: controller.mobileNumber.text,
                          //         ),
                          //   ),
                          // );
                        },

                        text: AppTexts.continueWithPhoneNumber,
                      );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
