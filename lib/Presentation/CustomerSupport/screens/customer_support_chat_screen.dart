import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/CustomerSupport/controller/customer_support_controller.dart';
import 'package:hopper/Presentation/CustomerSupport/models/customer_support_models.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

class CustomerSupportChatScreen extends StatefulWidget {
  final String ticketId;
  const CustomerSupportChatScreen({super.key, required this.ticketId});

  @override
  State<CustomerSupportChatScreen> createState() =>
      _CustomerSupportChatScreenState();
}

class _CustomerSupportChatScreenState extends State<CustomerSupportChatScreen> {
  late final CustomerSupportController c;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _loadingDetails = false;
  bool _sendingMessage = false;
  final List<File> _pendingAttachmentFiles = <File>[];
  final ImagePicker _picker = ImagePicker();
  Worker? _sendErrorWorker;
  bool _didInitialAutoScroll = false;

  @override
  void initState() {
    super.initState();
    c =
        Get.isRegistered<CustomerSupportController>()
            ? Get.find<CustomerSupportController>()
            : Get.put(CustomerSupportController());

    _sendErrorWorker = ever<String>(c.sendError, (msg) {
      final m = msg.trim();
      if (m.isEmpty) return;
      AppToasts.showErrorGlobal(m, title: 'Error');
      c.sendError.value = '';
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (c.ticketById(widget.ticketId) == null) {
        await c.refreshTickets();
      }
      if (mounted) setState(() => _loadingDetails = true);
      await c.refreshTicketDetails(widget.ticketId);
      if (mounted) setState(() => _loadingDetails = false);
      _jumpBottom();
    });
  }

