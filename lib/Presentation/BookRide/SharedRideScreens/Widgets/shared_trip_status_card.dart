import 'package:flutter/material.dart';
import 'package:hopper/Presentation/BookRide/Models/shared_my_state.dart';

/// Brand blue — used ONLY on the map (route, legend). The bottom sheet uses
/// black accents (kSheetInk), per the product's Uber-style look.
const Color kSharedBlue = Color(0xFF006FD0);
const Color kSheetInk = Color(0xFF111418);
const Color _kInk = Color(0xFF14213A);
const Color _kMuted = Color(0xFF6B7280);

/// Clean, reusable status card for the shared-ride bottom sheet.
///
/// Mirrors the product mockup: a small blue overline ("ON TRIP" / "YOU ARE NEXT"
/// …), a bold title, this rider's own detail line, a "Seat N" pill on the RIGHT,
/// and — when known — the privacy-safe horizontal stop timeline underneath.
///
/// Stateless + const-friendly so it repaints cheaply while the sheet scrolls.
/// It renders ONLY the data it is given; all ride logic stays in the screen.
class SharedTripStatusCard extends StatelessWidget {
  final String overline;
  final String title;
  final String detail;
  final IconData icon;
  final List<int> seats;
  final List<SharedPrivacyStop> stops;

  /// Slightly stronger accent for action stages (driver arrived / OTP).
  final bool emphasise;

  const SharedTripStatusCard({
    super.key,
    required this.overline,
    required this.title,
    required this.detail,
    required this.icon,
    this.seats = const [],
    this.stops = const [],
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: emphasise
                ? kSheetInk.withOpacity(0.30)
                : Colors.black.withOpacity(0.06),
            width: emphasise ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: kSheetInk.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: kSheetInk, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (overline.trim().isNotEmpty)
                        Text(
                          overline.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: kSheetInk,
                          ),
                        ),
                      const SizedBox(height: 3),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1.18,
                          color: Color(0xFF14213A),
                        ),
                      ),
                      if (detail.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          detail,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (seats.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  _SeatPill(seats: seats),
                ],
              ],
            ),
            if (stops.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: Colors.black.withOpacity(0.06)),
              const SizedBox(height: 12),
              SharedStopTimeline(stops: stops),
            ],
          ],
        ),
      ),
    );
  }
}

class _SeatPill extends StatelessWidget {
  final List<int> seats;
  const _SeatPill({required this.seats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: kSheetInk.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_seat_rounded, size: 14, color: kSheetInk),
          const SizedBox(width: 6),
          Text(
            seats.length == 1 ? 'Seat ${seats.first}' : 'Seat ${seats.join(', ')}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: kSheetInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean two-stop card for the bottom sheet: this rider's pickup and drop with a
/// dotted connector and a status/ETA on the right (mockup style). Shows ONLY the
/// rider's OWN addresses — never another passenger's. Drops into an existing
/// card (no outer fill of its own).
class SharedStopsCard extends StatelessWidget {
  final String pickupAddress;
  final String dropAddress;
  final String pickupTrailing;
  final String dropTrailing;
  final Color pickupTrailingColor;
  final VoidCallback? onTapPickup;
  final VoidCallback? onTapDrop;

  const SharedStopsCard({
    super.key,
    required this.pickupAddress,
    required this.dropAddress,
    this.pickupTrailing = '',
    this.dropTrailing = '',
    this.pickupTrailingColor = _kMuted,
    this.onTapPickup,
    this.onTapDrop,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 15, 12, 15),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(
            icon: const Icon(Icons.trip_origin, size: 18, color: _kInk),
            label: 'Pickup stop',
            address: pickupAddress,
            trailing: pickupTrailing,
            trailingColor: pickupTrailingColor,
            onTap: onTapPickup,
          ),
          // Dotted connector — centered under the 22px icon column so it lines up
          // exactly from the pickup icon down to the drop pin (no half gap).
          SizedBox(
            height: 26,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      5,
                      (_) => Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _row(
            icon: const Icon(Icons.location_on, size: 20, color: kSheetInk),
            label: 'Your drop',
            address: dropAddress,
            trailing: dropTrailing,
            trailingColor: kSheetInk,
            onTap: onTapDrop,
          ),
        ],
      ),
    );
  }

  Widget _row({
    required Widget icon,
    required String label,
    required String address,
    required String trailing,
    required Color trailingColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 22, child: Center(child: icon)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _kMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  address.trim().isEmpty ? '—' : address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: _kInk,
                  ),
                ),
              ],
            ),
          ),
          if (trailing.trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              trailing,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: trailingColor,
              ),
            ),
          ],
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right_rounded, size: 18, color: _kMuted),
        ],
      ),
    );
  }
}

/// Privacy-safe horizontal timeline of the remaining stops up to (and including)
/// MINE. Uses only the generic labels from [SharedPrivacyStop] — never another
/// rider's identity. My stop(s) are blue; other riders' stops stay neutral grey.
/// Horizontally scrollable so a long queue never overflows.
class SharedStopTimeline extends StatelessWidget {
  final List<SharedPrivacyStop> stops;
  const SharedStopTimeline({super.key, required this.stops});

  static bool _isMine(SharedPrivacyStop s) =>
      s.type == 'MY_PICKUP' || s.type == 'MY_DROP';

  @override
  Widget build(BuildContext context) {
    final grey = Colors.grey.shade400;
    final children = <Widget>[];
    for (int i = 0; i < stops.length; i++) {
      final s = stops[i];
      final mine = _isMine(s);
      children.add(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: mine ? 16 : 13,
              height: mine ? 16 : 13,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: mine ? kSharedBlue : Colors.white,
                border: Border.all(
                  color: mine ? kSharedBlue : grey,
                  width: mine ? 0 : 2.4,
                ),
              ),
              child: mine
                  ? const Icon(Icons.check_rounded,
                      size: 9.5, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 64,
              child: Text(
                s.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: mine ? FontWeight.w700 : FontWeight.w500,
                  color: mine ? _kInk : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      );
      if (i < stops.length - 1) {
        // The segment LEADING to my stop is solid blue ("your route"); segments
        // to another rider's stop stay grey ("serving another rider").
        final nextMine = _isMine(stops[i + 1]);
        children.add(
          Container(
            width: 26,
            height: 2.5,
            margin: const EdgeInsets.only(top: 7),
            color: nextMine ? kSharedBlue : grey,
          ),
        );
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// Small map legend overlay: "Your route" (solid blue) vs "Serving another
/// rider" (grey dotted). Purely presentational — shown over the map when the
/// ride is shared so the two route styles are self-explanatory.
class SharedRouteLegend extends StatelessWidget {
  const SharedRouteLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kSharedBlue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Your route',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      3,
                      (_) => Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade500,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Serving another rider',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
