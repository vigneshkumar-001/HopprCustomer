import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:hopper/Core/Consents/app_logger.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  late IO.Socket _socket;
  bool _initialized = false;
  bool get connected => _initialized && _socket.connected;

  // 🔹 Dynamic state storage
  String? _userId;
  final Map<String, String> _joinedRooms = {};
  final Map<String, Map<String, dynamic>> _bookingRoomPayloads = {};

  // Throttle for noisy connect/reconnect error logs (shared across handlers).
  DateTime _lastErrLogAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _shouldLogErr() {
    final now = DateTime.now();
    if (now.difference(_lastErrLogAt) < const Duration(seconds: 30)) {
      return false;
    }
    _lastErrLogAt = now;
    return true;
  }

  SocketService._internal();

  void initSocket(String url) {
    if (_initialized) {
      if (_socket.disconnected) _socket.connect();
      return;
    }

    _initialized = true;

    _socket = IO.io(
      url,
      IO.OptionBuilder()
          // Allow polling as well as websocket (matches the driver app). A
          // websocket-ONLY socket cannot fall back when the WS upgrade is
          // blocked or drops on a flaky mobile network / proxy, which stalls the
          // live feed and freezes the customer's car marker mid-ride. With
          // polling enabled socket.io connects over HTTP long-polling and
          // upgrades to WS when possible, so the stream self-heals.
          .setTransports(['websocket', 'polling'])
          .enableReconnection()
          .enableAutoConnect()
          // Was 10: after 10 'transport close' drops the socket gave up FOREVER,
          // killing live tracking mid-ride. Keep retrying effectively forever
          // with a capped exponential backoff so a flaky network self-heals.
          .setReconnectionAttempts(1 << 30)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setTimeout(20000)
          .build(),
    );

    _socket.connect();

    _socket.onConnect((_) {
      AppLogger.log.i("✅ Connected to $url");

      // Re-register user dynamically
      if (_userId != null) registerUser(_userId!);

      // Re-join booking rooms (without tracking)
      for (final payload in _bookingRoomPayloads.values) {
        emit('join-booking', payload);
      }

      // Resume driver tracking
      for (final driverId in _joinedRooms.values) {
        emit('track-driver', {'driverId': driverId});
      }

      // C7: invoke the single STORED external connect callback (set via
      // onConnect()). Stored, not re-registered, so reconnect / screen reopen
      // never multiplies it.
      _externalConnectCb?.call();
    });

    _socket.onDisconnect((_) => AppLogger.log.e("❌ Disconnected from $url"));
    // C7 + H6: on a real reconnect, ask the backend to validate our session and
    // resync the active ride — the server (Phase 2) replies with
    // 'active_ride_sync_required'. Then fan out to the stored external callback.
    _socket.onReconnect((_) {
      if (_userId != null) emit('reconnect', {'userId': _userId});
      _externalReconnectCb?.call();
    });
    // Throttle error logs: while offline the socket retries forever and would
    // otherwise flood the log with the same DNS/connect error every few seconds.
    _socket.onConnectError((err) {
      if (_shouldLogErr()) AppLogger.log.e("❗ Connect error: $err");
    });
    _socket.onReconnectAttempt((attempt) {
      if (_shouldLogErr()) AppLogger.log.w("🔁 Reconnecting… (attempt #$attempt)");
    });
    _socket.onError((err) {
      if (_shouldLogErr()) AppLogger.log.e("❗ General socket error: $err");
    });
    _socket.onAny(
      (event, data) => AppLogger.log.i("📦 Event: $event, Data: $data"),
    );
  }

  // 🔹 User registration
  void registerUser(String userId) {
    _userId = userId;
    emit('register', {'userId': userId, 'type': 'customer'});
  }

  // 🔹 Join a booking / tracking dynamically
  void joinBooking({required String bookingId, required String driverId}) {
    _joinedRooms[bookingId] = driverId;
    joinBookingRoom(bookingId: bookingId);
    emit('track-driver', {'driverId': driverId});
  }

  // 🔹 Join booking room (no driver tracking)
  void joinBookingRoom({
    required String bookingId,
    Map<String, dynamic>? payload,
    bool force = false,
  }) {
    if (!force && _bookingRoomPayloads.containsKey(bookingId)) return;
    _bookingRoomPayloads[bookingId] = payload ?? <String, dynamic>{'bookingId': bookingId};
    if (connected) {
      emit('join-booking', _bookingRoomPayloads[bookingId]);
    }
  }

  void leaveBookingRoom(String bookingId) {
    if (_bookingRoomPayloads.containsKey(bookingId)) {
      emit('leave-booking', {'bookingId': bookingId});
      _bookingRoomPayloads.remove(bookingId);
    }
  }

  // 🔹 Leave booking
  void leaveBooking(String bookingId) {
    if (_joinedRooms.containsKey(bookingId)) {
      _joinedRooms.remove(bookingId);
    }
    leaveBookingRoom(bookingId);
  }

  // 🔹 Event handling
  void retainOnlyBookingContext(
    String bookingId, {
    bool keepDriverTrackingForBooking = false,
  }) {
    _bookingRoomPayloads.removeWhere((key, _) => key != bookingId);
    if (keepDriverTrackingForBooking) {
      _joinedRooms.removeWhere((key, _) => key != bookingId);
    } else {
      _joinedRooms.clear();
    }
  }

  // C7: external connect/reconnect callbacks are STORED (single slot each), not
  // re-registered on the socket. The internal handlers in initSocket fan out to
  // these, so reconnect / screen reopen / controller recreate / app resume can
  // never stack duplicate connect handlers.
  Function()? _externalConnectCb;
  Function()? _externalReconnectCb;

  void onConnect(Function() callback) => _externalConnectCb = callback;
  void onReconnect(Function() callback) => _externalReconnectCb = callback;

  void on(String event, Function(dynamic) callback) {
    // C7: off-before-on so re-registering the same event REPLACES the handler
    // instead of stacking another one. Event name + payload unwrapping unchanged.
    _socket.off(event);
    _socket.on(event, (dynamic data) {
      // The backend sometimes emits with extra trailing args
      // (e.g. emit('nearby-driver-update', payload, packetId)). socket.io then
      // delivers the whole thing as a List [payload, id, ...]. Unwrap the leading
      // Map so handlers can read fields directly. No-op when already a Map.
      var payload = data;
      if (payload is List && payload.isNotEmpty && payload.first is Map) {
        payload = payload.first;
      }
      callback(payload);
    });
  }
  void emit(String event, dynamic data) => _socket.emit(event, data);
  void emitWithAck(String event, dynamic data, Function(dynamic)? ack) =>
      _socket.emitWithAck(event, data, ack: ack);
  void off(String event) => _socket.off(event);

  void dispose() {
    _socket.dispose();
    _initialized = false;
    _joinedRooms.clear();
    _bookingRoomPayloads.clear();
    _userId = null;
  }
}

