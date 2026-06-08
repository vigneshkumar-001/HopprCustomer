import 'package:flutter/material.dart';

/// Shared Hero tag for the "Search Destination" bar. The home screen's search
/// field and the search screen's search card both use this tag so the bar
/// smoothly morphs between the two screens.
const String kSearchHeroTag = 'home-destination-search-hero';

/// Neutral pill rendered DURING the hero flight, so the morph stays smooth and
/// never overflows regardless of what the source/destination actually contain
/// (the home field is short, the search card is taller with two inputs).
Widget searchHeroFlight(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  return Material(
    color: Colors.transparent,
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: Colors.grey),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Search Destination',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
}
