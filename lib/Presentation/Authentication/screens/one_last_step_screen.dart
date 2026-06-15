import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/Authentication/screens/post_otp_routing_screen.dart';
import 'package:hopper/Presentation/Drawer/controller/profle_cotroller.dart';

/// First-open details screen for new users (isNewUser == true OR
/// isProfileCompleted == false). Collects Name, Date of birth and Gender, then
/// submits via the same profile API and continues to the home flow.
class OneLastStepScreen extends StatefulWidget {
  const OneLastStepScreen({super.key, this.initialName = ''});

  final String initialName;

  @override
  State<OneLastStepScreen> createState() => _OneLastStepScreenState();
}

class _OneLastStepScreenState extends State<OneLastStepScreen> {
  static const Color _green = Color(0xFF15803D);

  final TextEditingController _nameC = TextEditingController();
  DateTime? _dob;
  String _gender = '';

  final ProfleCotroller _profile =
      Get.isRegistered<ProfleCotroller>()
          ? Get.find<ProfleCotroller>()
          : Get.put(ProfleCotroller());

  @override
  void initState() {
    super.initState();
    final n = widget.initialName.trim();
    if (n.isNotEmpty && n.toLowerCase() != 'guest') _nameC.text = n;
  }

  @override
  void dispose() {
    _nameC.dispose();
    super.dispose();
  }

  bool get _valid =>
      _nameC.text.trim().isNotEmpty && _gender.isNotEmpty && _dob != null;

  String get _dobLabel {
    final d = _dob;
    if (d == null) return 'Select your date of birth';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _pickDob() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1940),
      lastDate: now,
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: _green),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    if (!_valid) {
      AppToasts.showInfoGlobal('Please fill name, date of birth and gender.');
      return;
    }
    final d = _dob!;
    final dobIso =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final res = await _profile.submitProfileData(
      firstName: _nameC.text.trim(),
      lastName: '',
      dateOfBirth: dobIso,
      gender: _gender,
      email: '',
      emergencyNumber: '',
      countryCode: '',
      profileImage: '',
      context: context,
    );

    // submitProfileData returns null on failure (it already shows the error).
    if (res == null || !mounted) return;

    // Profile is now complete -> never show this screen again on re-route.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isProfileCompleted', true);
    await prefs.setBool('isNewUser', false);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PostOtpRoutingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'One last step',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const SizedBox(height: 6),
            const Text(
              'Your name',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameC,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Type your name',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _green, width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Date of birth',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickDob,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 18,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _dobLabel,
                      style: TextStyle(
                        fontSize: 15,
                        color: _dob == null ? Colors.grey.shade500 : Colors.black,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Gender',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _genderChip('Male'),
                const SizedBox(width: 12),
                _genderChip('Female'),
                const SizedBox(width: 12),
                _genderChip('Other'),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Obx(
            () => AppButtons.button(
              text: 'Next',
              isLoading: _profile.isLoading.value,
              buttonColor: _valid ? AppColors.commonBlack : AppColors.containerColor,
              textColor: Colors.white,
              onTap: _valid ? _submit : () {},
            ),
          ),
        ),
      ),
    );
  }

  Widget _genderChip(String value) {
    final selected = _gender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = value),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: selected ? AppColors.commonBlack : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.commonBlack : Colors.grey.shade300,
            ),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
