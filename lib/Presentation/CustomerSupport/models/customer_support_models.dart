import 'package:flutter/material.dart';

enum CustomerSupportTicketStatus { opened, pending, solved, closed }

enum CustomerSupportMessageSendState { sending, sent, failed }

extension CustomerSupportTicketStatusX on CustomerSupportTicketStatus {
  String get label {
    switch (this) {
      case CustomerSupportTicketStatus.opened:
        return 'Opened';
      case CustomerSupportTicketStatus.pending:
        return 'Pending';
      case CustomerSupportTicketStatus.solved:
        return 'Solved';
      case CustomerSupportTicketStatus.closed:
        return 'Closed';
    }
  }

  Color get accent {
    switch (this) {
      case CustomerSupportTicketStatus.opened:
        return const Color(0xFF2F80ED);
      case CustomerSupportTicketStatus.pending:
        return const Color(0xFFF2994A);
      case CustomerSupportTicketStatus.solved:
        return const Color(0xFF27AE60);
      case CustomerSupportTicketStatus.closed:
        return const Color(0xFF667085);
    }
  }

  IconData get icon {
    switch (this) {
      case CustomerSupportTicketStatus.opened:
        return Icons.hourglass_bottom_rounded;
      case CustomerSupportTicketStatus.pending:
        return Icons.access_time_rounded;
      case CustomerSupportTicketStatus.solved:
        return Icons.check_circle_rounded;
      case CustomerSupportTicketStatus.closed:
        return Icons.cancel_rounded;
    }
  }
}

class CustomerSupportMessage {
  final String id;
  final String text;
  final DateTime createdAt;
  final bool fromCustomer;
  final String? imageUrl;
  final String? localImagePath;
  final CustomerSupportMessageSendState sendState;

  CustomerSupportMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.fromCustomer,
    this.imageUrl,
    this.localImagePath,
    this.sendState = CustomerSupportMessageSendState.sent,
  });
}

class CustomerSupportTicket {
  final String id; // ticketId (e.g. "T78AGB17")
  final String subject;
  final String description;
  final DateTime createdAt;
  CustomerSupportTicketStatus status;
  final String? categoryId;
  final String? categoryLabel;
  final String? subcategoryId;
  final String? subcategoryLabel;
  final String? priorityId;
  final String? priorityLabel;
  final bool unreadByAdmin;
  final String? bookingId;
  final List<CustomerSupportMessage> messages;
  final List<String> attachments;

  CustomerSupportTicket({
    required this.id,
    required this.subject,
    required this.description,
    required this.createdAt,
    required this.status,
    this.categoryId,
    this.categoryLabel,
    this.subcategoryId,
    this.subcategoryLabel,
    this.priorityId,
    this.priorityLabel,
    this.unreadByAdmin = false,
    this.bookingId,
    this.attachments = const <String>[],
    List<CustomerSupportMessage>? messages,
  }) : messages = messages ?? <CustomerSupportMessage>[];
}

// ------------------------------------------------------------
// Support API models (clean JSON -> typed models)
// ------------------------------------------------------------

class SupportCommonDetailsResponse {
  final bool success;
  final SupportCommonDetailsData? data;

  SupportCommonDetailsResponse({required this.success, required this.data});

  factory SupportCommonDetailsResponse.fromJson(Map<String, dynamic> json) {
    return SupportCommonDetailsResponse(
      success: json['success'] == true,
      data:
          json['data'] is Map
              ? SupportCommonDetailsData.fromJson(
                Map<String, dynamic>.from(json['data'] as Map),
              )
              : null,
    );
  }
}

class SupportCommonDetailsData {
  final List<SupportCategory> categories;
  final List<SupportPriority> priorities;

  SupportCommonDetailsData({
    required this.categories,
    required this.priorities,
  });

