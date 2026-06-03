import 'package:hopper/Presentation/BookRide/Models/pricing_insights_model.dart';

// ---------- Safe casting helpers ----------
double _asDouble(dynamic v, {double def = 0.0}) {
  if (v == null) return def;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? def;
}

int _asInt(dynamic v, {int def = 0}) {
  if (v == null) return def;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? def;
}

String _asString(dynamic v, {String def = ''}) {
  if (v == null) return def;
  return v.toString();
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  try {
    return DateTime.tryParse(v.toString());
  } catch (_) {
    return null;
  }
}

// ---------- Models ----------
class DriverSearchModels {
  final int status;
  final List<DriverData> data;
  final int count;

  DriverSearchModels({
    required this.status,
    required this.data,
    required this.count,
  });

  factory DriverSearchModels.fromJson(Map<String, dynamic> json) {
    final list =
        (json['data'] as List? ?? [])
            .map((e) => DriverData.fromJson(e as Map<String, dynamic>))
            .toList();

    return DriverSearchModels(
      status: _asInt(json['status'], def: 0),
      data: list,
      // API response you shared didn’t include "count"; derive it safely
      count: _asInt(json['count'], def: list.length),
    );
  }
}

class DriverData {
  final String id;
  final DriverDetails driverId;
  final bool booked;
  final DateTime createdAt;
  final double currentLatitude;
  final double currentLongitude;
  final bool onlineStatus;
  final bool sharedBooking;
  final DateTime updatedAt;
  final DateTime? requestDateAndTime;
  final String? requestStatus;
  final double distance;
  final String estimatedPrice;
  final int estimatedTime;
  final List<EstimateFareByLocation> faresByLocation;

  // Optional extras you may want later (present in payload):
  final String? serviceType; // e.g. "Car"
  final String? carType; // e.g. "luxury"

  DriverData({
    required this.id,
    required this.driverId,
    required this.booked,
    required this.createdAt,
    required this.currentLatitude,
    required this.currentLongitude,
    required this.onlineStatus,
    required this.sharedBooking,
    required this.updatedAt,
    this.requestDateAndTime,
    this.requestStatus,
    required this.distance,
    required this.estimatedPrice,
    required this.estimatedTime,
    required this.faresByLocation,
    this.serviceType,
    this.carType,
  });

  factory DriverData.fromJson(Map<String, dynamic> json) {
    final created =
        _asDate(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final updated =
        _asDate(json['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);

    // driverId can theoretically be null; provide a safe empty object
    final drv =
        (json['driverId'] is Map<String, dynamic>)
            ? DriverDetails.fromJson(json['driverId'] as Map<String, dynamic>)
            : DriverDetails.empty();

    return DriverData(
      id: _asString(json['_id']),
      driverId: drv,
      booked: json['booked'] == true,
      createdAt: created,
      currentLatitude: _asDouble(json['currentLatitude']),
      currentLongitude: _asDouble(json['currentLongitude']),
      onlineStatus: json['onlineStatus'] == true,
      sharedBooking: json['sharedBooking'] == true,
      updatedAt: updated,
      requestDateAndTime: _asDate(json['requestDateAndTime']),
      requestStatus:
          json['requestStatus'] == null
              ? null
              : _asString(json['requestStatus']),
      distance: _asDouble(json['distance']),
      estimatedPrice: _asString(
        json['estimatedPrice'],
      ), // API gives "1315.52 - 3337.60"
      estimatedTime: _asInt(json['estimatedTime']),
      faresByLocation:
          (json['faresByLocation'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(EstimateFareByLocation.fromJson)
              .toList(),
      serviceType:
          _asString(json['serviceType'], def: '').isEmpty
              ? null
              : _asString(json['serviceType']),
      carType:
          _asString(json['carType'], def: '').isEmpty
              ? null
              : _asString(json['carType']),
    );
  }
}

class DriverDetails {
  final String id;
  final String firstName;
  final String lastName;
  final String? carBrand;
  final String? carModel;
  final String? carType;
  final String? serviceType;

  DriverDetails({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.carBrand,
    this.carModel,
    this.carType,
    this.serviceType,
  });

  factory DriverDetails.fromJson(Map<String, dynamic> json) {
    return DriverDetails(
      id: _asString(json['_id']),
      firstName: _asString(json['firstName']),
      lastName: _asString(json['lastName']),
      carBrand:
          _asString(json['carBrand'], def: '').isEmpty
              ? null
              : _asString(json['carBrand']),
      carModel:
          _asString(json['carModel'], def: '').isEmpty
              ? null
              : _asString(json['carModel']),
      carType:
          _asString(json['carType'], def: '').isEmpty
              ? null
              : _asString(json['carType']),
      serviceType:
          _asString(json['serviceType'], def: '').isEmpty
              ? null
              : _asString(json['serviceType']),
    );
  }

  factory DriverDetails.empty() =>
      DriverDetails(id: '', firstName: '', lastName: '');
}

class EstimateFareByLocation {
  final String locationId;
  final String locationName;
  final double baseFare;
  final double distanceFare;
  final double timeFare;
  final double pickupFare;
  final double bookingFee;
  final double subtotal;
  final double estimatedPrice;
  final PricingInsights? pricingInsights;

  EstimateFareByLocation({
    required this.locationId,
    required this.locationName,
    required this.baseFare,
    required this.distanceFare,
    required this.timeFare,
    required this.pickupFare,
    required this.bookingFee,
    required this.subtotal,
    required this.estimatedPrice,
    this.pricingInsights,
  });

  factory EstimateFareByLocation.fromJson(Map<String, dynamic> json) {
    return EstimateFareByLocation(
      locationId: _asString(json['locationId']),
      locationName: _asString(json['locationName']),
      baseFare: _asDouble(json['baseFare']),
      distanceFare: _asDouble(json['distanceFare']),
      timeFare: _asDouble(json['timeFare']),
      pickupFare: _asDouble(json['pickupFare']),
      bookingFee: _asDouble(json['bookingFee']),
      subtotal: _asDouble(json['subtotal']),
      estimatedPrice: _asDouble(json['estimatedPrice']),
      pricingInsights:
          json['pricingInsights'] is Map<String, dynamic>
              ? PricingInsights.fromJson(json['pricingInsights'])
              : null,
    );
  }
}
