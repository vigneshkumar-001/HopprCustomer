import 'dart:math';

import 'package:get/get.dart';
import 'package:hopper/Presentation/Support/models/support_models.dart';

class SupportController extends GetxController {
  final RxList<SupportTicket> tickets = <SupportTicket>[].obs;

  @override
  void onInit() {
    super.onInit();

    // Seed a few items so the UI matches design even before API hookup.
    if (tickets.isEmpty) {
      final now = DateTime.now();
      tickets.addAll(<SupportTicket>[
        SupportTicket(
          id: _id(),
          subject: "Transaction Failed due to some reason, I don't ...",
          description: 'Payment failed while finishing the ride.',
          createdAt: now.subtract(const Duration(days: 1)),
          status: SupportTicketStatus.opened,
        ),
        SupportTicket(
          id: _id(),
          subject: "Transaction Failed due to some reason, I don't ...",
          description: 'Need help with my last trip receipt.',
          createdAt: now.subtract(const Duration(days: 2)),
          status: SupportTicketStatus.solved,
        ),
        SupportTicket(
          id: _id(),
          subject: "Transaction Failed due to some reason, I don't ...",
          description: "Driver didn't move and app was stuck.",
          createdAt: now.subtract(const Duration(days: 3)),
          status: SupportTicketStatus.pending,
        ),
      ]);
    }
  }

  SupportTicket? ticketById(String id) {
    try {
      return tickets.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  SupportTicket createTicket({
    required String subject,
    required String description,
    String? bookingId,
    String? attachmentPath,
  }) {
    final t = SupportTicket(
      id: _id(),
      subject: subject.trim(),
      description: description.trim(),
      createdAt: DateTime.now(),
      status: SupportTicketStatus.opened,
      bookingId: bookingId?.trim().isEmpty == true ? null : bookingId?.trim(),
      attachmentPath: attachmentPath,
      messages: <SupportMessage>[
        SupportMessage(
          id: _id(),
          text: description.trim(),
          createdAt: DateTime.now(),
          fromCustomer: true,
          imagePath: attachmentPath,
        ),
      ],
    );
    tickets.insert(0, t);
    tickets.refresh();
    return t;
  }

  void sendMessage({
    required String ticketId,
    required String text,
    bool fromCustomer = true,
    String? imagePath,
  }) {
    final t = ticketById(ticketId);
    if (t == null) return;
    final msg = SupportMessage(
      id: _id(),
      text: text.trim(),
      createdAt: DateTime.now(),
      fromCustomer: fromCustomer,
      imagePath: imagePath,
    );
    t.messages.add(msg);
    tickets.refresh();
  }

  void closeTicket(String ticketId) {
    final t = ticketById(ticketId);
    if (t == null) return;
    t.status = SupportTicketStatus.closed;
    tickets.refresh();
  }

  String _id() => (Random().nextInt(900000) + 100000).toString();
}
