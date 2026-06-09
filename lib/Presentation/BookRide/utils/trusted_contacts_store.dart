import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A single trusted/emergency contact the rider can share their live trip with.
class TrustedContact {
  final String name;
  final String phone;

  const TrustedContact({required this.name, required this.phone});

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};

  factory TrustedContact.fromJson(Map<String, dynamic> j) => TrustedContact(
    name: (j['name'] ?? '').toString(),
    phone: (j['phone'] ?? '').toString(),
  );
}

/// Local-first store for the rider's trusted contacts. (No backend yet — these
/// live on the device, used to one-tap share the live trip link.)
class TrustedContactsStore {
  static const _key = 'trusted_contacts_v1';
  static const int maxContacts = 5;

  const TrustedContactsStore();

  Future<List<TrustedContact>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return <TrustedContact>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <TrustedContact>[];
      return decoded
          .whereType<Map>()
          .map((e) => TrustedContact.fromJson(e.cast<String, dynamic>()))
          .where((c) => c.phone.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return <TrustedContact>[];
    }
  }

  Future<void> _save(List<TrustedContact> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<TrustedContact>> add(TrustedContact contact) async {
    final list = await load();
    // De-dupe by phone; keep newest at the front, cap at maxContacts.
    list.removeWhere((c) => c.phone.trim() == contact.phone.trim());
    list.insert(0, contact);
    final capped = list.take(maxContacts).toList();
    await _save(capped);
    return capped;
  }

  Future<List<TrustedContact>> remove(String phone) async {
    final list = await load();
    list.removeWhere((c) => c.phone.trim() == phone.trim());
    await _save(list);
    return list;
  }
}