// import 'package:socket_io_client/socket_io_client.dart' as IO;
// import 'package:hopper/Core/Consents/app_logger.dart';
//
// class SocketService {
//   static final SocketService _instance = SocketService._internal();
//
//   factory SocketService() => _instance;
//
//   late IO.Socket _socket;
//   bool _initialized = false;
//   bool get connected => _socket.connected;
//
//   SocketService._internal();
//
//   void initSocket(String url) {
//     if (_initialized) {
//       if (_socket.disconnected) {
//         _socket.connect(); // reconnect if not connected
//       }
//       return;
//     }
//
//     _initialized = true;
//
//     _socket = IO.io(
//       url,
//       IO.OptionBuilder()
//           .setTransports(['websocket'])
//           .enableReconnection()
//           .enableAutoConnect()
//           .setReconnectionAttempts(5)
//           .setReconnectionDelay(2000)
//           .build(),
//     );
//
//     _socket.connect();
//
//     _socket.onConnect((_) {
//       AppLogger.log.i("✅ Connected to $url");
//     });
//
//     _socket.onDisconnect((_) {
//       AppLogger.log.e("❌ Disconnected from $url");
//     });
//
//     _socket.onConnectError((err) {
//       AppLogger.log.e("❗ Connect error: $err");
//     });
//
//
//
//     _socket.onReconnectAttempt((attempt) {
//       AppLogger.log.w("🔁 Reconnect attempt #$attempt");
//     });
//
//     _socket.onError((err) {
//       AppLogger.log.e("❗ General socket error: $err");
//     });
//
//     // Optional: log all incoming events
//     _socket.onAny((event, data) {
//       AppLogger.log.i("📦 [onAny] Event: $event, Data: $data");
//     });
//   }
//
//   void registerUser(String userId) {
//     emit('register', {'userId': userId, 'type': 'customer'});
//   }
//
//   void onConnect(Function() callback) {
//     _socket.onConnect((_) {
//       AppLogger.log.i("📡 onConnect triggered");
//       callback();
//     });
//   }
//   void onReconnect(Function() callback) {
//     _socket.onReconnect((_) {
//       callback();
//     });
//   }
//
//   void on(String event, Function(dynamic) callback) {
//     _socket.on(event, callback);
//   }
//
//   void emit(String event, dynamic data) {
//     _socket.emit(event, data);
//   }
//
//   void emitWithAck(String event, dynamic data, Function(dynamic)? ack) {
//     _socket.emitWithAck(event, data, ack: ack);
//   }
//
//   void off(String event) {
//     _socket.off(event);
//   }
//
//   void dispose() {
//     _socket.dispose();
//     _initialized = false;
//   }
// }
//
