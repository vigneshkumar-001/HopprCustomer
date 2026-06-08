import 'package:flutter/material.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:intl/intl.dart';

/// Vehicle image for a ride based on its car type.
/// Sedan -> sedan asset, Luxury -> luxury asset, Bike -> bike, else generic car.
String vehicleAssetForType(String? carType) {
  final t = (carType ?? '').trim().toLowerCase();
  if (t.contains('sedan')) return AppImages.sedan;
  if (t.contains('luxur') || t.contains('premium') || t.contains('suv')) {
    return AppImages.luxuryCar;
  }
  if (t.contains('bike') ||
      t.contains('two') ||
      t.contains('moto') ||
      t.contains('scooter')) {
    return AppImages.bikeImage;
  }
  return AppImages.carImage;
}

String _ordinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  switch (day % 10) {
    case 1:
      return '${day}st';
    case 2:
      return '${day}nd';
    case 3:
      return '${day}rd';
    default:
      return '${day}th';
  }
}

/// "5th April 2026 • 01:06 PM"
String formatRideDateLong(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  final day = _ordinal(dt.day);
  final month = DateFormat('MMMM').format(dt);
  final time = DateFormat('hh:mm a').format(dt);
  return '$day $month ${dt.year} • $time';
}

/// "5th Apr 2026 • 01:06 PM" (compact for list rows)
String formatRideDateShort(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  final day = _ordinal(dt.day);
  final month = DateFormat('MMM').format(dt);
  final time = DateFormat('hh:mm a').format(dt);
  return '$day $month ${dt.year} • $time';
}

/// "5th Apr 01:14 PM" (used on the pickup/drop timeline)
String formatTimelineStamp(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  final day = _ordinal(dt.day);
  final month = DateFormat('MMM').format(dt);
  final time = DateFormat('hh:mm a').format(dt);
  return '$day $month $time';
}

/// "Completed" for SUCCESS, else the raw status (title-cased).
String prettyStatus(String? status) {
  final s = (status ?? '').trim();
  if (s.toUpperCase() == 'SUCCESS') return 'Completed';
  if (s.isEmpty) return '';
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

/// Status accent colour. Falls back to a green for completed.
Color statusColor(String? hex, {Color fallback = const Color(0xFF009721)}) {
  final h = (hex ?? '').trim().replaceAll('#', '');
  if (h.length == 6) {
    final v = int.tryParse('0xFF$h');
    if (v != null) return Color(v);
  }
  return fallback;
}
