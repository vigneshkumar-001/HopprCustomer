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
    final t = ticketById(ticketId);
    if (t == null) return;
    t.messages.add(
      CustomerSupportMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text.trim(),
        createdAt: DateTime.now(),
        fromCustomer: fromCustomer,
        imageUrl: imageUrl,
      ),
    );
    tickets.refresh();
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
          ),
      ],
    );
  }
}
