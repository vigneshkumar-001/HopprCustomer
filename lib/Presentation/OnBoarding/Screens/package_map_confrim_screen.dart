import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/chat_screen.dart';
import 'package:dotted_line/dotted_line.dart';
 
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/payment_screen.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/uitls/websocket/socket_io_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import '../../../api/repository/api_consents.dart';
import '../../BookRide/Controllers/driver_search_controller.dart';

class PackageMapConfirmScreen extends StatefulWidget {
  final String bookingId;
  final String discountCode;
  final AddressModel senderData;
  final AddressModel receiverData;
  const PackageMapConfirmScreen({
    super.key,
    required this.bookingId,
    required this.discountCode,
    required this.senderData,
    required this.receiverData,
  });

  @override
  State<PackageMapConfirmScreen> createState() =>
      _PackageMapConfirmScreenState();
}

class _PackageMapConfirmScreenState extends State<PackageMapConfirmScreen> {
  bool isExpanded = false;
  GoogleMapController? _mapController;
  final socketService = SocketService();
  LatLng? _currentPosition;
  Set<Polyline> _polylines = {};
  BitmapDescriptor? _carIcon;
  Set<Marker> _markers = {};
  bool _isDriverConfirmed = false;
  Marker? _driverMarker;
  bool driverStartedRide = false;
  bool destinationReached = false;
  bool _autoFollowEnabled = false;
  bool _isDrawingPolyline = false;
  LatLng? _customerLatLng;
  LatLng? _customerToLatLang;
  String plateNumber = '';
  String driverName = '';
  double driverRating = 0.0;
  String carDetails = '';
  String CUSTOMERPHONE = '';
  String CARTYPE = '';
  String ProfilePic = '';
  String BookingId = '';
  int? MaxWeight;
  double Amount = 0.0;
  String PickupAddress = '';
  String DropAddress = '';
  bool _isOrderConfirmed = false;
  bool _isEnRoute = false;
  bool _isPackagePickup = false;
  bool _isPackageCollected = false;
  bool _isInTransit = false;
  bool _isOutForDelivery = false;
  String _estimateStt1 = '';
  String _estimateStt2 = '';
  String otp = '';
  LatLng? _currentDriverLatLng;
  bool isTripCancelled = false;
  String cancelReason = "";

  Future<void> _loadCustomMarker() async {
    _carIcon = await BitmapDescriptor.asset(
      height: 60,
      ImageConfiguration(size: Size(52, 52)),
      AppImages.packageBike,
    );
  }

  final GlobalKey _senderKey = GlobalKey();
  final GlobalKey _receiverKey = GlobalKey();

  double lineHeight = 60;
  void _calculateLineHeight() {
    final senderBox =
        _senderKey.currentContext?.findRenderObject() as RenderBox?;
    final receiverBox =
        _receiverKey.currentContext?.findRenderObject() as RenderBox?;

    if (senderBox != null && receiverBox != null) {
      final senderPos = senderBox.localToGlobal(Offset.zero);
      final receiverPos = receiverBox.localToGlobal(Offset.zero);

      final calculatedHeight = receiverPos.dy - senderPos.dy - 30;
      setState(() {
        lineHeight = calculatedHeight > 0 ? calculatedHeight : 0;
      });
    }
  }

