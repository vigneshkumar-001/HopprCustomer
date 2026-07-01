import 'dart:async';
import 'package:hopper/Core/Utility/shared_pref_helper.dart';
import 'dart:io';
import 'package:country_picker/country_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hopper/api/repository/request.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/Presentation/Authentication/screens/mobile_screens.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Core/Utility/app_showcase_key.dart';
import 'package:hopper/Core/Utility/compressImage.dart';
import 'package:hopper/Core/Utility/country_picker.dart';
import 'package:hopper/Core/Utility/country_picker.dart' as CountryPicker;
import 'package:hopper/TutorialService_widgets.dart';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/customBottemSheet.dart';

import 'package:image_picker/image_picker.dart';

import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:get/get.dart';
import 'package:hopper/Presentation/Drawer/controller/profle_cotroller.dart';

class SettingsScreen extends StatefulWidget {
  final String? flag;
  const SettingsScreen({super.key, this.flag});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ProfleCotroller controller = Get.find<ProfleCotroller>();

  bool isCountryPickerFocused = false;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKey1 = GlobalKey<FormState>();

  final ShowcaseKeys profileKeys = ShowcaseKeys();

  final ScrollController _scrollController = ScrollController();

  final GlobalKey _nameKey = GlobalKey();
  final GlobalKey _dobKey = GlobalKey();
  final GlobalKey _genderKey = GlobalKey();
  final GlobalKey _emailKey = GlobalKey();
  final GlobalKey _emergencyKey = GlobalKey();

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _emergencyFocus = FocusNode();

