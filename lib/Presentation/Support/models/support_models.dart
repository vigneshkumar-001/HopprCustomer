import 'package:flutter/material.dart';

enum SupportTicketStatus { opened, pending, solved, closed }

extension SupportTicketStatusX on SupportTicketStatus {
  String get label {
    switch (this) {
      case SupportTicketStatus.opened:
        return 'Opened';
      case SupportTicketStatus.pending:
        return 'Pending';
      case SupportTicketStatus.solved:
        return 'Solved';
      case SupportTicketStatus.closed:
        return 'Closed';
    }
  }

  Color get accent {
    switch (this) {
      case SupportTicketStatus.opened:
        return const Color(0xFF2F80ED);
      case SupportTicketStatus.pending:
        return const Color(0xFFF2994A);
      case SupportTicketStatus.solved:
        return const Color(0xFF27AE60);
      case SupportTicketStatus.closed:
        return const Color(0xFF667085);
    }
  }

  IconData get icon {
    switch (this) {
      case SupportTicketStatus.opened:
        return Icons.hourglass_bottom_rounded;
      case SupportTicketStatus.pending:
        return Icons.access_time_rounded;
      case SupportTicketStatus.solved:
        return Icons.check_circle_rounded;
      case SupportTicketStatus.closed:
        return Icons.cancel_rounded;
    }
  }
}

class SupportMessage {
  final String id;
  final String text;
  final DateTime createdAt;
  final bool fromCustomer;
  final String? imagePath;

  SupportMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.fromCustomer,
    this.imagePath,
  });
}

class SupportTicket {
  final String id;
  final String subject;
  final String description;
  final DateTime createdAt;
  SupportTicketStatus status;
  final String? bookingId;
  final List<SupportMessage> messages;
  final String? attachmentPath;

  SupportTicket({
    required this.id,
    required this.subject,
    required this.description,
    required this.createdAt,
    required this.status,
    this.bookingId,
    this.attachmentPath,
    List<SupportMessage>? messages,
  }) : messages = messages ?? <SupportMessage>[];
}

