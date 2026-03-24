import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/address_models.dart';

class SavedAddressEntry {
  final String id;
  final AddressModel address;
  final String label; // Home / Office / Work / Other
  final bool isFavorite;
  final int lastUsedAtEpochMs;

  const SavedAddressEntry({
    required this.id,
    required this.address,
    required this.label,
    required this.isFavorite,
    required this.lastUsedAtEpochMs,
  });

  factory SavedAddressEntry.fromJson(Map<String, dynamic> json) {
    return SavedAddressEntry(
      id: (json['id'] ?? '').toString(),
      address: AddressModel(
        name: (json['name'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        address: (json['address'] ?? '').toString(),
        landmark: (json['landmark'] ?? '').toString(),
        mapAddress: (json['mapAddress'] ?? '').toString(),
        latitude: (json['latitude'] ?? 0).toDouble(),
        longitude: (json['longitude'] ?? 0).toDouble(),
      ),
      label: (json['label'] ?? 'Other').toString(),
      isFavorite: json['isFavorite'] == true,
      lastUsedAtEpochMs: ((json['lastUsedAtEpochMs'] ?? 0) as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': address.name,
      'phone': address.phone,
      'address': address.address,
      'landmark': address.landmark,
      'mapAddress': address.mapAddress,
      'latitude': address.latitude,
      'longitude': address.longitude,
      'label': label,
      'isFavorite': isFavorite,
      'lastUsedAtEpochMs': lastUsedAtEpochMs,
    };
  }

  SavedAddressEntry copyWith({
    AddressModel? address,
    String? label,
    bool? isFavorite,
    int? lastUsedAtEpochMs,
  }) {
    return SavedAddressEntry(
      id: id,
      address: address ?? this.address,
      label: label ?? this.label,
      isFavorite: isFavorite ?? this.isFavorite,
      lastUsedAtEpochMs: lastUsedAtEpochMs ?? this.lastUsedAtEpochMs,
    );
  }
}

class SavedAddressesStore {
  static const _prefsKey = 'package_saved_addresses_v1';
  static const int _maxEntries = 15;
  static const List<String> labels = <String>[
    'Home',
    'Office',
    'Work',
    'Other',
  ];

  const SavedAddressesStore();

  int _labelPriority(String label) {
    final normalized = label.trim().toLowerCase();
    if (normalized == 'home') return 0;
    if (normalized == 'office') return 1;
    if (normalized == 'work') return 2;
    return 3; // Other / unknown
  }

  String _normalizeLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return 'Other';
    final lower = trimmed.toLowerCase();
    if (lower == 'home') return 'Home';
    if (lower == 'office') return 'Office';
    if (lower == 'work') return 'Work';
    return 'Other';
  }

  bool _isPinnedLabel(String label) => _labelPriority(label) != 3;

  String idFor(AddressModel address) {
    final raw =
        '${address.latitude.toStringAsFixed(6)}|${address.longitude.toStringAsFixed(6)}|${address.address}|${address.mapAddress}|${address.phone}';
    return base64UrlEncode(utf8.encode(raw));
  }

  Future<List<SavedAddressEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return <SavedAddressEntry>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <SavedAddressEntry>[];

      return decoded
          .whereType<Map>()
          .map((e) => SavedAddressEntry.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return <SavedAddressEntry>[];
    }
  }

  Future<void> save(List<SavedAddressEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
  }

  List<SavedAddressEntry> normalized(List<SavedAddressEntry> entries) {
    final byId = <String, SavedAddressEntry>{};
    for (final rawEntry in entries) {
      if (rawEntry.id.isEmpty) continue;
      final entry = rawEntry.copyWith(label: _normalizeLabel(rawEntry.label));
      final existing = byId[entry.id];
      if (existing == null) {
        byId[entry.id] = entry;
        continue;
      }
      final mergedIsFavorite = existing.isFavorite || entry.isFavorite;
      final mergedLabel =
          _labelPriority(existing.label) <= _labelPriority(entry.label)
              ? existing.label
              : entry.label;
      if (existing.lastUsedAtEpochMs >= entry.lastUsedAtEpochMs) {
        byId[entry.id] = existing.copyWith(
          isFavorite: mergedIsFavorite,
          label: mergedLabel,
        );
      } else {
        byId[entry.id] = entry.copyWith(
          isFavorite: mergedIsFavorite,
          label: mergedLabel,
        );
      }
    }

    final list =
        byId.values.toList()..sort((a, b) {
          final lp = _labelPriority(a.label).compareTo(_labelPriority(b.label));
          if (lp != 0) return lp;
          if (a.isFavorite != b.isFavorite) {
            return a.isFavorite ? -1 : 1;
          }
          return b.lastUsedAtEpochMs.compareTo(a.lastUsedAtEpochMs);
        });

    if (list.length > _maxEntries) return list.take(_maxEntries).toList();
    return list;
  }

  Future<List<SavedAddressEntry>> markUsed(
    AddressModel address, {
    String? label,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = await load();
    final id = idFor(address);
    final existing = current.firstWhere(
      (e) => e.id == id,
      orElse:
          () => SavedAddressEntry(
            id: id,
            address: address,
            label: 'Other',
            isFavorite: false,
            lastUsedAtEpochMs: 0,
          ),
    );

    final normalizedLabel = _normalizeLabel(label ?? existing.label);
    final updated =
        current.where((e) => e.id != id).where((e) {
            if (!_isPinnedLabel(normalizedLabel)) return true;
            // Only allow one pinned label (Home/Office/Work) at a time.
            return _normalizeLabel(e.label) != normalizedLabel;
          }).toList()
          ..add(
            SavedAddressEntry(
              id: id,
              address: address,
              label: normalizedLabel,
              isFavorite: existing.isFavorite,
              lastUsedAtEpochMs: now,
            ),
          );

    final normalizedList = normalized(updated);
    await save(normalizedList);
    return normalizedList;
  }

  Future<List<SavedAddressEntry>> setLabel(String id, String label) async {
    final current = await load();
    final normalizedLabel = _normalizeLabel(label);

    final updated =
        current
            .where((e) {
              if (!_isPinnedLabel(normalizedLabel)) return true;
              return _normalizeLabel(e.label) != normalizedLabel || e.id == id;
            })
            .map((e) {
              if (e.id != id) return e;
              return e.copyWith(label: normalizedLabel);
            })
            .toList();

    final normalizedList = normalized(updated);
    await save(normalizedList);
    return normalizedList;
  }

  Future<List<SavedAddressEntry>> toggleFavorite(String id) async {
    final current = await load();
    final updated =
        current.map((e) {
          if (e.id != id) return e;
          return e.copyWith(isFavorite: !e.isFavorite);
        }).toList();
    final normalizedList = normalized(updated);
    await save(normalizedList);
    return normalizedList;
  }

  Future<List<SavedAddressEntry>> remove(String id) async {
    final current = await load();
    final updated = current.where((e) => e.id != id).toList();
    final normalizedList = normalized(updated);
    await save(normalizedList);
    return normalizedList;
  }
}
