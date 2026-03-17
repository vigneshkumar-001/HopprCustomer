/*
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_place/google_place.dart';
import 'package:hopper/driver_detail_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:get/get.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:geocoding/geocoding.dart';

class UberStyleMapScreen extends StatefulWidget {
  @override
  _UberStyleMapScreenState createState() => _UberStyleMapScreenState();
}

class _UberStyleMapScreenState extends State<UberStyleMapScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  final driverController = Get.put(DriverController());

  LatLng? _destinationPosition;
  BitmapDescriptor? _carIcon, _startIcon, _endIcon;
  Marker? _carMarker;
  final _searchController = TextEditingController();
  late GooglePlace googlePlace;
  Timer? _carTimer;
  Set<Polyline> _polylines = {};
  String? _startLocationName;
  String? _selectedDestinationName;
  Offset? _startOffset;
  Offset? _destinationOffset;

  String? _destinationLocationName;
  @override
  void initState() {
    super.initState();
    _initGooglePlace();
    _loadCustomMarkers();
    _getCurrentLocation();
  }

  void _initGooglePlace() {
    const String apiKey = 'AIzaSyDgGqDOMvgHFLSF8okQYOEiWSe7RIgbEic';
    googlePlace = GooglePlace(apiKey);
  }

  void _updateMarkerLabels() async {
    if (_mapController == null) return;

    final screenSize = MediaQuery.of(context).size;

    if (_currentPosition != null) {
      final coord = await _mapController!.getScreenCoordinate(
        _currentPosition!,
      );
      _startOffset = Offset(
        coord.x.toDouble(),
        coord.y.toDouble().clamp(
          0.0,
          screenSize.height - 50,
        ), // Prevent off-screen
      );
    }

    if (_destinationPosition != null) {
      final coord = await _mapController!.getScreenCoordinate(
        _destinationPosition!,
      );
      _destinationOffset = Offset(
        coord.x.toDouble(),
        coord.y.toDouble().clamp(
          0.0,
          screenSize.height - 50,
        ), // Prevent off-screen
      );
    }

    setState(() {});
  }

  Widget _buildMarkerLabel(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  Future<void> _loadCustomMarkers() async {
    _carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(),
      AppImages.avoidDrinks,
    );
    _startIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(),
      AppImages.pencilBike,
    );
    _endIcon = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(0, 0)),
      AppImages.square,
      height: 30,
      width: 30,
    );
    setState(() {});
  }

  Future<void> _getCurrentLocation() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _currentPosition = LatLng(pos.latitude, pos.longitude);
      _mapController?.animateCamera(CameraUpdate.newLatLng(_currentPosition!));
      setState(() {});
      Future.delayed(const Duration(milliseconds: 300), () {
        _updateMarkerLabels();
      });
    }
  }

  Future<void> _getDirectionsPolyline(LatLng origin, LatLng destination) async {
    final String apiKey = 'AIzaSyDgGqDOMvgHFLSF8okQYOEiWSe7RIgbEic';
    final String url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      final route = data['routes'][0];
      final points = route['overview_polyline']['points'];
      final List<LatLng> polylinePoints = _decodePolyline(points);

      setState(() {
        _polylines.clear();
        _polylines.add(
          Polyline(
            polylineId: const PolylineId("route"),
            color: Colors.black,
            width: 5,

            points: polylinePoints,
          ),
        );
      });
    } else {
      print("Failed to load directions: ${response.body}");
    }
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

  void _onPlaceSelected(AutocompletePrediction prediction) async {
    print("Selected place: ${prediction.description}");

    // Save destination name for UI
    _selectedDestinationName = prediction.description;

    // Get place details from Google
    final details = await googlePlace.details.get(prediction.placeId!);
    if (details == null || details.result?.geometry?.location == null) {
      print("Failed to get place details or location");
      return;
    }

    final loc = details.result!.geometry!.location!;
    final newDestination = LatLng(loc.lat!, loc.lng!);

    // Get start location name using reverse geocoding
    try {
      final placemarks = await placemarkFromCoordinates(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        _startLocationName = '${place.name}, ${place.locality}';
      }
    } catch (e) {
      _startLocationName = "My Location";
      print("Error getting start location name: $e");
    }

    // Set destination and draw polyline
    setState(() {
      _destinationPosition = newDestination;
      _carMarker = null;
    });

    await _getDirectionsPolyline(_currentPosition!, _destinationPosition!);

    // Adjust camera bounds to fit the entire route (even short ones)
    LatLng southwest = LatLng(
      min(_currentPosition!.latitude, _destinationPosition!.latitude),
      min(_currentPosition!.longitude, _destinationPosition!.longitude),
    );

    LatLng northeast = LatLng(
      max(_currentPosition!.latitude, _destinationPosition!.latitude),
      max(_currentPosition!.longitude, _destinationPosition!.longitude),
    );

    // Widen bounds for short routes
    if ((northeast.latitude - southwest.latitude).abs() < 0.002 &&
        (northeast.longitude - southwest.longitude).abs() < 0.002) {
      const adjustment = 0.001; // About 100m
      southwest = LatLng(
        southwest.latitude - adjustment,
        southwest.longitude - adjustment,
      );
      northeast = LatLng(
        northeast.latitude + adjustment,
        northeast.longitude + adjustment,
      );
    }

    final bounds = LatLngBounds(southwest: southwest, northeast: northeast);

    await Future.delayed(
      const Duration(milliseconds: 300),
    ); // Wait before moving

    await _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 120),
    );

    // ✅ NOW: ensure update happens *after* camera animation
    await Future.delayed(const Duration(milliseconds: 400));
    _updateMarkerLabels();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  @override
  void dispose() {
    _carTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print("StartOffset: $_startOffset");
    print("DestinationOffset: $_destinationOffset");

    if (_currentPosition == null ||
        _carIcon == null ||
        _startIcon == null ||
        _endIcon == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final Set<Marker> markers = {};

    if (_destinationPosition == null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current'),
          position: _currentPosition!,
          icon: _startIcon!,
        ),
      );
    } else {
      markers.addAll([
        Marker(
          markerId: const MarkerId('start'),
          position: _currentPosition!,
          icon: _startIcon!,
        ),
        Marker(
          markerId: const MarkerId('end'),
          position: _destinationPosition!,
          icon: _endIcon!,
        ),
      ]);

      if (_carMarker != null) {
        markers.add(_carMarker!);
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _currentPosition!,
              zoom: 17,
            ),
            markers: markers,
            polylines: _polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            onCameraMove: (_) => _updateMarkerLabels(),
          ),

          Positioned(
            top: 40,
            left: 15,
            right: 15,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Autocomplete<AutocompletePrediction>(
                  optionsBuilder: (TextEditingValue textEditingValue) async {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<AutocompletePrediction>.empty();
                    }

                    final result = await googlePlace.autocomplete.get(
                      textEditingValue.text,
                      location:
                          _currentPosition == null
                              ? null
                              : LatLon(
                                _currentPosition!.latitude,
                                _currentPosition!.longitude,
                              ),
                      radius: 50000,
                      strictbounds: true,
                    );

                    return result?.predictions ??
                        const Iterable<AutocompletePrediction>.empty();
                  },
                  displayStringForOption:
                      (AutocompletePrediction option) =>
                          option.description ?? '',
                  fieldViewBuilder: (
                    context,
                    controller,
                    focusNode,
                    onEditingComplete,
                  ) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        hintText: 'Search destination',
                        hintStyle: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                        border: InputBorder.none,
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.grey,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            controller.clear();
                            _searchController.clear();
                            setState(() {
                              _polylines.clear();
                              _destinationPosition = null;
                            });
                          },
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                    );
                  },

                  /// 👇 Custom dropdown UI as ListView-style
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: options.length,
                            separatorBuilder:
                                (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              return ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.location_on_outlined,
                                  color: Colors.blueGrey,
                                ),
                                title: Text(
                                  option.description ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  onSelected: _onPlaceSelected,
                ),
              ),
            ),
          ),
          if (_startOffset != null)
            Positioned(
              left: _startOffset!.dx - 40,
              top: _startOffset!.dy - 40,
              child: IgnorePointer(
                child: _buildMarkerLabel(_startLocationName ?? "My Location"),
              ),
            ),

          if (_destinationOffset != null)
            Positioned(
              left: _destinationOffset!.dx - 50,
              top: _destinationOffset!.dy,
              child: _buildMarkerLabel(
                _destinationLocationName ?? "Destination",
              ),
            ),
        ],
      ),
    );
  }
}
*/

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/api/repository/api_consents.dart';

