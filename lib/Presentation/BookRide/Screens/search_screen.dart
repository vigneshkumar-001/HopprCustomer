import 'dart:convert';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/BookRide/Screens/book_map_screen.dart';
import 'package:hopper/Presentation/BookRide/Screens/locate_on_map_screen.dart';
import 'package:hopper/uitls/map/search.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BookRideSearchScreen extends StatefulWidget {
  final bool? isPickup;
  final Map<String, dynamic>? pickupData;
  final Map<String, dynamic>? destinationData;
  final String? flag;

  const BookRideSearchScreen({
    super.key,
    this.isPickup,
    this.pickupData,
    this.destinationData,
    this.flag,
  });

  @override
  State<BookRideSearchScreen> createState() => _BookRideSearchScreenState();
}

class _BookRideSearchScreenState extends State<BookRideSearchScreen> {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destController = TextEditingController();

  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _destinationFocus = FocusNode();

  /// current field focus (true = pickup, false = destination)
  bool _isStartFieldFocused = true;

  /// live results for each field
  List<Map<String, dynamic>> _startSearchResults = [];
  List<Map<String, dynamic>> _destSearchResults = [];

  /// recent locations (encoded as String)
  List<String> _recentLocations = [];

  /// selected values
  Map<String, dynamic>? _pickup;
  Map<String, dynamic>? _destination;

  /// loader state for search
  bool _isSearching = false;

  /// debounce timer
  Timer? _debounce;

  /// result cache by query (separate caches for pickup / destination)
  final Map<String, List<Map<String, dynamic>>> _cachePickup = {};
  final Map<String, List<Map<String, dynamic>>> _cacheDestination = {};

