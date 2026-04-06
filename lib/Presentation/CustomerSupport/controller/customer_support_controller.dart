import 'dart:io';

import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/api/dataSource/apiDataSource.dart';
import 'package:hopper/Presentation/CustomerSupport/models/customer_support_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerSupportController extends GetxController {
  final ApiDataSource api = ApiDataSource();

  final RxList<CustomerSupportTicket> tickets = <CustomerSupportTicket>[].obs;
  final Rxn<SupportCommonDetailsData> commonDetails =
      Rxn<SupportCommonDetailsData>();

  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;
  final RxString lastApiMessage = ''.obs;
  final RxString sendError = ''.obs;

  Future<void> refreshTickets() async {
    isLoading.value = true;
    error.value = '';
    try {
      final res = await api.getMySupportTickets();
      res.fold(
        (failure) {
          error.value = failure.message;
        },
        (resp) {
          final mapped = resp.data.map(_ticketFromApi).toList(growable: false);
          tickets.assignAll(mapped);
        },
      );
    } catch (e, st) {
      AppLogger.log.e('refreshTickets error: $e\n$st');
      error.value = 'Something went wrong';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshTicketDetails(String ticketId) async {
    final id = ticketId.trim();
    if (id.isEmpty) return;

    isLoading.value = true;
    error.value = '';

    try {
      final res = await api.getMySupportTicketDetails(ticketId: id);
      res.fold(
        (failure) {
          error.value = failure.message;
        },
        (resp) {
          final details = resp.data;
          final apiTicket = details?.ticket;
          if (apiTicket == null) return;

          final base = _ticketFromApi(apiTicket);

          final apiMessages = details?.messages ?? const <SupportTicketMessageApi>[];
          final mappedMessages = apiMessages
              .map((m) {
                final isAdmin = (m.adminId ?? '').trim().isNotEmpty;
                return CustomerSupportMessage(
                  id:
                      m.id.isNotEmpty
                          ? m.id
                          : DateTime.now().microsecondsSinceEpoch.toString(),
                  text: m.ticketMessage.trim(),
                  createdAt: m.createdAt,
                  fromCustomer: !isAdmin,
                  imageUrl: m.ticketFiles.isEmpty ? null : m.ticketFiles.first,
                  localImagePath: null,
                  sendState: CustomerSupportMessageSendState.sent,
                );
              })
              .where((m) => m.text.isNotEmpty || (m.imageUrl ?? '').isNotEmpty)
              // IMPORTANT: keep growable so we can append optimistic messages.
              .toList(growable: true)
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

          final merged = CustomerSupportTicket(
            id: base.id,
            subject: base.subject,
            description: base.description,
            createdAt: base.createdAt,
            status: base.status,
            categoryId: base.categoryId,
            categoryLabel: base.categoryLabel,
            subcategoryId: base.subcategoryId,
            subcategoryLabel: base.subcategoryLabel,
            priorityId: base.priorityId,
            priorityLabel: base.priorityLabel,
            unreadByAdmin: base.unreadByAdmin,
            bookingId: base.bookingId,
            attachments: base.attachments,
            messages: mappedMessages.isNotEmpty ? mappedMessages : base.messages,
          );

          final idx = tickets.indexWhere((t) => t.id == merged.id);
          if (idx >= 0) {
            tickets[idx] = merged;
          } else {
            tickets.insert(0, merged);
          }
          tickets.refresh();
        },
      );
    } catch (e, st) {
      AppLogger.log.e('refreshTicketDetails error: $e\n$st');
      error.value = 'Something went wrong';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshCommonDetails() async {
    try {
      final res = await api.getSupportCommonDetails();
      res.fold(
        (failure) {
          AppLogger.log.e('refreshCommonDetails error: ${failure.message}');
        },
        (resp) {
          commonDetails.value = resp.data;
        },
      );
    } catch (e, st) {
      AppLogger.log.e('refreshCommonDetails error: $e\n$st');
    }
  }

  Future<void> ensureCommonDetailsLoaded() async {
    if (commonDetails.value != null) return;
    await refreshCommonDetails();
  }

  CustomerSupportTicket? ticketById(String id) {
    try {
      return tickets.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<String?> uploadAttachment(File file) async {
    final res = await api.userProfileUpload(imageFile: file);
    return res.fold((_) => null, (ok) => ok.message);
  }

  Future<CustomerSupportTicket?> createTicket({
    required String subject,
    required String description,
    required String categoryId,
    required String subcategoryId,
    required String priority,
    String? bookingId,
    List<String> attachments = const <String>[],
  }) async {
    isLoading.value = true;
    error.value = '';
    lastApiMessage.value = '';

    try {
      final res = await api.createSupportTicket(
        categoryId: categoryId,
        subcategoryId: subcategoryId,
        priority: priority,
        subject: subject.trim(),
        detailedDescription: description.trim(),
        attachments: attachments,
      );

      return res.fold(
        (failure) {
          error.value = failure.message;
          lastApiMessage.value = failure.message;
          return null;
        },
        (resp) {
          lastApiMessage.value = resp.message;
          final apiTicket = resp.data;
          if (apiTicket == null) return null;

          final created = _ticketFromApi(apiTicket);
          final merged = CustomerSupportTicket(
            id: created.id,
            subject: created.subject,
            description: created.description,
            createdAt: created.createdAt,
            status: created.status,
            categoryId: created.categoryId,
            categoryLabel: created.categoryLabel,
            subcategoryId: created.subcategoryId,
            subcategoryLabel: created.subcategoryLabel,
            priorityId: created.priorityId,
            priorityLabel: created.priorityLabel,
            unreadByAdmin: created.unreadByAdmin,
            bookingId:
                (bookingId ?? '').trim().isEmpty
                    ? created.bookingId
                    : bookingId,
            attachments: created.attachments,
            messages: created.messages,
          );

          tickets.insert(0, merged);
          tickets.refresh();
          return merged;
        },
      );
    } catch (e, st) {
      AppLogger.log.e('createTicket error: $e\n$st');
      AppLogger.log.e('createTicket error: $e\n$st');
      error.value = 'Something went wrong';
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  void closeTicketLocal(String ticketId) {
    final t = ticketById(ticketId);
    if (t == null) return;
    t.status = CustomerSupportTicketStatus.closed;
    tickets.refresh();
  }

  void sendMessageLocal({
    required String ticketId,
    required String text,
    bool fromCustomer = true,
    String? imageUrl,
  }) {
    final id = ticketId.trim();
    if (id.isEmpty) return;
    final ticketIndex = tickets.indexWhere((t) => t.id == id);
    if (ticketIndex < 0) return;

    final t = tickets[ticketIndex];
    final mutable = _cloneTicketWithMessages(
      t,
      List<CustomerSupportMessage>.from(t.messages, growable: true),
    );
    tickets[ticketIndex] = mutable;

    mutable.messages.add(
      CustomerSupportMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text.trim(),
        createdAt: DateTime.now(),
        fromCustomer: fromCustomer,
        imageUrl: imageUrl,
        localImagePath: null,
        sendState: CustomerSupportMessageSendState.sent,
      ),
    );
    tickets.refresh();
  }

  int _ensureMutableTicketIndex(String ticketId) {
    final id = ticketId.trim();
    if (id.isEmpty) return -1;
    final idx = tickets.indexWhere((t) => t.id == id);
    if (idx < 0) return -1;

    final cur = tickets[idx];
    final mutable = _cloneTicketWithMessages(
      cur,
      List<CustomerSupportMessage>.from(cur.messages, growable: true),
    );
    tickets[idx] = mutable;
    return idx;
  }

  void _markMessageState({
    required String ticketId,
    required String messageId,
    required CustomerSupportMessageSendState state,
  }) {
    final idx = _ensureMutableTicketIndex(ticketId);
    if (idx < 0) return;
    final t = tickets[idx];
    final mi = t.messages.indexWhere((m) => m.id == messageId);
    if (mi < 0) return;

    final old = t.messages[mi];
    t.messages[mi] = CustomerSupportMessage(
      id: old.id,
      text: old.text,
      createdAt: old.createdAt,
      fromCustomer: old.fromCustomer,
      imageUrl: old.imageUrl,
      localImagePath: old.localImagePath,
      sendState: state,
    );
    tickets.refresh();
  }

  Future<void> sendMessageWithFiles({
    required String ticketId,
    required String text,
    List<File> attachmentFiles = const <File>[],
  }) async {
    final id = ticketId.trim();
    final msg = text.trim();
    if (id.isEmpty || (msg.isEmpty && attachmentFiles.isEmpty)) return;

    final ticketIndex = _ensureMutableTicketIndex(id);
    if (ticketIndex < 0) return;
    final t = tickets[ticketIndex];

    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final localImagePath =
        attachmentFiles.isEmpty ? null : attachmentFiles.first.path;
    final optimistic = CustomerSupportMessage(
      id: localId,
      text: msg,
      createdAt: DateTime.now(),
      fromCustomer: true,
      imageUrl: null,
      localImagePath: localImagePath,
      sendState: CustomerSupportMessageSendState.sending,
    );
    t.messages.add(optimistic);
    tickets.refresh();

    try {
      final urls = <String>[];
      for (final f in attachmentFiles) {
        final u = await uploadAttachment(f);
        if (u == null || u.trim().isEmpty) {
          sendError.value = 'Image upload failed';
          _markMessageState(
            ticketId: id,
            messageId: localId,
            state: CustomerSupportMessageSendState.failed,
          );
          return;
        }
        urls.add(u.trim());
      }

      final res = await api.sendSupportTicketMessage(
        ticketId: id,
        userType: 'customer',
        message: msg,
        attachments: urls,
      );

      res.fold(
        (failure) {
          sendError.value = failure.message;
          _markMessageState(
            ticketId: id,
            messageId: localId,
            state: CustomerSupportMessageSendState.failed,
          );
        },
        (ok) {
          lastApiMessage.value = ok.message;
          final apiMsg = ok.data?.message;
          if (apiMsg == null) return;

          final isAdmin = (apiMsg.adminId ?? '').trim().isNotEmpty;
          final serverMapped = CustomerSupportMessage(
            id: apiMsg.id.isNotEmpty ? apiMsg.id : localId,
            text: apiMsg.ticketMessage.trim(),
            createdAt: apiMsg.createdAt,
            fromCustomer: !isAdmin,
            imageUrl: apiMsg.ticketFiles.isEmpty ? null : apiMsg.ticketFiles.first,
            localImagePath: null,
            sendState: CustomerSupportMessageSendState.sent,
          );

          final curIdx = _ensureMutableTicketIndex(id);
          if (curIdx < 0) return;
          final curTicket = tickets[curIdx];

          final replaceIdx = curTicket.messages.indexWhere((m) => m.id == localId);
          if (replaceIdx >= 0) {
            curTicket.messages[replaceIdx] = serverMapped;
          } else {
            curTicket.messages.add(serverMapped);
          }
        },
      );
    } catch (e, st) {
      AppLogger.log.e('sendMessageWithFiles error: $e\n$st');
      sendError.value = 'Something went wrong';
      _markMessageState(
        ticketId: id,
        messageId: localId,
        state: CustomerSupportMessageSendState.failed,
      );
    } finally {
      tickets.refresh();
    }
  }

  Future<void> retryFailedMessage({
    required String ticketId,
    required String messageId,
  }) async {
    final id = ticketId.trim();
    final mid = messageId.trim();
    if (id.isEmpty || mid.isEmpty) return;

    final idx = _ensureMutableTicketIndex(id);
    if (idx < 0) return;
    final t = tickets[idx];
    final mi = t.messages.indexWhere((m) => m.id == mid);
    if (mi < 0) return;

    final m = t.messages[mi];
    if (!m.fromCustomer) return;
    if (m.sendState != CustomerSupportMessageSendState.failed) return;

    _markMessageState(
      ticketId: id,
      messageId: mid,
      state: CustomerSupportMessageSendState.sending,
    );

    try {
      final urls = <String>[];
      final localPath = (m.localImagePath ?? '').trim();
      if (localPath.isNotEmpty) {
        final u = await uploadAttachment(File(localPath));
        if (u == null || u.trim().isEmpty) {
          sendError.value = 'Image upload failed';
          _markMessageState(
            ticketId: id,
            messageId: mid,
            state: CustomerSupportMessageSendState.failed,
          );
          return;
        }
        urls.add(u.trim());
      }

      final res = await api.sendSupportTicketMessage(
        ticketId: id,
        userType: 'customer',
        message: m.text.trim(),
        attachments: urls,
      );

      res.fold(
        (failure) {
          sendError.value = failure.message;
          _markMessageState(
            ticketId: id,
            messageId: mid,
            state: CustomerSupportMessageSendState.failed,
          );
        },
        (ok) {
          lastApiMessage.value = ok.message;
          final apiMsg = ok.data?.message;
          if (apiMsg == null) return;

          final isAdmin = (apiMsg.adminId ?? '').trim().isNotEmpty;
          final serverMapped = CustomerSupportMessage(
            id: apiMsg.id.isNotEmpty ? apiMsg.id : mid,
            text: apiMsg.ticketMessage.trim(),
            createdAt: apiMsg.createdAt,
            fromCustomer: !isAdmin,
            imageUrl: apiMsg.ticketFiles.isEmpty ? null : apiMsg.ticketFiles.first,
            localImagePath: null,
            sendState: CustomerSupportMessageSendState.sent,
          );

          final curIdx = _ensureMutableTicketIndex(id);
          if (curIdx < 0) return;
          final curTicket = tickets[curIdx];
          final replaceIdx = curTicket.messages.indexWhere((x) => x.id == mid);
          if (replaceIdx >= 0) {
            curTicket.messages[replaceIdx] = serverMapped;
          } else {
            curTicket.messages.add(serverMapped);
          }
        },
      );
    } catch (e, st) {
      AppLogger.log.e('retryFailedMessage error: $e\n$st');
      sendError.value = 'Something went wrong';
      _markMessageState(
        ticketId: id,
        messageId: mid,
        state: CustomerSupportMessageSendState.failed,
      );
    } finally {
      tickets.refresh();
    }
  }

  CustomerSupportTicket _cloneTicketWithMessages(
    CustomerSupportTicket t,
    List<CustomerSupportMessage> messages,
  ) {
    return CustomerSupportTicket(
      id: t.id,
      subject: t.subject,
      description: t.description,
      createdAt: t.createdAt,
      status: t.status,
      categoryId: t.categoryId,
      categoryLabel: t.categoryLabel,
      subcategoryId: t.subcategoryId,
      subcategoryLabel: t.subcategoryLabel,
      priorityId: t.priorityId,
      priorityLabel: t.priorityLabel,
      unreadByAdmin: t.unreadByAdmin,
      bookingId: t.bookingId,
      attachments: t.attachments,
      messages: messages,
    );
  }

  Future<void> sendMessage({
    required String ticketId,
    required String text,
    List<String> attachments = const <String>[],
  }) async {
    final id = ticketId.trim();
    final msg = text.trim();
    if (id.isEmpty || (msg.isEmpty && attachments.isEmpty)) return;

    final ticketIndex = tickets.indexWhere((t) => t.id == id);
    if (ticketIndex < 0) return;

    var t = tickets[ticketIndex];
    // Defensive: always replace with a growable messages list so `.add` never crashes.
    t = _cloneTicketWithMessages(
      t,
      List<CustomerSupportMessage>.from(t.messages, growable: true),
    );
    tickets[ticketIndex] = t;

    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = CustomerSupportMessage(
      id: localId,
      text: msg,
      createdAt: DateTime.now(),
      fromCustomer: true,
      imageUrl: attachments.isEmpty ? null : attachments.first,
      localImagePath: null,
      sendState: CustomerSupportMessageSendState.sending,
    );
    t.messages.add(optimistic);
    tickets.refresh();

    try {
      final res = await api.sendSupportTicketMessage(
        ticketId: id,
        userType: 'customer',
        message: msg,
        attachments: attachments,
      );

      res.fold(
        (failure) {
          sendError.value = failure.message;
          _markMessageState(
            ticketId: id,
            messageId: localId,
            state: CustomerSupportMessageSendState.failed,
          );
        },
        (ok) {
          lastApiMessage.value = ok.message;
          final apiMsg = ok.data?.message;
          if (apiMsg == null) return;

          final isAdmin = (apiMsg.adminId ?? '').trim().isNotEmpty;
          final serverMapped = CustomerSupportMessage(
            id: apiMsg.id.isNotEmpty ? apiMsg.id : localId,
            text: apiMsg.ticketMessage.trim(),
            createdAt: apiMsg.createdAt,
            fromCustomer: !isAdmin,
            imageUrl: apiMsg.ticketFiles.isEmpty ? null : apiMsg.ticketFiles.first,
            localImagePath: null,
            sendState: CustomerSupportMessageSendState.sent,
          );

          // Re-fetch ticket in case it was replaced/updated.
          final curIdx = tickets.indexWhere((t) => t.id == id);
          if (curIdx < 0) return;
          var curTicket = tickets[curIdx];
          curTicket = _cloneTicketWithMessages(
            curTicket,
            List<CustomerSupportMessage>.from(
              curTicket.messages,
              growable: true,
            ),
          );
          tickets[curIdx] = curTicket;
          final idx = curTicket.messages.indexWhere((m) => m.id == localId);
          if (idx >= 0) {
            curTicket.messages[idx] = serverMapped;
          } else {
            curTicket.messages.add(serverMapped);
          }
        },
      );
    } catch (e, st) {
      AppLogger.log.e('sendMessage error: $e\n$st');
      sendError.value = 'Something went wrong';
      _markMessageState(
        ticketId: id,
        messageId: localId,
        state: CustomerSupportMessageSendState.failed,
      );
    } finally {
      tickets.refresh();
    }
  }

  Future<String> currentCustomerId() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('customer_Id') ?? '').trim();
  }

  CustomerSupportTicket _ticketFromApi(SupportTicketApi apiTicket) {
    final id = apiTicket.ticketId.trim();
    final subject = apiTicket.ticketSubject.trim();
    final desc = apiTicket.detailedDescription.trim();
    final createdAt = apiTicket.createdAt;

    final statusStr = apiTicket.status.toLowerCase().trim();
    final status =
        statusStr == 'open' || statusStr == 'opened'
            ? CustomerSupportTicketStatus.opened
            : statusStr == 'pending'
            ? CustomerSupportTicketStatus.pending
            : statusStr == 'solved' || statusStr == 'resolved'
            ? CustomerSupportTicketStatus.solved
            : statusStr == 'closed'
            ? CustomerSupportTicketStatus.closed
            : CustomerSupportTicketStatus.opened;

    final attachments = apiTicket.attachments;

    return CustomerSupportTicket(
      id: id.isEmpty ? DateTime.now().millisecondsSinceEpoch.toString() : id,
      subject: subject.isEmpty ? 'Support ticket' : subject,
      description: desc,
      createdAt: createdAt,
      status: status,
      categoryId:
          apiTicket.supportCategoryId.trim().isEmpty
              ? null
              : apiTicket.supportCategoryId.trim(),
      categoryLabel:
          apiTicket.supportCategoryLabel.trim().isEmpty
              ? null
              : apiTicket.supportCategoryLabel.trim(),
      subcategoryId:
          apiTicket.supportSubcategoryId.trim().isEmpty
              ? null
              : apiTicket.supportSubcategoryId.trim(),
      subcategoryLabel:
          apiTicket.supportSubcategoryLabel.trim().isEmpty
              ? null
              : apiTicket.supportSubcategoryLabel.trim(),
      priorityId:
          apiTicket.supportPriority.trim().isEmpty
              ? null
              : apiTicket.supportPriority.trim(),
      priorityLabel:
          apiTicket.supportPriority.trim().isEmpty
              ? null
              : apiTicket.supportPriority.trim().capitalizeFirst,
      unreadByAdmin: apiTicket.unreadByAdmin,
      attachments: attachments,
      messages: <CustomerSupportMessage>[
        if (desc.isNotEmpty)
          CustomerSupportMessage(
            id: 'init',
            text: desc,
            createdAt: createdAt,
            fromCustomer: true,
            imageUrl: attachments.isEmpty ? null : attachments.first,
            localImagePath: null,
            sendState: CustomerSupportMessageSendState.sent,
          ),
      ],
    );
  }
}
