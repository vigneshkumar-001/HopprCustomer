import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/OnBoarding/models/recent_location_model.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/uitls/map/google_map.dart'; // MapScreen
import 'package:shared_preferences/shared_preferences.dart';

class CommonLocationSearch extends StatefulWidget {
  final String? type;
  final String? Loaction;
  final String? initialAddress;
  final String? initialLandmark;
  final String? initialName;
  final String? initialPhone;
  const CommonLocationSearch({
    super.key,
    this.type,
    this.Loaction,
    this.initialAddress,
    this.initialLandmark,
    this.initialName,
    this.initialPhone,
  });

  @override
  State<CommonLocationSearch> createState() => _CommonLocationSearchState();
}

class _CommonLocationSearchState extends State<CommonLocationSearch> {
  final TextEditingController _searchController = TextEditingController();
  final List<dynamic> _searchResults = [];
  bool _showInfoMessage = false;

  final List<RecentLocation> _recentLocations = <RecentLocation>[];
  bool _loadingRecents = false;

  // NEW: performance helpers
  Timer? _debounce;
  bool _isLoading = false;
  Position? _origin; // cached once
  int _querySerial = 0; // incremental id per query
  String _sessionToken = ""; // Places session token

  @override
  void initState() {
    super.initState();
    if (widget.Loaction != null && widget.Loaction!.isNotEmpty) {
      _searchController.text = widget.Loaction!;
    }
    _initOrigin(); // get location once
    _resetSessionToken(); // new session token
    _loadRecentLocations();
  }