  @override
  void initState() {
    super.initState();

    _isStartFieldFocused = widget.isPickup ?? true;

    // place initial values
    if (widget.pickupData != null) {
      _startController.text = widget.pickupData!['description'] ?? '';
      _pickup = widget.pickupData;
    }
    if (widget.destinationData != null) {
      _destController.text = widget.destinationData!['description'] ?? '';
      _destination = widget.destinationData;
    }

    // autofocus after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      (_isStartFieldFocused ? _pickupFocus : _destinationFocus).requestFocus();
    });

    _loadRecentLocations();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _startController.dispose();
    _destController.dispose();
    _pickupFocus.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  // -------- SEARCH (debounced + cached) --------

  void _onQueryChanged(String value) {
    // clear list if too short
    if (value.trim().length < 2) {
      setState(() {
        if (_isStartFieldFocused) {
          _startSearchResults = [];
        } else {
          _destSearchResults = [];
        }
        _isSearching = false;
      });
      _debounce?.cancel();
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final q = value.trim();

      // cache hit?
      final cache = _isStartFieldFocused ? _cachePickup : _cacheDestination;
      if (cache.containsKey(q)) {
        setState(() {
          if (_isStartFieldFocused) {
            _startSearchResults = cache[q]!;
          } else {
            _destSearchResults = cache[q]!;
          }
          _isSearching = false;
        });
        return;
      }

      setState(() => _isSearching = true);

      try {
        // You can enhance LocationHelper.searchPlaces to accept current location
        // to improve relevance. Here we just call it as-is.
        final results = await LocationHelper.searchPlaces(q);

        // store in cache
        cache[q] = results;

        if (!mounted) return;
        setState(() {
          if (_isStartFieldFocused) {
            _startSearchResults = results;
          } else {
            _destSearchResults = results;
          }
          _isSearching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _isSearching = false);
      }
    });
  }

  // -------- NAV / SELECT --------

  void _goToMapScreen() {
    final isFromMap = ModalRoute.of(context)?.settings.arguments == 'fromMap';

    if (isFromMap) {
      Navigator.pop(context, {
        'pickup': {
          'description': _pickup!['description'],
          'lat': _pickup!['lat'],
          'lng': _pickup!['lng'],
        },
        'destination': {
          'description': _destination!['description'],
          'lat': _destination!['lat'],
          'lng': _destination!['lng'],
        },
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => BookMapScreen(
                pickupData: _pickup!,
                destinationData: _destination!,
                pickupAddress: _pickup!['description'],
                destinationAddress: _destination!['description'],
              ),
        ),
      );
    }
  }

  void _handleSelection(Map<String, dynamic> item) {
    late final Map<String, dynamic> selectedMapData;

    if (item['location'] is LatLng) {
      selectedMapData = {
        'description': item['description'],
        'location': item['location'],
      };
    } else if (item['lat'] != null && item['lng'] != null) {
      selectedMapData = {
        'description': item['description'],
        'location': LatLng(item['lat'], item['lng']),
      };
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected location is invalid.')),
      );
      return;
    }

    final LatLng newLoc = selectedMapData['location'];

    // prevent ≤ 1km between pickup/destination
    if (_isStartFieldFocused && _destination?['location'] != null) {
      final LatLng destLoc = _destination!['location'];
      final distance = Geolocator.distanceBetween(
        newLoc.latitude,
        newLoc.longitude,
        destLoc.latitude,
        destLoc.longitude,
      );
      if (distance <= 1000) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pickup and drop cannot be the same or within 1 km.'),
          ),
        );
        _startController.clear();
        _pickup = null;
        return;
      }
    }

    if (!_isStartFieldFocused && _pickup?['location'] != null) {
      final LatLng pickupLoc = _pickup!['location'];
      final distance = Geolocator.distanceBetween(
        pickupLoc.latitude,
        pickupLoc.longitude,
        newLoc.latitude,
        newLoc.longitude,
      );
      if (distance <= 1000) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pickup and drop cannot be the same or within 1 km.'),
          ),
        );
        _destController.clear();
        _destination = null;
        return;
      }
    }

    setState(() {
      if (_isStartFieldFocused) {
        _startController.text = selectedMapData['description'];
        _pickup = selectedMapData;
        _startSearchResults.clear();
      } else {
        _destController.text = selectedMapData['description'];
        _destination = selectedMapData;
        _destSearchResults.clear();
      }
    });

    _saveRecentLocation(selectedMapData['description'], newLoc);

    if (_pickup != null && _destination != null) {
      _goToMapScreen();
    }
  }

  Future<void> _locateOnMap() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => const LocateOnMapScreen(
              searchQuery: '',
              type:
                  'pickup', // this field isn’t actually used by that screen’s UI
              cameFromPackage: false,
            ),
      ),
    );

    if (result != null &&
        result['mapAddress'] != null &&
        result['location'] is LatLng) {
      final LatLng latLng = result['location'];

      // 1 km check
      if (_isStartFieldFocused && _destination?['location'] != null) {
        final LatLng dest = _destination!['location'];
        final distance = Geolocator.distanceBetween(
          latLng.latitude,
          latLng.longitude,
          dest.latitude,
          dest.longitude,
        );
        if (distance <= 1000) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pickup and drop cannot be the same or within 1 km.',
              ),
            ),
          );
          _startController.clear();
          _pickup = null;
          return;
        }
      }
      if (!_isStartFieldFocused && _pickup?['location'] != null) {
        final LatLng pickup = _pickup!['location'];
        final distance = Geolocator.distanceBetween(
          pickup.latitude,
          pickup.longitude,
          latLng.latitude,
          latLng.longitude,
        );
        if (distance <= 1000) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pickup and drop cannot be the same or within 1 km.',
              ),
            ),
          );
          _destController.clear();
          _destination = null;
          return;
        }
      }

      final selectedMapData = {
        'description': result['mapAddress'],
        'location': latLng,
      };

      setState(() {
        if (_isStartFieldFocused) {
          _startController.text = result['mapAddress'];
          _pickup = selectedMapData;
          _startSearchResults.clear();
        } else {
          _destController.text = result['mapAddress'];
          _destination = selectedMapData;
          _destSearchResults.clear();
        }
      });

      _saveRecentLocation(result['mapAddress'], latLng);

      if (_pickup != null && _destination != null) {
        _goToMapScreen();
      }
    }
  }

  // -------- RECENTS (SharedPreferences) --------

  Future<void> _saveRecentLocation(String description, LatLng location) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> recent = prefs.getStringList('recent_locations') ?? [];

    final newItem = jsonEncode({
      'description': description,
      'lat': location.latitude,
      'lng': location.longitude,
    });

    recent.removeWhere((item) {
      try {
        final decoded = jsonDecode(item);
        return decoded['description'] == description;
      } catch (_) {
        return item == description;
      }
    });

    recent.insert(0, newItem);
    if (recent.length > 5) recent = recent.sublist(0, 5);

    await prefs.setStringList('recent_locations', recent);
  }

  Future<void> _loadRecentLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final recentStrings = prefs.getStringList('recent_locations') ?? [];
    setState(() => _recentLocations = recentStrings);
  }

  @override
  Widget build(BuildContext context) {
    final resultsToShow =
        _isStartFieldFocused ? _startSearchResults : _destSearchResults;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (widget.flag != "bottomBar")
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Image.asset(
                              AppImages.backImage,
                              height: 19,
                              width: 19,
                            ),
                          ),
                        const SizedBox(width: 12),
                        CustomTextFields.textWithStyles600(
                          'Set pick up location',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // SEARCH CARD
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Column(
                            children: [
                              // --- PICKUP FIELD ---
                              CustomTextFields.plainTextField(
                                suffixIcon:
                                    _isStartFieldFocused &&
                                            _startController.text.isNotEmpty
                                        ? IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            _startController.clear();
                                            setState(() {
                                              _startSearchResults = [];
                                            });
                                          },
                                        )
                                        : null,
                                hintStyle: const TextStyle(fontSize: 11),
                                imgHeight: 15,
                                focusNode: _pickupFocus,
                                controller: _startController,
                                onChanged: _onQueryChanged,
                                onTap:
                                    () => setState(
                                      () => _isStartFieldFocused = true,
                                    ),
                                containerColor: AppColors.commonWhite,
                                leadingImage: AppImages.circleStart,
                                title: 'Search for an address or landmark',
                                readOnly: false,
                              ),

                              const Divider(
                                height: 10,
                                color: AppColors.containerColor,
                              ),

                              // --- DEST FIELD ---
                              CustomTextFields.plainTextField(
                                focusNode: _destinationFocus,
                                controller: _destController,
                                onChanged: _onQueryChanged,
                                onTap:
                                    () => setState(
                                      () => _isStartFieldFocused = false,
                                    ),
                                hintStyle: const TextStyle(fontSize: 11),
                                imgHeight: 16,
                                containerColor: AppColors.commonWhite,
                                leadingImage: AppImages.rectangleDest,
                                title: 'Enter destination',
                                readOnly: false,
                                suffixIcon:
                                    !_isStartFieldFocused &&
                                            _destController.text.isNotEmpty
                                        ? IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            _destController.clear();
                                            setState(() {
                                              _destSearchResults = [];
                                            });
                                          },
                                        )
                                        : null,
                              ),

                              // --- SINGLE loader at the bottom (for either field) ---
                              if (_isSearching)
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: LinearProgressIndicator(
                                    borderRadius: BorderRadius.circular(15),
                                    minHeight: 3,
                                    color: AppColors.commonBlack,
                                  ),
                                ),
                            ],
                          ),

                          Positioned(
                            left: 23,
                            top: 33,
                            bottom: 33,
                            child: Container(
                              width: 1.3,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            // RESULTS / RECENTS
            Expanded(
              child:
                  resultsToShow.isEmpty && _recentLocations.isNotEmpty
                      ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Recent locations',
                                style: TextStyle(color: Colors.grey),
                              ),
                              ..._recentLocations.map((locString) {
                                try {
                                  final locMap = jsonDecode(locString);
                                  return ListTile(
                                    leading: const Icon(
                                      Icons.history,
                                      size: 18,
                                      color: Colors.grey,
                                    ),
                                    title: Text(
                                      locMap['description'],
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    onTap: () {
                                      final selectedMapData = {
                                        'description': locMap['description'],
                                        'location': LatLng(
                                          locMap['lat'],
                                          locMap['lng'],
                                        ),
                                      };
                                      _handleSelection(selectedMapData);
                                    },
                                  );
                                } catch (_) {
                                  return ListTile(
                                    leading: const Icon(
                                      Icons.history,
                                      size: 18,
                                      color: Colors.grey,
                                    ),
                                    title: Text(
                                      locString,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    onTap: () {
                                      final selectedMapData = {
                                        'description': locString,
                                        'location': null,
                                      };
                                      _handleSelection(selectedMapData);
                                    },
                                  );
                                }
                              }),
                            ],
                          ),
                        ),
                      )
                      : resultsToShow.isNotEmpty
                      ? ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        itemCount: resultsToShow.length,
                        itemBuilder: (context, index) {
                          final item = resultsToShow[index];
                          return ListTile(
                            leading: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 19,
                                ),
                                const SizedBox(height: 4),
                                if (item['distance'] != null)
                                  Text(
                                    item['distance'],
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(
                              (item['description'] ?? '')
                                  .toString()
                                  .split(',')
                                  .first,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              item['description'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xff828284),
                              ),
                            ),
                            onTap: () => _handleSelection(item),
                          );
                        },
                      )
                      : const SizedBox.shrink(),
            ),

            AppButtons.button(
              hasBorder: true,
              fontSize: 14,
              borderColor: AppColors.containerColor,
              buttonColor: AppColors.commonWhite,
              textColor: AppColors.commonBlack,
              imagePath: AppImages.mapLocation,
              onTap: _locateOnMap,
              text: AppTexts.locateOnMap,
            ),
          ],
        ),
      ),
    );
  }
}