  Future<void> _initLocation() async {
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });
    AppLogger.log.i(_currentPosition);
  }

  void _goToCurrentLocation() async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    final latLng = LatLng(position.latitude, position.longitude);

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 17));
  }

  bool isWaitingForDriver = true;
  bool noDriverFound = false;
  void startDriverSearch() {
    isWaitingForDriver = true;
    noDriverFound = false;

    Future.delayed(Duration(minutes: 1), () async {
      if (!_isDriverConfirmed) {
        bool hasDriver = await driverSearchController.noDriverFound(
          context: context,
          bookingId: widget.bookingId,
          status: true,
        );

        setState(() {
          isWaitingForDriver = false;
          noDriverFound = !hasDriver;
        });
      }
    });
  }

  final PackageController packageController = Get.put(PackageController());
  @override
  void initState() {
    super.initState();
    _initLocation();
    _goToCurrentLocation();
    _loadCustomMarker();
    initSocket();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateLineHeight());
    startDriverSearch();
  }

  void initSocket() {
    socketService.onConnect(() {
      AppLogger.log.i("✅ Socket connected on booking screen");
    });

    socketService.on('joined-booking', (data) {
      if (!mounted) return;
      AppLogger.log.i("Package Joined booking data: $data");
      final vehicle = data['vehicle'] ?? {};
      final String driverId = data['driverId'] ?? '';
      final String driverFullName = data['driverName'] ?? '';
      final String customerPhone = data['customerPhone'].toString() ?? '';
      final double rating =
          double.tryParse(data['driverRating'].toString()) ?? 0.0;
      final String color = vehicle['color'] ?? '';
      final String model = vehicle['model'] ?? '';
      final String brand = vehicle['brand'] ?? '';
      final String carType = vehicle['carType'] ?? '';
      final bool driverAccepted = data['driver_accept_status'] == true;
      final String type = vehicle['type'] ?? '';
      final String plate = vehicle['plateNumber'] ?? '';
      final customerLoc = data['customerLocation'];
      final amount = data['amount'];
      final String profilePic = data['profilePic'];
      final String bookingId = data['bookingId'];
      final int maxWeight = data['maxWeight'];
      final String pickupAddress = data['pickupAddress'];
      final String dropAddress = data['dropAddress'];

      _customerLatLng = LatLng(
        customerLoc['fromLatitude'],
        customerLoc['fromLongitude'],
      );
      _customerToLatLang = LatLng(
        customerLoc['toLatitude'],
        customerLoc['toLongitude'],
      );

      setState(() {
        plateNumber = plate;
        driverName = '$driverFullName ⭐ $rating';
        carDetails = '$color - $brand';
        _isDriverConfirmed = driverAccepted;
        CUSTOMERPHONE = customerPhone;
        CARTYPE = carType;
        ProfilePic = profilePic;
        BookingId = bookingId;
        MaxWeight = maxWeight;
        PickupAddress = pickupAddress;
        DropAddress = dropAddress;
        Amount = amount;
      });

      AppLogger.log.i("🚕 Joined booking data: $data");
      AppLogger.log.i("🚕 driverAccepted ==  $driverAccepted");

      // Start real-time tracking
      if (driverId.trim().isNotEmpty) {
        AppLogger.log.i("📍 Tracking driver: $driverId");
        socketService.emit('track-driver', {'driverId': driverId.trim()});
      }
    });

    socketService.on('driver-location', (data) {
      AppLogger.log.i('📦 driver-location-updated: $data');

      final newDriverLatLng = LatLng(data['latitude'], data['longitude']);

      if (_currentDriverLatLng == null) {
        _currentDriverLatLng = newDriverLatLng;
        _updateDriverMarker(newDriverLatLng, 0);
        return;
      }

      // ✅ Animate movement
      _animateCarTo(_currentDriverLatLng!, newDriverLatLng);

      if (!driverStartedRide && _customerLatLng != null) {
        _drawPolylineFromDriverToCustomer(
          driverLatLng: newDriverLatLng,
          customerLatLng: _customerLatLng!,
        );
      }

      // ✅ CASE 2: After ride starts → Draw polyline to drop
      if (driverStartedRide && _customerToLatLang != null) {
        _drawPolylineFromDriverToCustomer(
          driverLatLng: newDriverLatLng,
          customerLatLng: _customerToLatLang!,
        );
      }

      // ✅ Update current driver position
      _currentDriverLatLng = newDriverLatLng;
      // 📦 Extract flags
      final basePayload = data['basePayload'] ?? {};
      final estimate = basePayload['getEstimateTime'] ?? {};
      if (!mounted) return;
      setState(() {
        _isOrderConfirmed = basePayload['orderConfirmationStatus'] ?? false;
        _isEnRoute = basePayload['enRoute'] ?? false;
        _isPackagePickup = basePayload['packagePickup'] ?? false;
        _isPackageCollected = basePayload['packageCollected'] ?? false;
        _isInTransit = basePayload['inTransit'] ?? false;
        _isOutForDelivery = basePayload['outForDelivery'] ?? false;
        _estimateStt1 = estimate['stt1'] ?? '';
        _estimateStt2 = estimate['stt2'] ?? '';
      });
    });

    socketService.on('driver-arrived', (data) {
      AppLogger.log.i("driver-arrived: $data");
    });

    socketService.on('otp-generated', (data) {
      if (!mounted) return;
      final otpGenerated = data['otpCode'];
      setState(() {
        otp = otpGenerated;
      });

      AppLogger.log.i("otp-generated: $data");
    });

    socketService.on('ride-started', (data) {
      final bool status = data['status'] == true;
      AppLogger.log.i("ride-started: $data");

      driverStartedRide = status; // don't wait for setState

      if (!mounted) return;
      setState(() {}); // only for UI like info card updates

      if (status &&
          _currentDriverLatLng != null &&
          _customerToLatLang != null) {
        final dropMarker = Marker(
          markerId: const MarkerId("drop_marker"),
          position: _customerToLatLang!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: "Destination"),
        );

        setState(() {
          _markers = {if (_driverMarker != null) _driverMarker!, dropMarker};
        });

        _drawPolylineFromDriverToCustomer(
          driverLatLng: _currentDriverLatLng!,
          customerLatLng: _customerToLatLang!,
        );
      }
    });
    socketService.on('driver-reached-destination', (data) {
      final String bookingId =
          driverSearchController.carBooking.value!.bookingId;
      final status = data['status'];
      final amount = data['amount'];
      if (status == true || status.toString() == 'status') {
        if (!mounted) return;
        setState(() {
          destinationReached = true;
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          Get.to(() => PaymentScreen(bookingId: bookingId, amount: Amount));
        });

        AppLogger.log.i("driver_reached,$data");
      }
    });
    socketService.on('customer-cancelled', (data) async {
      AppLogger.log.i('customer-cancelled : $data');

      if (data != null && data['status'] == true) {
        if (!mounted) return;

        setState(() {
          isTripCancelled = true;
          cancelReason =
              data['reason'] ?? "Driver had to cancel due to an emergency";
        });

        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        Get.offAll(() => CommonBottomNavigation(initialIndex: 0));
      }
    });
    socketService.on('driver-cancelled', (data) async {
      AppLogger.log.i('driver-cancelled : $data');

      if (data != null && data['status'] == true) {
        if (!mounted) return;

        setState(() {
          isTripCancelled = true;
          cancelReason =
              data['reason'] ?? "Driver had to cancel due to an emergency";
        });

        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        Get.offAll(() => CommonBottomNavigation(initialIndex: 0));
      }
    });
  }

  double _getBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * math.pi / 180;
    final lon1 = start.longitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final lon2 = end.longitude * math.pi / 180;

    final dLon = lon2 - lon1;

    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final bearing = math.atan2(y, x);
    return (bearing * 180 / math.pi + 360) % 360;
  }

  double _lerp(double start, double end, double t) {
    return start + (end - start) * t;
  }

  Future<void> _animateCarTo(LatLng from, LatLng to) async {
    const steps = 10;
    const duration = Duration(milliseconds: 800);
    final interval = duration.inMilliseconds ~/ steps;

    double currentBearing = _driverMarker?.rotation ?? 0;

    for (int i = 1; i <= steps; i++) {
      await Future.delayed(Duration(milliseconds: interval));

      final lat = _lerp(from.latitude, to.latitude, i / steps);
      final lng = _lerp(from.longitude, to.longitude, i / steps);
      final intermediate = LatLng(lat, lng);
      double newBearing = _getBearing(from, intermediate);

      if ((newBearing - currentBearing).abs() > 10) {
        currentBearing = newBearing;
      }

      _updateDriverMarker(intermediate, currentBearing);

      // ✅ Only auto-move camera if user is not interacting
      if (Geolocator.distanceBetween(
            _currentDriverLatLng!.latitude,
            _currentDriverLatLng!.longitude,
            intermediate.latitude,
            intermediate.longitude,
          ) >
          1) {
        _updateDriverMarker(intermediate, currentBearing);

        if (_autoFollowEnabled) {
          final zoom = await _mapController?.getZoomLevel() ?? 17;

          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: intermediate,
                zoom: zoom,
                tilt: 45, // optional
                bearing: currentBearing, // 👈 map rotates with car
              ),
            ),
          );
        }
      }
    }

    _currentDriverLatLng = to;

    if (driverStartedRide && _customerToLatLang != null) {
      await _drawPolylineFromDriverToCustomer(
        driverLatLng: to,
        customerLatLng: _customerToLatLang!,
      );
    } else if (!driverStartedRide && _customerLatLng != null) {
      await _drawPolylineFromDriverToCustomer(
        driverLatLng: to,
        customerLatLng: _customerLatLng!,
      );
    }
  }

  void _updateDriverMarker(LatLng position, double bearing) {
    _driverMarker = Marker(
      markerId: const MarkerId("driver_marker"),
      position: position,
      rotation: bearing,
      icon:
          _carIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      anchor: const Offset(0.5, 0.5),
      flat: true,
    );

    if (!mounted) return;
    setState(() {
      // 🟢 Remove old marker and add updated one
      _markers = {
        ..._markers.where((m) => m.markerId != const MarkerId("driver_marker")),
        _driverMarker!,
      };
    });
  }

  Future<void> _drawPolylineFromDriverToCustomer({
    required LatLng driverLatLng,
    required LatLng customerLatLng,
  }) async {
    if (_isDrawingPolyline) return; // prevent multiple calls
    _isDrawingPolyline = true;

    String apiKey = ApiConsents.googleMapApiKey;

    final url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=${driverLatLng.latitude},${driverLatLng.longitude}&destination=${customerLatLng.latitude},${customerLatLng.longitude}&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    final data = json.decode(response.body);
    if (!mounted) return;
    if (data['status'] == 'OK') {
      final encoded = data['routes'][0]['overview_polyline']['points'];
      final points = _decodePolyline(encoded);
      if (!mounted) return;
      setState(() {
        _polylines = {
          Polyline(
            polylineId: PolylineId(
              driverStartedRide ? "driver_to_drop" : "driver_to_pickup",
            ),
            points: points,
            color: Colors.black,
            width: 4,
          ),
        };
      });
    } else {
      print("❗ Error fetching directions: ${data['status']}");
    }
    _isDrawingPolyline = false;
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }

  final DriverSearchController driverSearchController = Get.put(
    DriverSearchController(),
  );
  bool _userInteractingWithMap = false;
  Timer? _autoFollowTimer;
  @override
  Widget build(BuildContext context) {
    return NoInternetOverlay(
      child: WillPopScope(
        onWillPop: () async {
          return await false;
        },
        child: Scaffold(
          body: Stack(
            children: [
              /* SizedBox(
                height: 550,
                width: double.infinity,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition ?? LatLng(9.9144908, 78.0970899),
                    zoom: 16,
                  ),
                  markers: _markers,
                  onMapCreated: (controller) async {
                    _mapController = controller;
                    String style = await DefaultAssetBundle.of(
                      context,
                    ).loadString('assets/map_style/map_style1.json');
                    _mapController?.setMapStyle(style);
                  },
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                ),
              ),*/
              SizedBox(
                height: 550,
                width: double.infinity,
                child: GoogleMap(
                  onCameraMoveStarted: () {
                    _userInteractingWithMap = true;
                    _autoFollowEnabled = false;

                    _autoFollowTimer?.cancel();

                    _autoFollowTimer = Timer(Duration(seconds: 10), () {
                      _autoFollowEnabled = true;
                      _userInteractingWithMap = false;
                    });
                  },

                  initialCameraPosition: CameraPosition(
                    target: _currentPosition ?? LatLng(9.9144908, 78.0970899),
                    zoom: 16,
                  ),
                  markers: _markers,
                  onMapCreated: (controller) async {
                    _mapController = controller;
                    String style = await DefaultAssetBundle.of(
                      context,
                    ).loadString('assets/map_style/map_style1.json');
                    _mapController?.setMapStyle(style);
                  },
                  polylines: _polylines,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                ),
              ),
              Positioned(
                top: 350,
                right: 10,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: _goToCurrentLocation,
                  child: Icon(Icons.my_location, color: Colors.black),
                ),
              ),
              Positioned(
                top: 50,
                right: 15,
                child: GestureDetector(
                  onTap: () async {
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      String? sosNumber = prefs.getString('sosNumber');

                      if (sosNumber == null || sosNumber.trim().isEmpty) {
                        AppToasts.showError('SOS number not set');
                        return;
                      }

                      // Keep leading + if present; remove spaces and other junk
                      sosNumber = sosNumber.trim();
                      final hasPlus = sosNumber.startsWith('+');
                      final digitsOnly = sosNumber.replaceAll(
                        RegExp(r'[^0-9]'),
                        '',
                      );
                      final normalized = hasPlus ? '+$digitsOnly' : digitsOnly;

                      if (normalized.isEmpty) {
                        AppToasts.showError('Invalid SOS number');
                        return;
                      }

                      final Uri telUri = Uri(scheme: 'tel', path: normalized);

                      // Try opening the dialer
                      final ok = await launchUrl(
                        telUri,
                        mode:
                            LaunchMode.externalApplication, // opens dialer app
                      );

                      if (!ok) {
                        AppToasts.showError('Could not open dialer');
                      }
                    } catch (e) {
                      AppToasts.showError('Failed to start call');
                    }
                  },

                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      color: AppColors.emergencyColor,
                    ),
                    child: CustomTextFields.textWithStyles600(
                      'Emergency',
                      color: AppColors.commonWhite,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

              // Positioned(
              //   top: 330,
              //   right: 10,
              //   child: Container(
              //     decoration: BoxDecoration(
              //       borderRadius: BorderRadius.circular(5),
              //       color: AppColors.commonWhite,
              //     ),
              //     child: Padding(
              //       padding: const EdgeInsets.all(5),
              //       child: Column(
              //         children: [
              //           CustomTextFields.textWithStyles600(
              //             '10:39',
              //             fontSize: 18,
              //             color: AppColors.walletCurrencyColor,
              //           ),
              //           CustomTextFields.textWithStylesSmall('minutes remaining'),
              //         ],
              //       ),
              //     ),
              //   ),
              // ),
              DraggableScrollableSheet(
                key: ValueKey(_isDriverConfirmed),

                initialChildSize: _isDriverConfirmed ? 0.55 : 0.4,
                minChildSize: 0.3,
                maxChildSize: _isDriverConfirmed ? 0.90 : 0.5,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(color: Colors.white),
                    child: SafeArea(
                      top: false,
                      child: ListView(
                        physics: BouncingScrollPhysics(),
                        controller: scrollController,
                        padding: EdgeInsets.only(top: 15),
                        children: [
                          SizedBox(height: 20),
                          if (!_isDriverConfirmed && isWaitingForDriver) ...[
                            // Text(
                            //   textAlign: TextAlign.center,
                            //   'Looking for the best drivers for you',
                            //   style: TextStyle(
                            //     fontSize: 18,
                            //     fontWeight: FontWeight.bold,
                            //   ),
                            // ),
                            // SizedBox(height: 12),
                            // LinearProgressIndicator(
                            //   borderRadius: BorderRadius.circular(10),
                            //   minHeight: 7,
                            //   backgroundColor: AppColors.linearIndicatorColor
                            //       .withOpacity(0.2),
                            //   color: AppColors.linearIndicatorColor,
                            // ),
                            // SizedBox(height: 20),
                            // Image.asset(
                            //   AppImages.confirmCar,
                            //   height: 100,
                            //   width: 100,
                            //   fit: BoxFit.contain,
                            // ),
                            // SizedBox(height: 20),
                            // Container(
                            //   decoration: BoxDecoration(
                            //     color: Colors.white,
                            //     borderRadius: BorderRadius.circular(12),
                            //     boxShadow: [
                            //       BoxShadow(
                            //         color: Colors.black12,
                            //         blurRadius: 8,
                            //         offset: Offset(0, 4),
                            //       ),
                            //     ],
                            //   ),
                            //   child: Column(
                            //     children: [
                            //       CustomTextFields.plainTextField(
                            //         readOnly: true,
                            //         Style: TextStyle(
                            //           fontSize: 12,
                            //           color: AppColors.commonBlack.withOpacity(0.6),
                            //           overflow: TextOverflow.ellipsis,
                            //         ),
                            //         controller: _startController,
                            //         containerColor: AppColors.commonWhite,
                            //         leadingImage: AppImages.circleStart,
                            //         title: 'Search for an address or landmark',
                            //         hintStyle: TextStyle(fontSize: 11),
                            //         imgHeight: 17,
                            //       ),
                            //       const Divider(
                            //         height: 0,
                            //         color: AppColors.containerColor,
                            //       ),
                            //       CustomTextFields.plainTextField(
                            //         readOnly: true,
                            //         Style: TextStyle(
                            //           fontSize: 12,
                            //           color: AppColors.commonBlack.withOpacity(0.6),
                            //           overflow: TextOverflow.ellipsis,
                            //         ),
                            //         controller: _destController,
                            //         containerColor: AppColors.commonWhite,
                            //         leadingImage: AppImages.rectangleDest,
                            //         title: 'Enter destination',
                            //         hintStyle: TextStyle(fontSize: 11),
                            //         imgHeight: 17,
                            //       ),
                            //     ],
                            //   ),
                            // ),
                            // SizedBox(height: 20),
                            // AppButtons.button(
                            //   hasBorder: true,
                            //   borderColor: AppColors.commonBlack.withOpacity(0.2),
                            //   buttonColor: AppColors.commonWhite,
                            //   textColor: AppColors.cancelRideColor,
                            //   onTap: () {
                            //     // setState(() {
                            //     //   isDriverConfirmed = !isDriverConfirmed;
                            //     // });
                            //     AppButtons.showCancelRideBottomSheet(
                            //       context,
                            //       onConfirmCancel: (String selectedReason) {
                            //         driverSearchController.cancelRide(
                            //           bookingId:
                            //               driverSearchController
                            //                   .carBooking
                            //                   .value!
                            //                   .bookingId,
                            //           selectedReason: selectedReason,
                            //           context: context,
                            //         );
                            //       },
                            //     );
                            //   },
                            //   text: 'Cancel Ride',
                            // ),
                            waitingForDriverUI(),
                          ] else if (!_isDriverConfirmed && noDriverFound) ...[
                            noDriverFoundUI(),
                          ] else ...[
                            if (isTripCancelled)
                              Container(
                                padding: const EdgeInsets.all(10),
                                margin: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.red.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.cancel, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "Your trip has been cancelled",
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            cancelReason,
                                            style: const TextStyle(
                                              color: Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Center(
                                child: CustomTextFields.textWithImage(
                                  fontSize: 20,
                                  imageSize: 24,
                                  fontWeight: FontWeight.w600,
                                  text:
                                      destinationReached
                                          ? 'Ride Completed'
                                          : driverStartedRide
                                          ? 'Ride in Progress'
                                          : 'Your ride is confirmed',
                                  colors: AppColors.commonBlack,
                                  rightImagePath: AppImages.clrTick,
                                ),
                              ),

                            // Center(
                            //   child: CustomTextFields.textWithImage(
                            //     imageColors: AppColors.walletCurrencyColor,
                            //     imagePath:
                            //         _isDriverConfirmed ? null : AppImages.clrTick,
                            //     colors: AppColors.commonBlack,
                            //     imageSize: 24,
                            //     fontWeight: FontWeight.w700,
                            //     text:
                            //         _isDriverConfirmed
                            //             ? 'Pickup in Progress'
                            //             : '  Your order is confirmed',
                            //     fontSize: 16,
                            //   ),
                            // ),
                            Divider(
                              thickness: 2,
                              color: AppColors.dividerColor1,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Column(
                                        spacing: 5,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CustomTextFields.textWithStylesSmall(
                                            'PKG - ${BookingId}',
                                            colors: AppColors.commonBlack,
                                            fontWeight: FontWeight.w500,
                                          ),

                                          Row(
                                            children: [
                                              ClipOval(
                                                child: Image.network(
                                                  ProfilePic,
                                                  fit: BoxFit.cover,
                                                  height: 40,
                                                  width: 40,
                                                ),
                                              ),
                                              SizedBox(width: 10),
                                              CustomTextFields.textWithStylesSmall(
                                                fontSize: 15,
                                                driverName,
                                                colors: AppColors.commonBlack,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              // SizedBox(width: 5),
                                              // Image.asset(
                                              //   AppImages.star,
                                              //   width: 13,
                                              //   height: 13,
                                              // ),
                                              // SizedBox(width: 5),
                                              // CustomTextFields.textWithStyles600(
                                              //   '4.5',
                                              // ),
                                            ],
                                          ),
                                          CustomTextFields.textWithStylesSmall(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14,
                                            'Vehicle: Bike ($plateNumber)',
                                            colors:
                                                AppColors
                                                    .rideShareContainerColor2,
                                          ),
                                        ],
                                      ),
                                      Spacer(),
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            50,
                                          ),
                                          color:
                                              AppColors.chatCallContainerColor,
                                        ),

                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: InkWell(
                                            onTap: () async {
                                              const phoneNumber =
                                                  'tel:8248191110';
                                              AppLogger.log.i(phoneNumber);
                                              final Uri url = Uri.parse(
                                                phoneNumber,
                                              );
                                              if (await canLaunchUrl(url)) {
                                                await launchUrl(url);
                                              } else {
                                                print(
                                                  'Could not launch dialer',
                                                );
                                              }
                                            },
                                            child: Image.asset(
                                              AppImages.chatCall,
                                              height: 20,
                                              width: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 20),
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            50,
                                          ),
                                          color: AppColors.chatBlueColor,
                                        ),

                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: InkWell(
                                            onTap: () async {
                                              Get.to(ChatScreen(bookingId: ''));
                                            },
                                            child: Image.asset(
                                              AppImages.chat,
                                              height: 20,
                                              width: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(''),

                                      otp == ''
                                          ? SizedBox.shrink()
                                          : Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              color:
                                                  AppColors
                                                      .userChatContainerColor,
                                            ),
                                            child:
                                                CustomTextFields.textWithStyles600(
                                                  'OTP - $otp',
                                                  fontSize: 12,
                                                  color: AppColors.commonWhite,
                                                ),
                                          ),
                                    ],
                                  ),
                                  SizedBox(height: 20),

                                  GestureDetector(
                                    onTap: () {},
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: AppColors.chatBlueColor
                                            .withOpacity(0.5),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 17,
                                        ),
                                        child: Column(
                                          children: [
                                            Row(
                                              children: [
                                                Image.asset(
                                                  AppImages.direction,
                                                  height: 20,
                                                  width: 20,
                                                ),
                                                const SizedBox(width: 10),
                                                CustomTextFields.textWithStyles600(
                                                  _estimateStt1,
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                const SizedBox(width: 30),
                                                Expanded(
                                                  child: CustomTextFields.textWithStylesSmall(
                                                    maxLines: 2,
                                                    fontWeight: FontWeight.w500,
                                                    colors:
                                                        _isDriverConfirmed
                                                            ? AppColors
                                                                .changeButtonColor
                                                            : AppColors
                                                                .greyDark,
                                                    _estimateStt2,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                  SizedBox(height: 25),
                                  _isOrderConfirmed && !_isPackageCollected
                                      ? PackageContainer.pickUpFields(
                                        imagePath: AppImages.clrTick1,
                                        title: 'Order Confirmed',
                                        subTitle: 'Courier En Route',
                                      )
                                      : PackageContainer.pickUpFields(
                                        imagePath: AppImages.clrTick1,
                                        title: 'Package Collected',
                                        subTitle: '3:45 PM • From Madurai, TN',
                                      ),
                                  const SizedBox(height: 10),
                                  _isEnRoute && !_isInTransit
                                      ? PackageContainer.pickUpFields(
                                        imagePath: AppImages.clrDirection,
                                        title: 'Courier En Route',
                                        subTitle: 'Completed',
                                      )
                                      : PackageContainer.pickUpFields(
                                        imagePath: AppImages.clrBox1,
                                        title: 'In Transit',
                                        subTitle:
                                            'Completed • To Kalavasal, TN',
                                      ),
                                  const SizedBox(height: 10),
                                  _isPackagePickup && !_isOutForDelivery
                                      ? PackageContainer.pickUpFields(
                                        title1: 'Ready',
                                        imagePath: AppImages.box,
                                        title: 'Package Pickup',
                                        subTitle: 'Ready for Pickup',
                                      )
                                      : PackageContainer.pickUpFields(
                                        title1: 'Ready',
                                        imagePath: AppImages.clrHome,
                                        title: 'Out for Delivery',
                                        subTitle: 'Attempting delivery',
                                      ),

                                  SizedBox(height: 15),
                                  Divider(color: AppColors.dividerColor1),

                                  Row(
                                    children: [
                                      CustomTextFields.textWithStylesSmall(
                                        'Order ID',
                                        fontWeight: FontWeight.w500,
                                        fontSize: 15,
                                        colors: AppColors.commonBlack,
                                      ),
                                      Spacer(),
                                      CustomTextFields.textWithStylesSmall(
                                        'PKG- ${BookingId}',
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                        colors: AppColors.commonBlack,
                                      ),
                                      SizedBox(width: 10),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            final textToCopy =
                                                'PKG- ${BookingId}';
                                            Clipboard.setData(
                                              ClipboardData(text: textToCopy),
                                            );

                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Copied: $textToCopy',
                                                ),
                                                duration: const Duration(
                                                  seconds: 1,
                                                ),
                                              ),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ), // Match with Material
                                          splashColor: Colors.blue.withOpacity(
                                            0.3,
                                          ), // Splash effect color
                                          highlightColor: Colors.blue
                                              .withOpacity(
                                                0.1,
                                              ), // Highlight color on tap down
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Image.asset(
                                              AppImages.paste,
                                              height: 15,
                                              width: 15,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 5),
                                  Row(
                                    children: [
                                      CustomTextFields.textWithStylesSmall(
                                        'Package Weight',
                                        fontWeight: FontWeight.w500,
                                        fontSize: 15,
                                        colors: AppColors.commonBlack,
                                      ),
                                      Spacer(),
                                      CustomTextFields.textWithStylesSmall(
                                        '${MaxWeight} kg',
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                        colors: AppColors.commonBlack,
                                      ),
                                    ],
                                  ),
                                  Divider(color: AppColors.dividerColor1),

                                  const SizedBox(height: 12),
                                  GestureDetector(
                                    onTap: () {
                                      Get.to(
                                        PaymentScreen(
                                          amount: 1500,
                                          bookingId: widget.bookingId,
                                        ),
                                      );
                                    },
                                    child: Card(
                                      elevation: 5,
                                      color: AppColors.commonWhite,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 20),
                                        child: Column(
                                          children: [
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                              child: Row(
                                                children: [
                                                  CustomTextFields.textWithImage(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 16,
                                                    colors:
                                                        AppColors.commonBlack,
                                                    text: 'Total Fare',
                                                    rightImagePath:
                                                        AppImages
                                                            .nBlackCurrency,
                                                    rightImagePathText:
                                                        ' $Amount',
                                                  ),

                                                  Spacer(),
                                                  Container(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      color:
                                                          AppColors.commonBlack,
                                                    ),
                                                    child:
                                                        CustomTextFields.textWithStyles600(
                                                          'PKG - ${BookingId}',
                                                          color:
                                                              AppColors
                                                                  .commonWhite,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            SizedBox(height: 20),
                                            /*     Padding(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8.0,
                                              ),
                                              child: InkWell(
                                                onTap: () {
                                                  setState(() {
                                                    isExpanded = !isExpanded;
                                                  });
                                                },
                                                child: Row(
                                                  children: [
                                                    CustomTextFields.textWithStylesSmall(
                                                      'View Details',
                                                      colors:
                                                          AppColors.changeButtonColor,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    AnimatedRotation(
                                                      turns: isExpanded ? 0.5 : 0,
                                                      duration: const Duration(
                                                        milliseconds: 300,
                                                      ),
                                                      child: Image.asset(
                                                        AppImages.dropDown,
                                                        height: 16,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              switchInCurve: Curves.easeInOut,
                                              switchOutCurve: Curves.easeInOut,
                                              transitionBuilder: (child, animation) {
                                                return SizeTransition(
                                                  sizeFactor: animation,
                                                  axisAlignment: -1, // expand downwards
                                                  child: FadeTransition(
                                                    opacity: animation,
                                                    child: child,
                                                  ),
                                                );
                                              },
                                              child:
                                              isExpanded
                                                  ? Column(
                                                key: const ValueKey("expanded"),
                                                children: [
                                                  const SizedBox(height: 10),

                                                  Container(
                                                    margin:
                                                    const EdgeInsets.only(
                                                      top: 10,
                                                    ),
                                                    padding:
                                                    const EdgeInsets.all(
                                                      10,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                        color: AppColors
                                                            .commonBlack
                                                            .withOpacity(0.1),
                                                      ),
                                                      borderRadius:
                                                      BorderRadius.circular(
                                                        8,
                                                      ),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .start,
                                                      children: [
                                                        const Text(
                                                          "Fare Breakdown",
                                                          style: TextStyle(
                                                            fontWeight:
                                                            FontWeight.bold,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 5,
                                                        ),

                                                        /// Base fare
                                                        Row(
                                                          children: [
                                                            CustomTextFields.textWithStylesSmall(
                                                              'Base Fare',
                                                            ),
                                                            const Spacer(),
                                                            CustomTextFields.textWithImage(
                                                              colors:
                                                              AppColors
                                                                  .commonBlack,
                                                              text:
                                                              widget
                                                                  .baseFare
                                                                  .toString() ??
                                                                  '0',
                                                              imagePath:
                                                              AppImages
                                                                  .nBlackCurrency,
                                                            ),
                                                          ],
                                                        ),

                                                        const SizedBox(
                                                          height: 10,
                                                        ),
                                                        Row(
                                                          children: [
                                                            CustomTextFields.textWithStylesSmall(
                                                              'Service Fare',
                                                            ),
                                                            const Spacer(),
                                                            CustomTextFields.textWithImage(
                                                              colors:
                                                              AppColors
                                                                  .commonBlack,
                                                              text:
                                                              widget
                                                                  .serviceFare
                                                                  .toString() ??
                                                                  '0',
                                                              imagePath:
                                                              AppImages
                                                                  .nBlackCurrency,
                                                            ),
                                                          ],
                                                        ),

                                                        const SizedBox(
                                                          height: 10,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                ],
                                              )
                                                  : const SizedBox.shrink(
                                                key: ValueKey("collapsed"),
                                              ),
                                            ),*/

                                            /* ListTile(
                                              leading: Image.asset(
                                                AppImages.cash,
                                                height: 24,
                                                width: 24,
                                              ),
                                              title:
                                                  CustomTextFields.textWithStylesSmall(
                                                    "Cash Payment",
                                                    fontSize: 15,
                                                    colors: AppColors.commonBlack,
                                                    fontWeight: FontWeight.w500,
                                                  ),

                                              trailing: Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 5,
                                                ),
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(
                                                    5,
                                                  ),
                                                  color: AppColors.resendBlue
                                                      .withOpacity(0.1),
                                                ),
                                                child:
                                                    CustomTextFields.textWithStyles600(
                                                      fontSize: 10,
                                                      color:
                                                          AppColors.changeButtonColor,
                                                      'Change',
                                                    ),
                                              ),
                                              onTap: () {},
                                            ),
                                            ListTile(
                                              leading: Image.asset(
                                                AppImages.digiPay,
                                                height: 32,
                                                width: 32,
                                              ),
                                              title:
                                                  CustomTextFields.textWithStylesSmall(
                                                    "Pay using card, UPI & more",
                                                    fontSize: 15,
                                                    colors: AppColors.commonBlack,
                                                    fontWeight: FontWeight.w500,
                                                  ),

                                              subtitle:
                                                  CustomTextFields.textWithStylesSmall(
                                                    'Pay during the ride to avoid cash payments',
                                                    fontSize: 10,
                                                  ),
                                              trailing: Image.asset(
                                                AppImages.rightArrow,
                                                height: 20,
                                                color: AppColors.commonBlack,
                                                width: 20,
                                              ),
                                              onTap: () {
                                                // Get.to(() => PaymentScreen());
                                              },
                                            ),*/
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Stack(
                                    children: [
                                      Card(
                                        elevation: 5,
                                        color: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            // Pickup Address
                                            Padding(
                                              padding: const EdgeInsets.all(
                                                16.0,
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 2,
                                                        ),
                                                    child: Icon(
                                                      Icons.circle,
                                                      color: Colors.green,
                                                      size: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Pickup Address',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                        SizedBox(height: 4),
                                                        Text(
                                                          PickupAddress,
                                                          style: TextStyle(
                                                            color:
                                                                Colors.black54,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            Divider(
                                              height: 0,
                                              color: Colors.grey[200],
                                            ),

                                            // Delivery Address
                                            Padding(
                                              padding: const EdgeInsets.all(
                                                16.0,
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 5,
                                                        ),
                                                    child: Icon(
                                                      Icons.circle,
                                                      color: Colors.orange,
                                                      size: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Delivery Address',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                        SizedBox(height: 4),
                                                        Text(
                                                          DropAddress,
                                                          style: TextStyle(
                                                            color:
                                                                Colors.black54,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            Divider(
                                              height: 0,
                                              color: Colors.grey[300],
                                            ),

                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 35,
                                                    vertical: 10,
                                                  ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  GestureDetector(
                                                    onTap:
                                                        otp.isEmpty
                                                            ? () {
                                                              AppLogger.log.i(
                                                                BookingId,
                                                              );

                                                              AppButtons.showPackageCancelBottomSheet(
                                                                context,
                                                                onConfirmCancel: (
                                                                  String
                                                                  selectedReason,
                                                                ) {
                                                                  driverSearchController.cancelRide(
                                                                    bookingId:
                                                                        BookingId.toString(),
                                                                    selectedReason:
                                                                        selectedReason,
                                                                    context:
                                                                        context,
                                                                  );
                                                                },
                                                              );
                                                            }
                                                            : null,
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.close,
                                                          color: Colors.red,
                                                          size: 16,
                                                        ),
                                                        const SizedBox(
                                                          width: 5,
                                                        ),
                                                        Text(
                                                          otp.isEmpty
                                                              ? 'Cancel Courier'
                                                              : 'Ratings',
                                                          style: TextStyle(
                                                            color: Colors.red,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Container(
                                                      height:
                                                          24, // Set the height you need
                                                      child: VerticalDivider(
                                                        color: Colors.grey,
                                                        thickness: 1,
                                                      ),
                                                    ),
                                                  ),
                                                  Row(
                                                    children: [
                                                      Image.asset(
                                                        AppImages.support,
                                                        height: 15,
                                                        width: 15,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        ' Support',
                                                        style: TextStyle(
                                                          color: Colors.black,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      Positioned(
                                        top: 37,
                                        left: 25,
                                        child: DottedLine(
                                          direction: Axis.vertical,
                                          lineLength: 80,
                                          dashLength: 4,
                                          dashColor: AppColors.dotLineColor,
                                        ),
                                      ),
                                    ],
                                  ),

                                  SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget waitingForDriverUI() {
    return Column(
      children: [
        Text(
          textAlign: TextAlign.center,
          'Looking for the best drivers for you',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        LinearProgressIndicator(
          borderRadius: BorderRadius.circular(10),
          minHeight: 7,
          backgroundColor: AppColors.linearIndicatorColor.withOpacity(0.2),
          color: AppColors.linearIndicatorColor,
        ),
        SizedBox(height: 20),
        Image.asset(
          AppImages.packageLoading,
          height: 100,
          width: 100,
          fit: BoxFit.contain,
        ),
        SizedBox(height: 20),

        SizedBox(height: 20),
        Obx(() {
          final loading = driverSearchController.isLoading.value;

          return AppButtons.button(
            size: 350,
            hasBorder: true,
            borderColor: AppColors.commonBlack.withOpacity(0.2),
            buttonColor: AppColors.commonWhite,
            textColor: AppColors.cancelRideColor,

            // disable while loading
            onTap:
                loading
                    ? null
                    : () {
                      AppButtons.showCancelRideBottomSheet(
                        context,
                        onConfirmCancel: (String selectedReason) {
                          driverSearchController.cancelRide(
                            bookingId: widget.bookingId.toString(),
                            selectedReason: selectedReason,
                            context: context,
                          );
                        },
                      );
                    },
            isLoading: driverSearchController.isLoading.value,
            // show loader instead of text
            text: 'Cancel Ride',
          );
        }),

        // AppButtons.button(
        //   hasBorder: true,
        //   borderColor: AppColors.commonBlack.withOpacity(0.2),
        //   buttonColor: AppColors.commonWhite,
        //   textColor: AppColors.cancelRideColor,
        //   onTap: () {
        //     // setState(() {
        //     //   isDriverConfirmed = !isDriverConfirmed;
        //     // });
        //     AppButtons.showCancelRideBottomSheet(
        //       context,
        //       onConfirmCancel: (String selectedReason) {
        //         print(widget.bookingId);
        //         driverSearchController.cancelRide(
        //           bookingId: widget.bookingId.toString() ?? '',
        //           selectedReason: selectedReason,
        //           context: context,
        //         );
        //       },
        //     );
        //   },
        //   text: 'Cancel Ride',
        // ),
      ],
    );
  }

  Widget noDriverFoundUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 80),
          const SizedBox(height: 20),
          const Text(
            "No Drivers Found",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "We couldn’t find any available drivers nearby.\nPlease try again in a few minutes.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 30),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 15),
            child: Column(
              children: [
                AppButtons.button(
                  buttonColor: Colors.blue,
                  textColor: Colors.white,
                  text: "Try Again",
                  onTap: () async {
                    setState(() {
                      isWaitingForDriver = true;
                      noDriverFound = false;
                    });

                    final allData = driverSearchController.carBooking.value;
                    setState(() {
                      isWaitingForDriver = true;
                      noDriverFound = false;
                    });
                    String? result = await packageController
                        .sendPackageDriverRequest(
                          discountCode: widget.discountCode ?? '',
                          bookingId: widget.bookingId,
                          receiverData: widget.receiverData,
                          senderData: widget.senderData,
                        );
                    if (result != null) {
                      startDriverSearch();
                    }
                  },
                ),
                SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      side: BorderSide(color: Colors.black),
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      'Go Home',
                      style: TextStyle(
                        color: AppColors.commonBlack,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
