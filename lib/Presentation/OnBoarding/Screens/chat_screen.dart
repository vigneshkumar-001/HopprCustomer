import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hopper/Core/Utility/phone_launcher.dart';

import 'package:hopper/Presentation/OnBoarding/Controller/chat_controller.dart';
import 'package:hopper/Presentation/OnBoarding/models/chat_history_response.dart';
import 'package:hopper/Presentation/OnBoarding/models/chat_response.dart';
import 'package:hopper/uitls/websocket/socket_io_client.dart';

import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Core/Utility/typing_animate.dart';
import '../Controller/upload_image_controller.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';

class ChatScreen extends StatefulWidget {
  final String bookingId;
  final double? pickupLatitude;
  final double? pickupLongitude;
  const ChatScreen({
    super.key,
    required this.bookingId,
    this.pickupLatitude,
    this.pickupLongitude,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final UploadImageController controller = Get.put(UploadImageController());
  final ChatController chatController = Get.put(ChatController());

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  final socketService = SocketService();

  bool _isRecording = false;
  String? _audioPath;
  String? _pendingAudioPath;

  String customerId = '';
  String myAvatarUrl = ''; // Customer avatar ('' => person icon)
  String driverAvatarUrl = ''; // Driver avatar ('' => person icon)
  Map<String, bool> _playingStates = {};

  List<ChatMessage> messages = [];

  // ---------- time helpers ----------
  // robust parser: handles ISO or `yyyy-MM-dd-HH:mm:ss:SSS...`
  DateTime? _parseServerTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.trim();

    // 1) try native ISO
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {}

    // 2) try custom pattern: 2025-10-24-16:23:24:5999499
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})-(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(s);
    if (m != null) {
      final y = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final d = int.parse(m.group(3)!);
      final h = int.parse(m.group(4)!);
      final mi = int.parse(m.group(5)!);
      final se = int.parse(m.group(6)!);
      // ignore extra fractional part if present
      return DateTime(y, mo, d, h, mi, se);
    }

    // 3) last resort: return now
    return DateTime.now();
  }

  String _relativeTimeFromString(String? raw) {
    final dt = _parseServerTime(raw) ?? DateTime.now();
    return _relativeFromDateTime(dt);
  }