// import 'dart:convert';
// import 'package:geolocator/geolocator.dart';
// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:hopper/Core/Consents/app_colors.dart';
// import 'package:hopper/Core/Consents/app_texts.dart';
// import 'package:hopper/Core/Utility/app_buttons.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
// import 'package:hopper/Presentation/BookRide/Screens/book_map_screen.dart';
// import 'package:hopper/Presentation/BookRide/Screens/locate_on_map_screen.dart';
// import 'package:hopper/uitls/map/search.dart';
// import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
// import 'package:shared_preferences/shared_preferences.dart';
//
// class BookRideSearchScreen extends StatefulWidget {
//   final bool? isPickup;
//   final Map<String, dynamic>? pickupData;
//   final Map<String, dynamic>? destinationData;
//   final String? flag;
//   const BookRideSearchScreen({
//     super.key,
//     this.isPickup,
//     this.pickupData,
//     this.destinationData,
//     this.flag,
//   });
//
//   @override
//   State<BookRideSearchScreen> createState() => _BookRideSearchScreenState();
// }
//
// class _BookRideSearchScreenState extends State<BookRideSearchScreen> {
//   final TextEditingController _startController = TextEditingController();
//   final TextEditingController _destController = TextEditingController();
//
//   List<Map<String, dynamic>> _startSearchResults = [];
//   List<Map<String, dynamic>> _destSearchResults = [];
//   List<String> _recentLocations = [];
//
//   bool _isStartFieldFocused = true;
//
//   Map<String, dynamic>? _pickup;
//   Map<String, dynamic>? _destination;
//
//   final FocusNode _pickupFocus = FocusNode();
//   final FocusNode _destinationFocus = FocusNode();
//
//   @override
//   void initState() {
//     super.initState();
//
//     _isStartFieldFocused = widget.isPickup ?? true;
//
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (_isStartFieldFocused) {
//         _pickupFocus.requestFocus();
//       } else {
//         _destinationFocus.requestFocus();
//       }
//     });
//
//     if (widget.pickupData != null) {
//       _startController.text = widget.pickupData!['description'] ?? '';
//       _pickup = widget.pickupData;
//     }
//     if (widget.destinationData != null) {
//       _destController.text = widget.destinationData!['description'] ?? '';
//       _destination = widget.destinationData;
//     }
//
//     _loadRecentLocations();
//   }
//
//   Future<void> _searchLocation(String value) async {
//     if (value.length < 3) return;
//
//     final results = await LocationHelper.searchPlaces(value);
//     setState(() {
//       if (_isStartFieldFocused) {
//         _startSearchResults = results;
//       } else {
//         _destSearchResults = results;
//       }
//     });
//   }
//
//   // void _goToMapScreen() {
//   //   Navigator.push(
//   //     context,
//   //     MaterialPageRoute(
//   //       builder:
//   //           (_) => BookMapScreen(
//   //             pickupData: _pickup!,
//   //             destinationData: _destination!,
//   //             pickupAddress: _pickup!['description'],
//   //             destinationAddress: _destination!['description'],
//   //           ),
//   //     ),
//   //   );
//   // }
//   void _goToMapScreen() {
//     final isFromMap = ModalRoute.of(context)?.settings.arguments == 'fromMap';
//
//     if (isFromMap) {
//       Navigator.pop(context, {
//         'pickup': {
//           'description': _pickup!['description'],
//           'lat': _pickup!['lat'],
//           'lng': _pickup!['lng'],
//         },
//         'destination': {
//           'description': _destination!['description'],
//           'lat': _destination!['lat'],
//           'lng': _destination!['lng'],
//         },
//       });
//     } else {
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder:
//               (_) => BookMapScreen(
//                 pickupData: _pickup!,
//                 destinationData: _destination!,
//                 pickupAddress: _pickup!['description'],
//                 destinationAddress: _destination!['description'],
//               ),
//         ),
//       );
//     }
//   }
//
//   /*  void _handleSelection(Map<String, dynamic> item) {
//     late final Map<String, dynamic> selectedMapData;
//
//     if (item['location'] is LatLng) {
//       selectedMapData = {
//         'description': item['description'],
//         'location': item['location'],
//       };
//     } else if (item['lat'] != null && item['lng'] != null) {
//       selectedMapData = {
//         'description': item['description'],
//         'location': LatLng(item['lat'], item['lng']),
//       };
//     } else {
//       // Skip handling if there's no location (can't navigate to map)
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text('Selected location is invalid.')));
//       return;
//     }
//
//     setState(() {
//       if (_isStartFieldFocused) {
//         _startController.text = selectedMapData['description'];
//         _pickup = selectedMapData;
//         _startSearchResults.clear();
//       } else {
//         _destController.text = selectedMapData['description'];
//         _destination = selectedMapData;
//         _destSearchResults.clear();
//       }
//     });
//
//     // Save only if location is present
//     if (selectedMapData['location'] != null) {
//       _saveRecentLocation(
//         selectedMapData['description'],
//         selectedMapData['location'],
//       );
//     }
//
//     if (_pickup != null && _destination != null) {
//       _goToMapScreen();
//     }
//   }*/
//
//   void _handleSelection(Map<String, dynamic> item) {
//     late final Map<String, dynamic> selectedMapData;
//
//     if (item['location'] is LatLng) {
//       selectedMapData = {
//         'description': item['description'],
//         'location': item['location'],
//       };
//     } else if (item['lat'] != null && item['lng'] != null) {
//       selectedMapData = {
//         'description': item['description'],
//         'location': LatLng(item['lat'], item['lng']),
//       };
//     } else {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text('Selected location is invalid.')));
//       return;
//     }
//
//     final LatLng newLoc = selectedMapData['location'];
//
//     if (_isStartFieldFocused &&
//         _destination != null &&
//         _destination!['location'] != null) {
//       final LatLng destLoc = _destination!['location'];
//       final distance = Geolocator.distanceBetween(
//         newLoc.latitude,
//         newLoc.longitude,
//         destLoc.latitude,
//         destLoc.longitude,
//       );
//
//       if (distance <= 1000) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text("Pickup and drop cannot be the same or within 1 km."),
//           ),
//         );
//         _startController.clear();
//         _pickup = null;
//         return;
//       }
//     }
//
//     if (!_isStartFieldFocused &&
//         _pickup != null &&
//         _pickup!['location'] != null) {
//       final LatLng pickupLoc = _pickup!['location'];
//       final distance = Geolocator.distanceBetween(
//         pickupLoc.latitude,
//         pickupLoc.longitude,
//         newLoc.latitude,
//         newLoc.longitude,
//       );
//
//       if (distance <= 1000) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text("Pickup and drop cannot be the same or within 1 km."),
//           ),
//         );
//         _destController.clear();
//         _destination = null;
//         return;
//       }
//     }
//
//     setState(() {
//       if (_isStartFieldFocused) {
//         _startController.text = selectedMapData['description'];
//         _pickup = selectedMapData;
//         _startSearchResults.clear();
//       } else {
//         _destController.text = selectedMapData['description'];
//         _destination = selectedMapData;
//         _destSearchResults.clear();
//       }
//     });
//
//     _saveRecentLocation(selectedMapData['description'], newLoc);
//
//     if (_pickup != null && _destination != null) {
//       _goToMapScreen();
//     }
//   }
//
//   Future<void> _locateOnMap() async {
//     final result = await Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder:
//             (_) => LocateOnMapScreen(
//               searchQuery: '',
//               type: _isStartFieldFocused ? 'pickup' : 'destination',
//               cameFromPackage: false,
//             ),
//       ),
//     );
//
//     if (result != null &&
//         result['mapAddress'] != null &&
//         result['location'] != null &&
//         result['location'] is LatLng) {
//       final LatLng latLng = result['location'];
//
//       if (_isStartFieldFocused &&
//           _destination != null &&
//           _destination!['location'] != null) {
//         final LatLng dest = _destination!['location'];
//         final distance = Geolocator.distanceBetween(
//           latLng.latitude,
//           latLng.longitude,
//           dest.latitude,
//           dest.longitude,
//         );
//         if (distance <= 1000) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text(
//                 "Pickup and drop cannot be the same or within 1 km.",
//               ),
//             ),
//           );
//           _startController.clear();
//           _pickup = null;
//           return;
//         }
//       }
//
//       if (!_isStartFieldFocused &&
//           _pickup != null &&
//           _pickup!['location'] != null) {
//         final LatLng pickup = _pickup!['location'];
//         final distance = Geolocator.distanceBetween(
//           pickup.latitude,
//           pickup.longitude,
//           latLng.latitude,
//           latLng.longitude,
//         );
//         if (distance <= 1000) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text(
//                 "Pickup and drop cannot be the same or within 1 km.",
//               ),
//             ),
//           );
//           _destController.clear();
//           _destination = null;
//           return;
//         }
//       }
//
//       final selectedMapData = {
//         'description': result['mapAddress'],
//         'location': latLng,
//       };
//
//       setState(() {
//         if (_isStartFieldFocused) {
//           _startController.text = result['mapAddress'];
//           _pickup = selectedMapData;
//           _startSearchResults.clear();
//         } else {
//           _destController.text = result['mapAddress'];
//           _destination = selectedMapData;
//           _destSearchResults.clear();
//         }
//       });
//
//       _saveRecentLocation(result['mapAddress'], latLng);
//
//       if (_pickup != null && _destination != null) {
//         _goToMapScreen();
//       }
//     }
//   }
//
//   /*  Future<void> _locateOnMap() async {
//     final result = await Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder:
//             (_) => LocateOnMapScreen(
//               searchQuery: '',
//               type: _isStartFieldFocused ? 'pickup' : 'destination',
//               cameFromPackage: false,
//             ),
//       ),
//     );
//
//     if (result != null &&
//         result['mapAddress'] != null &&
//         result['location'] != null &&
//         result['location'] is LatLng) {
//       final LatLng? latLng = result['location'] as LatLng?;
//       if (latLng == null) return;
//
//       final selectedMapData = {
//         'description': result['mapAddress'],
//         'location': latLng,
//       };
//
//       setState(() {
//         if (_isStartFieldFocused) {
//           _startController.text = result['mapAddress'];
//           _pickup = selectedMapData;
//           _startSearchResults.clear();
//         } else {
//           _destController.text = result['mapAddress'];
//           _destination = selectedMapData;
//           _destSearchResults.clear();
//         }
//       });
//
//       _saveRecentLocation(result['mapAddress'], result['location']);
//
//       if (_pickup != null && _destination != null) {
//         _goToMapScreen();
//       }
//     }
//   }*/
//
//   Future<void> _saveRecentLocation(String description, LatLng location) async {
//     final prefs = await SharedPreferences.getInstance();
//     List<String> recent = prefs.getStringList('recent_locations') ?? [];
//
//     final newItem = {
//       'description': description,
//       'lat': location.latitude,
//       'lng': location.longitude,
//     };
//
//     recent.removeWhere((item) {
//       try {
//         final decoded = jsonDecode(item);
//         return decoded['description'] == description;
//       } catch (_) {
//         return item == description;
//       }
//     });
//
//     recent.insert(0, jsonEncode(newItem));
//
//     if (recent.length > 5) recent = recent.sublist(0, 5);
//
//     await prefs.setStringList('recent_locations', recent);
//   }
//
//   Future<void> _loadRecentLocations() async {
//     final prefs = await SharedPreferences.getInstance();
//     final recentStrings = prefs.getStringList('recent_locations') ?? [];
//
//     setState(() {
//       _recentLocations = recentStrings;
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final resultsToShow =
//         _isStartFieldFocused ? _startSearchResults : _destSearchResults;
//
//     return Scaffold(
//       body: SafeArea(
//         child: Column(
//           children: [
//             SingleChildScrollView(
//               child: Padding(
//                 padding: const EdgeInsets.all(15),
//                 child: Column(
//                   children: [
//                     Row(
//                       children: [
//                         if (widget.flag != "bottomBar")
//                           GestureDetector(
//                             onTap: () => Navigator.pop(context),
//                             child: Image.asset(
//                               AppImages.backImage,
//                               height: 19,
//                               width: 19,
//                             ),
//                           ),
//                         SizedBox(width: 12),
//                         CustomTextFields.textWithStyles600(
//                           'Set pick up location',
//                         ),
//                       ],
//                     ),
//                     SizedBox(height: 20),
//                     Container(
//                       decoration: BoxDecoration(
//                         color: Colors.white,
//                         borderRadius: BorderRadius.circular(12),
//                         boxShadow: [
//                           BoxShadow(
//                             color: Colors.black12,
//                             blurRadius: 8,
//                             offset: Offset(0, 4),
//                           ),
//                         ],
//                       ),
//                       child: Stack(
//                         children: [
//                           Column(
//                             children: [
//                               CustomTextFields.plainTextField(
//                                 suffixIcon:
//                                     _isStartFieldFocused &&
//                                             _startController.text.isNotEmpty
//                                         ? IconButton(
//                                           icon: Icon(Icons.close, size: 18),
//                                           onPressed: () {
//                                             _startController.clear();
//                                             setState(() {});
//                                           },
//                                         )
//                                         : null,
//                                 hintStyle: TextStyle(fontSize: 11),
//                                 imgHeight: 15,
//                                 focusNode: _pickupFocus,
//                                 controller: _startController,
//                                 onChanged: _searchLocation,
//                                 onTap:
//                                     () => setState(
//                                       () => _isStartFieldFocused = true,
//                                     ),
//                                 containerColor: AppColors.commonWhite,
//                                 leadingImage: AppImages.circleStart,
//                                 title: 'Search for an address or landmark',
//                                 readOnly: false,
//                               ),
//                               const Divider(
//                                 height: 10,
//                                 color: AppColors.containerColor,
//                               ),
//                               CustomTextFields.plainTextField(
//                                 focusNode: _destinationFocus,
//                                 controller: _destController,
//                                 onChanged: _searchLocation,
//                                 onTap:
//                                     () => setState(
//                                       () => _isStartFieldFocused = false,
//                                     ),
//                                 hintStyle: TextStyle(fontSize: 11),
//                                 imgHeight: 16,
//                                 containerColor: AppColors.commonWhite,
//                                 leadingImage: AppImages.rectangleDest,
//                                 title: 'Enter destination',
//                                 readOnly: false,
//                                 suffixIcon:
//                                     !_isStartFieldFocused &&
//                                             _destController.text.isNotEmpty
//                                         ? IconButton(
//                                           icon: Icon(Icons.close, size: 18),
//                                           onPressed: () {
//                                             _destController.clear();
//                                             setState(() {});
//                                           },
//                                         )
//                                         : null,
//                               ),
//                             ],
//                           ),
//                           Positioned(
//                             left: 23,
//                             top: 33,
//                             bottom: 33,
//                             child: Container(
//                               width: 1.3,
//                               color: Colors.grey[700],
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                     SizedBox(height: 10),
//                   ],
//                 ),
//               ),
//             ),
//             Expanded(
//               child:
//                   resultsToShow.isEmpty && _recentLocations.isNotEmpty
//                       ? Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 15),
//                         child: SingleChildScrollView(
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Text(
//                                 'Recent locations',
//                                 style: TextStyle(color: Colors.grey),
//                               ),
//                               ..._recentLocations.map((locString) {
//                                 try {
//                                   final locMap = jsonDecode(locString);
//                                   return ListTile(
//                                     leading: Icon(
//                                       Icons.history,
//                                       size: 18,
//                                       color: Colors.grey,
//                                     ),
//                                     title: Text(
//                                       locMap['description'],
//                                       style: TextStyle(fontSize: 14),
//                                     ),
//                                     onTap: () {
//                                       final selectedMapData = {
//                                         'description': locMap['description'],
//                                         'location': LatLng(
//                                           locMap['lat'],
//                                           locMap['lng'],
//                                         ),
//                                       };
//                                       _handleSelection(selectedMapData);
//                                     },
//                                   );
//                                 } catch (e) {
//                                   return ListTile(
//                                     leading: Icon(
//                                       Icons.history,
//                                       size: 18,
//                                       color: Colors.grey,
//                                     ),
//                                     title: Text(
//                                       locString,
//                                       style: TextStyle(fontSize: 14),
//                                     ),
//                                     onTap: () {
//                                       final selectedMapData = {
//                                         'description': locString,
//                                         'location': null,
//                                       };
//                                       _handleSelection(selectedMapData);
//                                     },
//                                   );
//                                 }
//                               }),
//                             ],
//                           ),
//                         ),
//                       )
//                       : resultsToShow.isNotEmpty
//                       ? ListView.builder(
//                         shrinkWrap: true,
//                         physics: NeverScrollableScrollPhysics(),
//                         padding: EdgeInsets.symmetric(horizontal: 15),
//                         itemCount: resultsToShow.length,
//                         itemBuilder: (context, index) {
//                           final item = resultsToShow[index];
//                           return ListTile(
//                             leading: Column(
//                               mainAxisAlignment: MainAxisAlignment.start,
//
//                               children: [
//                                 Icon(Icons.location_on_outlined, size: 19),
//                                 SizedBox(height: 4),
//                                 if (item['distance'] != null)
//                                   Text(
//                                     item['distance'],
//                                     style: TextStyle(
//                                       fontSize: 9,
//                                       color: Colors.grey[600],
//                                     ),
//                                   ),
//                               ],
//                             ),
//                             title: Text(
//                               item['description'].split(',')[0],
//                               style: TextStyle(
//                                 fontSize: 14,
//                                 fontWeight: FontWeight.w600,
//                               ),
//                               overflow: TextOverflow.ellipsis,
//                             ),
//                             subtitle: Text(
//                               item['description'],
//                               maxLines: 1,
//                               overflow: TextOverflow.ellipsis,
//                               style: TextStyle(
//                                 fontSize: 12,
//                                 color: Color(0xff828284),
//                               ),
//                             ),
//                             onTap: () => _handleSelection(item),
//                           );
//                         },
//                       )
//                       : SizedBox.shrink(),
//             ),
//
//             AppButtons.button(
//               hasBorder: true,
//               fontSize: 14,
//               borderColor: AppColors.containerColor,
//               buttonColor: AppColors.commonWhite,
//               textColor: AppColors.commonBlack,
//               imagePath: AppImages.mapLocation,
//               onTap: _locateOnMap,
//               text: AppTexts.locateOnMap,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
