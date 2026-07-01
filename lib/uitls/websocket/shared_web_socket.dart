import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:hopper/Core/Consents/app_logger.dart';

class RideShareSocketService {
  static final RideShareSocketService _instance =
      RideShareSocketService._internal();
  factory RideShareSocketService() => _instance;

  RideShareSocketService._internal();

  IO.Socket? _socket;
  bool _initialized = false;

  String? _userId;
  String? _bookingId;
  String? _authToken; // optional JWT for the handshake (gated backend auth)

  // track rooms so we can rejoin on reconnect
  final List<String> _joinedRooms = [];
  List<String> get joinedRooms => _joinedRooms;

  // track shared-ride rooms separately so reconnect restores ALL shared legs
  final List<String> _sharedRideRooms = [];

  /// Set/clear the JWT used for the socket handshake. Safe to call before
  /// initSocket; when set, identity can be verified server-side once
  /// SOCKET_REQUIRE_AUTH is enabled. No effect on the current (unauthenticated)
  /// flow until the backend flag is flipped.
  void setAuthToken(String? token) {
    _authToken = token;
  }

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

    // Transport + reconnect parity with the (already-hardened) single-ride
    // SocketService: websocket-ONLY stalls the live feed and freezes the car
    // marker on flaky mobile networks where the WS upgrade is blocked, and
    // giving up after 10 attempts kills tracking mid-ride. Allow polling
    // fallback and effectively-unlimited reconnection with capped backoff.
    final optionBuilder = IO.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .enableAutoConnect()
        .enableReconnection()
        .setReconnectionDelay(2000)
        .setReconnectionDelayMax(10000)
        .setReconnectionAttempts(1 << 30)
        .setTimeout(20000);
    if (_authToken != null && _authToken!.isNotEmpty) {
      optionBuilder.setAuth({'token': _authToken, 'type': 'customer'});
    }

    _socket = IO.io(url, optionBuilder.build());

    _socket!.connect();

    _socket!.onConnect((_) {
      AppLogger.log.i("✅ [RIDE] Connected → $url");

      // restore identity (with booking if available)
      if (_userId != null) {
        registerUser(_userId!, bookingId: _bookingId);
      }

      // restore all booking rooms
      for (final room in _joinedRooms) {
        AppLogger.log.i("📡 [RIDE] Rejoining room: $room");
        emit("join-booking", {
          "bookingId": room,
          "userId": _userId,
          "userType": "customer",
        });
      }

      // restore ALL shared-ride rooms (so a reconnect doesn't lose tracking on
      // a multi-leg pooled ride).
      for (final sharedRideId in _sharedRideRooms) {
        AppLogger.log.i("📡 [RIDE] Rejoining shared ride: $sharedRideId");
        emit("customer:sharedRide:join", {
          "sharedRideId": sharedRideId,
          "userId": _userId,
          "customerId": _userId,
        });
      }

      // rebind all event listeners
      _callbacks.forEach((event, cb) {
        _socket?.off(event);
        _socket?.on(event, cb);
      });

      // C7: invoke the single STORED external connect callback (set via
      // onConnect()) — never re-registered, so it can't stack on reconnect.
      _externalConnectCb?.call();

      AppLogger.log.i("🔄 [RIDE] Listeners rebound, rooms rejoined");
    });
    _socket?.onError((err) => AppLogger.log.e("❗ General socket error: $err"));

    _socket!.onDisconnect((_) {
      AppLogger.log.e("❌ [RIDE] Disconnected from $url");
    });
    // C7: one internal reconnect handler fans out to the stored external one.
    _socket?.onReconnect((_) => _externalReconnectCb?.call());
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
  // Shared-ride room (Phase 3 backend rooms). Tracks the id so reconnect
  // restores it. Safe to call once the shared ride / sharedId is known.
  // ---------------------------------------------------------
  void joinSharedRide(String sharedRideId) {
    if (sharedRideId.isEmpty) return;
    if (!_sharedRideRooms.contains(sharedRideId)) {
      _sharedRideRooms.add(sharedRideId);
    }
    if (connected && _userId != null) {
      emit("customer:sharedRide:join", {
        "sharedRideId": sharedRideId,
        "userId": _userId,
        "customerId": _userId,
      });
      AppLogger.log.i("📡 [RIDE] Joined shared ride: $sharedRideId");
    }
  }

  // ---------------------------------------------------------
  // Emit & Listen
  // ---------------------------------------------------------
  // C7: external connect/reconnect callbacks are STORED (single slot each) and
  // fanned out from the internal handlers in initSocket — never re-registered on
  // the socket, so reconnect / screen reopen / controller recreate can't stack them.
  Function()? _externalConnectCb;
  Function()? _externalReconnectCb;

  void onConnect(Function() callback) => _externalConnectCb = callback;
  void onReconnect(Function() callback) => _externalReconnectCb = callback;
  void on(String event, Function(dynamic data) callback) {
    // Unwrap a leading Map when the backend emits extra trailing args
    // (socket.io then delivers the whole emit as a List [payload, id, ...]).
    // No-op when the payload is already a Map. Store the wrapped handler so
    // reconnect re-attach (via _callbacks) keeps the same normalization.
    void wrapped(dynamic data) {
      var payload = data;
      if (payload is List && payload.isNotEmpty && payload.first is Map) {
        payload = payload.first;
      }
      callback(payload);
    }

    _callbacks[event] = wrapped;
    // C7: off-before-on so re-registering the same event REPLACES the live
    // listener instead of stacking another one (matches the reconnect rebind).
    _socket?.off(event);
    _socket?.on(event, wrapped);
  }

  void onAck(String event, Function(dynamic data, Function? ack) callback) {
    // socket.io (socket_io_client) delivers an event to the handler in two
    // shapes depending on how the backend emitted it:
    //   * single payload arg          -> handler receives the payload directly
    //   * payload + extra/ack args     -> handler receives the WHOLE List
    //                                     [payload, ...trailingArgs, maybeAck]
    // The ack callback (when present) is always the LAST element and is a
    // Function. The real payload is the FIRST element; any middle args (e.g. a
    // trailing id) are ignored, matching `on()`'s normalization. Without this,
    // a trailing-arg emit (no ack) leaks the raw List into the handler and
    // `data['latitude']` throws "String is not a subtype of int of 'index'".
    void wrapped(dynamic incoming) {
      dynamic payload = incoming;
      Function? ackFn;

      if (incoming is List) {
        final args = List<dynamic>.from(incoming);
        if (args.isNotEmpty && args.last is Function) {
          ackFn = args.removeLast() as Function;
        }
        payload = args.isNotEmpty ? args.first : null;
      }

      callback(payload, ackFn);
    }

    // Store the SAME wrapped handler so reconnect re-attach (in onConnect)
    // preserves normalization and the ack instead of dropping them.
    _callbacks[event] = wrapped;
    // C7: off-before-on so re-registering this event REPLACES the live listener.
    _socket?.off(event);
    _socket?.on(event, wrapped);
  }
  void emitWithAck(String event, dynamic data, Function(dynamic)? ack) =>
      _socket?.emitWithAck(event, data, ack: ack);
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
    _socket = null;
    _initialized = false;
    _userId = null;
    _bookingId = null;
    _callbacks.clear();
    _joinedRooms.clear();
    _sharedRideRooms.clear();
    _authToken = null;
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
