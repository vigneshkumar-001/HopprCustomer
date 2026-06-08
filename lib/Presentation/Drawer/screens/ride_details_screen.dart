import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/Drawer/models/ride_history_response.dart';
import 'package:hopper/Presentation/Drawer/utils/ride_history_format.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/uitls/map/direction_helper.dart';

class RideDetailsScreen extends StatefulWidget {
  final RideHistoryData ride;

  const RideDetailsScreen({super.key, required this.ride});

  @override
  State<RideDetailsScreen> createState() => _RideDetailsScreenState();
}

class _RideDetailsScreenState extends State<RideDetailsScreen> {
  GoogleMapController? _mapController;
  List<LatLng> _routePoints = const [];

  LatLng? get _pickup {
    final r = widget.ride;
    if (r.fromLatitude == null || r.fromLongitude == null) return null;
    return LatLng(r.fromLatitude!, r.fromLongitude!);
  }

  LatLng? get _drop {
    final r = widget.ride;
    if (r.toLatitude == null || r.toLongitude == null) return null;
    return LatLng(r.toLatitude!, r.toLongitude!);
  }

  bool get _hasMap => _pickup != null && _drop != null;

  @override
  void initState() {
    super.initState();
    if (_hasMap) {
      // Show a straight line immediately; the real road route loads async.
      _routePoints = [_pickup!, _drop!];
      _loadRoute();
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadRoute() async {
    try {
      final dir = DirectionsHelper(apiKey: ApiConsents.googleMapApiKey);
      final info = await dir.getRouteInfo(origin: _pickup!, destination: _drop!);
      if (!mounted || info.points.isEmpty) return;
      setState(() => _routePoints = info.points);
      _fitToPoints(info.points);
    } catch (_) {
      // keep the straight-line fallback set in initState
    }
  }

  void _fitToPoints(List<LatLng> pts) {
    if (_mapController == null || pts.isEmpty) return;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    _mapController!.moveCamera(CameraUpdate.newLatLngBounds(bounds, 56));
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final driver = ride.driver;
    final driverName =
        '${driver?.firstName ?? ''} ${driver?.lastName ?? ''}'.trim();
    final accent = statusColor(ride.ridehistoryColor);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          children: [
            // ---- Header ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Ride Details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  _mapCard(),
                  const SizedBox(height: 12),
                  _driverCard(driverName, accent),
                  const SizedBox(height: 12),
                  _fareCard(),
                  const SizedBox(height: 12),
                  _routeCard(),
                  const SizedBox(height: 12),
                  _ratingCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- MAP ----------------
  Widget _mapCard() {
    if (!_hasMap) {
      return Container(
        height: 170,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.map_outlined, color: Colors.grey, size: 30),
            SizedBox(height: 8),
            Text(
              'Route preview not available',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: _pickup!,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueGreen,
        ),
      ),
      Marker(
        markerId: const MarkerId('drop'),
        position: _drop!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    final polylines = <Polyline>{
      if (_routePoints.length >= 2)
        Polyline(
          polylineId: const PolylineId('route'),
          points: _routePoints,
          color: Colors.black,
          width: 4,
        ),
    };

    final center = LatLng(
      (_pickup!.latitude + _drop!.latitude) / 2,
      (_pickup!.longitude + _drop!.longitude) / 2,
    );

    return Container(
      height: 190,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // IgnorePointer = display-only preview: the route polyline still updates
      // dynamically (unlike lite mode) and the map never steals list scroll.
      child: IgnorePointer(
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: center, zoom: 12),
          markers: markers,
          polylines: polylines,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (c) {
            _mapController = c;
            _fitToPoints(
              _routePoints.isNotEmpty ? _routePoints : [_pickup!, _drop!],
            );
          },
        ),
      ),
    );
  }

  // ---------------- DRIVER ----------------
  Widget _driverCard(String driverName, Color accent) {
    final ride = widget.ride;
    final driver = ride.driver;
    return _card(
      child: Row(
        children: [
          // profile + car
          SizedBox(
            width: 84,
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Image.asset(
                    vehicleAssetForType(driver?.carType),
                    width: 64,
                    height: 44,
                    fit: BoxFit.contain,
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.network(
                        driver?.profilePic ?? '',
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => Container(
                              width: 40,
                              height: 40,
                              color: AppColors.containerColor,
                              child: const Icon(
                                Icons.person,
                                size: 22,
                                color: Colors.grey,
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driverName.isEmpty ? 'Driver' : driverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  driver?.carPlateNumber ??
                      driver?.carRegistrationNumber ??
                      '',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: accent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    prettyStatus(ride.status),
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
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

  // ---------------- FARE ----------------
  Widget _fareCard() {
    final ride = widget.ride;
    final carType = ride.driver?.carType ?? ride.rideType ?? '';
    final km =
        ride.distance != null
            ? '${(ride.distance!).toStringAsFixed(1)} Kms'
            : '';
    final mins = ride.rideDurationFormatted ?? '';
    final metaParts =
        [
          if (carType.isNotEmpty) carType,
          if (km.isNotEmpty) km,
          if (mins.isNotEmpty) mins,
        ].join('  •  ');

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ride Details',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (metaParts.isNotEmpty)
            Text(
              metaParts,
              style: TextStyle(fontSize: 13, color: AppColors.textColor),
            ),
          const SizedBox(height: 4),
          Text(
            formatRideDateLong(ride.createdAt),
            style: TextStyle(fontSize: 13, color: AppColors.textColor),
          ),
          if ((ride.bookingId ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Booking ID',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              ride.bookingId ?? '',
              style: TextStyle(fontSize: 13, color: AppColors.textColor),
            ),
          ],
          const Divider(height: 26),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomTextFields.textWithImage(
                      text: (ride.amount ?? ride.total ?? '').toString(),
                      fontSize: 22,
                      imageColors: AppColors.commonBlack,
                      colors: AppColors.commonBlack,
                      fontWeight: FontWeight.w800,
                      imageSize: 22,
                      imagePath: AppImages.nBlackCurrency,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 16,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Cash',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: _onSendInvoice,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE53935)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                ),
                child: const Text(
                  'Send Invoice',
                  style: TextStyle(
                    color: Color(0xFFE53935),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onSendInvoice() {
    Get.snackbar(
      'Invoice',
      'Your invoice will be sent to your registered email shortly.',
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(14),
      backgroundColor: Colors.black87,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
  }

  // ---------------- ROUTE TIMELINE ----------------
  Widget _routeCard() {
    final ride = widget.ride;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _timelineRow(
            dotColor: const Color(0xFF009721),
            title: 'PICKUP AT',
            address: ride.pickupAddress ?? '',
            stamp: formatTimelineStamp(ride.createdAt),
            showConnector: true,
          ),
          _timelineRow(
            dotColor: const Color(0xFFE53935),
            title: 'DROP AT',
            address: ride.dropAddress ?? '',
            stamp: formatTimelineStamp(ride.completedAt ?? ride.updatedAt),
            showConnector: false,
          ),
        ],
      ),
    );
  }

  Widget _timelineRow({
    required Color dotColor,
    required String title,
    required String address,
    required String stamp,
    required bool showConnector,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 13,
                height: 13,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              if (showConnector)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: Colors.grey.shade300,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showConnector ? 14 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address,
                    style: const TextStyle(fontSize: 13.5, height: 1.35),
                  ),
                  if (stamp.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      stamp,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- DRIVER RATING (dynamic from ride.starRating) ----------------
  Widget _ratingCard() {
    final rating = double.tryParse(widget.ride.starRating ?? '') ?? 0;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Driver Rating',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (rating > 0)
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE79700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (rating > 0)
            Row(
              children: List.generate(5, (i) {
                final filled = i < rating.round();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 30,
                    color:
                        filled
                            ? const Color(0xFFE79700)
                            : Colors.grey.shade400,
                  ),
                );
              }),
            )
          else
            Text(
              'Not rated yet',
              style: TextStyle(fontSize: 13, color: AppColors.textColor),
            ),
        ],
      ),
    );
  }

  // ---------------- shared card ----------------
  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