  Future<void> _loadRecentLocations() async {
    try {
      setState(() => _loadingRecents = true);
      final prefs = await SharedPreferences.getInstance();
      final recentList = prefs.getStringList('recent_locations') ?? const [];
      final decoded = recentList
          .map((jsonStr) {
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            return RecentLocation.fromJson(json);
          })
          .where((e) => e.description.trim().isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _recentLocations
          ..clear()
          ..addAll(decoded);
        _loadingRecents = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recentLocations.clear();
        _loadingRecents = false;
      });
    }
  }

  // Generate a lightweight session token (avoids pulling in uuid pkg)
  void _resetSessionToken() {
    final r = Random();
    _sessionToken =
        "${DateTime.now().millisecondsSinceEpoch}-${r.nextInt(1 << 32)}-${r.nextInt(1 << 32)}";
  }

  Future<void> _initOrigin() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (mounted) setState(() => _origin = pos);
    } catch (_) {
      // ignore; search still works without bias
    }
  }

  Future<void> _openMapScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(searchQuery: widget.Loaction ?? ''),
      ),
    );
    if (result != null && result['_selectedAddress'] != null) {
      setState(() => _searchController.text = result['_selectedAddress']);
    }
  }

  // FAST: Autocomplete only (no Place Details here)
  Future<void> _searchPlacesFast(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      setState(() {
        _searchResults.clear();
        _isLoading = false;
      });
      return;
    }

    // mark this request
    final mySerial = ++_querySerial;

    setState(() => _isLoading = true);

    final key = ApiConsents.googleMapApiKey;
    final locationPart =
        (_origin != null)
            ? "&location=${_origin!.latitude},${_origin!.longitude}&radius=50000"
            : "";
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=$q'
      '$locationPart'
      '&components=country:in'
      '&types=geocode'
      '&sessiontoken=$_sessionToken'
      '&key=$key',
    );

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      final data = json.decode(res.body) as Map<String, dynamic>;

      // if another query started after this one, drop these results
      if (mySerial != _querySerial) return;

      if (mounted) {
        setState(() {
          _searchResults
            ..clear()
            ..addAll(
              (data['predictions'] as List? ?? const []).map(
                (p) => {
                  'description': p['description'],
                  'place_id': p['place_id'],
                },
              ),
            );
          _isLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchResults.clear();
        _isLoading = false;
      });
    }
  }

  // Only fetch details for the item the user taps (single fast call)
  void _getPlaceDetailsAndNavigate(String placeId, String placeName) async {
    final key = ApiConsents.googleMapApiKey;
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=$placeId'
      '&fields=geometry,formatted_address'
      '&sessiontoken=$_sessionToken'
      '&key=$key',
    );

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      final data = json.decode(res.body);

      if (res.statusCode == 200 && data['status'] == 'OK') {
        final loc = data['result']['geometry']['location'];
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();

        // After a selection, start a fresh session for better billing/results
        _resetSessionToken();

        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => MapScreen(
                  searchQuery: placeName,
                  location: LatLng(lat, lng),
                  type: widget.type ?? '',
                  initialAddress: widget.initialAddress,
                  initialLandmark: widget.initialLandmark,
                  initialName: widget.initialName,
                  initialPhone: widget.initialPhone,
                ),
          ),
        );

        if (!mounted) return;
        if (result != null && result['mapAddress'] != null) {
          Navigator.pop(context, {
            'mapAddress': result['mapAddress'],
            'location': result['location'],
            'address': result['address'],
            'landmark': result['landmark'],
            'name': result['name'],
            'phone': result['phone'],
          });
          return;
        } else if (result != null && result['_selectedAddress'] != null) {
          setState(() => _searchController.text = result['_selectedAddress']);
        }

        // Clear list after navigate (optional UX)
        setState(() {
          _searchResults.clear();
          _showInfoMessage = false;
        });
      }
    } catch (_) {
      // ignore; you can show a snackbar if you want
    }
  }

  Future<void> _openRecentLocation(RecentLocation recent) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => MapScreen(
              searchQuery: recent.description,
              location: LatLng(recent.lat, recent.lng),
              type: widget.type ?? '',
              initialAddress: widget.initialAddress,
              initialLandmark: widget.initialLandmark,
              initialName: widget.initialName,
              initialPhone: widget.initialPhone,
            ),
      ),
    );

    if (!mounted) return;
    if (result != null && result['mapAddress'] != null) {
      Navigator.pop(context, {
        'mapAddress': result['mapAddress'],
        'location': result['location'],
        'address': result['address'],
        'landmark': result['landmark'],
        'name': result['name'],
        'phone': result['phone'],
      });
    }
  }

  Future<void> _locateOnMap() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => MapScreen(
              searchQuery: '',
              type: widget.type ?? '',
              initialAddress: widget.initialAddress,
              initialLandmark: widget.initialLandmark,
              initialName: widget.initialName,
              initialPhone: widget.initialPhone,
            ),
      ),
    );

    if (!mounted) return;
    if (result != null && result['mapAddress'] != null) {
      Navigator.pop(context, {
        'mapAddress': result['mapAddress'],
        'location': result['location'],
        'address': result['address'],
        'landmark': result['landmark'],
        'name': result['name'],
        'phone': result['phone'],
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _showInfoMessage = value.isNotEmpty);

    // debounce 300ms
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchPlacesFast(value);
    });
  }

  Widget _buildRecentsList() {
    if (_loadingRecents) {
      return const Center(
        child: SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_recentLocations.isEmpty) return const SizedBox.shrink();

    return ListView.builder(
      itemCount: _recentLocations.length,
      itemBuilder: (context, index) {
        final recent = _recentLocations[index];
        return ListTile(
          leading: const Icon(Icons.history_rounded),
          title: Text(
            recent.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          onTap: () => _openRecentLocation(recent),
        );
      },
    );
  }

  Widget _buildPredictionsList() {
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final place = _searchResults[index];
        return ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: Text(
            place['description'] ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          onTap: () {
            _getPlaceDetailsAndNavigate(place['place_id'], place['description']);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final showRecents =
        _searchController.text.trim().isEmpty && _searchResults.isEmpty;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                children: [
                  Row(
                    children: [
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
                        widget.type == 'receiver' ? 'Send to' : 'Collect from',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        color: AppColors.containerColor.withOpacity(0.2),
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      children: [
                        // Search box
                        CustomTextFields.plainTextField(
                          autofocus: true,
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _searchResults.clear();
                                _searchController.text = '';
                                _showInfoMessage = false;
                                _isLoading = false;
                                _resetSessionToken();
                              });
                            },
                            icon: const Icon(Icons.clear, size: 19),
                          ),
                          hintStyle: const TextStyle(fontSize: 12),
                          imgHeight: 18,
                          containerColor: AppColors.commonWhite,
                          onChanged: _onSearchChanged,
                          controller: _searchController,
                          leadingImage: AppImages.dart,
                          title: 'Search for an address or landmark',
                          readOnly: false,
                        ),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 150),
                            child:
                                _isLoading
                                    ? LinearProgressIndicator(
                                  borderRadius: BorderRadius.circular(15),
                                      minHeight: 3,
                                      color: AppColors.commonBlack,
                                    )
                                    : const SizedBox(height: 2),
                          ),
                        ),
                      ],
                    ),
                  ),

                  !_showInfoMessage
                      ? const SizedBox(height: 10)
                      : const SizedBox.shrink(),
                  if (!_showInfoMessage)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Update your location on the Hoppr homepage to select address from a different city',
                            style: TextStyle(
                              color: AppColors.searchDownTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // Predictions list (autocomplete only — instant)
            Expanded(
              child: showRecents ? _buildRecentsList() : _buildPredictionsList(),
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
// import 'package:flutter/material.dart';
// import 'package:hopper/Core/Consents/app_colors.dart';
// import 'package:hopper/Core/Consents/app_texts.dart';
// import 'package:hopper/Core/Utility/app_buttons.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
// import 'package:hopper/api/repository/api_consents.dart';
// import 'package:http/http.dart' as http;
// import 'package:geolocator/geolocator.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:hopper/uitls/map/google_map.dart'; // Make sure this MapScreen accepts LatLng too
//
// class CommonLocationSearch extends StatefulWidget {
//   final String? type;
//   final String? Loaction;
//   final String? initialAddress;
//   final String? initialLandmark;
//   final String? initialName;
//   final String? initialPhone;
//   const CommonLocationSearch({
//     super.key,
//     this.type,
//     this.Loaction,
//     this.initialAddress,
//     this.initialLandmark,
//     this.initialName,
//     this.initialPhone,
//   });
//
//   @override
//   State<CommonLocationSearch> createState() => _CommonLocationSearchState();
// }
//
// class _CommonLocationSearchState extends State<CommonLocationSearch> {
//   final TextEditingController _searchController = TextEditingController();
//
//   bool _showInfoMessage = false;
//   @override
//   void initState() {
//     super.initState();
//     if (widget.Loaction != null && widget.Loaction!.isNotEmpty) {
//       _searchController.text = widget.Loaction!;
//     }
//   }
//
//   List<dynamic> _searchResults = [];
//   Future<void> _openMapScreen() async {
//     final result = await Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder:
//             (_) => MapScreen(
//               searchQuery: widget.Loaction ?? '',
//             ), // Go to map screen
//       ),
//     );
//
//     if (result != null && result['_selectedAddress'] != null) {
//       setState(() {
//         _searchController.text = result['_selectedAddress']; // Update input
//       });
//     }
//   }
//
//   // void _searchPlaces(String query) async {
//   //   final url =
//   //       'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$_apiKey&components=country:in';
//   //   final response = await http.get(Uri.parse(url));
//   //   final data = json.decode(response.body);
//   //
//   //   if (response.statusCode == 200 && data['status'] == 'OK') {
//   //     setState(() {
//   //       _searchResults = data['predictions'];
//   //     });
//   //   }
//   // }
//   void _searchPlaces(String query) async {
//     final position = await Geolocator.getCurrentPosition(
//       desiredAccuracy: LocationAccuracy.medium,
//     );
//     String _apiKey = ApiConsents.googleMapApiKey;
//
//     final url =
//         'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query'
//         '&location=${position.latitude},${position.longitude}'
//         '&radius=50000' // 50km
//         '&key=$_apiKey';
//
//     final response = await http.get(Uri.parse(url));
//     final data = json.decode(response.body);
//
//     if (response.statusCode == 200 && data['status'] == 'OK') {
//       List<dynamic> predictions = data['predictions'];
//
//       // Run all detail fetches in parallel
//       final futures = predictions.map((prediction) async {
//         final placeId = prediction['place_id'];
//         final detailUrl =
//             'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_apiKey';
//
//         final detailRes = await http.get(Uri.parse(detailUrl));
//         final detailData = json.decode(detailRes.body);
//
//         if (detailRes.statusCode == 200 && detailData['status'] == 'OK') {
//           final location = detailData['result']['geometry']['location'];
//           final lat = location['lat'];
//           final lng = location['lng'];
//
//           final distance = Geolocator.distanceBetween(
//             position.latitude,
//             position.longitude,
//             lat,
//             lng,
//           );
//
//           prediction['distance'] = '${(distance / 1000).toStringAsFixed(1)} km';
//           prediction['lat'] = lat;
//           prediction['lng'] = lng;
//
//           return prediction;
//         }
//         return null;
//       });
//
//       final detailedResults = await Future.wait(futures);
//       final filteredResults = detailedResults.whereType<Map>().toList();
//       if (!mounted) return;
//       setState(() {
//         _searchResults = filteredResults;
//       });
//     }
//   }
//
//   void _getPlaceDetailsAndNavigate(
//     String placeId,
//     String placeName,
//     String distance,
//   ) async {
//     String _apiKey = ApiConsents.googleMapApiKey;
//     final url =
//         'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_apiKey';
//     final response = await http.get(Uri.parse(url));
//     final data = json.decode(response.body);
//
//     if (response.statusCode == 200 && data['status'] == 'OK') {
//       final location = data['result']['geometry']['location'];
//       final lat = location['lat'];
//       final lng = location['lng'];
//
//       final result = await Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder:
//               (_) => MapScreen(
//                 searchQuery: placeName,
//                 location: LatLng(lat, lng),
//                 initialAddress: widget.initialAddress,
//                 initialLandmark: widget.initialLandmark,
//                 initialName: widget.initialName,
//                 initialPhone: widget.initialPhone,
//               ),
//         ),
//       );
//       if (result != null && result['_selectedAddress'] != null) {
//         _searchController.text = result['_selectedAddress']; // update the field
//       }
//     }
//   }
//
//   Future<void> _locateOnMap() async {
//     final result = await Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder:
//             (context) => MapScreen(
//               searchQuery: '',
//               type: widget.type ?? '',
//               initialAddress: widget.initialAddress,
//               initialLandmark: widget.initialLandmark,
//               initialName: widget.initialName,
//               initialPhone: widget.initialPhone,
//             ),
//       ),
//     );
//
//     if (result != null && result['mapAddress'] != null) {
//       Navigator.pop(context, {
//         'mapAddress': result['mapAddress'],
//         'location': result['location'],
//         'address': result['address'],
//         'landmark': result['landmark'],
//         'name': result['name'],
//         'phone': result['phone'],
//       });
//     }
//   }
//
//   /*  Future<void> _locateOnMap() async {
//     final result = await Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder:
//             (context) => MapScreen(
//               searchQuery: '',
//               type: widget.type ?? '',
//             ), // replace with your screen class
//       ),
//     );
//
//     if (result != null && result['_selectedAddress'] != null) {
//       _searchController.text = result['_selectedAddress']; // update the field
//     }
//     // Navigator.push(
//     //   context,
//     //   MaterialPageRoute(
//     //     builder: (_) => MapScreen(searchQuery: '', type: widget.type ?? ''),
//     //   ),
//     // );
//     // final searchText = _searchController.text.trim();
//     // if (searchText.isNotEmpty) {
//     //   Navigator.push(
//     //     context,
//     //     MaterialPageRoute(builder: (_) => MapScreen(searchQuery: searchText)),
//     //   );
//     // } else {
//     //   ScaffoldMessenger.of(
//     //     context,
//     //   ).showSnackBar(const SnackBar(content: Text("Please enter an address.")));
//     // }
//   }*/
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: SafeArea(
//         child: Column(
//           children: [
//             Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
//               child: Column(
//                 children: [
//                   Row(
//                     children: [
//                       GestureDetector(
//                         onTap: () => Navigator.pop(context),
//                         child: Image.asset(
//                           AppImages.backImage,
//                           height: 19,
//                           width: 19,
//                         ),
//                       ),
//                       SizedBox(width: 12),
//                       CustomTextFields.textWithStyles600(
//                         widget.type == 'receiver' ? 'Send to' : 'Collect from',
//                       ),
//                     ],
//                   ),
//                   SizedBox(height: 10),
//                   Card(
//                     elevation: 2,
//                     margin: EdgeInsets.symmetric(vertical: 5),
//                     shape: RoundedRectangleBorder(
//                       side: BorderSide(
//                         color: AppColors.containerColor.withOpacity(0.2),
//                       ),
//                       borderRadius: BorderRadius.circular(15),
//                     ),
//                     child: CustomTextFields.plainTextField(
//                       autofocus: true,
//                       suffixIcon: IconButton(
//                         onPressed: () {
//                           _searchResults.clear();
//                           _searchController.text = '';
//                         },
//                         icon: Icon(Icons.clear, size: 19),
//                       ),
//                       hintStyle: TextStyle(fontSize: 12),
//                       imgHeight: 18,
//
//                       containerColor: AppColors.commonWhite,
//
//                       onChanged: (value) {
//                         setState(() {
//                           _showInfoMessage = value.isNotEmpty;
//                         });
//
//                         if (value.isNotEmpty) {
//                           _searchPlaces(value);
//                         } else {
//                           setState(() => _searchResults.clear());
//                         }
//                       },
//                       controller: _searchController,
//                       leadingImage: AppImages.dart,
//                       title: 'Search for an address or landmark',
//                       readOnly: false,
//                     ),
//                   ),
//                   !_showInfoMessage ? SizedBox(height: 10) : SizedBox.shrink(),
//                   if (!_showInfoMessage)
//                     Row(
//                       children: [
//                         Expanded(
//                           child: Text(
//                             'Update your location on the Hoppr homepage to select address from a different city',
//                             style: TextStyle(
//                               color: AppColors.searchDownTextColor,
//                               fontSize: 12,
//                               fontWeight: FontWeight.w400,
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                 ],
//               ),
//             ),
//
//             Expanded(
//               child: ListView.builder(
//                 itemCount: _searchResults.length,
//                 itemBuilder: (context, index) {
//                   final place = _searchResults[index];
//                   return ListTile(
//                     leading: const Icon(Icons.location_on_outlined),
//                     title: Text(
//                       place['description'],
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                       style: TextStyle(
//                         fontSize: 14,
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                     subtitle: Text(place['distance'] ?? ''),
//                     onTap: () {
//                       _getPlaceDetailsAndNavigate(
//                         place['place_id'],
//                         place['description'],
//                         place['distance'] ?? '',
//                       );
//                       setState(() {
//                         _searchResults.clear();
//                         _searchController.text = '';
//                         _showInfoMessage = false;
//                       });
//                     },
//                   );
//                 },
//               ),
//             ),
//             AppButtons.button(
//               hasBorder: true,
//               fontSize: 14,
//               borderColor: AppColors.containerColor,
//               buttonColor: AppColors.commonWhite,
//               textColor: AppColors.commonBlack,
//               imagePath: AppImages.mapLocation,
//               onTap: () {
//                 _locateOnMap();
//               },
//
//               text: AppTexts.locateOnMap,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