  Future<void> pickImage() async {
    try {
      if (!controller.isEditing.value) return;

      final selectedSource = await _showImageSourcePicker();
      if (selectedSource == null || !mounted) return;

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: selectedSource);

      if (pickedFile == null) return;
      if (!mounted) return;

      final originalFile = File(pickedFile.path);
      printImageSize(originalFile, label: 'Original');

      final compressedFile = await compressImage(
        originalFile,
        quality: 70,
        minWidth: 1080,
        minHeight: 1080,
      );

      final fileToUse = compressedFile ?? originalFile;
      printImageSize(fileToUse, label: 'Final');

      controller.setProfileImage(fileToUse.path);
    } catch (e) {
      debugPrint('pickImage error: $e');
    }
  }

  Future<ImageSource?> _showImageSourcePicker() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                CustomTextFields.textWithStyles700(
                  'Choose profile photo',
                  fontSize: 18,
                  color: AppColors.textColor,
                ),
                const SizedBox(height: 6),
                Text(
                  'Open camera now or pick an image from gallery.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                _buildImageSourceTile(
                  icon: Icons.photo_camera_outlined,
                  title: 'Camera',
                  subtitle: 'Take a new photo',
                  onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
                ),
                const SizedBox(height: 12),
                _buildImageSourceTile(
                  icon: Icons.photo_library_outlined,
                  title: 'Gallery',
                  subtitle: 'Choose from your phone',
                  onTap:
                      () => Navigator.of(sheetContext).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageSourceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF7F8FC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: AppColors.containerColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.textColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomTextFields.textWithStyles600(
                      title,
                      fontSize: 15,
                      color: AppColors.textColor,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Colors.black54,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    if (controller.user.value == null) {
      controller.getProfileData();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      TutorialService.showProfileTutorial(context, keys: profileKeys);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _emergencyFocus.dispose();
    super.dispose();
  }

  String formatDob(String dob) {
    try {
      final parsedDate = DateTime.parse(dob);
      return DateFormat("d MMMM yyyy").format(parsedDate);
    } catch (e) {
      return dob;
    }
  }

  void _resetReadOnlyUiState() {
    if (!mounted) return;
    setState(() {
      isCountryPickerFocused = false;
    });
  }

  Future<void> _scrollToField(GlobalKey key) async {
    final context = key.currentContext;
    if (context != null) {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.2,
      );
    }
  }

  Future<void> _focusFirstError() async {
    final name = controller.nameController.text.trim();
    final dob = controller.dobController.text.trim();
    final gender = controller.genderController.text.trim();
    final email = controller.emailController.text.trim();
    final emergency = controller.emergencyController.text.trim();
    final code = controller.selectedCountryCode.value.isEmpty
        ? '+91'
        : controller.selectedCountryCode.value;

    if (name.isEmpty) {
      await _scrollToField(_nameKey);
      FocusScope.of(context).requestFocus(_nameFocus);
      return;
    }

    if (dob.isEmpty) {
      await _scrollToField(_dobKey);
      return;
    }

    if (gender.isEmpty) {
      await _scrollToField(_genderKey);
      return;
    }

    if (email.isEmpty) {
      await _scrollToField(_emailKey);
      FocusScope.of(context).requestFocus(_emailFocus);
      return;
    }

    // Emergency optional
    if (emergency.isNotEmpty) {
      if ((code == '+91' || code == '+234') && emergency.length != 10) {
        await _scrollToField(_emergencyKey);
        FocusScope.of(context).requestFocus(_emergencyFocus);
        return;
      }
    }
  }

  Future<void> _handleEditSave() async {
    if (controller.isEditing.value) {
      final isValid = _formKey.currentState?.validate() ?? false;

      if (!isValid) {
        await _focusFirstError();
        return;
      }

      await controller.saveData(_formKey, context);
      _resetReadOnlyUiState();
      // Save pressed -> drop focus / close the keyboard.
      if (mounted) FocusScope.of(context).unfocus();
    } else {
      // Edit pressed -> enter edit mode and auto-focus the name field.
      controller.toggleEdit();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _scrollToField(_nameKey);
        if (!mounted) return;
        FocusScope.of(context).requestFocus(_nameFocus);
      });
    }
  }

  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          buildMainContent(),
          Obx(() {
            return controller.isLoading.value
                ? Container(
              color: Colors.black.withOpacity(0.4),
              child: Center(child: AppLoader.circularLoader()),
            )
                : const SizedBox.shrink();
          }),
        ],
      ),
      // Fixed Edit / Save action at the bottom.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Obx(() {
            final editing = controller.isEditing.value;
            return SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                key: profileKeys.profileEditButton,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  _handleEditSave();
                },
                style: ElevatedButton.styleFrom(
                  // Save = green (confirm), Edit = black (neutral) → clearly different.
                  backgroundColor:
                      editing ? const Color(0xFF12B76A) : AppColors.commonBlack,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(
                  editing ? Icons.check_circle_rounded : Icons.edit_rounded,
                  size: 20,
                ),
                label: Text(
                  editing ? 'Save' : 'Edit',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget buildMainContent() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFD), Color(0xFFF6F7FF)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          child: buildSettingsContent(),
        ),
      ),
    );
  }

  Widget buildSettingsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildHeader(),
        const SizedBox(height: 20),
        buildProfileSection(),
        buildBasicInfoForm(),
        const SizedBox(height: 24),
      ],
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: AppColors.commonWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.logout, color: Colors.red, size: 28),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Log out',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Do you want to log out?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('No'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _logout(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Yes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final token = await SharedPrefHelper.getToken();
    unawaited(
      Request.sendLogoutFireAndForget(url: ApiConsents.logout, token: token),
    );
    unawaited(SharedPrefHelper.clearToken());
    unawaited(prefs.remove('refreshToken'));
    unawaited(prefs.remove('sessionToken'));
    unawaited(prefs.remove('role'));
    unawaited(prefs.remove('contacts_synced'));

    controller.clearSession();

    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => MobileScreens()),
      (route) => false,
    );
  }

  Widget buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
      child: Row(
        children: [
          if (widget.flag != "bottomBar")
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Image.asset(AppImages.backImage, height: 19, width: 19),
            ),
          const Spacer(),
          CustomTextFields.textWithStyles700('Profile', fontSize: 20),
          const Spacer(),
          // Logout (moved here from the Edit button position).
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showLogoutDialog(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.logout, color: Colors.red, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildProfileSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Stack(
            children: [
              Obx(() {
                final path = controller.profileImagePath.value;
                return ClipOval(
                  child: path.isEmpty
                      ? Container(
                    height: 85,
                    width: 85,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[300],
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 40,
                      color: Colors.white,
                    ),
                  )
                      : path.startsWith('http')
                      ? CachedNetworkImage(
                    imageUrl: path,
                    height: 85,
                    width: 85,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const SizedBox(
                      height: 85,
                      width: 85,
                      child: Center(
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 85,
                      width: 85,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[300],
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  )
                      : Image.file(
                    File(path),
                    height: 85,
                    width: 85,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        Container(
                          height: 85,
                          width: 85,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[300],
                          ),
                          child: const Icon(
                            Icons.person,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                  ),
                );
              }),
              Obx(
                    () => controller.isEditing.value
                    ? Positioned(
                  top: 25,
                  left: 30,
                  child: InkWell(
                    key: profileKeys.profileImage,
                    onTap: pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(
                        AppImages.camera,
                        height: 20,
                        color: Colors.black,
                      ),
                    ),
                  ),
                )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Obx(
                    () => Text(
                  controller.userName.value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Obx(
                    () => Text(
                  "User ID - ${controller.userId.value}",
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildBasicInfoForm() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 25),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomTextFields.textWithStyles700('Basic Info', fontSize: 20),
            const SizedBox(height: 20),

            Container(
              key: _nameKey,
              child: Obx(
                    () => CustomTextFields.textField(
                  filled: true,
                  filledColor: AppColors.commonWhite,
                  controller: controller.nameController,
                  tittle: 'Your Name',
                  hintText: 'Enter Your Name',
                  readOnly: !controller.isEditing.value,
                  focusNode: _nameFocus,
                ),
              ),
            ),
            const SizedBox(height: 24),

            Container(
              key: _dobKey,
              child: Obx(
                    () => AbsorbPointer(
                  absorbing: !controller.isEditing.value,
                  child: CustomTextFields.datePickerField(
                    filled: true,
                    filledColor: AppColors.commonWhite,
                    formKey: _formKey1,
                    context: context,
                    title: 'Date of Birth',
                    hintText: 'Select your DOB',
                    controller: controller.dobController,
                    readOnly: !controller.isEditing.value,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            Container(
              key: _genderKey,
              child: Obx(
                    () => AbsorbPointer(
                  absorbing: !controller.isEditing.value,
                  child: CustomTextFields.dropDown(
                    filled: true,
                    filledColor: AppColors.commonWhite,
                    controller: controller.genderController,
                    title: 'Gender',
                    hintText: 'Select gender',
                    readOnly: !controller.isEditing.value,
                    onTap: () {
                      if (controller.isEditing.value) {
                        CustomBottomSheet.showOptionsBottomSheet(
                          title: 'Select Gender',
                          options: ['Male', 'Female', 'Other'],
                          context: context,
                          controller: controller.genderController,
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            Container(
              key: _emailKey,
              child: Obx(
                    () => CustomTextFields.textField(
                  filled: true,
                  filledColor: AppColors.commonWhite,
                  controller: controller.emailController,
                  tittle: 'Your Email',
                  hintText: 'Enter your Email',
                  readOnly: !controller.isEditing.value,
                  focusNode: _emailFocus,
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Emergency Number (Optional)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),

            Container(
              key: _emergencyKey,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Obx(
                          () => IgnorePointer(
                        ignoring: !controller.isEditing.value,
                        child: GestureDetector(
                          onTapDown: (_) {
                            if (controller.isEditing.value) {
                              setState(() => isCountryPickerFocused = true);
                            }
                          },
                          onTapUp: (_) {
                            if (controller.isEditing.value) {
                              Future.delayed(
                                const Duration(milliseconds: 200),
                                    () {
                                  if (mounted) {
                                    setState(
                                          () => isCountryPickerFocused = false,
                                    );
                                  }
                                },
                              );
                            }
                          },
                          onTapCancel: () {
                            if (mounted) {
                              setState(() => isCountryPickerFocused = false);
                            }
                          },
                          onTap: () {
                            if (controller.isEditing.value) {
                              showCountryPicker(
                                context: context,
                                showPhoneCode: true,
                                showSearch: true,
                                searchAutofocus: true,
                                countryListTheme: CountryListThemeData(
                                  flagSize: 22,
                                  backgroundColor: Colors.white,
                                  bottomSheetHeight: 600,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(30.0),
                                    topRight: Radius.circular(30.0),
                                  ),
                                  searchTextStyle:
                                  const TextStyle(color: Colors.black),
                                  inputDecoration: InputDecoration(
                                    hintText: 'Search',
                                    hintStyle:
                                    const TextStyle(color: Colors.grey),
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: Colors.black,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: const BorderSide(
                                        color: Colors.black,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: const BorderSide(
                                        color: Colors.black,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding:
                                    const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                                onSelect: (Country country) {
                                  controller.selectedCountryCode.value =
                                  '+${country.phoneCode}';
                                  controller.selectedCountryFlag.value =
                                      country.flagEmoji;
                                },
                              );
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.commonWhite,
                              border: Border.all(
                                color: isCountryPickerFocused
                                    ? Colors.black
                                    : Colors.grey.shade400,
                                width: isCountryPickerFocused ? 1.5 : 1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  controller.selectedCountryFlag.value.isEmpty
                                      ? '🇮🇳'
                                      : controller.selectedCountryFlag.value,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  controller.selectedCountryCode.value.isEmpty
                                      ? '+91'
                                      : controller.selectedCountryCode.value,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    flex: 4,
                    child: Obx(
                          () => TextFormField(
                        focusNode: _emergencyFocus,
                        readOnly: !controller.isEditing.value,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        controller: controller.emergencyController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(10),
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (value) {
                          final code =
                          controller.selectedCountryCode.value.isEmpty
                              ? '+91'
                              : controller.selectedCountryCode.value;

                          // optional field
                          if (value.trim().isEmpty) {
                            controller.errorText.value = '';
                          } else if (code == '+91' && value.length != 10) {
                            controller.errorText.value =
                            'Indian numbers must be exactly 10 digits';
                          } else if (code == '+234' && value.length != 10) {
                            controller.errorText.value =
                            'Nigerian numbers must be exactly 10 digits';
                          } else {
                            controller.errorText.value = '';
                          }

                          _formKey.currentState?.validate();
                        },
                        validator: (value) {
                          final code =
                          controller.selectedCountryCode.value.isEmpty
                              ? '+91'
                              : controller.selectedCountryCode.value;

                          // optional field
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }

                          if (code == '+91' && value.length != 10) {
                            return 'Indian numbers must be exactly 10 digits';
                          }

                          if (code == '+234' && value.length != 10) {
                            return 'Nigerian numbers must be exactly 10 digits';
                          }

                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: 'Enter mobile number',
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 10,
                          ),
                          filled: true,
                          fillColor: AppColors.commonWhite,
                          enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Colors.grey,
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Colors.black,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Colors.red,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Colors.red,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Obx(
                  () => CustomTextFields.mobileNumber(
                prefixIcon: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  child: Text(
                    controller.code.value.isNotEmpty
                        ? controller.code.value
                        : "+91",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                readOnly: true,
                title: 'Mobile Number',
                initialValue: controller.mobileNumber,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// import 'dart:io';
// import 'package:country_picker/country_picker.dart';
//
// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:hopper/Core/Utility/app_loader.dart';
// import 'package:hopper/Core/Utility/app_showcase_key.dart';
// import 'package:hopper/Core/Utility/compressImage.dart';
// import 'package:hopper/Core/Utility/country_picker.dart';
// import 'package:hopper/Core/Utility/country_picker.dart' as CountryPicker;
// import 'package:hopper/TutorialService_widgets.dart';
// import 'package:intl/intl.dart';
//
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:hopper/Core/Consents/app_colors.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/Core/Utility/customBottemSheet.dart';
//
// import 'package:image_picker/image_picker.dart';
//
// import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
// import 'package:get/get.dart';
// import 'package:hopper/Presentation/Drawer/controller/profle_cotroller.dart';
//
// class SettingsScreen extends StatefulWidget {
//   final String? flag;
//   const SettingsScreen({super.key, this.flag});
//
//   @override
//   State<SettingsScreen> createState() => _SettingsScreenState();
// }
//
// class _SettingsScreenState extends State<SettingsScreen> {
//   final ProfleCotroller controller = Get.find<ProfleCotroller>();
//   bool isCountryPickerFocused = false;
//   final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
//   final GlobalKey<FormState> _formKey1 = GlobalKey<FormState>();
//   // Future<void> pickImage() async {
//   //   final picker = ImagePicker();
//   //   final pickedFile = await picker.pickImage(source: ImageSource.gallery);
//   //   if (pickedFile != null) {
//   //     controller.setProfileImage(pickedFile.path);
//   //   }
//   // }
//   Future<void> pickImage() async {
//     try {
//       final picker = ImagePicker();
//       final pickedFile = await picker.pickImage(source: ImageSource.gallery);
//
//       if (pickedFile == null) return;
//       if (!mounted) return;
//
//       final originalFile = File(pickedFile.path);
//       printImageSize(originalFile, label: 'Original');
//
//       final compressedFile = await compressImage(
//         originalFile,
//         quality: 70,
//         minWidth: 1080,
//         minHeight: 1080,
//       );
//
//       final fileToUse = compressedFile ?? originalFile;
//       printImageSize(fileToUse, label: 'Final');
//
//       controller.setProfileImage(fileToUse.path);
//     } catch (e) {
//       debugPrint('pickImage error: $e');
//     }
//   }
//
//   final ShowcaseKeys profileKeys = ShowcaseKeys();
//
//   @override
//   void initState() {
//     super.initState();
//     if (controller.user.value == null) {
//       controller.getProfileData();
//     }
//
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) return;
//       // Pass the keys to the tutorial (this fixes: "Required named parameter 'keys' must be provided")
//       TutorialService.showProfileTutorial(context, keys: profileKeys);
//     });
//   }
//
//   String formatDob(String dob) {
//     try {
//       final parsedDate = DateTime.parse(dob);
//       return DateFormat("d MMMM yyyy").format(parsedDate);
//     } catch (e) {
//       return dob;
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Stack(
//         children: [
//           buildMainContent(),
//           Obx(() {
//             return controller.isLoading.value
//                 ? Container(
//                   color: Colors.black.withOpacity(0.4),
//                   child: Center(child: AppLoader.circularLoader()),
//                 )
//                 : const SizedBox.shrink();
//           }),
//         ],
//       ),
//     );
//   }
//
//   Widget buildMainContent() {
//     return Container(
//       decoration: const BoxDecoration(
//         gradient: LinearGradient(
//           begin: Alignment.topCenter,
//           end: Alignment.bottomCenter,
//           colors: [Color(0xFFFFFFFD), Color(0xFFF6F7FF)],
//         ),
//       ),
//       child: SafeArea(
//         child: SingleChildScrollView(
//           physics: const BouncingScrollPhysics(),
//           child: buildSettingsContent(),
//         ),
//       ),
//     );
//   }
//
//   Widget buildSettingsContent() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         buildHeader(),
//         const SizedBox(height: 20),
//         buildProfileSection(),
//         buildBasicInfoForm(),
//       ],
//     );
//   }
//
//   Widget buildHeader() {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
//       child: Row(
//         children: [
//           if (widget.flag != "bottomBar")
//             GestureDetector(
//               onTap: () => Navigator.pop(context),
//               child: Image.asset(AppImages.backImage, height: 19, width: 19),
//             ),
//           const Spacer(),
//           CustomTextFields.textWithStyles700('Settings', fontSize: 20),
//           const Spacer(),
//           Obx(
//             () => GestureDetector(
//               key:
//                   controller.isEditing.value
//                       ? profileKeys.profileEditButton
//                       : null,
//
//               onTap: () {
//                 if (controller.isEditing.value) {
//                   controller.saveData(_formKey, context);
//                 } else {
//                   controller.toggleEdit();
//                 }
//               },
//               child: Container(
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 11,
//                   vertical: 2,
//                 ),
//                 decoration: BoxDecoration(
//                   color: AppColors.containerColor,
//                   borderRadius: BorderRadius.circular(5),
//                 ),
//                 child: CustomTextFields.textWithStyles600(
//                   controller.isEditing.value ? "Save" : "Edit",
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget buildProfileSection() {
//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Row(
//         children: [
//           Stack(
//             children: [
//               Obx(() {
//                 final path = controller.profileImagePath.value;
//                 return ClipOval(
//                   child:
//                       path.isEmpty
//                           ? Container(
//                             height: 85,
//                             width: 85,
//                             decoration: BoxDecoration(
//                               shape: BoxShape.circle,
//                               color: Colors.grey[300],
//                             ),
//                             child: const Icon(
//                               Icons.person,
//                               size: 40,
//                               color: Colors.white,
//                             ),
//                           )
//                           : path.startsWith('http')
//                           ? CachedNetworkImage(
//                             // key: profileKeys.profileImage,
//                             imageUrl: path,
//                             height: 85,
//                             width: 85,
//                             fit: BoxFit.cover,
//                             placeholder:
//                                 (context, url) => SizedBox(
//                                   height: 85,
//                                   width: 85,
//                                   child: const Center(
//                                     child: SizedBox(
//                                       height: 20,
//                                       width: 20,
//                                       child: CircularProgressIndicator(
//                                         strokeWidth: 2,
//                                       ),
//                                     ),
//                                   ),
//                                 ),
//                             errorWidget:
//                                 (context, url, error) => Container(
//                                   height: 85,
//                                   width: 85,
//                                   decoration: BoxDecoration(
//                                     shape: BoxShape.circle,
//                                     color: Colors.grey[300],
//                                   ),
//                                   child: const Icon(
//                                     Icons.person,
//                                     size: 40,
//                                     color: Colors.white,
//                                   ),
//                                 ),
//                           )
//                           : Image.file(
//                             File(path),
//                             height: 85,
//                             width: 85,
//                             fit: BoxFit.cover,
//                             errorBuilder:
//                                 (context, error, stackTrace) => Container(
//                                   height: 85,
//                                   width: 85,
//                                   decoration: BoxDecoration(
//                                     shape: BoxShape.circle,
//                                     color: Colors.grey[300],
//                                   ),
//                                   child: const Icon(
//                                     Icons.person,
//                                     size: 40,
//                                     color: Colors.white,
//                                   ),
//                                 ),
//                           ),
//                 );
//               }),
//               Obx(
//                 () =>
//                     controller.isEditing.value
//                         ? Positioned(
//                           top: 25,
//                           left: 30,
//                           child: InkWell(
//                             key: profileKeys.profileImage,
//                             onTap: () {
//                               pickImage();
//                             },
//                             child: Container(
//                               padding: const EdgeInsets.all(5),
//                               decoration: const BoxDecoration(
//                                 color: Colors.white,
//                                 shape: BoxShape.circle,
//                               ),
//                               child: Image.asset(
//                                 AppImages.camera,
//                                 height: 20,
//                                 color: Colors.black,
//                               ),
//                             ),
//                           ),
//                         )
//                         : const SizedBox.shrink(),
//               ),
//             ],
//           ),
//           const SizedBox(width: 16),
//           Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Obx(
//                 () => Text(
//                   controller.userName.value,
//                   style: const TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 4),
//               Obx(
//                 () => Text(
//                   "User ID - ${controller.userId.value}",
//                   style: const TextStyle(fontSize: 14, color: Colors.grey),
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget buildBasicInfoForm() {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 25),
//       child: Form(
//         key: _formKey,
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             CustomTextFields.textWithStyles700('Basic Info', fontSize: 20),
//             const SizedBox(height: 20),
//             Obx(
//               () => CustomTextFields.textField(
//                 filled: true,
//                 filledColor: AppColors.commonWhite,
//                 controller: controller.nameController,
//                 tittle: 'Your Name',
//                 hintText: 'Enter Your Name',
//                 readOnly: !controller.isEditing.value,
//               ),
//             ),
//             const SizedBox(height: 24),
//             Obx(
//               () => CustomTextFields.datePickerField(
//                 filled: true,
//                 filledColor: AppColors.commonWhite,
//                 formKey: _formKey1,
//                 context: context,
//                 title: 'Date of Birth',
//                 hintText: 'Select your DOB',
//                 controller: controller.dobController,
//                 readOnly: !controller.isEditing.value,
//               ),
//             ),
//             const SizedBox(height: 24),
//             Obx(
//               () => CustomTextFields.dropDown(
//                 filled: true,
//                 filledColor: AppColors.commonWhite,
//                 controller: controller.genderController,
//                 title: 'Gender',
//                 hintText: 'Select gender',
//                 readOnly: !controller.isEditing.value,
//                 onTap: () {
//                   if (controller.isEditing.value) {
//                     CustomBottomSheet.showOptionsBottomSheet(
//                       title: 'Select Gender',
//                       options: ['Male', 'Female', 'Other'],
//                       context: context,
//                       controller: controller.genderController,
//                     );
//                   }
//                 },
//               ),
//             ),
//             const SizedBox(height: 24),
//             Obx(
//               () => CustomTextFields.textField(
//                 filled: true,
//                 filledColor: AppColors.commonWhite,
//                 controller: controller.emailController,
//                 tittle: 'Your Email',
//                 hintText: 'Enter your Email',
//                 readOnly: !controller.isEditing.value,
//               ),
//             ),
//             const SizedBox(height: 24),
//
//             Text(
//               'Emergency Number',
//               style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
//             ),
//             const SizedBox(height: 10),
//             Row(
//               children: [
//                 Expanded(
//                   flex: 2,
//                   child: GestureDetector(
//                     onTapDown: (_) {
//                       setState(() => isCountryPickerFocused = true);
//                     },
//                     onTapUp: (_) {
//                       // Remove focus after a short delay
//                       Future.delayed(const Duration(milliseconds: 200), () {
//                         setState(() => isCountryPickerFocused = false);
//                       });
//                     },
//                     onTap: () {
//                       if (controller.isEditing.value) {
//                         showCountryPicker(
//                           context: context,
//                           showPhoneCode: true,
//                           showSearch: true,
//                           searchAutofocus: true,
//                           countryListTheme: CountryListThemeData(
//                             flagSize: 22,
//                             backgroundColor: Colors.white,
//                             bottomSheetHeight: 600,
//                             borderRadius: const BorderRadius.only(
//                               topLeft: Radius.circular(30.0),
//                               topRight: Radius.circular(30.0),
//                             ),
//                             searchTextStyle: const TextStyle(
//                               color: Colors.black,
//                             ),
//                             inputDecoration: InputDecoration(
//                               hintText: 'Search',
//                               hintStyle: const TextStyle(color: Colors.grey),
//                               prefixIcon: const Icon(
//                                 Icons.search,
//                                 color: Colors.black,
//                               ),
//                               enabledBorder: OutlineInputBorder(
//                                 borderSide: const BorderSide(
//                                   color: Colors.black,
//                                 ),
//                                 borderRadius: BorderRadius.circular(8),
//                               ),
//                               focusedBorder: OutlineInputBorder(
//                                 borderSide: const BorderSide(
//                                   color: Colors.black,
//                                   width: 2,
//                                 ),
//                                 borderRadius: BorderRadius.circular(8),
//                               ),
//                               contentPadding: const EdgeInsets.symmetric(
//                                 horizontal: 12,
//                                 vertical: 10,
//                               ),
//                             ),
//                           ),
//                           onSelect: (Country country) {
//                             controller.selectedCountryCode.value =
//                                 '+${country.phoneCode}';
//                             controller.selectedCountryFlag.value =
//                                 country.flagEmoji;
//                           },
//                         );
//                       }
//                     },
//
//                     child: Obx(
//                       () => AnimatedContainer(
//                         duration: const Duration(milliseconds: 200),
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 10,
//                           vertical: 11,
//                         ),
//                         decoration: BoxDecoration(
//                           color: AppColors.commonWhite,
//                           border: Border.all(
//                             color:
//                                 isCountryPickerFocused
//                                     ? Colors.black
//                                     : Colors.grey.shade400,
//                             width: isCountryPickerFocused ? 1.5 : 1,
//                           ),
//                           borderRadius: BorderRadius.circular(4),
//                         ),
//                         child: Row(
//                           children: [
//                             Text(
//                               controller.selectedCountryFlag.value.isEmpty
//                                   ? '🇮🇳'
//                                   : controller.selectedCountryFlag.value,
//                               style: const TextStyle(fontSize: 16),
//                             ),
//                             const SizedBox(width: 4),
//                             Text(
//                               controller.selectedCountryCode.value.isEmpty
//                                   ? '+91'
//                                   : controller.selectedCountryCode.value,
//                               style: const TextStyle(fontSize: 14),
//                             ),
//                             const Icon(Icons.arrow_drop_down),
//                           ],
//                         ),
//                       ),
//                     ),
//                   ),
//                 ),
//
//                 const SizedBox(width: 5),
//
//                 // 📱 Mobile Number Field with Validation
//                 Expanded(
//                   flex: 4,
//                   child: TextFormField(
//                     readOnly: !controller.isEditing.value,
//                     autovalidateMode: AutovalidateMode.onUserInteraction,
//                     controller: controller.emergencyController,
//                     keyboardType: TextInputType.phone,
//                     inputFormatters: [
//                       LengthLimitingTextInputFormatter(10),
//                       FilteringTextInputFormatter.digitsOnly,
//                     ],
//                     onChanged: (value) {
//                       final code = controller.selectedCountryCode.value;
//
//                       if (value.isEmpty) {
//                         controller.errorText.value =
//                             'Please enter your Mobile Number';
//                       } else if (code == '+91' && value.length != 10) {
//                         controller.errorText.value =
//                             'Indian numbers must be exactly 10 digits';
//                       } else if (code == '+234' && value.length != 10) {
//                         controller.errorText.value =
//                             'Nigerian numbers must be exactly 10 digits';
//                       } else {
//                         controller.errorText.value = '';
//                       }
//
//                       _formKey.currentState?.validate();
//                     },
//                     decoration: InputDecoration(
//                       hintText: 'Enter mobile number',
//                       contentPadding: const EdgeInsets.symmetric(
//                         vertical: 12,
//                         horizontal: 10,
//                       ),
//                       filled: true,
//                       fillColor: AppColors.commonWhite,
//
//                       // ✅ Border when NOT focused
//                       enabledBorder: OutlineInputBorder(
//                         borderSide: const BorderSide(
//                           color: Colors.grey,
//                           width: 1,
//                         ),
//                         borderRadius: BorderRadius.circular(4),
//                       ),
//
//                       // ✅ Border when focused
//                       focusedBorder: OutlineInputBorder(
//                         borderSide: const BorderSide(
//                           color: Colors.black,
//                           width: 1.5,
//                         ),
//                         borderRadius: BorderRadius.circular(4),
//                       ),
//
//                       // ✅ Border when there’s an error
//                       errorBorder: OutlineInputBorder(
//                         borderSide: const BorderSide(
//                           color: Colors.red,
//                           width: 1.5,
//                         ),
//                         borderRadius: BorderRadius.circular(4),
//                       ),
//
//                       // ✅ Border when focused + error
//                       focusedErrorBorder: OutlineInputBorder(
//                         borderSide: const BorderSide(
//                           color: Colors.red,
//                           width: 1.5,
//                         ),
//                         borderRadius: BorderRadius.circular(4),
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 24),
//
//             Obx(
//               () => CustomTextFields.mobileNumber(
//                 prefixIcon: Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 10),
//                   alignment: Alignment.center,
//                   child: Text(
//                     controller.code.value.isNotEmpty
//                         ? controller.code.value
//                         : "+91",
//                     style: const TextStyle(
//                       fontSize: 16,
//                       fontWeight: FontWeight.w500,
//                     ),
//                   ),
//                 ),
//                 readOnly: true,
//                 title: 'Mobile Number',
//                 initialValue: controller.mobileNumber,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
