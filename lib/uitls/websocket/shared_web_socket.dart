import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:hopper/Core/Consents/app_logger.dart';

class RideShareSocketService {
  static final RideShareSocketService _instance =
      RideShareSocketService._internal();
  factory RideShareSocketService() => _instance;

  RideShareSocketService._internal();

  late IO.Socket _socket;
  bool _initialized = false;

  String? _userId;
  String? _bookingId;

  // track rooms so we can rejoin on reconnect
  final List<String> _joinedRooms = [];
  List<String> get joinedRooms => _joinedRooms;

  // store listeners so they can be re-registered after reconnect
  final Map<String, Function(dynamic)> _callbacks = {};

  bool get connected => _socket?.connected ?? false;

  // ---------------------------------------------------------
  // Initialize socket
  // ---------------------------------------------------------
  void initSocket(String url) {
    if (_initialized) {
      if (_socket?.disconnected ?? true) _socket?.connect();
      return;
    }

    _initialized = true;

    _socket = IO.io(
      url,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionAttempts(10)
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      AppLogger.log.i("✅ [RIDE] Connected → $url");

      // restore identity (with booking if available)
      if (_userId != null) {
        registerUser(_userId!, bookingId: _bookingId);
      }

      // restore all rooms
      for (final room in _joinedRooms) {
        AppLogger.log.i("📡 [RIDE] Rejoining room: $room");
        emit("join-booking", {
          "bookingId": room,
          "userId": _userId,
          "userType": "customer",
        });
      }

      // rebind all event listeners
      _callbacks.forEach((event, cb) {
        _socket?.off(event);
        _socket?.on(event, cb);
      });

      AppLogger.log.i("🔄 [RIDE] Listeners rebound, rooms rejoined");
    });
    _socket.onError((err) => AppLogger.log.e("❗ General socket error: $err"));

    _socket!.onDisconnect((_) {
      AppLogger.log.e("❌ [RIDE] Disconnected from $url");
    });
    _socket?.onReconnectAttempt(
          (attempt) => AppLogger.log.w("🔁 Reconnect attempt #$attempt"),
    );
    _socket!.onConnectError((err) {
      AppLogger.log.e("❗ [RIDE] Connect error: $err");
    });

    _socket!.onError((err) {
      AppLogger.log.e("❗ [RIDE] General error: $err \n $url");
    });

    _socket!.onAny((event, data) {
      AppLogger.log.i("📦 [RIDE] Event: $event → $data");
    });
  }

  // ---------------------------------------------------------
  // Register current user (optionally with booking)
  // ---------------------------------------------------------
  void registerUser(String userId, {String? bookingId}) {
    _userId = userId;

    if (bookingId != null) {
      _bookingId = bookingId;
      if (!_joinedRooms.contains(bookingId)) {
        _joinedRooms.add(bookingId);
      }
    }

    final payload = <String, dynamic>{
      "userId": userId,
      "type": "customer",
      if (bookingId != null) "bookingId": bookingId,
    };

    emit("register", payload);
    AppLogger.log.i("🙋 [RIDE] register → $payload");
  }

  // ---------------------------------------------------------
  // Active booking
  // ---------------------------------------------------------
  void setBooking(String bookingId) {
    _bookingId = bookingId;

    if (!_joinedRooms.contains(bookingId)) {
      _joinedRooms.add(bookingId);
    }

    if (connected && _userId != null) {
      emit("join-booking", {
        "bookingId": bookingId,
        "userId": _userId,
        "userType": "customer",
      });
      AppLogger.log.i("📡 [RIDE] Joined booking: $bookingId");
    } else {
      AppLogger.log.w(
        "⏳ [RIDE] Socket not connected yet, will auto-join after connect",
      );
    }
  }

  // ---------------------------------------------------------
  // Emit & Listen
  // ---------------------------------------------------------
  void onConnect(Function() callback) => _socket.onConnect((_) => callback());
  void onReconnect(Function() callback) =>
      _socket.onReconnect((_) => callback());
  void on(String event, Function(dynamic data) callback) {
    _callbacks[event] = callback;
    _socket?.on(event, callback);
  }

  void onAck(String event, Function(dynamic data, Function? ack) callback) {
    _callbacks[event] = (data) => callback(data, null);

    _socket.on(event, (dynamic incoming) {
      if (incoming is List && incoming.length == 2 && incoming[1] is Function) {
        final payload = incoming[0];
        final ackFn = incoming[1] as Function;
        callback(payload, ackFn);
      } else {
        callback(incoming, null);
      }
    });
  }
  void emitWithAck(String event, dynamic data, Function(dynamic)? ack) =>
      _socket.emitWithAck(event, data, ack: ack);
  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  void off(String event) {
    _callbacks.remove(event);
    _socket?.off(event);
  }

  // ---------------------------------------------------------
  // Clean up
  // ---------------------------------------------------------
  void dispose() {
    _socket?.dispose();
    _initialized = false;
    _userId = null;
    _bookingId = null;
    _callbacks.clear();
    _joinedRooms.clear();
  }
}