  String _relativeFromDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds.abs() <= 30) return 'now';

    if (diff.inMinutes < 1) {
      final s = diff.inSeconds;
      return '$s sec ago';
    }
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return m == 1 ? '1 min ago' : '$m min ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return h == 1 ? '1 hr ago' : '$h hr ago';
    }
    if (diff.inHours < 48) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';

    // 7+ days → show nice date
    const month = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final ampmHour = (dt.hour % 12 == 0) ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${month[dt.month - 1]} ${dt.year}, $ampmHour:$minute $ampm';
  }

  // ---------- utils ----------
  String _normalizeUrl(String raw) {
    var url = (raw).trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http')) {
      url = url.replaceAll('/./', '/');
      return url;
    }
    const base = 'https://YOUR-API-HOST.com';
    return ('$base$url').replaceAll('/./', '/');
  }

  // ---------- history flatten ----------
  List<ChatMessage> _flattenFromHistory(List<ChatHistoryMessage> items) {
    final out = <ChatMessage>[];
    for (final it in items) {
      final side = (it.side).toLowerCase(); // "left" / "right"
      final isMe = side == 'right'; // API contract: right = customer
      final apiImg = _normalizeUrl(it.senderImage ?? '');

      final avatar =
          isMe
              ? (apiImg.isNotEmpty ? apiImg : myAvatarUrl)
              : (apiImg.isNotEmpty ? apiImg : driverAvatarUrl);

      final timeStr = _relativeTimeFromString(it.timestamp);

      for (final part in it.contents) {
        final t = part.type.toLowerCase();
        final v = part.value.trim();
        if (v.isEmpty) continue;

        if (t == 'text') {
          out.add(
            ChatMessage(
              message: v,
              audioUrl: null,
              isMe: isMe,
              time: timeStr,
              avatar: avatar,
              imageUrl: null,
              isSending: false,
            ),
          );
        } else if (t == 'image') {
          out.add(
            ChatMessage(
              message: '',
              audioUrl: null,
              isMe: isMe,
              time: timeStr,
              avatar: avatar,
              imageUrl: _normalizeUrl(v),
              isSending: false,
            ),
          );
        }
      }
    }
    return out;
  }

  // ---------- lifecycle ----------
  @override
  void initState() {
    super.initState();
    _initializeSocketAndData();
    _loadHistory();
    _initRecorder();
    _player.openPlayer();
  }

  @override
  void dispose() {
    _player.closePlayer();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- history ----------
  Future<void> _loadHistory() async {
    await chatController.fetchChatHistory(
      bookingId: widget.bookingId,
      pickupLatitude: widget.pickupLatitude,
      pickupLongitude: widget.pickupLongitude,
      context: context,
    );

    // refresh avatars from controller (more reliable than prefs)
    final apiDriverUrl = _normalizeUrl(chatController.driverImage.value);
    if (apiDriverUrl.isNotEmpty && apiDriverUrl != driverAvatarUrl) {
      driverAvatarUrl = apiDriverUrl;
    }
    final apiMyUrl = _normalizeUrl(chatController.customerImage.value);
    if (apiMyUrl.isNotEmpty && apiMyUrl != myAvatarUrl) {
      myAvatarUrl = apiMyUrl;
    }

    setState(() {
      messages = _flattenFromHistory(
        List<ChatHistoryMessage>.from(chatController.chatMessages),
      );
    });

    _scrollToBottom();
  }

  // ---------- sockets ----------
  late final Function(dynamic) _bookingMessageHandler;

  Future<void> _initializeSocketAndData() async {
    await _loadCustomerAndDriverInfo();

    socketService.initSocket('https://bk.myhoppr.com');

    socketService.onConnect(() {
      socketService.registerUser(customerId);
      socketService.onReconnect(() {
        AppLogger.log.i("🔄 Reconnected");
        socketService.registerUser(customerId);
      });
    });

    socketService.on('registered', (data) {
      AppLogger.log.i("✅ Registered → $data");
    });

    socketService.on("typing", (data) {
      if (!mounted) return;
      final senderType = (data["senderType"] ?? '').toString().toLowerCase();
      if (senderType == 'customer') return; // ignore my own typing

      setState(() {
        messages.removeWhere((m) => m.isTyping && !m.isMe);
        messages.add(
          ChatMessage(
            message: "",
            isMe: false, // driver typing bubble (left)
            avatar: driverAvatarUrl, // driver avatar or person icon
            time: "",
            isTyping: true,
          ),
        );
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            messages.removeWhere((m) => m.isTyping);
          });
        }
      });
    });

    _bookingMessageHandler = (data) {
      // Ignore echo: if server mirrors my sent message back
      final senderId = (data['senderId'] ?? '').toString();
      if (senderId == customerId) return;

      final List<dynamic> contents = data['contents'] ?? [];
      if (contents.isEmpty || !mounted) return;

      // Not me.
      const bool isMe = false;

      // Prefer socket senderImage, else controller driverImage, else person icon
      final socketImg = _normalizeUrl((data['senderImage'] ?? '').toString());
      final controllerDriverImg = _normalizeUrl(
        chatController.driverImage.value,
      );
      final avatarForBubble =
          socketImg.isNotEmpty
              ? socketImg
              : (driverAvatarUrl.isNotEmpty
                  ? driverAvatarUrl
                  : controllerDriverImg);

      final tm = _relativeFromDateTime(DateTime.now());

      for (var c in contents) {
        final type = (c['type'] ?? '').toString().toLowerCase();
        final value = (c['value'] ?? '').toString().trim();
        if (value.isEmpty) continue;

        setState(() {
          messages.add(
            ChatMessage(
              message: type == 'text' ? value : '',
              imageUrl: type == 'image' ? _normalizeUrl(value) : '',
              audioUrl: null,
              isMe: isMe,
              time: tm,
              avatar: avatarForBubble,
            ),
          );
        });
      }
      _scrollToBottom();
    };

    socketService.on('booking-message', _bookingMessageHandler);
  }

  Future<void> _loadCustomerAndDriverInfo() async {
    final prefs = await SharedPreferences.getInstance();
    customerId = prefs.getString('customer_Id') ?? '';

    // Start with prefs (if any)
    myAvatarUrl = _normalizeUrl(prefs.getString('customer_image') ?? '');
    driverAvatarUrl = _normalizeUrl(prefs.getString('driver_image') ?? '');

    // Prefer controller values (after fetch they'll be available)
    final ctrlMy = _normalizeUrl(chatController.customerImage.value);
    if (ctrlMy.isNotEmpty) myAvatarUrl = ctrlMy;

    final ctrlDriver = _normalizeUrl(chatController.driverImage.value);
    if (ctrlDriver.isNotEmpty) driverAvatarUrl = ctrlDriver;

    AppLogger.log.i(
      '✅ Loaded customerId=$customerId | myAvatarUrl=$myAvatarUrl | driverAvatarUrl=$driverAvatarUrl',
    );
  }

  // ---------- media / send ----------
  Future<void> _initRecorder() async {
    await Permission.microphone.request();
    await Permission.storage.request();
    await _recorder.openRecorder();
    _recorder.setSubscriptionDuration(const Duration(milliseconds: 500));
  }

  Future<void> _pickAndSendImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image == null) return;

    // placeholder (RIGHT bubble)
    setState(() {
      messages.add(
        ChatMessage(
          isMe: true,
          imageUrl: image.path, // local preview
          message: '',
          time: 'now',
          avatar: myAvatarUrl,
          isSending: true,
        ),
      );
    });
    _scrollToBottom();

    await controller.uploadImage(context, File(image.path));
    final uploadedUrl = _normalizeUrl(controller.frontImageUrl.value);

    final index = messages.lastIndexWhere((m) => m.isSending);
    if (uploadedUrl.isNotEmpty && index != -1) {
      _sendMessage('', imageUrl: uploadedUrl);
    } else {
      setState(() {
        if (index >= 0 && index < messages.length) messages.removeAt(index);
      });
    }
  }

  Future<void> _sendMessage(String message, {String? imageUrl}) async {
    if (message.trim().isEmpty && imageUrl == null) return;

    // placeholder for TEXT (RIGHT)
    if (message.trim().isNotEmpty) {
      setState(() {
        messages.add(
          ChatMessage(
            message: message,
            imageUrl: imageUrl,
            isMe: true,
            time: 'now',
            avatar: myAvatarUrl,
            isSending: true,
          ),
        );
      });
      _scrollToBottom();
    }

    final contents = <Map<String, String>>[];
    if (message.trim().isNotEmpty) {
      contents.add({"type": "text", "value": message});
    }
    if (imageUrl != null) {
      contents.add({"type": "image", "value": imageUrl});
    }

    final payload = {
      'bookingId': widget.bookingId,
      'senderId': customerId,
      'senderType': "customer",
      'contents': contents,
    };

    socketService.emitWithAck("booking-message", payload, (ack) {
      final index = messages.lastIndexWhere((m) => m.isSending);
      if (ack != null && ack['success'] == true && index != -1) {
        setState(() {
          messages[index] = ChatMessage(
            message: message,
            imageUrl: imageUrl,
            isMe: true,
            time: _relativeFromDateTime(DateTime.now()),
            avatar: myAvatarUrl,
            isSending: false,
          );
        });
        _textController.clear();
        _scrollToBottom();
      } else {
        AppLogger.log.e("Message send failed: $ack");
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 75,
        backgroundColor: AppColors.commonWhite,
        automaticallyImplyLeading: false,
        title: Obx(() {
          final reactiveDriver = _normalizeUrl(
            chatController.driverImage.value,
          );
          final img =
              (reactiveDriver.isNotEmpty ? reactiveDriver : driverAvatarUrl)
                  .trim();
          final name =
              chatController.driverName.value.isNotEmpty
                  ? chatController.driverName.value
                  : 'Driver';

          final driverPhone =
              chatController.driverPhone.value.isNotEmpty
                  ? chatController.driverPhone.value
                  : ' ';

          return Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Image.asset(AppImages.backImage, height: 25, width: 25),
              ),
              const SizedBox(width: 15),
              Stack(
                children: [
                  ClipOval(
                    child: _cachedCircleImage(
                      imageUrl: img,
                      size: 45,
                      fallbackAsset: '',
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Image.asset(
                      AppImages.dart,
                      height: 8,
                      color: const Color(0xff52C41A),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 13),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomTextFields.textWithStylesSmall(
                    name,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    colors: AppColors.commonBlack,
                  ),
                  CustomTextFields.textWithStylesSmall(
                    'Online',
                    fontSize: 12,
                    colors: AppColors.commonBlack.withOpacity(0.6),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  color: AppColors.chatCallContainerColor,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(50),
                    onTap: () async {
                      var raw = driverPhone;
                      final sanitized = sanitizePhoneNumber(raw);
                      AppLogger.log.i(raw);
                      AppLogger.log.i('tel:$sanitized');

                      try {
                        final ok = await launchPhoneDialer(sanitized);
                        if (!ok) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No dialer available on this device',
                                ),
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not open dialer: $e'),
                            ),
                          );
                        }
                      }
                    },
                    child: Image.asset(
                      AppImages.chatCall,
                      height: 20,
                      width: 20,
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Obx(() {
                final loading = chatController.isLoading.value;
                if (loading && messages.isEmpty) {
                  return Center(child: AppLoader.circularLoader());
                }

                return RefreshIndicator(
                  onRefresh: () async => _loadHistory(),
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: messages.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final current = messages[index];
                      final previous = index > 0 ? messages[index - 1] : null;
                      final next =
                          index < messages.length - 1
                              ? messages[index + 1]
                              : null;

                      final showAvatar =
                          previous == null || previous.isMe != current.isMe;
                      final showTime =
                          next == null || next.isMe != current.isMe;

                      return buildMessage(current, showAvatar, showTime);
                    },
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            _messageInputRow(),
          ],
        ),
      ),
    );
  }

  Widget _quickChip(String text) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.black.withOpacity(0.05),
        highlightColor: Colors.transparent,
        onTap: () => _sendMessage(text),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.containerColor1,
            borderRadius: BorderRadius.circular(20),
          ),
          child: CustomTextFields.textWithStylesSmall(
            text,
            fontSize: 14,
            colors: AppColors.commonBlack,
          ),
        ),
      ),
    );
  }

  Widget _messageInputRow() {
    return Column(
      children: [
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(
              children: [
                _quickChip("I'm waiting downstairs"),
                const SizedBox(width: 10),
                _quickChip("Please call when you arrive"),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_pendingAudioPath != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lowLightBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.play_arrow),
                  const SizedBox(width: 8),
                  const Text("Voice message ready to send"),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _pendingAudioPath = null),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: _pickAndSendImage,
                child: Image.asset(AppImages.camera, height: 26, width: 26),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: AppColors.containerColor1,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (val) {
                            final data = {
                              'bookingId': widget.bookingId,
                              'senderId': customerId,
                              'senderType': 'customer',
                            };
                            socketService.emit('typing', data);
                          },
                          controller: _textController,
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          if (!_isRecording) {
                            final tempDir = await getTemporaryDirectory();
                            _audioPath =
                                '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.aac';
                            await _recorder.startRecorder(
                              toFile: _audioPath,
                              codec: Codec.aacADTS,
                            );
                          } else {
                            await _recorder.stopRecorder();
                            setState(() => _pendingAudioPath = _audioPath);
                          }
                          setState(() => _isRecording = !_isRecording);
                        },
                        child:
                            _isRecording
                                ? const Icon(Icons.pause)
                                : Image.asset(
                                  AppImages.mic,
                                  height: 26,
                                  width: 26,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 5),
              InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: () {
                  final message = _textController.text.trim();
                  if (_pendingAudioPath != null) {
                    final audioMsg = ChatMessage(
                      isMe: true,
                      audioUrl: _pendingAudioPath!,
                      message: '',
                      time: 'now',
                      avatar: myAvatarUrl,
                    );
                    setState(() {
                      messages.add(audioMsg);
                      _pendingAudioPath = null;
                    });
                    _scrollToBottom();
                  } else if (message.isNotEmpty) {
                    _sendMessage(message);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(3.0),
                  child: Image.asset(
                    AppImages.sendButton,
                    height: 40,
                    width: 40,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- image helpers & preview ----------
  Widget _cachedCircleImage({
    required String imageUrl,
    required double size,
    required String fallbackAsset,
  }) {
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.grey.shade300,
        child: const Icon(Icons.person, color: Colors.white),
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder:
          (_, __) => CircleAvatar(
            radius: size / 2,
            backgroundColor: Colors.grey.shade200,
            child: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      errorWidget:
          (_, __, ___) => CircleAvatar(
            radius: size / 2,
            backgroundColor: Colors.grey.shade300,
            child: const Icon(Icons.person, color: Colors.white),
          ),
    );
  }

  Widget _cachedRectImage({
    required String imageUrl,
    required double w,
    required double h,
  }) {
    if (imageUrl.isEmpty) {
      return Container(
        width: w,
        height: h,
        color: Colors.grey.shade200,
        child: const Icon(Icons.image, color: Colors.white70),
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: w,
      height: h,
      fit: BoxFit.cover,
      placeholder:
          (_, __) => SizedBox(
            width: w,
            height: h,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      errorWidget:
          (_, __, ___) => Container(
            width: w,
            height: h,
            color: Colors.grey.shade300,
            child: const Icon(Icons.broken_image),
          ),
    );
  }

  Widget _buildChatImage(String imagePath) {
    if (imagePath.startsWith('http')) {
      return GestureDetector(
        onTap: () => _openImagePreview(imagePath),
        child: Hero(
          tag: 'img:${imagePath.hashCode}',
          child: _cachedRectImage(imageUrl: imagePath, w: 160, h: 160),
        ),
      );
    }
    final clean = imagePath.replaceFirst('file://', '');
    if (File(clean).existsSync()) {
      return GestureDetector(
        onTap: () => _openImagePreview(clean),
        child: Hero(
          tag: 'img:${clean.hashCode}',
          child: Image.file(
            File(clean),
            width: 160,
            height: 160,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: 160,
      height: 160,
      color: Colors.grey.shade200,
      child: const Icon(Icons.image_not_supported),
    );
  }

  void _openImagePreview(String pathOrUrl) {
    final imageProvider =
        pathOrUrl.startsWith('http')
            ? CachedNetworkImageProvider(pathOrUrl)
            : FileImage(File(pathOrUrl.replaceFirst('file://', '')))
                as ImageProvider;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder:
            (_, __, ___) => ImagePreviewPage(
              imageProvider: imageProvider,
              heroTag: 'img:${pathOrUrl.hashCode}',
            ),
        transitionsBuilder:
            (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Widget buildMessage(ChatMessage msg, bool showAvatar, bool showTime) {
    return Row(
      mainAxisAlignment:
          msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!msg.isMe && showAvatar) buildAvatar(msg.avatar),
        if (!msg.isMe && !showAvatar) const SizedBox(width: 46),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment:
              msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (msg.isTyping)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const SmoothTypingIndicator(),
              ),

            // TEXT bubble
            if (msg.message.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.adminChatContainerColor),
                  color:
                      msg.isMe
                          ? AppColors.userChatContainerColor
                          : AppColors.commonWhite,
                  borderRadius: BorderRadius.circular(15),
                ),
                constraints: const BoxConstraints(maxWidth: 250),
                child: Text(
                  msg.message,
                  style: TextStyle(
                    color: msg.isMe ? Colors.white : const Color(0xff262626),
                  ),
                ),
              ),

            // IMAGE bubble
            if ((msg.imageUrl ?? '').isNotEmpty)
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.adminChatContainerColor,
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: _buildChatImage(msg.imageUrl!),
                  ),
                  if (msg.isSending)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.changeButtonColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

            if (showTime && !msg.isTyping)
              Text(
                msg.time,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
          ],
        ),
        const SizedBox(width: 6),
        if (msg.isMe && showAvatar) buildAvatar(msg.avatar),
        if (msg.isMe && !showAvatar) const SizedBox(width: 46),
      ],
    );
  }

  Widget buildAvatar(String? imagePath) {
    const size = 40.0;
    final path = imagePath?.trim() ?? '';

    if (path.isEmpty) return _personCircle(size);

    if (path.startsWith('http')) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: CachedNetworkImageProvider(path),
      );
    }

    if (File(path).existsSync()) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: FileImage(File(path)),
      );
    }

    return _personCircle(size);
  }

  Widget _personCircle(double size) => CircleAvatar(
    radius: size / 2,
    backgroundColor: Colors.grey.shade300,
    child: const Icon(Icons.person, color: Colors.white),
  );
}