  factory SupportCommonDetailsData.fromJson(Map<String, dynamic> json) {
    final cats =
        (json['categories'] is List)
            ? (json['categories'] as List)
                .whereType<Map>()
                .map(
                  (e) => SupportCategory.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
            : <SupportCategory>[];

    final prios =
        (json['priorities'] is List)
            ? (json['priorities'] as List)
                .whereType<Map>()
                .map(
                  (e) => SupportPriority.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
            : <SupportPriority>[];

    return SupportCommonDetailsData(categories: cats, priorities: prios);
  }

  SupportCategory? categoryById(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  SupportPriority? priorityById(String id) {
    for (final p in priorities) {
      if (p.id == id) return p;
    }
    return null;
  }
}

class SupportCategory {
  final String id;
  final String label;
  final List<SupportSubcategory> subcategories;

  SupportCategory({
    required this.id,
    required this.label,
    required this.subcategories,
  });

  factory SupportCategory.fromJson(Map<String, dynamic> json) {
    final subs =
        (json['subcategories'] is List)
            ? (json['subcategories'] as List)
                .whereType<Map>()
                .map(
                  (e) =>
                      SupportSubcategory.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
            : <SupportSubcategory>[];

    return SupportCategory(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      subcategories: subs,
    );
  }

  SupportSubcategory? subcategoryById(String id) {
    for (final s in subcategories) {
      if (s.id == id) return s;
    }
    return null;
  }
}

class SupportSubcategory {
  final String id;
  final String label;

  SupportSubcategory({required this.id, required this.label});

  factory SupportSubcategory.fromJson(Map<String, dynamic> json) {
    return SupportSubcategory(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
    );
  }
}

class SupportPriority {
  final String id;
  final String label;

  SupportPriority({required this.id, required this.label});

  factory SupportPriority.fromJson(Map<String, dynamic> json) {
    return SupportPriority(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
    );
  }
}

class SupportPagination {
  final int page;
  final int limit;
  final int totalCount;
  final int totalPages;

  SupportPagination({
    required this.page,
    required this.limit,
    required this.totalCount,
    required this.totalPages,
  });

  factory SupportPagination.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
    return SupportPagination(
      page: toInt(json['page']),
      limit: toInt(json['limit']),
      totalCount: toInt(json['totalCount']),
      totalPages: toInt(json['totalPages']),
    );
  }
}

class SupportMyTicketsResponse {
  final bool success;
  final List<SupportTicketApi> data;
  final SupportPagination? pagination;

  SupportMyTicketsResponse({
    required this.success,
    required this.data,
    this.pagination,
  });

  factory SupportMyTicketsResponse.fromJson(Map<String, dynamic> json) {
    final list =
        (json['data'] is List)
            ? (json['data'] as List)
                .whereType<Map>()
                .map(
                  (e) =>
                      SupportTicketApi.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
            : <SupportTicketApi>[];

    return SupportMyTicketsResponse(
      success: json['success'] == true,
      data: list,
      pagination:
          json['pagination'] is Map
              ? SupportPagination.fromJson(
                Map<String, dynamic>.from(json['pagination'] as Map),
              )
              : null,
    );
  }
}

class SupportCreateTicketResponse {
  final bool success;
  final String message;
  final SupportTicketApi? data;

  SupportCreateTicketResponse({
    required this.success,
    required this.message,
    required this.data,
  });

  factory SupportCreateTicketResponse.fromJson(Map<String, dynamic> json) {
    return SupportCreateTicketResponse(
      success: json['success'] == true,
      message: (json['message'] ?? '').toString(),
      data:
          json['data'] is Map
              ? SupportTicketApi.fromJson(
                Map<String, dynamic>.from(json['data'] as Map),
              )
              : null,
    );
  }
}

class SupportTicketApi {
  final String id; // _id
  final String ticketId;
  final String userId;
  final String userType;
  final String status;
  final bool unreadByAdmin;
  final String ticketSubject;
  final String supportCategoryId;
  final String supportCategoryLabel;
  final String supportSubcategoryId;
  final String supportSubcategoryLabel;
  final String supportPriority;
  final String detailedDescription;
  final List<String> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;

  SupportTicketApi({
    required this.id,
    required this.ticketId,
    required this.userId,
    required this.userType,
    required this.status,
    required this.unreadByAdmin,
    required this.ticketSubject,
    required this.supportCategoryId,
    required this.supportCategoryLabel,
    required this.supportSubcategoryId,
    required this.supportSubcategoryLabel,
    required this.supportPriority,
    required this.detailedDescription,
    required this.attachments,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SupportTicketApi.fromJson(Map<String, dynamic> json) {
    DateTime parseDt(dynamic v) =>
        DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();

    final rawAttachments = json['attachments'];
    final attachments =
        rawAttachments is List
            ? rawAttachments.map((e) => e.toString()).toList(growable: false)
            : <String>[];

    return SupportTicketApi(
      id: (json['_id'] ?? '').toString(),
      ticketId: (json['ticketId'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      userType: (json['userType'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      unreadByAdmin: json['unreadByAdmin'] == true,
      ticketSubject: (json['ticketSubject'] ?? '').toString(),
      supportCategoryId: (json['supportCategoryId'] ?? '').toString(),
      supportCategoryLabel: (json['supportCategoryLabel'] ?? '').toString(),
      supportSubcategoryId: (json['supportSubcategoryId'] ?? '').toString(),
      supportSubcategoryLabel:
          (json['supportSubcategoryLabel'] ?? '').toString(),
      supportPriority: (json['supportPriority'] ?? '').toString(),
      detailedDescription: (json['detailedDescription'] ?? '').toString(),
      attachments: attachments,
      createdAt: parseDt(json['createdAt']),
      updatedAt: parseDt(json['updatedAt']),
    );
  }
}

class SupportTicketMessageApi {
  final String id; // _id
  final String ticketId;
  final String ticketMessage;
  final List<String> ticketFiles;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? userId;
  final String? adminId;

  SupportTicketMessageApi({
    required this.id,
    required this.ticketId,
    required this.ticketMessage,
    required this.ticketFiles,
    required this.createdAt,
    required this.updatedAt,
    this.userId,
    this.adminId,
  });

  factory SupportTicketMessageApi.fromJson(Map<String, dynamic> json) {
    DateTime parseDt(dynamic v) =>
        DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();

    final rawFiles = json['ticketFiles'];
    final files =
        rawFiles is List
            ? rawFiles.map((e) => e.toString()).toList(growable: false)
            : <String>[];

    return SupportTicketMessageApi(
      id: (json['_id'] ?? '').toString(),
      ticketId: (json['ticketId'] ?? '').toString(),
      ticketMessage: (json['ticketMessage'] ?? '').toString(),
      ticketFiles: files,
      createdAt: parseDt(json['createdAt'] ?? json['date']),
      updatedAt: parseDt(json['updatedAt'] ?? json['date']),
      userId:
          (json['userId'] == null) ? null : (json['userId'] ?? '').toString(),
      adminId:
          (json['adminId'] == null) ? null : (json['adminId'] ?? '').toString(),
    );
  }
}

class SupportTicketDetailsData {
  final SupportTicketApi? ticket;
  final List<SupportTicketMessageApi> messages;

  SupportTicketDetailsData({required this.ticket, required this.messages});

  factory SupportTicketDetailsData.fromJson(Map<String, dynamic> json) {
    final ticketJson = json['ticket'];
    final ticket =
        ticketJson is Map
            ? SupportTicketApi.fromJson(Map<String, dynamic>.from(ticketJson))
            : null;

    final rawMessages = json['messages'];
    final messages =
        rawMessages is List
            ? rawMessages
                .whereType<Map>()
                .map(
                  (e) => SupportTicketMessageApi.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList(growable: false)
            : <SupportTicketMessageApi>[];

    return SupportTicketDetailsData(ticket: ticket, messages: messages);
  }
}

class SupportTicketDetailsResponse {
  final bool success;
  final SupportTicketDetailsData? data;

  SupportTicketDetailsResponse({required this.success, required this.data});

  factory SupportTicketDetailsResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return SupportTicketDetailsResponse(
      success: json['success'] == true,
      data:
          data is Map
              ? SupportTicketDetailsData.fromJson(
                Map<String, dynamic>.from(data),
              )
              : null,
    );
  }
}

class SupportSendMessageTicketApi {
  final String id; // _id
  final String ticketId;
  final String userId;
  final String userType;
  final String status;

  SupportSendMessageTicketApi({
    required this.id,
    required this.ticketId,
    required this.userId,
    required this.userType,
    required this.status,
  });

  factory SupportSendMessageTicketApi.fromJson(Map<String, dynamic> json) {
    return SupportSendMessageTicketApi(
      id: (json['_id'] ?? '').toString(),
      ticketId: (json['ticketId'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      userType: (json['userType'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
    );
  }
}

class SupportSendMessageData {
  final SupportSendMessageTicketApi? ticket;
  final SupportTicketMessageApi? message;

  SupportSendMessageData({required this.ticket, required this.message});

  factory SupportSendMessageData.fromJson(Map<String, dynamic> json) {
    final ticketJson = json['ticket'];
    final messageJson = json['message'];
    return SupportSendMessageData(
      ticket:
          ticketJson is Map
              ? SupportSendMessageTicketApi.fromJson(
                Map<String, dynamic>.from(ticketJson),
              )
              : null,
      message:
          messageJson is Map
              ? SupportTicketMessageApi.fromJson(
                Map<String, dynamic>.from(messageJson),
              )
              : null,
    );
  }
}

class SupportSendMessageResponse {
  final bool success;
  final String message;
  final SupportSendMessageData? data;

  SupportSendMessageResponse({
    required this.success,
    required this.message,
    required this.data,
  });

  factory SupportSendMessageResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return SupportSendMessageResponse(
      success: json['success'] == true,
      message: (json['message'] ?? '').toString(),
      data:
          data is Map
              ? SupportSendMessageData.fromJson(
                Map<String, dynamic>.from(data),
              )
              : null,
    );
  }
}