// import 'package:socket_io_client/socket_io_client.dart' as IO;
// import 'package:hopper/Core/Consents/app_logger.dart';
//
// class RideShareSocketService {
//   static final RideShareSocketService _instance =
//   RideShareSocketService._internal();
//   factory RideShareSocketService() => _instance;
//
//   late IO.Socket _socket;
//   bool _initialized = false;
//   bool get connected => _socket.connected;
//
//   // 🔹 Dynamic state storage
//   String? _userId;
//   final Map<String, String> _joinedRooms = {}; // bookingId -> driverId
//
//   RideShareSocketService._internal();
//
//   void initSocket(String url) {
//     if (_initialized) {
//       if (_socket.disconnected) _socket.connect();
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
//           .setReconnectionAttempts(10)
//           .setReconnectionDelay(2000)
//           .build(),
//     );
//
//     _socket.connect();
//
//     _socket.onConnect((_) {
//       AppLogger.log.i("✅ [RIDE-SHARE] Connected to $url");
//
//       // Re-register user dynamically
//       if (_userId != null) registerUser(_userId!);
//
//       // Re-join all previous rooms
//       _joinedRooms.forEach((bookingId, driverId) {
//         joinBooking(bookingId: bookingId, driverId: driverId);
//       });
//     });
//
//     _socket.onDisconnect(
//           (_) => AppLogger.log.e("❌ [RIDE-SHARE] Disconnected from $url"),
//     );
//     _socket.onConnectError(
//           (err) => AppLogger.log.e("❗ [RIDE-SHARE] Connect error: $err"),
//     );
//     _socket.onReconnectAttempt(
//           (attempt) =>
//           AppLogger.log.w("🔁 [RIDE-SHARE] Reconnect attempt #$attempt"),
//     );
//     _socket.onError(
//           (err) => AppLogger.log.e("❗ [RIDE-SHARE] General socket error: $err"),
//     );
//     _socket.onAny(
//           (event, data) =>
//           AppLogger.log.i("📦 [RIDE-SHARE] Event: $event, Data: $data"),
//     );
//   }
//
//
//   void registerUser(String userId) {
//     _userId = userId;
//
//     // TODO: change 'type' if backend expects different for ride-share
//     emit('register', {
//       'userId': userId,
//       'type': 'customer-shared',
//     });
//   }
//
//   // 🔹 Join a booking / tracking dynamically
//   void joinBooking({required String bookingId, required String driverId}) {
//     _joinedRooms[bookingId] = driverId;
//
//     // TODO: if your backend uses different event names for shared:
//     // emit('join-shared-booking', {'bookingId': bookingId});
//     // emit('track-shared-driver', {'driverId': driverId});
//     emit('join-booking', {'bookingId': bookingId});
//     emit('track-driver', {'driverId': driverId});
//   }
//
//   // 🔹 Leave booking
//   void leaveBooking(String bookingId) {
//     if (_joinedRooms.containsKey(bookingId)) {
//       // TODO: change to 'leave-shared-booking' if needed
//       emit('leave-booking', {'bookingId': bookingId});
//       _joinedRooms.remove(bookingId);
//     }
//   }
//
//   // 🔹 Event handling
//   void onConnect(Function() callback) => _socket.onConnect((_) => callback());
//   void onReconnect(Function() callback) =>
//       _socket.onReconnect((_) => callback());
//   void on(String event, Function(dynamic) callback) =>
//       _socket.on(event, callback);
//   void emit(String event, dynamic data) => _socket.emit(event, data);
//   void emitWithAck(String event, dynamic data, Function(dynamic)? ack) =>
//       _socket.emitWithAck(event, data, ack: ack);
//   void off(String event) => _socket.off(event);
//
//   void dispose() {
//     _socket.dispose();
//     _initialized = false;
//     _joinedRooms.clear();
//     _userId = null;
//   }
// }
