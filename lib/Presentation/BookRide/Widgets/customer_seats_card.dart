import 'package:flutter/material.dart';

/// Shows the customer their chosen seat on the LIVE shared-ride screen.
///
/// Self-contained (no external seat widget) and used ONLY on the live tracking
/// screen — the seat SELECTION screen keeps its original UI. Compact by default
/// (a "Your seat · N" header so the seat is always visible at a glance); tap to
/// expand a small top-view car layout with the customer's seat highlighted.
/// Fixed 4-seat car: seat 1 = driver, seats 2-4 = passengers.
class CustomerSeatsCard extends StatefulWidget {
  /// Seat numbers this customer booked (e.g. [2] or [3, 4]).
  final List<int> mySeats;
  const CustomerSeatsCard({super.key, required this.mySeats});

  @override
  State<CustomerSeatsCard> createState() => _CustomerSeatsCardState();
}

class _CustomerSeatsCardState extends State<CustomerSeatsCard> {
  bool _expanded = false;

  static const _tealFill = Color(0xFF1D9E75);
  static const _tealDark = Color(0xFF0F6E56);
  static const _tealLight = Color(0xFFE1F5EE);
  static const _neutralFill = Color(0xFFF1EFE8);
  static const _neutralBorder = Color(0xFFB4B2A9);
  static const _neutralText = Color(0xFF5F5E5A);

  @override
  Widget build(BuildContext context) {
    final mine = widget.mySeats.where((n) => n >= 2 && n <= 4).toSet();
    final mySorted = mine.toList()..sort();
    final label = mySorted.isEmpty
        ? 'Your seat'
        : mySorted.length == 1
            ? 'Your seat · ${mySorted.first}'
            : 'Your seats · ${mySorted.join(", ")}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.event_seat, size: 20, color: _tealFill),
                  const SizedBox(width: 10),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: _neutralText,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: Center(child: _carLayout(mine)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _carLayout(Set<int> mine) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 9,
            decoration: const BoxDecoration(
              color: _neutralBorder,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [_seat(1, mine), _seat(2, mine)],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [_seat(3, mine), _seat(4, mine)],
          ),
        ],
      ),
    );
  }

  Widget _seat(int number, Set<int> mine) {
    final bool isDriver = number == 1;
    final bool isMine = mine.contains(number);

    Color fill;
    Color border;
    double borderWidth;
    Widget center;
    String caption;
    Color captionColor;

    if (isDriver) {
      fill = _neutralFill;
      border = _neutralBorder;
      borderWidth = 0.5;
      center = const Icon(Icons.airline_seat_recline_normal,
          size: 22, color: _neutralText);
      caption = 'Driver';
      captionColor = _neutralText;
    } else if (isMine) {
      fill = _tealFill;
      border = _tealDark;
      borderWidth = 2;
      center = Stack(
        alignment: Alignment.center,
        children: [
          Text('$number',
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w600, color: Colors.white)),
          const Positioned(
              top: 5, right: 6, child: Icon(Icons.check, size: 12, color: Colors.white)),
        ],
      );
      caption = 'Your seat';
      captionColor = _tealDark;
    } else {
      fill = _tealLight;
      border = _neutralBorder;
      borderWidth = 0.5;
      center = Text('$number',
          style: const TextStyle(
              fontSize: 19, fontWeight: FontWeight.w600, color: _neutralText));
      caption = 'Seat $number';
      captionColor = _neutralText;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 6,
          decoration: BoxDecoration(
            color: border,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: 58,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: border, width: borderWidth),
          ),
          child: center,
        ),
        const SizedBox(height: 5),
        Text(caption, style: TextStyle(fontSize: 11, color: captionColor)),
      ],
    );
  }
}
