// import 'dart:async';
// import 'package:hopper/Core/Consents/app_logger.dart';
// import 'dart:convert';
// import 'dart:math';
// import 'dart:ui';
//
// import 'package:flutter/foundation.dart';
// import 'package:flutter/gestures.dart';
// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:http/http.dart' as http;
//
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/api/repository/api_consents.dart';
// import 'package:hopper/uitls/websocket/socket_io_client.dart';
//
// class Dummy2 extends StatefulWidget {
//   const Dummy2({super.key});
//
//   @override
//   State<Dummy2> createState() => _Dummy2State();
// }
//
// class _Dummy2State extends State<Dummy2> {
//   GoogleMapController? _mapController;
//   final socketService = SocketService();
//
//   LatLng? _currentDriverLatLng;
//   LatLng? _customerLatLng;
//   LatLng? _customerToLatLng;
//
//   BitmapDescriptor? _carIcon;
//   Marker? _driverMarker;
//
//   Set<Polyline> _polylines = {};
//   Set<Marker> _markers = {};
//
//   bool driverStartedRide = false;
//   bool _isDrawingPolyline = false;
//   bool _autoFollowEnabled = true;
//
//   Timer? _autoFollowTimer;
//   bool _userInteractingWithMap = false;
//
//   // ===== Dummy Route (Kalavasal → Othakkadai) =====
//   final LatLng _startPoint = const LatLng(9.9196, 78.0959);
//   final LatLng _endPoint = const LatLng(9.9583, 78.1472);
//   int _currentStep = 0;
//   final int _totalSteps = 50; // more = smoother path
//
//   @override
//   void initState() {
//     super.initState();
//     _loadCustomMarker();
//     initSocket();
//   }
//
//   @override
//   void dispose() {
//     _mapController?.dispose();
//     _autoFollowTimer?.cancel();
//     super.dispose();
//   }
//
//   Future<void> _loadCustomMarker() async {
//     _carIcon = await BitmapDescriptor.asset(
//       ImageConfiguration(size: const Size(60, 60)),
//       AppImages.packageBike,
//     );
//   }
//
//   void initSocket() {
//     socketService.onConnect(() {
//       AppLogger.log.i("✅ Socket connected on booking screen");
//     });
//
//     // listen for events here when real API is ready
//   }
//
//   // ================================
//   // 🚖 DRIVER MARKER UPDATES
//   // ================================
//   Future<void> _animateCarTo(LatLng newLatLng) async {
//     if (_currentDriverLatLng == null) {
//       _currentDriverLatLng = newLatLng;
//
//       final firstMarker = Marker(
//         markerId: const MarkerId("driver"),
//         position: newLatLng,
//         rotation: 0,
//         anchor: const Offset(0.5, 0.5),
//         flat: true,
//         icon: _carIcon ?? BitmapDescriptor.defaultMarker,
//       );
//
//       setState(() {
//         _markers.add(firstMarker);
//         _driverMarker = firstMarker;
//       });
//
//       if (_mapController != null) {
//         _mapController!.animateCamera(
//           CameraUpdate.newCameraPosition(
//             CameraPosition(target: newLatLng, zoom: 16, tilt: 60),
//           ),
//         );
//       }
//       return;
//     }
//
//     final oldLatLng = _currentDriverLatLng!;
//     final bearing = _getBearing(oldLatLng, newLatLng);
//
//     final updatedMarker = Marker(
//       markerId: const MarkerId("driver"),
//       position: newLatLng,
//       rotation: bearing,
//       anchor: const Offset(0.5, 0.5),
//       flat: true,
//       icon: _carIcon ?? BitmapDescriptor.defaultMarker,
//     );
//
//     setState(() {
//       _markers.removeWhere((m) => m.markerId.value == "driver");
//       _markers.add(updatedMarker);
//       _driverMarker = updatedMarker;
//     });
//
//     if (_autoFollowEnabled && _mapController != null) {
//       await _mapController!.animateCamera(
//         CameraUpdate.newCameraPosition(
//           CameraPosition(
//             target: newLatLng,
//             zoom: 16,
//             tilt: 60,
//             bearing: bearing,
//           ),
//         ),
//       );
//     }
//
//     _currentDriverLatLng = newLatLng;
//   }
//
//   double _getBearing(LatLng start, LatLng end) {
//     double lat1 = start.latitude * (pi / 180.0);
//     double lon1 = start.longitude * (pi / 180.0);
//     double lat2 = end.latitude * (pi / 180.0);
//     double lon2 = end.longitude * (pi / 180.0);
//
//     double dLon = lon2 - lon1;
//     double y = sin(dLon) * cos(lat2);
//     double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
//     double bearing = atan2(y, x);
//     bearing = bearing * (180 / pi);
//     return (bearing + 360) % 360;
//   }
//
//   // ===== Dummy movement helper =====
//   LatLng _getNextDummyPoint() {
//     final t = _currentStep / _totalSteps;
//     final lat =
//         _startPoint.latitude + t * (_endPoint.latitude - _startPoint.latitude);
//     final lng =
//         _startPoint.longitude +
//         t * (_endPoint.longitude - _startPoint.longitude);
//     return LatLng(lat, lng);
//   }
//
//   // ================================
//   // 📍 UI
//   // ================================
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Stack(
//         children: [
//           GoogleMap(
//             initialCameraPosition: CameraPosition(
//               target: _startPoint,
//               zoom: 14,
//             ),
//             markers: _markers,
//             polylines: _polylines,
//             myLocationEnabled: true,
//             myLocationButtonEnabled: false,
//             zoomControlsEnabled: true,
//             onMapCreated: (controller) async {
//               _mapController = controller;
//             },
//             onCameraMoveStarted: () {
//               _userInteractingWithMap = true;
//               _autoFollowEnabled = false;
//
//               _autoFollowTimer?.cancel();
//               _autoFollowTimer = Timer(const Duration(seconds: 10), () {
//                 _autoFollowEnabled = true;
//                 _userInteractingWithMap = false;
//               });
//             },
//             gestureRecognizers: {
//               Factory<OneSequenceGestureRecognizer>(
//                 () => EagerGestureRecognizer(),
//               ),
//             },
//           ),
//         ],
//       ),
//       // 👇 Dummy test button (moves car along route)
//       floatingActionButton: FloatingActionButton(
//         child: const Icon(Icons.directions_car),
//         onPressed: () {
//           if (_currentStep <= _totalSteps) {
//             final next = _getNextDummyPoint();
//             _animateCarTo(next);
//             _currentStep++;
//           }
//         },
//       ),
//     );
//   }
// }
