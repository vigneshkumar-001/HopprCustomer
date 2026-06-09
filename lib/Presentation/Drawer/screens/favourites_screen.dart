import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
import 'package:hopper/Presentation/OnBoarding/utils/saved_addresses_store.dart';
import 'package:hopper/uitls/map/search_loaction.dart';

/// Uber-style favourite places (Home / Work / saved places). Local-first —
/// reuses the same [SavedAddressesStore] the package flow already uses, so
/// places saved here also show up while booking.
class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  static const Color _accent = Color(0xFF2563EB);

  final SavedAddressesStore _store = const SavedAddressesStore();
  List<SavedAddressEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _store.load();
    if (!mounted) return;
    setState(() {
      _entries = _store.normalized(list);
      _loading = false;
    });
  }

  SavedAddressEntry? _entryForLabel(String label) {
    for (final e in _entries) {
      if (e.label.toLowerCase() == label.toLowerCase()) return e;
    }
    return null;
  }

  String _addressText(SavedAddressEntry e) {
    if (e.address.mapAddress.trim().isNotEmpty) return e.address.mapAddress;
    if (e.address.address.trim().isNotEmpty) return e.address.address;
    return '${e.address.latitude}, ${e.address.longitude}';
  }

  Future<void> _pickAndSave({String? forcedLabel}) async {
    // Reuse the existing, tested place picker (search -> map -> details).
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(builder: (_) => const CommonLocationSearch()),
    );
    if (!mounted || result is! Map) return;
    final loc = result['location'];
    if (loc is! LatLng) return;

    final address = AddressModel(
      name: (result['name'] ?? '').toString(),
      phone: (result['phone'] ?? '').toString(),
      address: (result['address'] ?? '').toString(),
      landmark: (result['landmark'] ?? '').toString(),
      mapAddress: (result['mapAddress'] ?? '').toString(),
      latitude: loc.latitude,
      longitude: loc.longitude,
    );

    final label = forcedLabel ?? await _askLabel();
    if (label == null) return; // cancelled

    await _store.markUsed(address, label: label);
    await _load();
  }

  Future<String?> _askLabel() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        Widget tile(String label, IconData icon) => ListTile(
          leading: Icon(icon, color: _accent),
          title: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          onTap: () => Navigator.pop(ctx, label),
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),
              const Text(
                'Save as',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              tile('Home', Icons.home_rounded),
              tile('Work', Icons.work_rounded),
              tile('Other', Icons.star_rounded),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmRemove(SavedAddressEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Remove place'),
        content: Text('Remove "${e.label}" from favourites?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _store.remove(e.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = _entryForLabel('Home');
    final work = _entryForLabel('Work');
    final others = _entries
        .where((e) => e.id != home?.id && e.id != work?.id)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: Colors.white,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 16, 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back, color: Colors.black),
                        ),
                        const SizedBox(width: 2),
                        const Text(
                          'Favourites',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: const Color(0xFFEDEFF3)),
                ],
              ),
            ),

            Expanded(
              child: _loading
                  ? Center(child: AppLoader.circularLoader())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      children: [
                        _quickTile('Home', Icons.home_rounded, home),
                        const SizedBox(height: 10),
                        _quickTile('Work', Icons.work_rounded, work),
                        if (others.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          const Text(
                            'Saved places',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...others.map(_placeRow),
                        ],
                        const SizedBox(height: 18),
                        _addButton(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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

  Widget _quickTile(String label, IconData icon, SavedAddressEntry? entry) {
    final isSet = entry != null;
    return _card(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _pickAndSave(forcedLabel: label),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: _accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isSet ? _addressText(entry) : 'Tap to add $label',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isSet ? Colors.black54 : _accent,
                          fontWeight:
                              isSet ? FontWeight.w400 : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSet)
                  IconButton(
                    onPressed: () => _confirmRemove(entry),
                    icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  )
                else
                  const Icon(Icons.add, color: _accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeRow(SavedAddressEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFE79700),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _addressText(entry),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _confirmRemove(entry),
                icon: const Icon(Icons.close, color: Colors.grey, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: () => _pickAndSave(),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: const BorderSide(color: _accent),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text(
          'Add a place',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
