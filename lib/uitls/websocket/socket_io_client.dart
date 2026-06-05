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
          .setTransports(['websocket'])
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
    });

    _socket.onDisconnect((_) => AppLogger.log.e("❌ Disconnected from $url"));
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
  void onConnect(Function() callback) => _socket.onConnect((_) => callback());
  void onReconnect(Function() callback) =>
      _socket.onReconnect((_) => callback());
  void on(String event, Function(dynamic) callback) =>
      _socket.on(event, callback);
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
