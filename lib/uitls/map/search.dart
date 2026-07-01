import 'package:geolocator/geolocator.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LocationHelper {
  static   final String _apiKey =
      ApiConsents. googleMapApiKey;
  // String apiKey =  ApiConsents.googleMapApiKey;

  static Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    // Current location is used ONLY to bias results + compute distance. Guard it
    // (timeout + last-known fallback) so a slow/denied GPS never hangs or throws;
    // distance is omitted when we have no origin (never show a fake value).
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }

    final bias = position != null
        ? '&location=${position.latitude},${position.longitude}&radius=50000'
        : '';
    final url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query'
        '$bias'
        '&key=$_apiKey';

    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    final data = json.decode(response.body);
    AppLogger.log.i('Autocomplete API response: $data');
    if (response.statusCode == 200 && data['status'] == 'OK') {
      final List predictions = data['predictions'];
      final Position? origin = position;

      final List<Future<Map<String, dynamic>?>> futures =
          predictions.map((prediction) async {
            final placeId = prediction['place_id'];
            final detailUrl =
                'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_apiKey';

            final detailRes = await http
                .get(Uri.parse(detailUrl))
                .timeout(const Duration(seconds: 10));
            final detailData = json.decode(detailRes.body);

            if (detailRes.statusCode == 200 && detailData['status'] == 'OK') {
              final location = detailData['result']['geometry']['location'];
              final lat = (location['lat'] as num).toDouble();
              final lng = (location['lng'] as num).toDouble();

              final double? distance = origin != null
                  ? Geolocator.distanceBetween(
                      origin.latitude, origin.longitude, lat, lng)
                  : null;

              return {
                'placeId': placeId,
                'description': prediction['description'],
                'lat': lat,
                'lng': lng,
                if (distance != null)
                  'distance': '${(distance / 1000).round()} km',
              };
            }
            return null;
          }).toList();

      final detailedResults = await Future.wait(futures);
      return detailedResults.whereType<Map<String, dynamic>>().toList();
    }

    return [];
  }

  /// Up to [limit] nearby places of a given Google `type` (train_station /
  /// airport / bus_station / shopping_mall / hospital), ranked BY DISTANCE from
  /// the user's current location, each with a correct distance string. Returns an
  /// empty list when location/results are unavailable (never fakes a distance).
  /// Used by the quick-destination chips to show a pick list.
  static Future<List<Map<String, dynamic>>> nearbyPlacesByType(
    String type, {
    int limit = 6,
  }) async {
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }
    if (position == null) return const [];

    final url =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=${position.latitude},${position.longitude}'
        '&rankby=distance&type=$type&key=$_apiKey';
    try {
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final data = json.decode(res.body);
      if (res.statusCode == 200 && data['status'] == 'OK') {
        final results = (data['results'] as List?) ?? const [];
        final out = <Map<String, dynamic>>[];
        for (final place in results) {
          if (out.length >= limit) break;
          final loc = place['geometry']?['location'];
          if (loc == null) continue;
          final lat = (loc['lat'] as num?)?.toDouble();
          final lng = (loc['lng'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;
          final distance = Geolocator.distanceBetween(
              position.latitude, position.longitude, lat, lng);
          final name = (place['name'] ?? '').toString();
          final vicinity = (place['vicinity'] ?? '').toString();
          out.add({
            'description': vicinity.isNotEmpty ? '$name, $vicinity' : name,
            'lat': lat,
            'lng': lng,
            'distance': '${(distance / 1000).toStringAsFixed(1)} km',
          });
        }
        return out;
      }
    } catch (_) {}
    return const [];
  }

  /// Nearest single place of a given Google `type` ranked BY DISTANCE from the
  /// user's current location. Returns null when location/results are unavailable
  /// so the caller can avoid showing a fake distance.
  static Future<Map<String, dynamic>?> nearestPlaceByType(String type) async {
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }
    if (position == null) return null;

    // rankby=distance REQUIRES type/keyword and must NOT include radius.
    final url =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=${position.latitude},${position.longitude}'
        '&rankby=distance&type=$type&key=$_apiKey';
    try {
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final data = json.decode(res.body);
      if (res.statusCode == 200 && data['status'] == 'OK') {
        final results = (data['results'] as List?) ?? const [];
        if (results.isEmpty) return null;
        final place = results.first;
        final loc = place['geometry']['location'];
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();
        final distance = Geolocator.distanceBetween(
          position.latitude, position.longitude, lat, lng);
        return {
          'description': (place['name'] ?? '').toString(),
          'lat': lat,
          'lng': lng,
          'distance': '${(distance / 1000).toStringAsFixed(1)} km',
        };
      }
    } catch (_) {}
    return null;
  }
}
