import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/CustomerSupport/controller/customer_support_controller.dart';
import 'package:hopper/Presentation/CustomerSupport/models/customer_support_models.dart';
import 'package:hopper/Presentation/CustomerSupport/screens/customer_support_list_screen.dart';
import 'package:image_picker/image_picker.dart';

class CreateCustomerSupportScreen extends StatefulWidget {
  final String? prefillBookingId;
  const CreateCustomerSupportScreen({super.key, this.prefillBookingId});

  @override
  State<CreateCustomerSupportScreen> createState() =>
      _CreateCustomerSupportScreenState();
}

class _CreateCustomerSupportScreenState
    extends State<CreateCustomerSupportScreen> {
  late final CustomerSupportController c;
  final _title = TextEditingController();
  final _desc = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final List<File> _attachments = <File>[];

  bool _submitting = false;

  String? _categoryId;
  String? _subcategoryId;
  String? _priorityId;

  void _showSnack(String title, String message) {
    final normalized = title.trim().toLowerCase();
    if (normalized == 'success') {
      AppToasts.showSuccessGlobal(message);
      return;
    }

    if (normalized == 'failed' ||
        normalized == 'error' ||
        normalized.contains('missing')) {
      AppToasts.showErrorGlobal(message, title: title);
      return;
    }

    AppToasts.showInfoGlobal(message, title: title);
  }
  @override
  void initState() {
    super.initState();
    c =
        Get.isRegistered<CustomerSupportController>()
            ? Get.find<CustomerSupportController>()
            : Get.put(CustomerSupportController());

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await c.ensureCommonDetailsLoaded();
      if (!mounted) return;
      final meta = c.commonDetails.value;
      if (meta == null) return;

      if ((_categoryId ?? '').trim().isEmpty && meta.categories.isNotEmpty) {
        setState(() {
          _categoryId = meta.categories.first.id;
          _subcategoryId =
              meta.categories.first.subcategories.isNotEmpty
                  ? meta.categories.first.subcategories.first.id
                  : null;
          _priorityId =
              meta.priorities.isNotEmpty ? meta.priorities.first.id : null;
        });
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (picked == null) return;
      setState(() => _attachments.add(File(picked.path)));
    } catch (_) {}
  }

  Future<void> _showPickSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Camera'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _pickAttachment(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Gallery'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _pickAttachment(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickCategory(SupportCommonDetailsData meta) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            itemCount: meta.categories.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final item = meta.categories[i];
              final selected = item.id == _categoryId;
              return ListTile(
                title: Text(
                  item.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                trailing:
                    selected
                        ? const Icon(Icons.check_circle, color: Colors.black)
                        : null,
                onTap: () {
                  setState(() {
                    _categoryId = item.id;
                    _subcategoryId =
                        item.subcategories.isNotEmpty
                            ? item.subcategories.first.id
                            : null;
                  });
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _pickSubcategory(SupportCommonDetailsData meta) async {
    final categoryId = (_categoryId ?? '').trim();
    final cat = meta.categoryById(categoryId);
    if (cat == null) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            itemCount: cat.subcategories.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final item = cat.subcategories[i];
              final selected = item.id == _subcategoryId;
              return ListTile(
                title: Text(
                  item.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                trailing:
                    selected
                        ? const Icon(Icons.check_circle, color: Colors.black)
                        : null,
                onTap: () {
                  setState(() => _subcategoryId = item.id);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _pickPriority(SupportCommonDetailsData meta) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            itemCount: meta.priorities.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final item = meta.priorities[i];
              final selected = item.id == _priorityId;
              return ListTile(
                title: Text(
                  item.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                trailing:
                    selected
                        ? const Icon(Icons.check_circle, color: Colors.black)
                        : null,
                onTap: () {
                  setState(() => _priorityId = item.id);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _create() async {
    if (_submitting) return;

    final subject = _title.text.trim();
    final desc = _desc.text.trim();

    final categoryId = (_categoryId ?? '').trim();
    final subcategoryId = (_subcategoryId ?? '').trim();
    final priorityId = (_priorityId ?? '').trim();

    if (subject.isEmpty || desc.isEmpty) {
      _showSnack('Missing info', 'Please enter title and description');
      return;
    }

    if (categoryId.isEmpty || subcategoryId.isEmpty || priorityId.isEmpty) {
      _showSnack(
        'Missing info',
        'Please select category, subcategory and priority',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final List<String> urls = <String>[];
      for (final f in _attachments) {
        final url = await c.uploadAttachment(f);
        if (url != null && url.trim().isNotEmpty) urls.add(url.trim());
      }

      final created = await c.createTicket(
        subject: subject,
        description: desc,
        categoryId: categoryId,
        subcategoryId: subcategoryId,
        priority: priorityId,
        bookingId: widget.prefillBookingId,
        attachments: urls,
      );

      if (!mounted) return;

      if (created == null) {
        final apiMsg = c.lastApiMessage.value.trim();
        _showSnack(
          'Failed',
          apiMsg.isEmpty
              ? (c.error.value.isEmpty
                  ? 'Failed to create ticket'
                  : c.error.value)
              : apiMsg,
        );
        return;
      }

      final apiMsg = c.lastApiMessage.value.trim();
      _showSnack('Success', apiMsg.isEmpty ? 'Support ticket created' : apiMsg);
      Get.off(
        () => CustomerSupportListScreen(bookingId: widget.prefillBookingId),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _selectTile({
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black),
          ],
        ),
      ),
    );
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
            fontSize: 16,
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Title',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _title,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF2F4F7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _desc,
                minLines: 6,
                maxLines: 10,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF2F4F7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Issue details',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              Obx(() {
                final meta = c.commonDetails.value;
                if (meta == null) {
                  return Column(
                    children: [
                      _selectTile(
                        label: 'Category',
                        value: 'Loading...',
                        onTap: null,
                      ),
                      const SizedBox(height: 12),
                      _selectTile(
                        label: 'Subcategory',
                        value: 'Loading...',
                        onTap: null,
                      ),
                      const SizedBox(height: 12),
                      _selectTile(
                        label: 'Priority',
                        value: 'Loading...',
                        onTap: null,
                      ),
                    ],
                  );
                }

                final category = meta.categoryById((_categoryId ?? '').trim());
                final subcategory = category?.subcategoryById(
                  (_subcategoryId ?? '').trim(),
                );
                final priority = meta.priorityById((_priorityId ?? '').trim());

                return Column(
                  children: [
                    _selectTile(
                      label: 'Category',
                      value: category?.label ?? 'Select',
                      onTap:
                          meta.categories.isEmpty
                              ? null
                              : () => _pickCategory(meta),
                    ),
                    const SizedBox(height: 12),
                    _selectTile(
                      label: 'Subcategory',
                      value: subcategory?.label ?? 'Select',
                      onTap:
                          (category == null || category.subcategories.isEmpty)
                              ? null
                              : () => _pickSubcategory(meta),
                    ),
                    const SizedBox(height: 12),
                    _selectTile(
                      label: 'Priority',
                      value: priority?.label ?? 'Select',
                      onTap:
                          meta.priorities.isEmpty
                              ? null
                              : () => _pickPriority(meta),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 18),
              Row(
                children: const [
                  Text(
                    'Upload Photo',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Colors.blue,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: _showPickSheet,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  height: 60,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: Color(0xFF98A2B3),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Upload Image',
                        style: TextStyle(
                          color: Color(0xFF98A2B3),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(_attachments.length, (i) {
                    final f = _attachments[i];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(
                            f,
                            width: 92,
                            height: 92,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: InkWell(
                            onTap:
                                () => setState(() => _attachments.removeAt(i)),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            height: 58,
            child: ElevatedButton(
              onPressed: _submitting ? null : _create,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.commonBlack,
                disabledBackgroundColor: AppColors.commonBlack.withOpacity(0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
              child:
                  _submitting
                      ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                      : const Row(
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
                          SizedBox(width: 14),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                          ),
                        ],
                      ),
            ),
          ),
        ),
      ),
    );
  }
}
