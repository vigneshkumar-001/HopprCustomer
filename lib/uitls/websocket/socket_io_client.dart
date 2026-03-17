import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:hopper/Core/Consents/app_logger.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  late IO.Socket _socket;
  bool _initialized = false;
  bool get connected => _socket.connected;

  // 🔹 Dynamic state storage
  String? _userId;
  final Map<String, String> _joinedRooms = {};

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
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket.connect();

    _socket.onConnect((_) {
      AppLogger.log.i("✅ Connected to $url");

      // Re-register user dynamically
      if (_userId != null) registerUser(_userId!);

      // Re-join all previous rooms
      _joinedRooms.forEach((bookingId, driverId) {
        joinBooking(bookingId: bookingId, driverId: driverId);
      });
    });

    _socket.onDisconnect((_) => AppLogger.log.e("❌ Disconnected from $url"));
    _socket.onConnectError((err) => AppLogger.log.e("❗ Connect error: $err"));
    _socket.onReconnectAttempt(
      (attempt) => AppLogger.log.w("🔁 Reconnect attempt #$attempt"),
    );
    _socket.onError((err) => AppLogger.log.e("❗ General socket error: $err"));
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
    emit('join-booking', {'bookingId': bookingId});
    emit('track-driver', {'driverId': driverId});
  }

  // 🔹 Leave booking
  void leaveBooking(String bookingId) {
    if (_joinedRooms.containsKey(bookingId)) {
      emit('leave-booking', {'bookingId': bookingId});
      _joinedRooms.remove(bookingId);
    }
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
