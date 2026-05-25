import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/uitls/map/driver_motion_engine.dart';

/// Thin wrapper around [DriverMotionEngine] to keep CustomerRideMapView clean.
class VehicleAnimationService {
  VehicleAnimationService({
    required DriverMotionEngine engine,
  }) : _engine = engine;

  final DriverMotionEngine _engine;

  void reset(LatLng pos, {double bearing = 0}) => _engine.reset(pos, bearing: bearing);

  void ingest(LatLng pos, {DateTime? ts, double? bearing}) =>
      _engine.ingest(pos, serverTs: ts, bearing: bearing);

  void dispose() => _engine.dispose();
}

