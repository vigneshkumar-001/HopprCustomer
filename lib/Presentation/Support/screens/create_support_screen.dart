import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/Support/controller/support_controller.dart';
import 'package:hopper/Presentation/Support/screens/support_chat_screen.dart';
import 'package:image_picker/image_picker.dart';

class CreateSupportScreen extends StatefulWidget {
  final String? prefillBookingId;
  const CreateSupportScreen({super.key, this.prefillBookingId});

  @override
  State<CreateSupportScreen> createState() => _CreateSupportScreenState();
}

class _CreateSupportScreenState extends State<CreateSupportScreen> {
  final SupportController c =
      Get.isRegistered<SupportController>()
          ? Get.find<SupportController>()
          : Get.put(SupportController());

  final TextEditingController subjectCtrl = TextEditingController();
  final TextEditingController descCtrl = TextEditingController();
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    final b = (widget.prefillBookingId ?? '').trim();
    if (b.isNotEmpty) {
      subjectCtrl.text = 'Ride support (Booking #$b)';
    }
  }

  @override
  void dispose() {
    subjectCtrl.dispose();
    descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      setState(() => _imagePath = file.path);
    } catch (_) {
      if (!mounted) return;
      AppToasts.showError(context, 'Failed to pick image');
    }
  }

  void _createNow() {
    final subject = subjectCtrl.text.trim();
    final desc = descCtrl.text.trim();
    if (subject.isEmpty || desc.isEmpty) {
      AppToasts.showError(context, 'Please fill subject and description');
      return;
    }

    final t = c.createTicket(
      subject: subject,
      description: desc,
      bookingId: widget.prefillBookingId,
      attachmentPath: _imagePath,
    );
    Get.off(() => SupportChatScreen(ticketId: t.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Create Support',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: InkWell(
            onTap: () => Get.back(),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          children: [
            const Text(
              'Subject',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _field(subjectCtrl, maxLines: 1),
            const SizedBox(height: 24),
            const Text(
              'Description',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _field(descCtrl, maxLines: 8),
            const SizedBox(height: 24),
            Row(
              children: const [
                Text(
                  'Upload Photo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                SizedBox(width: 8),
                Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF98A2B3)),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF98A2B3)),
                    const SizedBox(width: 10),
                    Text(
                      _imagePath == null ? 'Upload Image' : 'Image selected',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF98A2B3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_imagePath != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(_imagePath!),
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _createNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.commonBlack,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Create Now',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 12),
                    Icon(Icons.arrow_forward_rounded, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, {required int maxLines}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}

