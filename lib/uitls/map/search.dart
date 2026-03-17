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
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    );

    final url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query'
        '&location=${position.latitude},${position.longitude}'
        '&radius=50000'
        '&key=$_apiKey';

    final response = await http.get(Uri.parse(url));
    final data = json.decode(response.body);
    AppLogger.log.i('Autocomplete API response: $data');
    if (response.statusCode == 200 && data['status'] == 'OK') {
      final List predictions = data['predictions'];

      // ✅ Create explicit list of Future<Map<String, dynamic>?>
      final List<Future<Map<String, dynamic>?>> futures =
          predictions.map((prediction) async {
            final placeId = prediction['place_id'];
            final detailUrl =
                'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_apiKey';

            final detailRes = await http.get(Uri.parse(detailUrl));
            final detailData = json.decode(detailRes.body);

            if (detailRes.statusCode == 200 && detailData['status'] == 'OK') {
              final location = detailData['result']['geometry']['location'];
              final lat = location['lat'];
              final lng = location['lng'];

              final distance = Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                lat,
                lng,
              );

              return {
                'placeId': placeId,
                'description': prediction['description'],
                'lat': lat,
                'lng': lng,
                'distance': '${(distance / 1000).round()} km',
              };
            }
            return null;
          }).toList(); // ✅ Now this is List<Future<Map<String, dynamic>?>>

      final detailedResults = await Future.wait(futures);
      return detailedResults
          .whereType<Map<String, dynamic>>()
          .toList(); // ✅ filter nulls
    }

    return [];
  }
}
