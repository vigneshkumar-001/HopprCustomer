// import 'dart:async';
// import 'dart:convert';
// import 'dart:math' as math;
// import 'package:flutter/foundation.dart';
// import 'package:flutter/gestures.dart';
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:http/http.dart' as http;
//
// import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
// import 'package:hopper/Presentation/OnBoarding/Screens/home_screens.dart';
// import 'package:hopper/Core/Consents/app_colors.dart';
// import 'package:hopper/Core/Consents/app_logger.dart';
// import 'package:hopper/Core/Utility/app_buttons.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/api/repository/api_consents.dart';
// import 'package:hopper/uitls/websocket/socket_io_client.dart';
//
// class DummyScreen extends StatefulWidget {
//   final Map<String, dynamic> pickupData;
//   final Map<String, dynamic> destinationData;
//   final String pickupAddress;
//   final String destinationAddress;
//
//   const DummyScreen({
//     super.key,
//     required this.pickupData,
//     required this.destinationData,
//     required this.pickupAddress,
//     required this.destinationAddress,
//   });
//
//   @override
//   State<DummyScreen> createState() => _DummyScreenState();
// }
//
// class _DummyScreenState extends State<DummyScreen>
//     with AutomaticKeepAliveClientMixin {
//   @override
//   bool get wantKeepAlive => true;
//
//   final TextEditingController _startController = TextEditingController();
//   final TextEditingController _destController = TextEditingController();
//   final DriverSearchController driverSearchController = Get.put(
//     DriverSearchController(),
//   );
//   final socketService = SocketService();
//
//   GoogleMapController? _mapController;
//   LatLng? _currentPosition;
//   LatLng? _customerLatLng;
//   LatLng? _customerToLatLng;
//   LatLng? _currentDriverLatLng;
//
//   Marker? _driverMarker;
//   Set<Marker> _markers = {};
//   Set<Polyline> _polylines = {};
//   BitmapDescriptor? _carIcon;
//
//   Timer? _autoFollowTimer;
//   bool _autoFollowEnabled = true;
//   bool _userInteractingWithMap = false;
//   bool _isDrawingPolyline = false;
//
//   bool isDriverConfirmed = false;
//   bool driverStartedRide = false;
//   bool destinationReached = false;
//
//   String bookingId = '';
//   String plateNumber = '';
//   String driverName = '';
//   String carDetails = '';
//   String CUSTOMERPHONE = '';
//   String CARTYPE = '';
//   String otp = '';
//   int Amount = 0;
//
//   final double _zoomThreshold = 0.01;
//
//   // Kalman filter variables
//   double? _lastLat;
//   double? _lastLng;
//   double _latError = 1;
//   double _lngError = 1;
//   final double _processNoise = 0.00001; // small value
//   final double _measurementNoise = 0.0001;
//
//   @override
//   void initState() {
//     super.initState();
//     _startController.text = widget.pickupAddress;
//     _destController.text = widget.destinationAddress;
//     _loadCustomMarker();
//     _initLocation();
//     _setupSocketListeners();
//   }
//
//   Future<void> _loadCustomMarker() async {
//     _carIcon = await BitmapDescriptor.asset(
//       height: 60,
//       ImageConfiguration(size: Size(52, 52)),
//       AppImages.carHop,
//     );
//   }
//
//   Future<void> _initLocation() async {
//     Position position = await Geolocator.getCurrentPosition();
//     _currentPosition = LatLng(position.latitude, position.longitude);
//     _lastLat = position.latitude;
//     _lastLng = position.longitude;
//     setState(() {});
//   }
//
//   void _goToCurrentLocation() async {
//     Position position = await Geolocator.getCurrentPosition(
//       desiredAccuracy: LocationAccuracy.high,
//     );
//     final latLng = LatLng(position.latitude, position.longitude);
//     _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 17));
//   }
//
//   void _setupSocketListeners() {
//     socketService.onConnect(() {
//       AppLogger.log.i("✅ Socket connected on booking screen");
//     });
//
//     socketService.on('joined-booking', (data) {
//       if (!mounted) return;
//       AppLogger.log.i("🚕 Joined booking data: $data");
//       final vehicle = data['vehicle'] ?? {};
//       final String driverId = data['driverId'] ?? '';
//       final String driverFullName = data['driverName'] ?? '';
//       final String customerPhone = data['customerPhone'].toString() ?? '';
//       final double rating =
//           double.tryParse(data['driverRating'].toString()) ?? 0.0;
//       final String color = vehicle['color'] ?? '';
//       final String model = vehicle['model'] ?? '';
//       final String brand = vehicle['brand'] ?? '';
//       final String carType = vehicle['carType'] ?? '';
//       final bool driverAccepted = data['driver_accept_status'] == true;
//       final String type = vehicle['type'] ?? '';
//       final String plate = vehicle['plateNumber'] ?? '';
//       final customerLoc = data['customerLocation'];
//       final amount = data['amount'];
//
//       _customerLatLng = LatLng(
//         customerLoc['fromLatitude'],
//         customerLoc['fromLongitude'],
//       );
//       _customerToLatLng = LatLng(
//         customerLoc['toLatitude'],
//         customerLoc['toLongitude'],
//       );
//
//       setState(() {
//         plateNumber = plate;
//         driverName = '$driverFullName ⭐ $rating';
//         carDetails = '$color - $brand';
//         isDriverConfirmed = driverAccepted;
//         CUSTOMERPHONE = customerPhone;
//         CARTYPE = carType;
//         Amount = amount;
//       });
//
//       AppLogger.log.i("🚕 Joined booking data: $data");
//       AppLogger.log.i("🚕 driverAccepted ==  $driverAccepted");
//
//       // Start real-time tracking
//       if (driverId.trim().isNotEmpty) {
//         AppLogger.log.i("📍 Tracking driver: $driverId");
//         socketService.emit('track-driver', {'driverId': driverId.trim()});
//       }
//     });
//
//     socketService.on('driver-location', (data) {
//       _handleDriverLocation(data);
//     });
//
//     socketService.on('ride-started', (data) {
//       _handleRideStarted(data);
//     });
//
//     socketService.on('driver-reached-destination', (data) {
//       _handleDestinationReached(data);
//     });
//
//     socketService.on('customer-cancelled', (data) {
//       if (data?['status'] == true) Get.offAll(() => HomeScreens());
//     });
//
//     socketService.on('driver-cancelled', (data) {
//       if (data?['status'] == true) Get.offAll(() => HomeScreens());
//     });
//
//     socketService.on('otp-generated', (data) {
//       if (!mounted) return;
//       setState(() => otp = data['otpCode']);
//     });
//   }
//
//   void _handleDriverLocation(dynamic data) {
//     double lat = data['latitude'];
//     double lng = data['longitude'];
//
//     // Apply Kalman filter
//     if (_lastLat != null && _lastLng != null) {
//       _latError += _processNoise;
//       _lngError += _processNoise;
//
//       double kalmanGainLat = _latError / (_latError + _measurementNoise);
//       double kalmanGainLng = _lngError / (_lngError + _measurementNoise);
//
//       lat = _lastLat! + kalmanGainLat * (lat - _lastLat!);
//       lng = _lastLng! + kalmanGainLng * (lng - _lastLng!);
//
//       _latError = (1 - kalmanGainLat) * _latError;
//       _lngError = (1 - kalmanGainLng) * _lngError;
//     }
//
//     _lastLat = lat;
//     _lastLng = lng;
//
//     final newDriverLatLng = LatLng(lat, lng);
//
//     if (_currentDriverLatLng == null) {
//       _currentDriverLatLng = newDriverLatLng;
//       _updateDriverMarker(newDriverLatLng, 0);
//       return;
//     }
//
//     _animateCarTo(_currentDriverLatLng!, newDriverLatLng);
//
//     if (!driverStartedRide && _customerLatLng != null) {
//       _drawPolylineFromDriverToCustomer(
//         driverLatLng: newDriverLatLng,
//         customerLatLng: _customerLatLng!,
//       );
//     } else if (driverStartedRide && _customerToLatLng != null) {
//       _drawPolylineFromDriverToCustomer(
//         driverLatLng: newDriverLatLng,
//         customerLatLng: _customerToLatLng!,
//       );
//     }
//
//     _currentDriverLatLng = newDriverLatLng;
//   }
//
//   void _handleRideStarted(dynamic data) {
//     driverStartedRide = data['status'] == true;
//     if (!mounted) return;
//     setState(() {});
//
//     if (driverStartedRide &&
//         _currentDriverLatLng != null &&
//         _customerToLatLng != null) {
//       final dropMarker = Marker(
//         markerId: const MarkerId("drop_marker"),
//         position: _customerToLatLng!,
//         icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
//         infoWindow: const InfoWindow(title: "Destination"),
//       );
//       setState(() {
//         _markers = {if (_driverMarker != null) _driverMarker!, dropMarker};
//       });
//       _drawPolylineFromDriverToCustomer(
//         driverLatLng: _currentDriverLatLng!,
//         customerLatLng: _customerToLatLng!,
//       );
//     }
//   }
//
//   void _handleDestinationReached(dynamic data) {
//     final status = data['status'];
//     if (status == true) {
//       if (!mounted) return;
//       setState(() => destinationReached = true);
//     }
//   }
//
//   void _updateDriverMarker(LatLng position, double bearing) {
//     _driverMarker = Marker(
//       markerId: const MarkerId("driver_marker"),
//       position: position,
//       rotation: bearing,
//       icon:
//           _carIcon ??
//           BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
//       anchor: const Offset(0.5, 0.5),
//       flat: true,
//     );
//
//     if (!mounted) return;
//     setState(() {
//       _markers = {
//         ..._markers.where((m) => m.markerId != const MarkerId("driver_marker")),
//         _driverMarker!,
//       };
//     });
//   }
//
//   Future<void> _animateCarTo(LatLng from, LatLng to) async {
//     const steps = 10;
//     const duration = Duration(milliseconds: 800);
//     final interval = duration.inMilliseconds ~/ steps;
//
//     double currentBearing = _driverMarker?.rotation ?? 0;
//
//     for (int i = 1; i <= steps; i++) {
//       await Future.delayed(Duration(milliseconds: interval));
//
//       final lat = _lerp(from.latitude, to.latitude, i / steps);
//       final lng = _lerp(from.longitude, to.longitude, i / steps);
//       final intermediate = LatLng(lat, lng);
//       double newBearing = _getBearing(from, intermediate);
//
//       if ((newBearing - currentBearing).abs() > 10) {
//         currentBearing = newBearing;
//       }
//
//       _updateDriverMarker(intermediate, currentBearing);
//
//       if (_autoFollowEnabled) {
//         final zoom = await _mapController?.getZoomLevel() ?? 17;
//         _mapController?.animateCamera(
//           CameraUpdate.newCameraPosition(
//             CameraPosition(
//               target: intermediate,
//               zoom: zoom,
//               tilt: 45,
//               bearing: currentBearing,
//             ),
//           ),
//         );
//       }
//     }
//
//     _currentDriverLatLng = to;
//   }
//
//   double _getBearing(LatLng start, LatLng end) {
//     final lat1 = start.latitude * math.pi / 180;
//     final lon1 = start.longitude * math.pi / 180;
//     final lat2 = end.latitude * math.pi / 180;
//     final lon2 = end.longitude * math.pi / 180;
//     final dLon = lon2 - lon1;
//     final y = math.sin(dLon) * math.cos(lat2);
//     final x =
//         math.cos(lat1) * math.sin(lat2) -
//         math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
//     final bearing = math.atan2(y, x);
//     return (bearing * 180 / math.pi + 360) % 360;
//   }
//
//   double _lerp(double start, double end, double t) => start + (end - start) * t;
//
//   Future<void> _drawPolylineFromDriverToCustomer({
//     required LatLng driverLatLng,
//     required LatLng customerLatLng,
//   }) async {
//     if (_isDrawingPolyline) return;
//     _isDrawingPolyline = true;
//
//     String apiKey = ApiConsents.googleMapApiKey;
//     final url =
//         'https://maps.googleapis.com/maps/api/directions/json?origin=${driverLatLng.latitude},${driverLatLng.longitude}&destination=${customerLatLng.latitude},${customerLatLng.longitude}&key=$apiKey';
//     final response = await http.get(Uri.parse(url));
//     final data = json.decode(response.body);
//
//     if (!mounted) return;
//
//     if (data['status'] == 'OK') {
//       final encoded = data['routes'][0]['overview_polyline']['points'];
//       final points = _decodePolyline(encoded);
//       setState(() {
//         _polylines = {
//           Polyline(
//             polylineId: PolylineId(
//               driverStartedRide ? "driver_to_drop" : "driver_to_pickup",
//             ),
//             points: points,
//             color: Colors.black,
//             width: 4,
//           ),
//         };
//       });
//     }
//
//     _isDrawingPolyline = false;
//   }
//
//   List<LatLng> _decodePolyline(String encoded) {
//     List<LatLng> points = [];
//     int index = 0, lat = 0, lng = 0;
//
//     while (index < encoded.length) {
//       int shift = 0, result = 0, b;
//       do {
//         b = encoded.codeUnitAt(index++) - 63;
//         result |= (b & 0x1f) << shift;
//         shift += 5;
//       } while (b >= 0x20);
//       int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
//       lat += dlat;
//
//       shift = 0;
//       result = 0;
//       do {
//         b = encoded.codeUnitAt(index++) - 63;
//         result |= (b & 0x1f) << shift;
//         shift += 5;
//       } while (b >= 0x20);
//       int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
//       lng += dlng;
//
//       points.add(LatLng(lat / 1E5, lng / 1E5));
//     }
//
//     return points;
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     super.build(context);
//     return Scaffold(
//       body: Stack(
//         children: [
//           _buildGoogleMap(),
//           _buildCurrentLocationButton(),
//           _buildDraggableSheet(),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildGoogleMap() {
//     return SizedBox(
//       height: 550,
//       width: double.infinity,
//       child: GoogleMap(
//         initialCameraPosition: CameraPosition(
//           target: _currentPosition ?? LatLng(9.9144908, 78.0970899),
//           zoom: 16,
//         ),
//         markers: _markers,
//         polylines: _polylines,
//         myLocationEnabled: true,
//         myLocationButtonEnabled: false,
//         zoomControlsEnabled: false,
//         onMapCreated: (controller) async {
//           _mapController = controller;
//           String style = await DefaultAssetBundle.of(
//             context,
//           ).loadString('assets/map_style/map_style1.json');
//           _mapController?.setMapStyle(style);
//         },
//         onCameraMoveStarted: () {
//           _userInteractingWithMap = true;
//           _autoFollowEnabled = false;
//           _autoFollowTimer?.cancel();
//           _autoFollowTimer = Timer(const Duration(seconds: 10), () {
//             _autoFollowEnabled = true;
//             _userInteractingWithMap = false;
//           });
//         },
//         gestureRecognizers: {
//           Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
//         },
//       ),
//     );
//   }
//
//   Widget _buildCurrentLocationButton() {
//     return Positioned(
//       top: 350,
//       right: 10,
//       child: FloatingActionButton(
//         mini: true,
//         backgroundColor: Colors.white,
//         onPressed: _goToCurrentLocation,
//         child: Icon(Icons.my_location, color: Colors.black),
//       ),
//     );
//   }
//
//   Widget _buildDraggableSheet() {
//     return DraggableScrollableSheet(
//       key: ValueKey(isDriverConfirmed),
//       initialChildSize: isDriverConfirmed ? 0.65 : 0.5,
//       minChildSize: 0.4,
//       maxChildSize: isDriverConfirmed ? 0.9 : 0.75,
//       builder: (context, scrollController) {
//         return Container(
//           padding: const EdgeInsets.symmetric(horizontal: 15),
//           decoration: const BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//           ),
//           child: ListView(
//             controller: scrollController,
//             children: [
//               Center(
//                 child: Container(
//                   width: 40,
//                   height: 4,
//                   margin: const EdgeInsets.only(top: 8),
//                   decoration: BoxDecoration(
//                     color: Colors.grey[400],
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 12),
//               if (!isDriverConfirmed)
//                 ..._buildSearchingUI()
//               else
//                 ..._buildConfirmedUI(),
//             ],
//           ),
//         );
//       },
//     );
//   }
//
//   List<Widget> _buildSearchingUI() {
//     return [
//       const Text(
//         textAlign: TextAlign.center,
//         'Looking for the best drivers for you',
//         style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//       ),
//       const SizedBox(height: 12),
//       LinearProgressIndicator(
//         borderRadius: BorderRadius.circular(10),
//         minHeight: 7,
//         backgroundColor: AppColors.linearIndicatorColor.withOpacity(0.2),
//         color: AppColors.linearIndicatorColor,
//       ),
//       const SizedBox(height: 20),
//       Image.asset(AppImages.confirmCar, height: 100, width: 100),
//       const SizedBox(height: 20),
//       Obx(() {
//         final loading = driverSearchController.isLoading.value;
//
//         return AppButtons.button(
//           size: 350,
//           hasBorder: true,
//           borderColor: AppColors.commonBlack.withOpacity(0.2),
//           buttonColor: AppColors.commonWhite,
//           textColor: AppColors.cancelRideColor,
//
//           // disable while loading
//           onTap:
//               loading
//                   ? null
//                   : () {
//                     AppButtons.showCancelRideBottomSheet(
//                       context,
//                       onConfirmCancel: (String selectedReason) {
//                         driverSearchController.cancelRide(
//                           bookingId:
//                               driverSearchController
//                                   .carBooking
//                                   .value!
//                                   .bookingId,
//                           selectedReason: selectedReason,
//                           context: context,
//                         );
//                       },
//                     );
//                   },
//           isLoading: driverSearchController.isLoading.value,
//           // show loader instead of text
//           text: 'Cancel Ride',
//         );
//       }),
//       // AppButtons.button(
//       //   hasBorder: true,
//       //   borderColor: AppColors.commonBlack.withOpacity(0.2),
//       //   buttonColor: AppColors.commonWhite,
//       //   textColor: AppColors.cancelRideColor,
//       //   onTap: () {
//       //     AppButtons.showCancelRideBottomSheet(
//       //       context,
//       //       onConfirmCancel: (selectedReason) {
//       //         driverSearchController.cancelRide(
//       //           bookingId: driverSearchController.carBooking.value!.bookingId,
//       //           selectedReason: selectedReason,
//       //           context: context,
//       //         );
//       //       },
//       //     );
//       //   },
//       //   text: 'Cancel Ride',
//       // ),
//     ];
//   }
//
//   List<Widget> _buildConfirmedUI() {
//     return [
//       Text(
//         'Your driver ${driverName.split(' ')[0]} is on the way',
//         style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//       ),
//       const SizedBox(height: 12),
//       Row(
//         children: [
//           Image.asset(AppImages.confirmCar, height: 60, width: 60),
//           const SizedBox(width: 12),
//           Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(carDetails),
//               Text('Plate Number: $plateNumber'),
//               Text('Car Type: $CARTYPE'),
//               Text('OTP: $otp'),
//             ],
//           ),
//         ],
//       ),
//       const SizedBox(height: 20),
//       AppButtons.button(onTap: () => {}, text: 'Call Driver'),
//     ];
//   }
//
//   @override
//   void dispose() {
//     _mapController?.dispose();
//     _autoFollowTimer?.cancel();
//     socketService.dispose();
//     super.dispose();
//   }
// }