class CarRoutePage extends StatefulWidget {
  const CarRoutePage({super.key});

  @override
  State<CarRoutePage> createState() => _CarRoutePageState();
}

class _CarRoutePageState extends State<CarRoutePage>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  BitmapDescriptor? _carIcon;

  // Route points (Kalavasal → Othakkadai)
  LatLng kalavasal = const LatLng(9.9196, 78.0959);
  LatLng othakkadai = const LatLng(9.9583, 78.1472);

  final Set<Polyline> _polylines = {};
  final List<LatLng> _polylineCoordinates = [];
  final Set<Marker> _markers = {};

  int _carIndex = 0;
  LatLng? _carPosition;
  double _carRotation = 0;

  AnimationController? _movementController;
  Animation<LatLng>? _movementAnimation;

  @override
  void initState() {
    super.initState();
    _loadCustomMarker();
    _getRoute();
  }
  Future<void> _loadCustomMarker() async {
    _carIcon = await BitmapDescriptor.asset(
      height: 60,
      ImageConfiguration(size: Size(52, 52)),
      AppImages.packageBike,
    );
  }

  /// Fetch route using Google Directions API
  Future<void> _getRoute() async {
    PolylinePoints polylinePoints = PolylinePoints();
    String apiKey = ApiConsents.googleMapApiKey;

    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      apiKey,
      PointLatLng(kalavasal.latitude, kalavasal.longitude),
      PointLatLng(othakkadai.latitude, othakkadai.longitude),
      travelMode: TravelMode.driving,
    );

    if (result.points.isNotEmpty) {
      _polylineCoordinates.clear();
      for (var point in result.points) {
        _polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      }

      setState(() {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId("route"),
            color: Colors.blue,
            width: 6,
            points: _polylineCoordinates,
          ),
        );

        if (_polylineCoordinates.isNotEmpty) {
          _carPosition = _polylineCoordinates.first;
          _setCarMarker(_carPosition!, 0);
        }
      });
    }
  }

  /// Place car marker
  void _setCarMarker(LatLng position, double rotation) {
    setState(() {
      _carPosition = position;
      _carRotation = rotation;
      _markers.clear();
      _markers.add(
        Marker(
          markerId: const MarkerId("car"),
          position: position,
          icon: _carIcon ?? BitmapDescriptor.defaultMarker,
          rotation: rotation,
          anchor: const Offset(0.5, 0.5),
          flat: true,
        ),
      );
    });
  }

  /// Start car movement smoothly
  void _startCarMovement() {
    if (_polylineCoordinates.isEmpty) return;

    _carIndex = 0;
    _moveToNextPoint();
  }

  void _moveToNextPoint() {
    if (_carIndex >= _polylineCoordinates.length - 1) return;

    LatLng from = _polylineCoordinates[_carIndex];
    LatLng to = _polylineCoordinates[_carIndex + 1];

    double bearing = _getBearing(from, to);

    _movementController?.dispose();
    _movementController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _movementAnimation = LatLngTween(begin: from, end: to).animate(
      CurvedAnimation(parent: _movementController!, curve: Curves.linear),
    );

    _movementController!.addListener(() {
      LatLng newPos = _movementAnimation!.value;
      _setCarMarker(newPos, bearing);

      // 🔥 keep map aligned with car movement
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: newPos,
            zoom: 17,
            tilt: 45,
            bearing: bearing, // now map turns with car
          ),
        ),
      );
    });

    _movementController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _carIndex++;
        _moveToNextPoint();
      }
    });

    _movementController!.forward();
  }

  /// Bearing calculation for rotation
  double _getBearing(LatLng from, LatLng to) {
    double lat1 = from.latitude * pi / 180.0;
    double lon1 = from.longitude * pi / 180.0;
    double lat2 = to.latitude * pi / 180.0;
    double lon2 = to.longitude * pi / 180.0;

    double dLon = lon2 - lon1;
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) -
        sin(lat1) * cos(lat2) * cos(dLon);
    double brng = atan2(y, x);

    return (brng * 180 / pi + 360) % 360;
  }

  @override
  void dispose() {
    _movementController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Uber/Ola Smooth Car Movement")),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: kalavasal,
              zoom: 14,
            ),
            polylines: _polylines,
            markers: _markers,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
            },
          ),

          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: _startCarMovement,
              child: const Text("Start Journey"),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tween for LatLng interpolation
class LatLngTween extends Tween<LatLng> {
  LatLngTween({LatLng? begin, LatLng? end}) : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) => LatLng(
    begin!.latitude + (end!.latitude - begin!.latitude) * t,
    begin!.longitude + (end!.longitude - begin!.longitude) * t,
  );
}
