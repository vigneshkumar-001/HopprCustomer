import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Single, canonical representation of a pickup/destination selection used
/// throughout the booking flow (address history, search, map pin, current
/// location, saved places). Replaces passing around ad hoc `Map<String,
/// dynamic>` shapes with inconsistent keys (`'lat'/'lng'` vs `'location'`)
/// between screens.
class SelectedLocation {
  final String address;
  final double latitude;
  final double longitude;
  final String? placeId;

  /// Where this selection came from: 'history' | 'search' | 'map' |
  /// 'current_location' | 'saved' | 'resume' | 'unknown'.
  final String source;

  /// Optional structured address parts (street, city, state, etc.), when
  /// available from the source (e.g. geocoding placemark).
  final Map<String, dynamic>? structured;

  const SelectedLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
    this.placeId,
    this.source = 'unknown',
    this.structured,
  });

  /// A location counts as a completed selection once it has a non-empty
  /// address and finite, non-null-island coordinates. Deliberately does NOT
  /// require [placeId] — a point dropped directly on the map is still valid.
  bool get isValid =>
      address.trim().isNotEmpty &&
      latitude.isFinite &&
      longitude.isFinite &&
      !(latitude == 0.0 && longitude == 0.0);

  LatLng get latLng => LatLng(latitude, longitude);

  factory SelectedLocation.fromLatLng(
    LatLng point, {
    required String address,
    String? placeId,
    String source = 'unknown',
    Map<String, dynamic>? structured,
  }) {
    return SelectedLocation(
      address: address,
      latitude: point.latitude,
      longitude: point.longitude,
      placeId: placeId,
      source: source,
      structured: structured,
    );
  }

  /// Accepts either of the two shapes already used across the app:
  /// `{'description'|'mapAddress'|'address': .., 'location': LatLng}` or
  /// `{'description': .., 'lat': .., 'lng': ..}`.
  factory SelectedLocation.fromMap(
    Map<String, dynamic> map, {
    String source = 'unknown',
  }) {
    double? lat;
    double? lng;
    final dynamic loc = map['location'];
    if (loc is LatLng) {
      lat = loc.latitude;
      lng = loc.longitude;
    } else {
      lat = (map['lat'] as num?)?.toDouble();
      lng = (map['lng'] as num?)?.toDouble();
    }
    final description =
        (map['description'] ??
                map['mapAddress'] ??
                map['address'] ??
                map['name'] ??
                '')
            .toString();
    return SelectedLocation(
      address: description,
      latitude: lat ?? 0.0,
      longitude: lng ?? 0.0,
      placeId: map['placeId'] as String?,
      source: (map['source'] as String?) ?? source,
    );
  }

  /// Flat shape consumed by the rest of the booking flow (`BookMapScreen`,
  /// `ConfirmBooking`, `RideShareScreen` all read `['description']`/
  /// `['lat']`/`['lng']`).
  Map<String, dynamic> toMap() => {
        'description': address,
        'lat': latitude,
        'lng': longitude,
        if (placeId != null) 'placeId': placeId,
        'source': source,
      };

  SelectedLocation copyWith({
    String? address,
    double? latitude,
    double? longitude,
    String? placeId,
    String? source,
    Map<String, dynamic>? structured,
  }) {
    return SelectedLocation(
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      placeId: placeId ?? this.placeId,
      source: source ?? this.source,
      structured: structured ?? this.structured,
    );
  }

  @override
  String toString() =>
      'SelectedLocation(address: $address, lat: $latitude, lng: $longitude, '
      'placeId: $placeId, source: $source)';
}