/// ===========================
/// Full-screen Image Preview
/// ===========================
class ImagePreviewPage extends StatelessWidget {
  final ImageProvider imageProvider;
  final String heroTag;

  const ImagePreviewPage({
    super.key,
    required this.imageProvider,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Center(
              child: Hero(
                tag: heroTag,
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image(image: imageProvider, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:flutter_sound/flutter_sound.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:url_launcher/url_launcher.dart';
// import 'package:cached_network_image/cached_network_image.dart';
//
// import 'package:hopper/Presentation/OnBoarding/Controller/chat_controller.dart';
// import 'package:hopper/Presentation/OnBoarding/models/chat_history_response.dart';
// import 'package:hopper/Presentation/OnBoarding/models/chat_response.dart';
// import 'package:hopper/uitls/websocket/socket_io_client.dart';
//
// import 'package:hopper/Core/Consents/app_colors.dart';
// import 'package:hopper/Core/Consents/app_logger.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/Core/Utility/app_loader.dart';
// import 'package:hopper/Core/Utility/typing_animate.dart';
// import '../Controller/upload_image_controller.dart';
// import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
//
// class ChatScreen extends StatefulWidget {
//   final String bookingId;
//   const ChatScreen({super.key, required this.bookingId});
//
//   @override
//   State<ChatScreen> createState() => _ChatScreenState();
// }
//
// class _ChatScreenState extends State<ChatScreen> {
//   final TextEditingController _textController = TextEditingController();
//   final ScrollController _scrollController = ScrollController();
//
//   final UploadImageController controller = Get.put(UploadImageController());
//   final ChatController chatController = Get.put(ChatController());
//
//   final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
//   final FlutterSoundPlayer _player = FlutterSoundPlayer();
//
//   final socketService = SocketService();
//
//   bool _isRecording = false;
//   String? _audioPath;
//   String? _pendingAudioPath;
//
//   String customerId = '';
//   Map<String, bool> _playingStates = {};
//
//   /// Flattened bubbles for the UI
//   List<ChatMessage> messages = [];
//
//   // ---------- helpers: flatten API history into UI bubbles ----------
//   /// IMPORTANT: align using API's "side" field.
//   /// side == "right"  -> isMe = true  (RIGHT)
//   /// side != "right"  -> isMe = false (LEFT)
//   List<ChatMessage> _flattenFromHistory(List<ChatHistoryMessage> items) {
//     final out = <ChatMessage>[];
//     for (final it in items) {
//       final side = (it.side).toLowerCase(); // "left" or "right" (from API)
//       final isMe = side == 'right'; // RIGHT == current user (customer)
//       final avatar =
//           (it.senderImage.isNotEmpty) ? it.senderImage : AppImages.dummy;
//       final timeStr = _hhmm(it.timestamp);
//
//       for (final part in it.contents) {
//         final t = part.type.toLowerCase();
//         final v = part.value.trim();
//         if (v.isEmpty) continue;
//
//         if (t == 'text') {
//           out.add(
//             ChatMessage(
//               message: v,
//               audioUrl: null,
//               isMe: isMe, // ← use API side
//               time: timeStr,
//               avatar: avatar,
//               imageUrl: null,
//               isSending: false,
//             ),
//           );
//         } else if (t == 'image') {
//           out.add(
//             ChatMessage(
//               message: '',
//               audioUrl: null,
//               isMe: isMe,
//               time: timeStr,
//               avatar: avatar,
//               imageUrl: v,
//               isSending: false,
//             ),
//           );
//         }
//       }
//     }
//     return out;
//   }
//
//   String _hhmm(String? iso) {
//     final dt = DateTime.tryParse(iso ?? '');
//     if (dt == null) return '';
//     final h = dt.hour.toString().padLeft(2, '0');
//     final m = dt.minute.toString().padLeft(2, '0');
//     return '$h:$m';
//   }
//
//   // ---------- lifecycle ----------
//   @override
//   void initState() {
//     super.initState();
//     _loadHistory(); // 1) API history
//     _initializeSocketAndData(); // 2) websocket updates only
//     _initRecorder();
//     _player.openPlayer();
//   }
//
//   @override
//   void dispose() {
//     // remove socket listener to avoid duplicate events after navigating
//
//     _player.closePlayer();
//     _textController.dispose();
//     _scrollController.dispose();
//     super.dispose();
//   }
//
//   // ---------- history ----------
//   Future<void> _loadHistory() async {
//     await chatController.fetchChatHistory(
//       bookingId: widget.bookingId,
//       context: context,
//     );
//
//     setState(() {
//       messages = _flattenFromHistory(
//         List<ChatHistoryMessage>.from(chatController.chatMessages),
//       );
//     });
//
//     _scrollToBottom();
//   }
//
//   // ---------- sockets ----------
//   late final Function(dynamic) _bookingMessageHandler;
//
//   Future<void> _initializeSocketAndData() async {
//     await _loadCustomerId();
//     socketService.initSocket(
//       'https://hoppr-face-two-dbe557472d7f.herokuapp.com',
//     );
//
//     socketService.onConnect(() {
//       socketService.registerUser(customerId);
//       socketService.onReconnect(() {
//         AppLogger.log.i("🔄 Reconnected");
//         socketService.registerUser(customerId);
//       });
//     });
//
//     socketService.on('registered', (data) {
//       AppLogger.log.i("✅ Registered → $data");
//     });
//
//     socketService.on("typing", (data) {
//       if (!mounted) return;
//       final senderType = (data["senderType"] ?? '').toString().toLowerCase();
//       if (senderType == 'customer') return; // don't show my own typing
//
//       setState(() {
//         messages.removeWhere((m) => m.isTyping && !m.isMe);
//         messages.add(
//           ChatMessage(
//             message: "",
//             isMe: false, // driver typing on LEFT
//             avatar: AppImages.dummy,
//             time: "",
//             isTyping: true,
//           ),
//         );
//       });
//
//       Future.delayed(const Duration(seconds: 3), () {
//         if (mounted) {
//           setState(() {
//             messages.removeWhere((m) => m.isTyping);
//           });
//         }
//       });
//     });
//
//     _bookingMessageHandler = (data) {
//       // ALIGNMENT for live messages:
//       // If senderId == my customerId -> RIGHT (isMe: true), else LEFT.
//       final senderId = (data['senderId'] ?? '').toString();
//       if (senderId == customerId) return; // ignore my own echo from server
//
//       final List<dynamic> contents = data['contents'] ?? [];
//       if (contents.isEmpty || !mounted) return;
//
//       final avatar = (data['senderImage'] ?? '').toString();
//       final avatarOrFallback = avatar.isNotEmpty ? avatar : AppImages.dummy;
//       final tm = DateTime.now().toString().substring(11, 16);
//
//       final isMe = senderId == customerId; // right if I'm the sender (safety)
//
//       for (var c in contents) {
//         final type = (c['type'] ?? '').toString().toLowerCase();
//         final value = (c['value'] ?? '').toString().trim();
//         if (value.isEmpty) continue;
//
//         if (type == 'text') {
//           setState(() {
//             messages.add(
//               ChatMessage(
//                 message: value,
//                 imageUrl: '',
//                 audioUrl: null,
//                 isMe: isMe, // RIGHT if me, LEFT if driver
//                 time: tm,
//                 avatar: avatarOrFallback,
//               ),
//             );
//           });
//         } else if (type == 'image') {
//           setState(() {
//             messages.add(
//               ChatMessage(
//                 message: '',
//                 imageUrl: value,
//                 audioUrl: null,
//                 isMe: isMe,
//                 time: tm,
//                 avatar: avatarOrFallback,
//               ),
//             );
//           });
//         }
//       }
//       _scrollToBottom();
//     };
//
//     socketService.on('booking-message', _bookingMessageHandler);
//   }
//
//   String myAvatarUrl = ''; // keep '' when not available
//   Future<void> _loadCustomerId() async {
//     final prefs = await SharedPreferences.getInstance();
//     customerId = prefs.getString('customer_Id') ?? '';
//     myAvatarUrl = chatController.  customerImage .toString() ?? '';
//     if (customerId.isEmpty) {
//       AppLogger.log.w('⚠️ No customer ID found in shared preferences.');
//     } else {
//       AppLogger.log.i('✅ Loaded customerId = $customerId');
//     }
//   }
//
//   // ---------- media / send ----------
//   Future<void> _initRecorder() async {
//     await Permission.microphone.request();
//     await Permission.storage.request();
//     await _recorder.openRecorder();
//     _recorder.setSubscriptionDuration(const Duration(milliseconds: 500));
//   }
//
//   Future<void> _pickAndSendImage() async {
//     final ImagePicker picker = ImagePicker();
//     final XFile? image = await picker.pickImage(source: ImageSource.camera);
//
//     if (image == null) return;
//
//     // placeholder (ME/CUSTOMER = RIGHT -> isMe = true)
//     setState(() {
//       messages.add(
//         ChatMessage(
//           isMe: true,
//           imageUrl: image.path,
//           message: '',
//           time: 'Now',
//           avatar: myAvatarUrl,
//           isSending: true,
//         ),
//       );
//     });
//     _scrollToBottom();
//
//     await controller.uploadImage(context, File(image.path));
//     final uploadedUrl = controller.frontImageUrl.value;
//
//     final index = messages.lastIndexWhere((m) => m.isSending);
//     if (uploadedUrl.isNotEmpty && index != -1) {
//       _sendMessage('', imageUrl: uploadedUrl); // send via socket
//     } else {
//       setState(() {
//         if (index >= 0 && index < messages.length) messages.removeAt(index);
//       });
//     }
//   }
//
//   Future<void> _sendMessage(String message, {String? imageUrl}) async {
//     if (message.trim().isEmpty && imageUrl == null) return;
//
//     // placeholder for TEXT (ME/CUSTOMER = RIGHT)
//     if (message.trim().isNotEmpty) {
//       setState(() {
//         messages.add(
//           ChatMessage(
//             message: message,
//             imageUrl: imageUrl,
//             isMe: true, // RIGHT
//             time: 'Now',
//             avatar: AppImages.dummy1,
//             isSending: true,
//           ),
//         );
//       });
//       _scrollToBottom();
//     }
//
//     final contents = <Map<String, String>>[];
//     if (message.trim().isNotEmpty)
//       contents.add({"type": "text", "value": message});
//     if (imageUrl != null) contents.add({"type": "image", "value": imageUrl});
//
//     final payload = {
//       'bookingId': widget.bookingId,
//       'senderId': customerId,
//       'senderType': "customer",
//       'contents': contents,
//     };
//
//     socketService.emitWithAck("booking-message", payload, (ack) {
//       final index = messages.lastIndexWhere((m) => m.isSending);
//       if (ack != null && ack['success'] == true && index != -1) {
//         final img = chatController. customerImage.value;
//         setState(() {
//           messages[index] = ChatMessage(
//             message: message,
//             imageUrl: imageUrl,
//             isMe: true,
//             time: DateTime.now().toString(),
//             avatar: img,
//             isSending: false,
//           );
//         });
//         _textController.clear();
//         _scrollToBottom();
//       } else {
//         AppLogger.log.e("Message send failed: $ack");
//       }
//     });
//   }
//
//   void _scrollToBottom() {
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (_scrollController.hasClients) {
//         _scrollController.animateTo(
//           _scrollController.position.maxScrollExtent,
//           duration: const Duration(milliseconds: 300),
//           curve: Curves.easeOut,
//         );
//       }
//     });
//   }
//
//   // ---------- UI ----------
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         toolbarHeight: 75,
//         scrolledUnderElevation: 0,
//         surfaceTintColor: Colors.transparent,
//         backgroundColor: AppColors.commonWhite,
//         automaticallyImplyLeading: false,
//         title: Obx(() {
//           final name =
//               chatController.driverName.value.isNotEmpty
//                   ? chatController.driverName.value
//                   : 'Driver';
//           final img = chatController.driverImage.value;
//
//           return Row(
//             children: [
//               Image.asset(AppImages.backImage, height: 25, width: 25),
//               const SizedBox(width: 15),
//
//               // cached + loader avatar
//               Stack(
//                 children: [
//                   ClipPath(
//                     clipper: CutOutCircleClipper(cutRadius: 5),
//                     child: _cachedCircleImage(
//                       imageUrl: img,
//                       size: 45,
//                       fallbackAsset: AppImages.dummy,
//                     ),
//                   ),
//                   Positioned(
//                     top: 2,
//                     right: 2,
//                     child: Image.asset(
//                       AppImages.dart,
//                       height: 8,
//                       color: const Color(0xff52C41A),
//                     ),
//                   ),
//                 ],
//               ),
//
//               const SizedBox(width: 13),
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   CustomTextFields.textWithStylesSmall(
//                     name,
//                     fontSize: 14,
//                     fontWeight: FontWeight.w500,
//                     colors: AppColors.commonBlack,
//                   ),
//                   CustomTextFields.textWithStylesSmall(
//                     'Online',
//                     fontSize: 12,
//                     colors: AppColors.commonBlack.withOpacity(0.6),
//                   ),
//                 ],
//               ),
//               const Spacer(),
//               Container(
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(50),
//                   color: AppColors.chatCallContainerColor,
//                 ),
//                 child: Padding(
//                   padding: const EdgeInsets.all(8.0),
//                   child: InkWell(
//                     onTap: () async {
//                       const phoneNumber = 'tel:8248191110';
//                       final Uri url = Uri.parse(phoneNumber);
//                       if (await canLaunchUrl(url)) {
//                         await launchUrl(url);
//                       } else {
//                         debugPrint('Could not launch dialer');
//                       }
//                     },
//                     child: Image.asset(
//                       AppImages.chatCall,
//                       height: 20,
//                       width: 20,
//                     ),
//                   ),
//                 ),
//               ),
//             ],
//           );
//         }),
//       ),
//       body: SafeArea(
//         child: Column(
//           children: [
//             // Row(
//             //   children: [
//             //     Expanded(
//             //       child: Container(
//             //         decoration: BoxDecoration(
//             //           color: AppColors.lowLightBlue,
//             //           borderRadius: BorderRadius.circular(10),
//             //         ),
//             //         child: ListTile(
//             //           leading: Image.asset(AppImages.box, height: 35, width: 35),
//             //           title: CustomTextFields.textWithStyles600('Order PKG-2025-7841'),
//             //           subtitle: CustomTextFields.textWithStylesSmall(
//             //             'Pickup: 123 Main Street • Weight: 2.5 kg',
//             //             fontSize: 12,
//             //             colors: AppColors.changeButtonColor,
//             //           ),
//             //         ),
//             //       ),
//             //     ),
//             //   ],
//             // ),
//             Expanded(
//               child: Column(
//                 children: [
//                   Expanded(
//                     child: Obx(() {
//                       final loading = chatController.isLoading.value;
//                       final hasNoMessagesYet = loading && messages.isEmpty;
//
//                       if (hasNoMessagesYet) {
//                         return Center(
//                           child: SizedBox(
//                             width: 36,
//                             height: 36,
//                             child: CircularProgressIndicator(
//                               strokeWidth: 2.8,
//                               color: AppColors.changeButtonColor,
//                             ),
//                           ),
//                         );
//                       }
//
//                       return RefreshIndicator(
//                         onRefresh: () async => _loadHistory(),
//                         child: Container(
//                           decoration: BoxDecoration(
//                             borderRadius: BorderRadius.circular(5),
//                             border: Border.all(
//                               color: AppColors.adminChatContainerColor,
//                             ),
//                           ),
//                           child: ListView.builder(
//                             controller: _scrollController,
//                             itemCount: messages.length,
//                             padding: const EdgeInsets.all(16),
//                             itemBuilder: (context, index) {
//                               final current = messages[index];
//                               final previous =
//                                   index > 0 ? messages[index - 1] : null;
//                               final next =
//                                   index < messages.length - 1
//                                       ? messages[index + 1]
//                                       : null;
//
//                               final showAvatar =
//                                   previous == null ||
//                                   previous.isMe != current.isMe;
//                               final showTime =
//                                   next == null || next.isMe != current.isMe;
//
//                               return buildMessage(
//                                 current,
//                                 showAvatar,
//                                 showTime,
//                               );
//                             },
//                           ),
//                         ),
//                       );
//                     }),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 15),
//             SingleChildScrollView(
//               scrollDirection: Axis.horizontal,
//               child: Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 15),
//                 child: Row(
//                   children: [
//                     _quickChip("I’m waiting downstairs"),
//                     const SizedBox(width: 10),
//                     _quickChip("Please call when you arrive"),
//                     const SizedBox(width: 10),
//                   ],
//                 ),
//               ),
//             ),
//             const SizedBox(height: 10),
//             if (_pendingAudioPath != null)
//               Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 15),
//                 child: Container(
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: AppColors.lowLightBlue,
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Row(
//                     children: [
//                       const Icon(Icons.play_arrow),
//                       const SizedBox(width: 8),
//                       const Text("Voice message ready to send"),
//                       const Spacer(),
//                       IconButton(
//                         icon: const Icon(Icons.close),
//                         onPressed:
//                             () => setState(() => _pendingAudioPath = null),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             Padding(
//               padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
//               child: Row(
//                 children: [
//                   GestureDetector(
//                     onTap: _pickAndSendImage,
//                     child: Image.asset(AppImages.camera, height: 26, width: 26),
//                   ),
//                   const SizedBox(width: 10),
//                   Expanded(
//                     child: Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 15),
//                       decoration: BoxDecoration(
//                         color: AppColors.containerColor1,
//                         borderRadius: BorderRadius.circular(40),
//                       ),
//                       child: Row(
//                         children: [
//                           Expanded(
//                             child: TextField(
//                               onChanged: (val) {
//                                 final data = {
//                                   'bookingId': widget.bookingId,
//                                   'senderId': customerId,
//                                   'senderType': 'customer',
//                                 };
//                                 socketService.emit('typing', data);
//                               },
//                               controller: _textController,
//                               decoration: const InputDecoration(
//                                 hintText: 'Type a message...',
//                                 border: InputBorder.none,
//                               ),
//                             ),
//                           ),
//                           GestureDetector(
//                             onTap: () async {
//                               if (!_isRecording) {
//                                 final tempDir = await getTemporaryDirectory();
//                                 _audioPath =
//                                     '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.aac';
//                                 await _recorder.startRecorder(
//                                   toFile: _audioPath,
//                                   codec: Codec.aacADTS,
//                                 );
//                               } else {
//                                 await _recorder.stopRecorder();
//                                 setState(() => _pendingAudioPath = _audioPath);
//                               }
//                               setState(() => _isRecording = !_isRecording);
//                             },
//                             child:
//                                 _isRecording
//                                     ? const Icon(Icons.pause)
//                                     : Image.asset(
//                                       AppImages.mic,
//                                       height: 26,
//                                       width: 26,
//                                     ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                   const SizedBox(width: 5),
//                   InkWell(
//                     borderRadius: BorderRadius.circular(15),
//                     splashColor: Colors.blue.withOpacity(0.2),
//                     highlightColor: Colors.blue.withOpacity(0.1),
//                     onTap: () {
//                       final message = _textController.text.trim();
//
//                       if (_pendingAudioPath != null) {
//                         // local-only demo bubble (ME = RIGHT)
//                         final audioMsg = ChatMessage(
//                           isMe: true,
//                           audioUrl: _pendingAudioPath!,
//                           message: '',
//                           time: 'Now',
//                           avatar: AppImages.dummy1,
//                         );
//                         setState(() {
//                           messages.add(audioMsg);
//                           _pendingAudioPath = null;
//                         });
//                         _scrollToBottom();
//                       } else if (message.isNotEmpty) {
//                         _sendMessage(message);
//                       }
//                     },
//                     child: Padding(
//                       padding: const EdgeInsets.all(3.0),
//                       child: Image.asset(
//                         AppImages.sendButton,
//                         height: 40,
//                         width: 40,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   // ---------- Helpers: cached images ----------
//   Widget _cachedCircleImage({
//     required String imageUrl,
//     required double size,
//     required String
//     fallbackAsset, // kept for compatibility, not used for icon case
//   }) {
//     if (imageUrl.isEmpty) {
//       // No URL at all → person icon
//       return CircleAvatar(
//         radius: size / 2,
//         backgroundColor: Colors.grey.shade300,
//         child: const Icon(Icons.person, color: Colors.white),
//       );
//     }
//     return CachedNetworkImage(
//       imageUrl: imageUrl,
//       width: size,
//       height: size,
//       fit: BoxFit.cover,
//       placeholder:
//           (_, __) => CircleAvatar(
//             radius: size / 2,
//             backgroundColor: Colors.grey.shade200,
//             child: const SizedBox(
//               width: 16,
//               height: 16,
//               child: CircularProgressIndicator(strokeWidth: 2),
//             ),
//           ),
//       errorWidget:
//           (_, __, ___) => CircleAvatar(
//             radius: size / 2,
//             backgroundColor: Colors.grey.shade300,
//             child: const Icon(Icons.person, color: Colors.white),
//           ),
//     );
//   }
//
//   Widget _cachedRectImage({
//     required String imageUrl,
//     required double w,
//     required double h,
//     required String fallbackAsset,
//   }) {
//     if (imageUrl.isEmpty) {
//       return Image.asset(fallbackAsset, width: w, height: h, fit: BoxFit.cover);
//     }
//     return CachedNetworkImage(
//       imageUrl: imageUrl,
//       width: w,
//       height: h,
//       fit: BoxFit.cover,
//       placeholder:
//           (_, __) => SizedBox(
//             width: w,
//             height: h,
//             child: const Center(
//               child: SizedBox(
//                 width: 18,
//                 height: 18,
//                 child: CircularProgressIndicator(strokeWidth: 2),
//               ),
//             ),
//           ),
//       errorWidget:
//           (_, __, ___) => Image.asset(
//             fallbackAsset,
//             width: w,
//             height: h,
//             fit: BoxFit.cover,
//           ),
//     );
//   }
//
//   Widget _quickChip(String text) {
//     return Material(
//       color: Colors.transparent,
//       borderRadius: BorderRadius.circular(20),
//       child: InkWell(
//         borderRadius: BorderRadius.circular(20),
//         splashColor: Colors.black.withOpacity(0.05),
//         highlightColor: Colors.transparent,
//         onTap: () => _sendMessage(text),
//         child: Ink(
//           padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
//           decoration: BoxDecoration(
//             color: AppColors.containerColor1,
//             borderRadius: BorderRadius.circular(20),
//           ),
//           child: CustomTextFields.textWithStylesSmall(
//             text, // positional first
//             fontSize: 14,
//             colors: AppColors.commonBlack,
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget buildMessage(ChatMessage msg, bool showAvatar, bool showTime) {
//     return Row(
//       mainAxisAlignment:
//           msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         if (!msg.isMe && showAvatar) buildAvatar(msg.avatar),
//         if (!msg.isMe && !showAvatar) const SizedBox(width: 46),
//         const SizedBox(width: 6),
//         Column(
//           crossAxisAlignment:
//               msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
//           children: [
//             if (msg.isTyping)
//               Container(
//                 padding: const EdgeInsets.symmetric(
//                   vertical: 8,
//                   horizontal: 12,
//                 ),
//                 margin: const EdgeInsets.symmetric(vertical: 2),
//                 decoration: BoxDecoration(
//                   color: Colors.grey.shade200,
//                   borderRadius: BorderRadius.circular(15),
//                 ),
//                 child: const SmoothTypingIndicator(),
//               ),
//             if (msg.message.isNotEmpty)
//               Container(
//                 padding: const EdgeInsets.all(12),
//                 margin: const EdgeInsets.symmetric(vertical: 2),
//                 decoration: BoxDecoration(
//                   border: Border.all(color: AppColors.adminChatContainerColor),
//                   color:
//                       msg.isMe
//                           ? AppColors.userChatContainerColor
//                           : AppColors.commonWhite,
//                   borderRadius: BorderRadius.circular(15),
//                 ),
//                 constraints: const BoxConstraints(maxWidth: 250),
//                 child: Text(
//                   msg.message,
//                   style: TextStyle(
//                     color: msg.isMe ? Colors.white : const Color(0xff262626),
//                   ),
//                 ),
//               ),
//             if (msg.audioUrl != null && msg.audioUrl!.isNotEmpty)
//               Container(
//                 padding: const EdgeInsets.all(8),
//                 margin: const EdgeInsets.symmetric(vertical: 2),
//                 decoration: BoxDecoration(
//                   border: Border.all(color: AppColors.adminChatContainerColor),
//                   borderRadius: BorderRadius.circular(15),
//                 ),
//                 child: Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     IconButton(
//                       icon: Icon(
//                         _playingStates[msg.audioUrl] == true
//                             ? Icons.pause
//                             : Icons.play_arrow,
//                         color: Colors.blue,
//                       ),
//                       onPressed: () async {
//                         final key = msg.audioUrl!;
//                         final isPlaying = _playingStates[key] == true;
//                         if (isPlaying) {
//                           await _player.stopPlayer();
//                           setState(() => _playingStates[key] = false);
//                         } else {
//                           await _player.stopPlayer();
//                           setState(() {
//                             _playingStates.updateAll((_, __) => false);
//                             _playingStates[key] = true;
//                           });
//                           await _player.startPlayer(
//                             fromURI: key,
//                             codec: Codec.aacADTS,
//                             whenFinished: () {
//                               setState(() => _playingStates[key] = false);
//                             },
//                           );
//                         }
//                       },
//                     ),
//                     const Text("Voice message"),
//                   ],
//                 ),
//               ),
//             if (msg.imageUrl != null && msg.imageUrl!.isNotEmpty)
//               Stack(
//                 children: [
//                   Container(
//                     padding: const EdgeInsets.all(8),
//                     margin: const EdgeInsets.symmetric(vertical: 2),
//                     decoration: BoxDecoration(
//                       border: Border.all(
//                         color: AppColors.adminChatContainerColor,
//                       ),
//                       borderRadius: BorderRadius.circular(15),
//                     ),
//                     child: buildChatImage(msg.imageUrl!),
//                   ),
//                   if (msg.isSending)
//                     Positioned.fill(
//                       child: Container(
//                         color: Colors.black.withOpacity(0.3),
//                         child: Center(child: AppLoader.circularLoader()),
//                       ),
//                     ),
//                 ],
//               ),
//             if (showTime && !msg.isTyping)
//               Text(
//                 msg.time,
//                 style: const TextStyle(fontSize: 10, color: Colors.grey),
//               ),
//           ],
//         ),
//         const SizedBox(width: 6),
//         if (msg.isMe && showAvatar) buildAvatar(msg.avatar),
//         if (msg.isMe && !showAvatar) const SizedBox(width: 46),
//       ],
//     );
//   }
//
//   Widget buildChatImage(String imagePath) {
//     if (imagePath.startsWith('http')) {
//       return _cachedRectImage(
//         imageUrl: imagePath,
//         w: 100,
//         h: 100,
//         fallbackAsset: AppImages.dummy,
//       );
//     } else {
//       final cleanPath = imagePath.replaceFirst('file://', '');
//       if (File(cleanPath).existsSync()) {
//         return Image.file(
//           File(cleanPath),
//           width: 100,
//           height: 100,
//           fit: BoxFit.cover,
//         );
//       } else {
//         return _cachedRectImage(
//           imageUrl: '',
//           w: 100,
//           h: 100,
//           fallbackAsset: AppImages.dummy,
//         );
//       }
//     }
//   }
//
//   Widget buildAvatar(String? imagePath) {
//     const size = 40.0;
//
//     // Network image → cached with person icon fallback
//     if (imagePath != null && imagePath.startsWith('http')) {
//       return Stack(
//         children: [
//           ClipOval(
//             child: _cachedCircleImage(
//               imageUrl: imagePath,
//               size: size,
//               fallbackAsset: AppImages.dummy, // not shown; we use icon instead
//             ),
//           ),
//           _onlineDot(),
//         ],
//       );
//     }
//
//     // Local file path → if missing/invalid show person icon
//     if (imagePath != null &&
//         (imagePath.startsWith('/data') || imagePath.startsWith('file:/'))) {
//       final clean = imagePath.replaceFirst('file://', '');
//       final avatar =
//           File(clean).existsSync()
//               ? ClipOval(
//                 child: Image.file(
//                   File(clean),
//                   width: size,
//                   height: size,
//                   fit: BoxFit.cover,
//                 ),
//               )
//               : _personCircle(size);
//       return Stack(children: [avatar, _onlineDot()]);
//     }
//
//     // Empty or asset path → show person icon (ignore asset if you prefer the icon)
//     final Widget avatar =
//         (imagePath != null &&
//                 imagePath.isNotEmpty &&
//                 !imagePath.startsWith('http'))
//             ? ClipOval(
//               child: Image.asset(
//                 imagePath,
//                 width: size,
//                 height: size,
//                 fit: BoxFit.cover,
//               ),
//             )
//             : _personCircle(size);
//
//     return Stack(children: [avatar, _onlineDot()]);
//   }
//
//   Widget _personCircle(double size) => CircleAvatar(
//     radius: size / 2,
//     backgroundColor: Colors.grey.shade300,
//     child: const Icon(Icons.person, color: Colors.white),
//   );
//
//   Widget _onlineDot() => Positioned(
//     right: 0,
//     top: 0,
//     child: Container(
//       width: 10,
//       height: 10,
//       decoration: BoxDecoration(
//         color: Colors.green,
//         shape: BoxShape.circle,
//         border: Border.all(color: Colors.white, width: 1.5),
//       ),
//     ),
//   );
// }
//
// class CutOutCircleClipper extends CustomClipper<Path> {
//   final double? cutRadius;
//   CutOutCircleClipper({this.cutRadius = 8});
//
//   @override
//   Path getClip(Size size) {
//     final mainRadius = size.width / 2;
//     final radius = cutRadius ?? 5;
//     final cutCenter = Offset(size.width - 6, 6);
//
//     final fullCircle =
//         Path()..addOval(
//           Rect.fromCircle(
//             center: Offset(mainRadius, mainRadius),
//             radius: mainRadius,
//           ),
//         );
//     final cutCircle =
//         Path()..addOval(Rect.fromCircle(center: cutCenter, radius: radius));
//     return Path.combine(PathOperation.difference, fullCircle, cutCircle);
//   }
//
//   @override
//   bool shouldReclip(CustomClipper<Path> oldClipper) => false;
// }
