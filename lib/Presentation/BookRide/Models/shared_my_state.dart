/// Privacy-safe per-customer shared-ride state from the backend
/// (`shared_my_state` socket event + GET /shared/my-state/:bookingId).
/// Carries ONLY this customer's own data + counts + generic labels — never any
/// other passenger's name / phone / address / id / coordinates.
class SharedPrivacyStop {
  final String label; // e.g. "Pickup before you", "Your pickup"
  final String type; // PICKUP | DROP | MY_PICKUP | MY_DROP
  const SharedPrivacyStop({required this.label, required this.type});
}

class SharedMyState {
  final String sharedRideId;
  final String customerBookingId;
  final String myStatus; // PICKUP_PENDING | PICKED_UP | DROPPED | CANCELLED
  final String driverCurrentAction;
  final bool amINextPickup;
  final bool amINextDrop;
  final int stopsBeforeMe;
  final int? etaToMyPickupMinutes;
  final int? etaToMyDropMinutes;
  final List<int> mySeatNumbers;
  final List<SharedPrivacyStop> privacySafeStops;
  final String pickupInstruction; // DB-sourced "Directions to reach" note
  final String paymentMode; // DB-sourced payment method (COD/PAYSTACK/WALLET/…)
  final bool myBookingCompleted; // booking-doc terminal status (SUCCESS/PAID)

  const SharedMyState({
    required this.sharedRideId,
    required this.customerBookingId,
    required this.myStatus,
    required this.driverCurrentAction,
    required this.amINextPickup,
    required this.amINextDrop,
    required this.stopsBeforeMe,
    required this.etaToMyPickupMinutes,
    required this.etaToMyDropMinutes,
    required this.mySeatNumbers,
    required this.privacySafeStops,
    this.pickupInstruction = '',
    this.paymentMode = '',
    this.myBookingCompleted = false,
  });

  /// Friendly label for the payment method, or '' when unknown.
  String get paymentLabel {
    switch (paymentMode.toUpperCase().trim()) {
      case 'COD':
        return 'Cash';
      case 'WALLET':
        return 'Wallet';
      case 'PAYSTACK':
      case 'STRIPE':
      case 'FLUTTERWAVE':
      case 'PAYPAL':
        return 'Online';
      default:
        return '';
    }
  }

  bool get isOnboard => myStatus == 'PICKED_UP' || myStatus == 'DROPPED';

  static int? _toInt(dynamic v) =>
      v is num ? v.toInt() : (v == null ? null : int.tryParse(v.toString()));

  factory SharedMyState.fromJson(Map<String, dynamic> j) {
    return SharedMyState(
      sharedRideId: (j['sharedRideId'] ?? '').toString(),
      customerBookingId: (j['customerBookingId'] ?? '').toString(),
      pickupInstruction: (j['pickupInstruction'] ?? '').toString(),
      paymentMode: (j['paymentMode'] ?? '').toString(),
      myBookingCompleted: j['myBookingCompleted'] == true,
      myStatus: (j['myStatus'] ?? '').toString(),
      driverCurrentAction: (j['driverCurrentAction'] ?? '').toString(),
      amINextPickup: j['amINextPickup'] == true,
      amINextDrop: j['amINextDrop'] == true,
      stopsBeforeMe: _toInt(j['stopsBeforeMe']) ?? 0,
      etaToMyPickupMinutes: _toInt(j['etaToMyPickupMinutes']),
      etaToMyDropMinutes: _toInt(j['etaToMyDropMinutes']),
      mySeatNumbers: (j['mySeatNumbers'] as List?)
              ?.map((e) => _toInt(e) ?? 0)
              .where((n) => n > 0)
              .toList() ??
          const [],
      privacySafeStops: (j['privacySafeStops'] as List?)
              ?.whereType<Map>()
              .map((m) => SharedPrivacyStop(
                    label: (m['label'] ?? '').toString(),
                    type: (m['type'] ?? '').toString(),
                  ))
              .toList() ??
          const [],
    );
  }

  String _plural(int n) => n == 1 ? '' : 's';

  /// True once MY leg is finished (backend SUCCESS/PAID).
  bool get isDropped => myStatus == 'DROPPED';

  /// Count of OTHER riders' DROP stops ahead of mine — derived from the TYPE-ONLY
  /// privacySafeStops list (generic labels), never any rider identity. When this
  /// is 0, the stops ahead are all pickups → "N pickup(s) before you"; otherwise
  /// the queue is mixed → the generic "N stops before you".
  int get _otherDropsAhead =>
      privacySafeStops.where((s) => s.type == 'DROP').length;

  /// Primary headline for the status card. Privacy-safe: counts + the driver's
  /// current generic action only (driverCurrentAction), never who.
  String get primaryTitle {
    if (isDropped) return 'You have reached your destination';
    if (!isOnboard) {
      if (amINextPickup) return 'You are next';
      // Surface exactly what the driver is doing for the stop ahead of you.
      if (driverCurrentAction == 'DROPPING_OTHER_RIDER') {
        return 'Driver is dropping another rider first';
      }
      // All stops ahead are pickups → "N pickup(s) before you"; mixed → "N stops".
      if (_otherDropsAhead == 0 && stopsBeforeMe > 0) {
        return '$stopsBeforeMe pickup${_plural(stopsBeforeMe)} before you';
      }
      return '$stopsBeforeMe stop${_plural(stopsBeforeMe)} before you';
    }
    if (amINextDrop) return 'You are next';
    return '$stopsBeforeMe drop${_plural(stopsBeforeMe)} before yours';
  }

  /// Privacy-safe detail line (sequence-aware ETA).
  String get primaryDetail {
    if (isDropped) return '';
    if (!isOnboard) {
      final eta = etaToMyPickupMinutes;
      if (amINextPickup) {
        return eta != null ? 'Driver arriving in $eta min' : 'Driver is on the way';
      }
      return eta != null ? 'ETA to your pickup: $eta min' : '';
    }
    final eta = etaToMyDropMinutes;
    if (amINextDrop) {
      return eta != null
          ? 'Arriving at your destination in $eta min'
          : 'On the way to your destination';
    }
    return eta != null ? 'Drop ETA: $eta min' : '';
  }

  /// Compact text for the collapsed bottom sheet.
  String get collapsedText {
    if (isDropped) return 'You have reached your destination';
    if (!isOnboard) {
      final eta = etaToMyPickupMinutes;
      if (amINextPickup) {
        return eta != null
            ? 'You are next • Driver arriving $eta min'
            : 'You are next';
      }
      final etaTxt = eta != null ? ' • ETA $eta min' : '';
      if (driverCurrentAction == 'DROPPING_OTHER_RIDER') {
        return 'Driver dropping another rider first$etaTxt';
      }
      if (_otherDropsAhead == 0 && stopsBeforeMe > 0) {
        return '$stopsBeforeMe pickup${_plural(stopsBeforeMe)} before you$etaTxt';
      }
      return '$stopsBeforeMe stop${_plural(stopsBeforeMe)} before you$etaTxt';
    }
    final eta = etaToMyDropMinutes;
    if (amINextDrop) {
      return eta != null
          ? 'You are next • Arriving in $eta min'
          : 'On the way to your destination';
    }
    final etaTxt = eta != null ? ' • ETA $eta min' : '';
    return '$stopsBeforeMe drop${_plural(stopsBeforeMe)} before yours$etaTxt';
  }
}