  @override
  void dispose() {
    _sendErrorWorker?.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _send() async {
    if (_sendingMessage) return;

    final msg = _text.text.trim();
    if (msg.isEmpty && _pendingAttachmentFiles.isEmpty) return;

    if (mounted) setState(() => _sendingMessage = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());

    try {
      final files = List<File>.from(_pendingAttachmentFiles);
      _text.clear();
      _pendingAttachmentFiles.clear();

      await c.sendMessageWithFiles(
        ticketId: widget.ticketId,
        text: msg,
        attachmentFiles: files,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  Future<void> _pickAndUploadAttachment() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
      );
      if (x == null) return;

      if (!mounted) return;
      setState(() => _pendingAttachmentFiles.add(File(x.path)));
    } catch (_) {
      // ignore
    }
  }

  Widget _attachmentPreviewBar() {
    if (_pendingAttachmentFiles.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pendingAttachmentFiles.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final file = _pendingAttachmentFiles[i];
            return Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    file,
                    height: 64,
                    width: 64,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) => Container(
                          height: 64,
                          width: 64,
                          color: const Color(0xFFF2F4F7),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: Color(0xFF98A2B3),
                          ),
                        ),
                  ),
                ),
                Positioned(
                  top: -8,
                  right: -8,
                  child: InkWell(
                    onTap: () {
                      setState(() => _pendingAttachmentFiles.removeAt(i));
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 22,
                      width: 22,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('hh.mma');
    final dateFmt = DateFormat('dd.MM.yy');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Support Chat',
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
        child: Column(
          children: [
            Obx(() {
              final t = c.ticketById(widget.ticketId);
              if (t == null) return const SizedBox(height: 12);

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFE4E7EC))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.status.label,
                            style: TextStyle(
                              color: t.status.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t.subject,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Created on ${dateFmt.format(t.createdAt)}',
                            style: const TextStyle(
                              color: Color(0xFF98A2B3),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 54,
                      width: 86,
                      child: ElevatedButton(
                        onPressed: () {
                          Get.back();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.commonBlack,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Close\nTicket',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            Expanded(
              child: Obx(() {
                final t = c.ticketById(widget.ticketId);
                final messages = t?.messages ?? const [];

                if (_loadingDetails) {
                  return const Center(
                    child: CupertinoActivityIndicator(radius: 14),
                  );
                }

                if (t == null && c.isLoading.value) {
                  return const Center(
                    child: CupertinoActivityIndicator(radius: 14),
                  );
                }

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }

                if (!_didInitialAutoScroll) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _didInitialAutoScroll) return;
                    setState(() => _didInitialAutoScroll = true);
                    _jumpBottom();
                  });
                }

                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    final isCustomer = m.fromCustomer;
                    final bubbleColor =
                        isCustomer
                            ? const Color(0xFF101828)
                            : const Color(0xFFF2F4F7);
                    final textColor = isCustomer ? Colors.white : Colors.black;
                    final timeColor =
                        isCustomer
                            ? Colors.white.withOpacity(0.6)
                            : const Color(0xFF98A2B3);

                    final canRetry =
                        isCustomer &&
                        m.sendState == CustomerSupportMessageSendState.failed;

                    return Align(
                      alignment:
                          isCustomer
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                      child: InkWell(
                        onTap:
                            canRetry
                                ? () => c.retryFailedMessage(
                                  ticketId: widget.ticketId,
                                  messageId: m.id,
                                )
                                : null,
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78,
                          ),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          decoration: BoxDecoration(
                            color: bubbleColor,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            if ((m.localImagePath ?? '').trim().isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    Image.file(
                                      File(m.localImagePath!.trim()),
                                      height: 140,
                                      width: 240,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (_, __, ___) =>
                                              const SizedBox.shrink(),
                                    ),
                                    Positioned(
                                      right: 10,
                                      bottom: 10,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.45),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child:
                                            m.sendState ==
                                                    CustomerSupportMessageSendState.failed
                                                ? const Icon(
                                                  Icons.refresh_rounded,
                                                  size: 18,
                                                  color: Colors.white,
                                                )
                                                : const CupertinoActivityIndicator(
                                                  radius: 9,
                                                ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                            ] else if ((m.imageUrl ?? '').trim().isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CachedNetworkImage(
                                  imageUrl: m.imageUrl!.trim(),
                                  height: 140,
                                  width: 240,
                                  fit: BoxFit.cover,
                                  placeholder:
                                      (_, __) => const SizedBox(
                                        height: 140,
                                        width: 240,
                                        child: Center(
                                          child: CupertinoActivityIndicator(
                                            radius: 12,
                                          ),
                                        ),
                                      ),
                                  errorWidget:
                                      (_, __, ___) =>
                                          const SizedBox.shrink(),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            Text(
                              m.text,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  timeFmt.format(m.createdAt).toLowerCase(),
                                  style: TextStyle(
                                    color: timeColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                if (isCustomer) ...[
                                  const SizedBox(width: 8),
                                  if (m.sendState ==
                                      CustomerSupportMessageSendState.sending)
                                    CupertinoActivityIndicator(
                                      radius: 8,
                                      color: timeColor,
                                    )
                                  else if (m.sendState ==
                                      CustomerSupportMessageSendState.failed)
                                    Text(
                                      'Failed · Tap to retry',
                                      style: TextStyle(
                                        color: Colors.redAccent.withOpacity(
                                          isCustomer ? 0.85 : 1,
                                        ),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                  },
                );
              }),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _attachmentPreviewBar(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _text,
                              decoration: InputDecoration(
                                hintText: 'Type here',
                                filled: true,
                                fillColor: const Color(0xFFF2F4F7),
                                suffixIcon: IconButton(
                                  onPressed:
                                      _sendingMessage
                                          ? null
                                          : _pickAndUploadAttachment,
                                  icon: const Icon(
                                    Icons.attach_file_rounded,
                                    color: Color(0xFF667085),
                                  ),
                                ),
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
                                  vertical: 14,
                                ),
                              ),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              enabled: !_sendingMessage,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 54,
                            width: 54,
                            child: ElevatedButton(
                              onPressed: _sendingMessage ? null : _send,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.commonBlack,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                elevation: 0,
                                padding: EdgeInsets.zero,
                              ),
                              child: const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
