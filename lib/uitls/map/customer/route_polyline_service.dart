import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/uitls/map/direction_helper.dart';

class RoutePolylineService {
  RoutePolylineService({required String apiKey}) : _dir = DirectionsHelper(apiKey: apiKey);

  final DirectionsHelper _dir;

  Future<List<LatLng>> fetchRoutePoints({
    required LatLng origin,
    required LatLng destination,
    String mode = 'driving',
  }) async {
    final route = await _dir.getRouteInfo(
      origin: origin,
      destination: destination,
      mode: mode,
      alternatives: false,
      traffic: true,
      routeIndex: 0,
    );
    return route.points;
  }
}

