import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hopper/Presentation/BookRide/utils/trusted_contacts_store.dart';

/// Standalone "Setup Safety" hub opened from the home safety banner (deepLink
/// `safety`). Lets the rider manage trusted contacts (who receive their live
/// trip link during a ride) and reach the emergency / SOS number — all before
/// a ride even starts. Local-first (TrustedContactsStore) so it never depends on
/// a network call to function.
class SafetySetupScreen extends StatefulWidget {
  const SafetySetupScreen({super.key});

  @override
  State<SafetySetupScreen> createState() => _SafetySetupScreenState();
}

class _SafetySetupScreenState extends State<SafetySetupScreen> {
  static const Color _ink = Color(0xFF161A2E);
  static const Color _amber = Color(0xFFE79700);
  static const Color _green = Color(0xFF12B76A);
  static const Color _red = Color(0xFFE5484D);

  final TrustedContactsStore _store = const TrustedContactsStore();
  List<TrustedContact> _contacts = const [];
  String _sos = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _store.load();
    String sos = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      sos = (prefs.getString('sosNumber') ?? '').trim();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _contacts = list;
      _sos = sos;
      _loading = false;
    });
  }

  Future<void> _removeContact(String phone) async {
    final updated = await _store.remove(phone);
    if (!mounted) return;
    setState(() => _contacts = updated);
  }

  Future<void> _callSos() async {
    if (_sos.isEmpty) return;
    try {
      await launchUrl(
        Uri(scheme: 'tel', path: _sos),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  Future<void> _openAddContact() async {
    if (_contacts.length >= TrustedContactsStore.maxContacts) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You can add up to ${TrustedContactsStore.maxContacts} contacts',
          ),
        ),
      );
      return;
    }
    final added = await showModalBottomSheet<TrustedContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddContactSheet(),
    );
    if (added == null) return;
    final saved = await _store.add(added);
    if (!mounted) return;
    setState(() => _contacts = saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F7FB),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Safety',
          style: TextStyle(
            color: _ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
              children: [
                _heroCard(),
                const SizedBox(height: 20),
                _trustedContactsSection(),
                const SizedBox(height: 20),
                _emergencySection(),
              ],
            ),
    );
  }

  Widget _heroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_ink, Color(0xFF2A3050)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            height: 52,
            width: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_rounded, color: _amber, size: 28),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ride with peace of mind',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Add trusted contacts to share your live trip, and reach '
                  'emergency help in one tap.',
                  style: TextStyle(
                    color: Color(0xFFC7CBDA),
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _trustedContactsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Trusted contacts',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _openAddContact,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _ink,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: _amber, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Add',
                        style: TextStyle(
                          color: _amber,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_contacts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.group_add_rounded,
                    color: Colors.grey.shade400,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No trusted contacts yet. Add people who should get your '
                      'live trip link during a ride.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ...List.generate(_contacts.length, (i) {
              final c = _contacts[i];
              final initial =
                  c.name.trim().isNotEmpty ? c.name.trim()[0].toUpperCase() : '#';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      height: 40,
                      width: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name.trim().isEmpty ? 'Contact' : c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            c.phone,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: _red,
                        size: 22,
                      ),
                      onPressed: () => _removeContact(c.phone),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _emergencySection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Emergency',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sos_rounded, color: _red, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sos.isEmpty ? 'Emergency helpline' : _sos,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _sos.isEmpty
                          ? 'Not configured yet'
                          : 'Tap to call for immediate help',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (_sos.isNotEmpty)
                GestureDetector(
                  onTap: _callSos,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: _red,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.call_rounded, color: Colors.white, size: 15),
                        SizedBox(width: 6),
                        Text(
                          'Call',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'During a ride you can also share your live trip and call for help '
            'from the in-trip safety toolkit.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet to add a trusted contact (name + phone). Pops a [TrustedContact]
/// on save, or null on cancel.
class _AddContactSheet extends StatefulWidget {
  const _AddContactSheet();

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  static const Color _ink = Color(0xFF161A2E);

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    if (phone.replaceAll(RegExp(r'[^0-9]'), '').length < 7) {
      setState(() => _error = 'Enter a valid phone number');
      return;
    }
    Navigator.pop(context, TrustedContact(name: name, phone: phone));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D5DD),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Add trusted contact',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 16),
            _field(_nameCtrl, 'Name', TextInputType.name),
            const SizedBox(height: 12),
            _field(
              _phoneCtrl,
              'Phone number',
              TextInputType.phone,
              formatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFE5484D), fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _ink,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Save contact',
                  style: TextStyle(
                    color: Color(0xFFE79700),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String hint,
    TextInputType type, {
    List<TextInputFormatter>? formatters,
  }) {
    return TextField(
      controller: c,
      keyboardType: type,
      inputFormatters: formatters,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF3F5F9),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _ink, width: 1.4),
        ),
      ),
    );
  }
}
