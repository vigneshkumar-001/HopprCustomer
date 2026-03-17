import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';

import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
import 'package:hopper/Presentation/BookRide/Controllers/book_map_controller.dart';
import 'package:hopper/Presentation/BookRide/Screens/confirm_booking.dart';
import 'package:hopper/Presentation/BookRide/Screens/search_screen.dart';
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Screens/ride_share_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';

class BookMapScreen extends StatefulWidget {
  final Map<String, dynamic> pickupData;
  final Map<String, dynamic> destinationData;
  final String pickupAddress;
  final String destinationAddress;

  const BookMapScreen({
    super.key,
    required this.pickupData,
    required this.destinationData,
    required this.pickupAddress,
    required this.destinationAddress,
  });

  @override
  State<BookMapScreen> createState() => _BookMapScreenState();
}

class _BookMapScreenState extends State<BookMapScreen> {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destController = TextEditingController();

  final DriverSearchController driverController =
      Get.isRegistered<DriverSearchController>()
          ? Get.find<DriverSearchController>()
          : Get.put(DriverSearchController());
  final BookMapController mapC =
      Get.isRegistered<BookMapController>()
          ? Get.find<BookMapController>()
          : Get.put(BookMapController());

  @override
  void initState() {
    super.initState();

    _startController.text = widget.pickupAddress;
    _destController.text = widget.destinationAddress;

    LatLng? pickupLocation;
    LatLng? destinationLocation;

    if (widget.pickupData.containsKey('location')) {
      pickupLocation = widget.pickupData['location'];
    } else if (widget.pickupData.containsKey('lat') &&
        widget.pickupData.containsKey('lng')) {
      pickupLocation = LatLng(
        widget.pickupData['lat'],
        widget.pickupData['lng'],
      );
    }

    if (widget.destinationData.containsKey('location')) {
      destinationLocation = widget.destinationData['location'];
    } else if (widget.destinationData.containsKey('lat') &&
        widget.destinationData.containsKey('lng')) {
      destinationLocation = LatLng(
        widget.destinationData['lat'],
        widget.destinationData['lng'],
      );
    }

    if (pickupLocation == null || destinationLocation == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.back();
        Get.snackbar("Error", "Location data is missing");
      });
      return;
    }

    final resolvedPickup = pickupLocation;
    final resolvedDestination = destinationLocation;

    // optional: distance check
    final distance = Geolocator.distanceBetween(
      resolvedPickup.latitude,
      resolvedPickup.longitude,
      resolvedDestination.latitude,
      resolvedDestination.longitude,
    );
    AppLogger.log.i("distance meters: $distance");

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await mapC.initPositions(
        pickup: resolvedPickup,
        destination: resolvedDestination,
      );

      // ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Prefetch both once
      await Future.wait([
        driverController.getDriverSearch(
          pickupLat: resolvedPickup.latitude,
          pickupLng: resolvedPickup.longitude,
          dropLat: resolvedDestination.latitude,
          dropLng: resolvedDestination.longitude,
        ),
        driverController.getSharedDriverSearch(
          pickupLat: resolvedPickup.latitude,
          pickupLng: resolvedPickup.longitude,
          dropLat: resolvedDestination.latitude,
          dropLng: resolvedDestination.longitude,
        ),
      ]);
    });
  }

  @override
  void dispose() {
    _startController.dispose();
    _destController.dispose();
    if (Get.isRegistered<BookMapController>()) {
      Get.delete<BookMapController>();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NoInternetOverlay(
      child: WillPopScope(
        onWillPop: () async => false,
        child: Scaffold(
          body: NotificationListener<ScrollNotification>(
            onNotification: (_) => true,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  backgroundColor: Colors.white,
                  expandedHeight: 320,
                  automaticallyImplyLeading: false,
                  pinned: true,
                  elevation: 0,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      children: [
                        Obx(() {
                          return GoogleMap(
                            compassEnabled: false,
                            myLocationEnabled: true,
                            zoomControlsEnabled: false,
                            myLocationButtonEnabled: false,

                            initialCameraPosition: CameraPosition(
                              target: mapC.pickupPosition ?? const LatLng(0, 0),
                              zoom: 14,
                            ),

                            onMapCreated: (controller) async {
                              await mapC.attachMap(controller);
                            },

                            onCameraIdle: mapC.onCameraIdle,

                            polylines: mapC.polylines.toSet(),
                            markers: mapC.markers.toSet(),

                            gestureRecognizers: {
                              Factory<OneSequenceGestureRecognizer>(
                                () => EagerGestureRecognizer(),
                              ),
                            },
                          );
                        }),

                        Positioned(
                          top: 270,
                          right: 10,
                          child: FloatingActionButton(
                            mini: true,
                            backgroundColor: Colors.white,
                            onPressed: () => mapC.goToCurrentLocation(),
                            child: const Icon(
                              Icons.my_location,
                              color: Colors.black,
                              size: 20,
                            ),
                          ),
                        ),

                        Positioned(
                          top: 50,
                          left: 15,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => const CommonBottomNavigation(
                                        initialIndex: 0,
                                      ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                AppImages.backImage,
                                height: 25,
                                width: 25,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 15,
                    ),
                    child: Column(
                      children: [
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
                          child: Column(
                            children: [
                              CustomTextFields.plainTextField(
                                autofocus: false,
                                Style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.commonBlack.withOpacity(0.6),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                readOnly: true,
                                onTap: () async {
                                  final selected = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => BookRideSearchScreen(
                                            isPickup: true,
                                            pickupData: {
                                              'description':
                                                  _startController.text,
                                              'lat':
                                                  mapC.pickupPosition?.latitude,
                                              'lng':
                                                  mapC
                                                      .pickupPosition
                                                      ?.longitude,
                                            },
                                            destinationData: {
                                              'description':
                                                  _destController.text,
                                              'lat':
                                                  mapC
                                                      .destinationPosition
                                                      ?.latitude,
                                              'lng':
                                                  mapC
                                                      .destinationPosition
                                                      ?.longitude,
                                            },
                                          ),
                                    ),
                                  );

                                  if (selected != null &&
                                      selected['pickup'] != null) {
                                    final pickup = selected['pickup'];
                                    final LatLng updatedPickupLoc =
                                        pickup['location'];

                                    _startController.text =
                                        pickup['description'];

                                    mapC.pickupPosition = updatedPickupLoc;
                                    await mapC.drawPolyline();
                                    await mapC.fitBounds();

                                    // reset marker time cache
                                    driverController.markerAdded.value = false;
                                  }
                                },
                                hintStyle: const TextStyle(fontSize: 11),
                                imgHeight: 17,
                                controller: _startController,
                                containerColor: AppColors.commonWhite,
                                leadingImage: AppImages.circleStart,
                                title: 'Search for an address or landmark',
                              ),
                              const Divider(
                                height: 0,
                                color: AppColors.containerColor,
                              ),

                              CustomTextFields.plainTextField(
                                autofocus: false,
                                Style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.commonBlack.withOpacity(0.6),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                readOnly: true,
                                onTap: () async {
                                  final selected = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => BookRideSearchScreen(
                                            isPickup: false,
                                            pickupData: {
                                              'description':
                                                  _startController.text,
                                              'lat':
                                                  mapC.pickupPosition?.latitude,
                                              'lng':
                                                  mapC
                                                      .pickupPosition
                                                      ?.longitude,
                                            },
                                            destinationData: {
                                              'description':
                                                  _destController.text,
                                              'lat':
                                                  mapC
                                                      .destinationPosition
                                                      ?.latitude,
                                              'lng':
                                                  mapC
                                                      .destinationPosition
                                                      ?.longitude,
                                            },
                                          ),
                                    ),
                                  );

                                  if (selected != null &&
                                      selected['destination'] != null) {
                                    final dest = selected['destination'];
                                    final LatLng updatedDestLoc =
                                        dest['location'];

                                    _destController.text = dest['description'];

                                    mapC.destinationPosition = updatedDestLoc;
                                    await mapC.drawPolyline();
                                    await mapC.fitBounds();

                                    driverController.markerAdded.value = false;
                                  }
                                },
                                controller: _destController,
                                hintStyle: const TextStyle(fontSize: 11),
                                imgHeight: 17,
                                containerColor: AppColors.commonWhite,
                                leadingImage: AppImages.rectangleDest,
                                title: 'Enter destination',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        /// Ride Only vs Shared toggle
                        Obx(() {
                          return PackageContainer.bookContainers(
                            isSendSelected: mapC.isRideOnly.value,
                            onSelectionChanged: (selected) async {
                              if (selected == mapC.isRideOnly.value) return;
                              mapC.isRideOnly.value = selected;

                              AppLogger.log.i(
                                'Ride type: ${mapC.isRideOnly.value ? 'Ride Only' : 'Shared'}',
                              );

                              if (mapC.pickupPosition == null ||
                                  mapC.destinationPosition == null) {
                                AppToasts.customToast(
                                  context,
                                  'Pickup or destination is missing',
                                );
                                return;
                              }
                              // no API call: already prefetched
                            },
                          );
                        }),

                        const SizedBox(height: 20),

                        Obx(() {
                          if (driverController.isGetLoading.value) {
                            return AppLoader.circularLoader();
                          }

                          final bool rideOnly = mapC.isRideOnly.value;

                          final normalDrivers = driverController.serviceType;
                          final sharedDrivers =
                              driverController.sharedServiceType;

                          final hasDrivers =
                              rideOnly
                                  ? normalDrivers.isNotEmpty
                                  : sharedDrivers.isNotEmpty;

                          if (!hasDrivers) {
                            return const Center(
                              child: Text(
                                'No drivers in your location',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            );
                          }

                          // ---------- RIDE ONLY ----------
                          if (rideOnly) {
                            final luxuryDriver = normalDrivers.firstWhereOrNull(
                              (e) =>
                                  e.driverId.carType?.toLowerCase() == 'luxury',
                            );
                            final sedanDriver = normalDrivers.firstWhereOrNull(
                              (e) =>
                                  e.driverId.carType?.toLowerCase() == 'sedan',
                            );

                            // Set default marker once
                            if (!driverController.markerAdded.value &&
                                (luxuryDriver != null || sedanDriver != null)) {
                              final defaultDriver =
                                  luxuryDriver ?? sedanDriver!;
                              driverController.estimatedTime.value =
                                  defaultDriver.estimatedTime?.toString() ?? '';

                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                mapC.updateMarkersDebounced(
                                  pickupLabel: widget.pickupAddress,
                                  dropLabel: widget.destinationAddress,
                                  estimatedMin:
                                      driverController.estimatedTime.value,
                                );
                                driverController.markerAdded.value = true;
                              });
                            }

                            return Column(
                              children: [
                                if (luxuryDriver != null)
                                  PackageContainer.bookCarTypeContainer(
                                    borderColor:
                                        driverController
                                                    .selectedCarType
                                                    .value ==
                                                'Luxury'
                                            ? AppColors.commonBlack
                                            : AppColors.containerColor,
                                    carImg: AppImages.luxuryCar,
                                    onTap: () {
                                      driverController.selectedCarType.value =
                                          'Luxury';
                                      driverController.estimatedTime.value =
                                          luxuryDriver.estimatedTime
                                              .toString() ??
                                          '';

                                      mapC.updateMarkersDebounced(
                                        pickupLabel: widget.pickupAddress,
                                        dropLabel: widget.destinationAddress,
                                        estimatedMin:
                                            driverController
                                                .estimatedTime
                                                .value,
                                      );
                                    },
                                    carTitle: 'Luxury',
                                    carMinRate:
                                        luxuryDriver.estimatedPrice.toString(),
                                    carSubTitle: 'Comfy, Economical Cars',
                                    arrivingTime:
                                        '${luxuryDriver.estimatedTime ?? 0} min',
                                  ),
                                const SizedBox(height: 20),
                                if (sedanDriver != null)
                                  PackageContainer.bookCarTypeContainer(
                                    borderColor:
                                        driverController
                                                    .selectedCarType
                                                    .value ==
                                                'Sedan'
                                            ? AppColors.commonBlack
                                            : AppColors.containerColor,
                                    carImg: AppImages.sedan,
                                    onTap: () {
                                      driverController.selectedCarType.value =
                                          'Sedan';
                                      driverController.estimatedTime.value =
                                          sedanDriver.estimatedTime
                                              .toString() ??
                                          '';

                                      mapC.updateMarkersDebounced(
                                        pickupLabel: widget.pickupAddress,
                                        dropLabel: widget.destinationAddress,
                                        estimatedMin:
                                            driverController
                                                .estimatedTime
                                                .value,
                                      );
                                    },
                                    carTitle: 'Sedan',
                                    carMinRate:
                                        sedanDriver.estimatedPrice.toString(),
                                    carMaxRate:
                                        sedanDriver.estimatedPrice.toString(),
                                    carSubTitle: 'Comfy, Economical Cars',
                                    arrivingTime:
                                        '${sedanDriver.estimatedTime ?? 0} min',
                                  ),
                              ],
                            );
                          }

                          // ---------- SHARED ----------
                          final luxuryShared = sharedDrivers.firstWhereOrNull(
                            (e) =>
                                e.driverId?.carType?.toLowerCase() == 'luxury',
                          );
                          final sedanShared = sharedDrivers.firstWhereOrNull(
                            (e) =>
                                e.driverId?.carType?.toLowerCase() == 'sedan',
                          );

                          if (!driverController.markerAdded.value &&
                              (luxuryShared != null || sedanShared != null)) {
                            final defaultDriver = luxuryShared ?? sedanShared;
                            driverController.estimatedTime.value =
                                defaultDriver?.estimatedTime?.toString() ?? '';

                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              mapC.updateMarkersDebounced(
                                pickupLabel: widget.pickupAddress,
                                dropLabel: widget.destinationAddress,
                                estimatedMin:
                                    driverController.estimatedTime.value,
                              );
                              driverController.markerAdded.value = true;
                            });
                          }

                          return Column(
                            children: [
                              if (luxuryShared != null)
                                PackageContainer.bookCarTypeContainer(
                                  borderColor:
                                      driverController.selectedCarType.value ==
                                              'Luxury'
                                          ? AppColors.commonBlack
                                          : AppColors.containerColor,
                                  carImg: AppImages.luxuryCar,
                                  onTap: () {
                                    driverController.selectedCarType.value =
                                        'Luxury';
                                    driverController
                                        .selectedSharedDriver
                                        .value = luxuryShared;
                                    driverController.estimatedTime.value =
                                        luxuryShared.estimatedTime
                                            ?.toString() ??
                                        '';

                                    mapC.updateMarkersDebounced(
                                      pickupLabel: widget.pickupAddress,
                                      dropLabel: widget.destinationAddress,
                                      estimatedMin:
                                          driverController.estimatedTime.value,
                                    );
                                  },
                                  carTitle: 'Luxury',
                                  carMinRate:
                                      luxuryShared.estimatedPrice.toString(),
                                  carSubTitle: 'Shared comfy ride',
                                  arrivingTime:
                                      '${luxuryShared.estimatedTime ?? 0} min',
                                ),
                              const SizedBox(height: 20),
                              if (sedanShared != null)
                                PackageContainer.bookCarTypeContainer(
                                  borderColor:
                                      driverController.selectedCarType.value ==
                                              'Sedan'
                                          ? AppColors.commonBlack
                                          : AppColors.containerColor,
                                  carImg: AppImages.sedan,
                                  onTap: () {
                                    driverController.selectedCarType.value =
                                        'Sedan';
                                    driverController
                                        .selectedSharedDriver
                                        .value = sedanShared;
                                    driverController.estimatedTime.value =
                                        sedanShared.estimatedTime?.toString() ??
                                        '';

                                    mapC.updateMarkersDebounced(
                                      pickupLabel: widget.pickupAddress,
                                      dropLabel: widget.destinationAddress,
                                      estimatedMin:
                                          driverController.estimatedTime.value,
                                    );
                                  },
                                  carTitle: 'Sedan',
                                  carMinRate:
                                      sedanShared.estimatedPrice.toString(),
                                  carMaxRate:
                                      sedanShared.estimatedPrice.toString(),
                                  carSubTitle: 'Shared comfy ride',
                                  arrivingTime:
                                      '${sedanShared.estimatedTime ?? 0} min',
                                ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          bottomNavigationBar: Obx(
            () => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child:
                  driverController.isLoading.value
                      ? AppLoader.appLoader()
                      : AppButtons.button(
                        buttonColor:
                            driverController.selectedCarType.value.isEmpty
                                ? AppColors.containerColor
                                : AppColors.commonBlack,
                        textColor: Colors.white,
                        onTap: () async {
                          if (driverController.selectedCarType.value.isEmpty) {
                            Get.closeAllSnackbars();
                            Get.snackbar(
                              'Info',
                              'Please select a car before proceeding.',
                              backgroundColor: AppColors.commonBlack,
                              colorText: AppColors.commonWhite,
                            );
                            return;
                          }

                          final selectedCarType =
                              driverController.selectedCarType.value;

                          if (mapC.isRideOnly.value) {
                            final result = await driverController
                                .createBookingCar(
                                  carType: selectedCarType,
                                  fromLatitude:
                                      mapC.pickupPosition?.latitude ?? 0.0,
                                  fromLongitude:
                                      mapC.pickupPosition?.longitude ?? 0.0,
                                  toLatitude:
                                      mapC.destinationPosition?.latitude ?? 0.0,
                                  toLongitude:
                                      mapC.destinationPosition?.longitude ??
                                      0.0,
                                  customerId: '',
                                  context: context,
                                );

                            if (result == null) {
                              final bookingId =
                                  driverController.carBooking.value?.bookingId;

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => ConfirmBooking(
                                        carType: selectedCarType,
                                        bookingId: bookingId,
                                        selectedCarType: selectedCarType,
                                        pickupData: {
                                          'description': widget.pickupAddress,
                                          'lat':
                                              mapC.pickupPosition?.latitude ??
                                              0.0,
                                          'lng':
                                              mapC.pickupPosition?.longitude ??
                                              0.0,
                                        },
                                        destinationData: {
                                          'description':
                                              widget.destinationAddress,
                                          'lat':
                                              mapC
                                                  .destinationPosition
                                                  ?.latitude ??
                                              0.0,
                                          'lng':
                                              mapC
                                                  .destinationPosition
                                                  ?.longitude ??
                                              0.0,
                                        },
                                        pickupAddress: widget.pickupAddress,
                                        destinationAddress:
                                            widget.destinationAddress,
                                      ),
                                ),
                              );
                            }
                          } else {
                            final sharedDriver =
                                driverController.selectedSharedDriver.value;
                            if (sharedDriver == null) {
                              Get.snackbar(
                                'Info',
                                'Please select a shared car option first.',
                                backgroundColor: AppColors.commonBlack,
                                colorText: AppColors.commonWhite,
                              );
                              return;
                            }

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => RideShareScreen(
                                      occupiedSeats: sharedDriver.occupiedSeats,
                                      maxSeats: sharedDriver.maxSeats,
                                      sharedDriver: sharedDriver,
                                      seats: sharedDriver.seats,
                                      selectedCarType: selectedCarType,
                                      pickupData: {
                                        'description': widget.pickupAddress,
                                        'lat':
                                            mapC.pickupPosition?.latitude ??
                                            0.0,
                                        'lng':
                                            mapC.pickupPosition?.longitude ??
                                            0.0,
                                      },
                                      destinationData: {
                                        'description':
                                            widget.destinationAddress,
                                        'lat':
                                            mapC
                                                .destinationPosition
                                                ?.latitude ??
                                            0.0,
                                        'lng':
                                            mapC
                                                .destinationPosition
                                                ?.longitude ??
                                            0.0,
                                      },
                                      pickupAddress: widget.pickupAddress,
                                      destinationAddress:
                                          widget.destinationAddress,
                                    ),
                              ),
                            );
                          }
                        },
                        text:
                            driverController.selectedCarType.value.isEmpty
                                ? 'Book'
                                : 'Book ${driverController.selectedCarType.value}',
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

// import 'dart:math' as math;
// import 'dart:convert';
// import 'dart:typed_data';
// import 'dart:ui' as ui;
//
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // for rootBundle
// import 'package:get/get.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:geocoding/geocoding.dart';
// import 'package:hopper/Presentation/BookRide/SharedRideScreens/Screens/ride_share_screen.dart';
// import 'package:http/http.dart' as http;
//
// import 'package:hopper/Core/Consents/app_colors.dart';
// import 'package:hopper/Core/Consents/app_logger.dart';
// import 'package:hopper/Core/Utility/app_buttons.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/Core/Utility/app_loader.dart';
// import 'package:hopper/Core/Utility/app_toasts.dart';
//
// import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
// import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
// import 'package:hopper/Presentation/BookRide/Screens/confirm_booking.dart';
//
// import 'package:hopper/Presentation/BookRide/Screens/search_screen.dart';
//
// import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
// import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
//
// import 'package:hopper/api/repository/api_consents.dart';
// import 'package:hopper/driver_detail_controller.dart';
// import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
//
// class BookMapScreen extends StatefulWidget {
//   final Map<String, dynamic> pickupData;
//   final Map<String, dynamic> destinationData;
//   final String pickupAddress;
//   final String destinationAddress;
//
//   const BookMapScreen({
//     super.key,
//     required this.pickupData,
//     required this.destinationData,
//     required this.pickupAddress,
//     required this.destinationAddress,
//   });
//
//   @override
//   State<BookMapScreen> createState() => _BookMapScreenState();
// }
//
// class _BookMapScreenState extends State<BookMapScreen> {
//   final TextEditingController _startController = TextEditingController();
//   final TextEditingController _destController = TextEditingController();
//
//   final DriverSearchController driverController = Get.put(
//     DriverSearchController(),
//   );
//
//   LatLng? _pickupPosition;
//   LatLng? _destinationPosition;
//
//   BitmapDescriptor? _startIcon;
//   BitmapDescriptor? _destinationIcon;
//   Set<Marker> _markers = {};
//   Offset? _pickupOffset;
//   Offset? _dropOffset;
//   bool _markerAdded = false;
//   String? _estimatedTime;
//
//   Set<Polyline> _polylines = {};
//   GoogleMapController? _mapController;
//   bool isSendSelected = true; // true = normal ride, false = shared ride
//
//   String _address = 'Search...';
//   LatLng? _currentPosition;
//
//   String? _mapStyle;
//
//   @override
//   void initState() {
//     super.initState();
//     _loadMapStyle();
//     _loadCustomMarkers();
//
//     LatLng? pickupLocation;
//     LatLng? destinationLocation;
//
//     if (widget.pickupData.containsKey('location')) {
//       pickupLocation = widget.pickupData['location'];
//     } else if (widget.pickupData.containsKey('lat') &&
//         widget.pickupData.containsKey('lng')) {
//       pickupLocation = LatLng(
//         widget.pickupData['lat'],
//         widget.pickupData['lng'],
//       );
//     }
//
//     if (widget.destinationData.containsKey('location')) {
//       destinationLocation = widget.destinationData['location'];
//     } else if (widget.destinationData.containsKey('lat') &&
//         widget.destinationData.containsKey('lng')) {
//       destinationLocation = LatLng(
//         widget.destinationData['lat'],
//         widget.destinationData['lng'],
//       );
//     }
//
//     if (pickupLocation == null || destinationLocation == null) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         Get.back();
//         Get.snackbar("Error", "Location data is missing");
//       });
//       return;
//     }
//
//     final distance = Geolocator.distanceBetween(
//       pickupLocation.latitude,
//       pickupLocation.longitude,
//       destinationLocation.latitude,
//       destinationLocation.longitude,
//     );
//
//     // if (distance < 1000) {
//     //   WidgetsBinding.instance.addPostFrameCallback((_) {
//     //     Get.back();
//     //     Future.delayed(const Duration(milliseconds: 300), () {
//     //       AppToasts.customToast(
//     //         Get.context!,
//     //         'Pickup and destination must be more than 1 km apart.',
//     //       );
//     //     });
//     //   });
//     //   return;
//     // }
//
//     _pickupPosition = pickupLocation;
//     _destinationPosition = destinationLocation;
//
//     // ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â¹ Default: load Ride Only drivers initially
//     // ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â¹ Prefetch BOTH ride only & shared once
//     WidgetsBinding.instance.addPostFrameCallback((_) async {
//       await Future.wait([
//         driverController.getDriverSearch(
//           pickupLat: _pickupPosition!.latitude,
//           pickupLng: _pickupPosition!.longitude,
//           dropLat: _destinationPosition!.latitude,
//           dropLng: _destinationPosition!.longitude,
//         ),
//         driverController.getSharedDriverSearch(
//           pickupLat: _pickupPosition!.latitude,
//           pickupLng: _pickupPosition!.longitude,
//           dropLat: _destinationPosition!.latitude,
//           dropLng: _destinationPosition!.longitude,
//         ),
//       ]);
//     });
//
//     _drawPolyline();
//   }
//
//   Future<void> _loadMapStyle() async {
//     _mapStyle = await rootBundle.loadString('assets/map_style/map_style.json');
//   }
//
//   Future<void> _loadCustomMarkers() async {
//     _startIcon = await BitmapDescriptor.fromAssetImage(
//       const ImageConfiguration(size: Size(65, 65)),
//       AppImages.circleStart,
//     );
//     _destinationIcon = await BitmapDescriptor.fromAssetImage(
//       const ImageConfiguration(size: Size(65, 65)),
//       AppImages.rectangleDest,
//     );
//     setState(() {});
//   }
//
//   void _fitBounds() async {
//     if (_pickupPosition == null ||
//         _destinationPosition == null ||
//         _mapController == null)
//       return;
//
//     double minLat = math.min(
//       _pickupPosition!.latitude,
//       _destinationPosition!.latitude,
//     );
//     double maxLat = math.max(
//       _pickupPosition!.latitude,
//       _destinationPosition!.latitude,
//     );
//     double minLng = math.min(
//       _pickupPosition!.longitude,
//       _destinationPosition!.longitude,
//     );
//     double maxLng = math.max(
//       _pickupPosition!.longitude,
//       _destinationPosition!.longitude,
//     );
//
//     const minDelta = 0.009;
//     if ((maxLat - minLat) < minDelta) {
//       minLat -= minDelta;
//       maxLat += minDelta;
//     }
//     if ((maxLng - minLng) < minDelta) {
//       minLng -= minDelta;
//       maxLng += minDelta;
//     }
//
//     final bounds = LatLngBounds(
//       southwest: LatLng(minLat, minLng),
//       northeast: LatLng(maxLat, maxLng),
//     );
//
//     await _mapController!.animateCamera(
//       CameraUpdate.newLatLngBounds(bounds, 120),
//     );
//   }
//
//   Future<void> _drawPolyline() async {
//     if (_pickupPosition == null || _destinationPosition == null) return;
//
//     final apiKey = ApiConsents.googleMapApiKey;
//     final url =
//         'https://maps.googleapis.com/maps/api/directions/json?origin=${_pickupPosition!.latitude},${_pickupPosition!.longitude}&destination=${_destinationPosition!.latitude},${_destinationPosition!.longitude}&key=$apiKey';
//
//     final response = await http.get(Uri.parse(url));
//     final data = json.decode(response.body);
//
//     if (data['status'] == 'OK') {
//       final encoded = data['routes'][0]['overview_polyline']['points'];
//       final points = _decodePolyline(encoded);
//
//       setState(() {
//         _polylines = {
//           Polyline(
//             polylineId: const PolylineId("route"),
//             points: points,
//             color: AppColors.commonBlack,
//             width: 3,
//           ),
//         };
//       });
//     } else {
//       print("Error fetching directions: ${data['status']}");
//     }
//   }
//
//   List<LatLng> _decodePolyline(String encoded) {
//     final points = <LatLng>[];
//     int index = 0, len = encoded.length;
//     int lat = 0, lng = 0;
//
//     while (index < len) {
//       int b, shift = 0, result = 0;
//       do {
//         b = encoded.codeUnitAt(index++) - 63;
//         result |= (b & 0x1f) << shift;
//         shift += 5;
//       } while (b >= 0x20);
//       final dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
//       lat += dlat;
//
//       shift = 0;
//       result = 0;
//       do {
//         b = encoded.codeUnitAt(index++) - 63;
//         result |= (b & 0x1f) << shift;
//         shift += 5;
//       } while (b >= 0x20);
//       final dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
//       lng += dlng;
//
//       points.add(LatLng(lat / 1E5, lng / 1E5));
//     }
//
//     return points;
//   }
//
//   Future<void> _getAddressFromLatLng(LatLng position) async {
//     try {
//       final placemarks = await placemarkFromCoordinates(
//         position.latitude,
//         position.longitude,
//       );
//       if (placemarks.isNotEmpty) {
//         final placemark = placemarks.first;
//         setState(() {
//           _address = "${placemark.street}, ${placemark.locality}";
//         });
//       }
//     } catch (e) {
//       print("Error getting address: $e");
//     }
//   }
//
//   void _goToCurrentLocation() async {
//     final position = await Geolocator.getCurrentPosition(
//       desiredAccuracy: LocationAccuracy.high,
//     );
//
//     final latLng = LatLng(position.latitude, position.longitude);
//
//     _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 17));
//   }
//
//   Future<BitmapDescriptor> createCustomMarkerWithLabel({
//     required String label,
//     required String assetPath,
//     String? timeText, // null means no time box
//     double width = 300,
//     double height = 100,
//     double iconSize = 50,
//   }) async {
//     final recorder = ui.PictureRecorder();
//     final canvas = Canvas(recorder);
//     final paint = Paint();
//
//     const double cornerRadius = 0;
//     const double padding = 10;
//     const double timeBoxWidth = 60;
//
//     final bool showTime = timeText != null;
//     final double labelBoxWidth =
//         showTime ? width - timeBoxWidth - (padding * 3) : width - (padding * 2);
//     final double totalHeight = height + iconSize + 10;
//
//     // Background
//     final backgroundBox = RRect.fromLTRBR(
//       0,
//       0,
//       width,
//       height,
//       const Radius.circular(cornerRadius),
//     );
//     paint.color = Colors.white;
//     canvas.drawRRect(backgroundBox, paint);
//
//     // Time Box
//     if (showTime) {
//       paint.color = Colors.black;
//       final timeBox = RRect.fromLTRBR(
//         0,
//         0,
//         padding + timeBoxWidth,
//         height,
//         const Radius.circular(0),
//       );
//       canvas.drawRRect(timeBox, paint);
//
//       final timePara =
//           ui.ParagraphBuilder(
//               ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 2),
//             )
//             ..pushStyle(
//               ui.TextStyle(
//                 color: Colors.white,
//                 fontSize: 22,
//                 fontWeight: FontWeight.w400,
//               ),
//             )
//             ..addText(timeText!.replaceAll(" ", "\n"));
//
//       final timeParagraph = timePara.build();
//       timeParagraph.layout(const ui.ParagraphConstraints(width: timeBoxWidth));
//       canvas.drawParagraph(
//         timeParagraph,
//         Offset(padding, (height - timeParagraph.height) / 2),
//       );
//     }
//
//     // Label
//     final labelPara =
//         ui.ParagraphBuilder(
//             ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 2),
//           )
//           ..pushStyle(
//             ui.TextStyle(
//               color: Colors.black,
//               fontSize: 29,
//               fontWeight: FontWeight.w600,
//             ),
//           )
//           ..addText(label);
//
//     final labelParagraph = labelPara.build();
//     labelParagraph.layout(ui.ParagraphConstraints(width: labelBoxWidth));
//
//     final labelOffsetX = showTime ? padding + timeBoxWidth + padding : padding;
//     canvas.drawParagraph(
//       labelParagraph,
//       Offset(labelOffsetX, (height - labelParagraph.height) / 2),
//     );
//
//     // Marker Icon
//     final data = await rootBundle.load(assetPath);
//     final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
//     final frame = await codec.getNextFrame();
//     final markerImage = frame.image;
//
//     final imageOffset = Offset((width - iconSize) / 2, height + 5);
//     canvas.drawImageRect(
//       markerImage,
//       Rect.fromLTWH(
//         0,
//         0,
//         markerImage.width.toDouble(),
//         markerImage.height.toDouble(),
//       ),
//       Rect.fromLTWH(imageOffset.dx, imageOffset.dy, iconSize, iconSize),
//       paint,
//     );
//
//     final picture = recorder.endRecording();
//     final finalImage = await picture.toImage(
//       width.toInt(),
//       totalHeight.toInt(),
//     );
//     final byteData = await finalImage.toByteData(
//       format: ui.ImageByteFormat.png,
//     );
//
//     return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
//   }
//
//   void _addMarkers(String estimatedTime) async {
//     if (_pickupPosition == null || _destinationPosition == null) return;
//
//     final startIcon = await createCustomMarkerWithLabel(
//       timeText: estimatedTime.isNotEmpty ? '$estimatedTime MIN' : null,
//       label: widget.pickupAddress,
//       assetPath: AppImages.circleStart,
//     );
//
//     final destIcon = await createCustomMarkerWithLabel(
//       timeText: null,
//       label: widget.destinationAddress,
//       assetPath: AppImages.rectangleDest,
//     );
//
//     _markers.clear();
//
//     _markers.add(
//       Marker(
//         markerId: const MarkerId("pickup"),
//         icon: startIcon,
//         position: _pickupPosition!,
//       ),
//     );
//
//     _markers.add(
//       Marker(
//         markerId: const MarkerId("destination"),
//         icon: destIcon,
//         position: _destinationPosition!,
//       ),
//     );
//
//     if (mounted) {
//       setState(() {});
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     _startController.text = widget.pickupAddress;
//     _destController.text = widget.destinationAddress;
//
//     return NoInternetOverlay(
//       child: WillPopScope(
//         onWillPop: () async => false,
//         child: Scaffold(
//           body: NotificationListener<ScrollNotification>(
//             onNotification: (_) => true,
//             child: CustomScrollView(
//               physics: const BouncingScrollPhysics(),
//               slivers: [
//                 SliverAppBar(
//                   backgroundColor: Colors.white,
//                   expandedHeight: 320,
//                   automaticallyImplyLeading: false,
//                   pinned: true,
//                   elevation: 0,
//                   flexibleSpace: FlexibleSpaceBar(
//                     background: Stack(
//                       children: [
//                         GoogleMap(
//                           compassEnabled: false,
//                           myLocationEnabled: true,
//                           zoomControlsEnabled: false,
//                           myLocationButtonEnabled: false,
//                           initialCameraPosition: CameraPosition(
//                             target: _pickupPosition ?? const LatLng(0, 0),
//                             zoom: 14,
//                           ),
//                           onMapCreated: (controller) async {
//                             _mapController = controller;
//                             if (!mounted) return;
//
//                             final style = await DefaultAssetBundle.of(
//                               context,
//                             ).loadString('assets/map_style/map_style.json');
//                             _mapController!.setMapStyle(style);
//
//                             _fitBounds();
//                           },
//                           onCameraIdle: () async {
//                             final bounds =
//                                 await _mapController?.getVisibleRegion();
//                             if (bounds != null) {
//                               final centerLat =
//                                   (bounds.northeast.latitude +
//                                       bounds.southwest.latitude) /
//                                   2;
//                               final centerLng =
//                                   (bounds.northeast.longitude +
//                                       bounds.southwest.longitude) /
//                                   2;
//
//                               _currentPosition = LatLng(centerLat, centerLng);
//                               await _getAddressFromLatLng(_currentPosition!);
//                               setState(() {});
//                             }
//                           },
//                           polylines: _polylines,
//                           markers: _markers,
//                         ),
//                         Positioned(
//                           top: 270,
//                           right: 10,
//                           child: FloatingActionButton(
//                             mini: true,
//                             backgroundColor: Colors.white,
//                             onPressed: _goToCurrentLocation,
//                             child: const Icon(
//                               Icons.my_location,
//                               color: Colors.black,
//                               size: 20,
//                             ),
//                           ),
//                         ),
//                         Positioned(
//                           top: 50,
//                           left: 15,
//                           child: GestureDetector(
//                             onTap: () async {
//                               Navigator.pushReplacement(
//                                 context,
//                                 MaterialPageRoute(
//                                   builder:
//                                       (context) => const CommonBottomNavigation(
//                                         initialIndex: 0,
//                                       ),
//                                 ),
//                               );
//                             },
//                             child: Container(
//                               padding: const EdgeInsets.all(5),
//                               decoration: BoxDecoration(
//                                 color: Colors.white,
//                                 borderRadius: BorderRadius.circular(30),
//                                 boxShadow: const [
//                                   BoxShadow(
//                                     color: Colors.black12,
//                                     blurRadius: 4,
//                                   ),
//                                 ],
//                               ),
//                               child: Image.asset(
//                                 AppImages.backImage,
//                                 height: 25,
//                                 width: 25,
//                               ),
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//                 SliverToBoxAdapter(
//                   child: Padding(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 15,
//                       vertical: 15,
//                     ),
//                     child: Column(
//                       children: [
//                         Container(
//                           decoration: BoxDecoration(
//                             color: Colors.white,
//                             borderRadius: BorderRadius.circular(12),
//                             boxShadow: const [
//                               BoxShadow(
//                                 color: Colors.black12,
//                                 blurRadius: 8,
//                                 offset: Offset(0, 4),
//                               ),
//                             ],
//                           ),
//                           child: Column(
//                             children: [
//                               CustomTextFields.plainTextField(
//                                 autofocus: false,
//                                 Style: TextStyle(
//                                   fontSize: 12,
//                                   color: AppColors.commonBlack.withOpacity(0.6),
//                                   overflow: TextOverflow.ellipsis,
//                                 ),
//                                 readOnly: true,
//                                 onTap: () async {
//                                   final selected = await Navigator.push(
//                                     context,
//                                     MaterialPageRoute(
//                                       builder:
//                                           (_) => BookRideSearchScreen(
//                                             isPickup: true,
//                                             pickupData: {
//                                               'description':
//                                                   _startController.text,
//                                               'lat': _pickupPosition?.latitude,
//                                               'lng': _pickupPosition?.longitude,
//                                             },
//                                             destinationData: {
//                                               'description':
//                                                   _destController.text,
//                                               'lat':
//                                                   _destinationPosition
//                                                       ?.latitude,
//                                               'lng':
//                                                   _destinationPosition
//                                                       ?.longitude,
//                                             },
//                                           ),
//                                     ),
//                                   );
//
//                                   if (selected != null &&
//                                       selected['pickup'] != null) {
//                                     final pickup = selected['pickup'];
//                                     final LatLng updatedPickupLoc =
//                                         pickup['location'];
//
//                                     setState(() {
//                                       _startController.text =
//                                           pickup['description'];
//                                       _pickupPosition = updatedPickupLoc;
//                                       _drawPolyline();
//                                       _fitBounds();
//                                     });
//                                   }
//                                 },
//                                 hintStyle: const TextStyle(fontSize: 11),
//                                 imgHeight: 17,
//                                 controller: _startController,
//                                 containerColor: AppColors.commonWhite,
//                                 leadingImage: AppImages.circleStart,
//                                 title: 'Search for an address or landmark',
//                               ),
//                               const Divider(
//                                 height: 0,
//                                 color: AppColors.containerColor,
//                               ),
//                               CustomTextFields.plainTextField(
//                                 autofocus: false,
//                                 Style: TextStyle(
//                                   fontSize: 12,
//                                   color: AppColors.commonBlack.withOpacity(0.6),
//                                   overflow: TextOverflow.ellipsis,
//                                 ),
//                                 readOnly: true,
//                                 onTap: () async {
//                                   final selected = await Navigator.push(
//                                     context,
//                                     MaterialPageRoute(
//                                       builder:
//                                           (_) => BookRideSearchScreen(
//                                             isPickup: false,
//                                             pickupData: {
//                                               'description':
//                                                   _startController.text,
//                                               'lat': _pickupPosition?.latitude,
//                                               'lng': _pickupPosition?.longitude,
//                                             },
//                                             destinationData: {
//                                               'description':
//                                                   _destController.text,
//                                               'lat':
//                                                   _destinationPosition
//                                                       ?.latitude,
//                                               'lng':
//                                                   _destinationPosition
//                                                       ?.longitude,
//                                             },
//                                           ),
//                                     ),
//                                   );
//
//                                   if (selected != null &&
//                                       selected['destination'] != null) {
//                                     final dest = selected['destination'];
//                                     final LatLng updatedDestLoc =
//                                         dest['location'];
//
//                                     setState(() {
//                                       _destController.text =
//                                           dest['description'];
//                                       _destinationPosition = updatedDestLoc;
//                                       _drawPolyline();
//                                       _fitBounds();
//                                     });
//                                   }
//                                 },
//                                 controller: _destController,
//                                 hintStyle: const TextStyle(fontSize: 11),
//                                 imgHeight: 17,
//                                 containerColor: AppColors.commonWhite,
//                                 leadingImage: AppImages.rectangleDest,
//                                 title: 'Enter destination',
//                               ),
//                             ],
//                           ),
//                         ),
//                         const SizedBox(height: 20),
//
//                         /// ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â¹ Ride Only vs Shared toggle + driver search
//                         PackageContainer.bookContainers(
//                           isSendSelected: isSendSelected,
//                           onSelectionChanged: (selected) async {
//                             // if same value, no need to do anything
//                             if (selected == isSendSelected) return;
//
//                             setState(() {
//                               isSendSelected = selected;
//                             });
//                             AppLogger.log.i(
//                               'Ride type: ${isSendSelected ? 'Ride Only' : 'Shared'}',
//                             );
//
//                             if (_pickupPosition == null ||
//                                 _destinationPosition == null) {
//                               AppToasts.customToast(
//                                 context,
//                                 'Pickup or destination is missing',
//                               );
//                               return;
//                             }
//
//                             // ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â¹ No API call here: data already prefetched in initState
//                             // Just rebuild UI -> Obx will show correct list based on isSendSelected
//                           },
//                         ),
//
//                         const SizedBox(height: 20),
//
//                         Obx(() {
//                           if (driverController.isGetLoading.value) {
//                             return AppLoader.circularLoader();
//                           }
//
//                           // true -> Ride Only, false -> Shared Booking
//                           final bool isRideOnly = isSendSelected;
//
//                           final normalDrivers = driverController.serviceType;
//                           final sharedDrivers =
//                               driverController.sharedServiceType;
//
//                           final hasDrivers =
//                               isRideOnly
//                                   ? normalDrivers.isNotEmpty
//                                   : sharedDrivers.isNotEmpty;
//
//                           if (!hasDrivers) {
//                             return const Center(
//                               child: Text(
//                                 'No drivers in your location',
//                                 style: TextStyle(
//                                   fontSize: 16,
//                                   color: Colors.grey,
//                                 ),
//                               ),
//                             );
//                           }
//
//                           if (isRideOnly) {
//                             final luxuryDriver = normalDrivers.firstWhereOrNull(
//                               (e) =>
//                                   e.driverId.carType?.toLowerCase() == 'luxury',
//                             );
//
//                             final sedanDriver = normalDrivers.firstWhereOrNull(
//                               (e) =>
//                                   e.driverId.carType?.toLowerCase() == 'sedan',
//                             );
//
//                             if (!driverController.markerAdded.value &&
//                                 (luxuryDriver != null || sedanDriver != null)) {
//                               final defaultDriver = luxuryDriver ?? sedanDriver;
//                               driverController.estimatedTime.value =
//                                   defaultDriver.estimatedTime?.toString() ??
//                                   '';
//                               WidgetsBinding.instance.addPostFrameCallback((_) {
//                                 _addMarkers(
//                                   driverController.estimatedTime.value,
//                                 );
//                                 driverController.markerAdded.value = true;
//                               });
//                             }
//
//                             return Column(
//                               children: [
//                                 if (luxuryDriver != null)
//                                   PackageContainer.bookCarTypeContainer(
//                                     borderColor:
//                                         driverController
//                                                     .selectedCarType
//                                                     .value ==
//                                                 'Luxury'
//                                             ? AppColors.commonBlack
//                                             : AppColors.containerColor,
//                                     carImg: AppImages.luxuryCar,
//                                     onTap: () {
//                                       driverController.selectedCarType.value =
//                                           'Luxury';
//                                       driverController.estimatedTime.value =
//                                           luxuryDriver.estimatedTime
//                                               ?.toString() ??
//                                           '';
//                                       _addMarkers(
//                                         driverController.estimatedTime.value,
//                                       );
//                                     },
//                                     carTitle: 'Luxury',
//                                     carMinRate:
//                                         luxuryDriver.estimatedPrice.toString(),
//                                     carSubTitle: 'Comfy, Economical Cars',
//                                     arrivingTime:
//                                         '${luxuryDriver.estimatedTime ?? 0} min',
//                                   ),
//                                 const SizedBox(height: 20),
//                                 if (sedanDriver != null)
//                                   PackageContainer.bookCarTypeContainer(
//                                     borderColor:
//                                         driverController
//                                                     .selectedCarType
//                                                     .value ==
//                                                 'Sedan'
//                                             ? AppColors.commonBlack
//                                             : AppColors.containerColor,
//                                     carImg: AppImages.sedan,
//                                     onTap: () {
//                                       driverController.selectedCarType.value =
//                                           'Sedan';
//                                       driverController.estimatedTime.value =
//                                           sedanDriver.estimatedTime
//                                               ?.toString() ??
//                                           '';
//                                       _addMarkers(
//                                         driverController.estimatedTime.value,
//                                       );
//                                     },
//                                     carTitle: 'Sedan',
//                                     carMinRate:
//                                         sedanDriver.estimatedPrice.toString(),
//                                     carMaxRate:
//                                         sedanDriver.estimatedPrice.toString(),
//                                     carSubTitle: 'Comfy, Economical Cars',
//                                     arrivingTime:
//                                         '${sedanDriver.estimatedTime ?? 0} min',
//                                   ),
//                               ],
//                             );
//                           }
//
//                           // ========= SHARED =========
//                           final luxuryShared = sharedDrivers.firstWhereOrNull(
//                             (e) =>
//                                 e.driverId?.carType?.toLowerCase() == 'luxury',
//                           );
//
//                           final sedanShared = sharedDrivers.firstWhereOrNull(
//                             (e) =>
//                                 e.driverId?.carType?.toLowerCase() == 'sedan',
//                           );
//
//                           if (!driverController.markerAdded.value &&
//                               (luxuryShared != null || sedanShared != null)) {
//                             final defaultDriver = luxuryShared ?? sedanShared;
//                             driverController.estimatedTime.value =
//                                 defaultDriver?.estimatedTime?.toString() ?? '';
//                             WidgetsBinding.instance.addPostFrameCallback((_) {
//                               _addMarkers(driverController.estimatedTime.value);
//                               driverController.markerAdded.value = true;
//                             });
//                           }
//
//                           return Column(
//                             children: [
//                               if (luxuryShared != null)
//                                 PackageContainer.bookCarTypeContainer(
//                                   borderColor:
//                                       driverController.selectedCarType.value ==
//                                               'Luxury'
//                                           ? AppColors.commonBlack
//                                           : AppColors.containerColor,
//                                   carImg: AppImages.luxuryCar,
//                                   onTap: () {
//                                     driverController.selectedCarType.value =
//                                         'Luxury';
//                                     driverController
//                                         .selectedSharedDriver
//                                         .value = luxuryShared;
//                                     driverController.estimatedTime.value =
//                                         luxuryShared.estimatedTime
//                                             ?.toString() ??
//                                         '';
//                                     _addMarkers(
//                                       driverController.estimatedTime.value,
//                                     );
//                                   },
//                                   carTitle: 'Luxury',
//                                   carMinRate:
//                                       luxuryShared.estimatedPrice.toString(),
//                                   carSubTitle: 'Shared comfy ride',
//                                   arrivingTime:
//                                       '${luxuryShared.estimatedTime ?? 0} min',
//                                 ),
//                               const SizedBox(height: 20),
//                               if (sedanShared != null)
//                                 PackageContainer.bookCarTypeContainer(
//                                   borderColor:
//                                       driverController.selectedCarType.value ==
//                                               'Sedan'
//                                           ? AppColors.commonBlack
//                                           : AppColors.containerColor,
//                                   carImg: AppImages.sedan,
//                                   onTap: () {
//                                     driverController.selectedCarType.value =
//                                         'Sedan';
//                                     driverController
//                                         .selectedSharedDriver
//                                         .value = sedanShared;
//                                     driverController.estimatedTime.value =
//                                         sedanShared.estimatedTime?.toString() ??
//                                         '';
//                                     _addMarkers(
//                                       driverController.estimatedTime.value,
//                                     );
//                                   },
//                                   carTitle: 'Sedan',
//                                   carMinRate:
//                                       sedanShared.estimatedPrice.toString(),
//                                   carMaxRate:
//                                       sedanShared.estimatedPrice.toString(),
//                                   carSubTitle: 'Shared comfy ride',
//                                   arrivingTime:
//                                       '${sedanShared.estimatedTime ?? 0} min',
//                                 ),
//                             ],
//                           );
//                         }),
//                       ],
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//
//           bottomNavigationBar: Obx(
//             () => Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
//               child:
//                   driverController.isLoading.value
//                       ? AppLoader.appLoader()
//                       : AppButtons.button(
//                         buttonColor:
//                             driverController.selectedCarType.value.isEmpty
//                                 ? AppColors.containerColor
//                                 : AppColors.commonBlack,
//                         textColor: Colors.white,
//                         onTap: () async {
//                           if (driverController.selectedCarType.value.isEmpty) {
//                             Get.closeAllSnackbars();
//                             Get.snackbar(
//                               'Info',
//                               'Please select a car before proceeding.',
//                               backgroundColor: AppColors.commonBlack,
//                               colorText: AppColors.commonWhite,
//                             );
//                             return;
//                           }
//
//                           final selectedCarType =
//                               driverController.selectedCarType.value;
//
//                           if (isSendSelected) {
//                             final result = await driverController
//                                 .createBookingCar(
//                                   carType: selectedCarType,
//                                   fromLatitude:
//                                       _pickupPosition?.latitude ?? 0.0,
//                                   fromLongitude:
//                                       _pickupPosition?.longitude ?? 0.0,
//                                   toLatitude:
//                                       _destinationPosition?.latitude ?? 0.0,
//                                   toLongitude:
//                                       _destinationPosition?.longitude ?? 0.0,
//                                   customerId: '',
//                                   context: context,
//                                 );
//
//                             if (result == null) {
//                               final carType =
//                                   driverController.selectedCarType.value;
//                               final bookingId =
//                                   driverController.carBooking.value?.bookingId;
//
//                               Navigator.push(
//                                 context,
//                                 MaterialPageRoute(
//                                   builder:
//                                       (context) => ConfirmBooking(
//                                         carType: carType,
//                                         bookingId: bookingId,
//                                         selectedCarType: selectedCarType,
//                                         pickupData: {
//                                           'description': widget.pickupAddress,
//                                           'lat':
//                                               _pickupPosition?.latitude ?? 0.0,
//                                           'lng':
//                                               _pickupPosition?.longitude ?? 0.0,
//                                         },
//                                         destinationData: {
//                                           'description':
//                                               widget.destinationAddress,
//                                           'lat':
//                                               _destinationPosition?.latitude ??
//                                               0.0,
//                                           'lng':
//                                               _destinationPosition?.longitude ??
//                                               0.0,
//                                         },
//                                         pickupAddress: widget.pickupAddress,
//                                         destinationAddress:
//                                             widget.destinationAddress,
//                                       ),
//                                 ),
//                               );
//                             }
//                           } else {
//                             final sharedDriver =
//                                 driverController.selectedSharedDriver.value;
//                             if (sharedDriver == null) {
//                               Get.snackbar(
//                                 'Info',
//                                 'Please select a shared car option first.',
//                                 backgroundColor: AppColors.commonBlack,
//                                 colorText: AppColors.commonWhite,
//                               );
//                               return;
//                             }
//
//                             Navigator.push(
//                               context,
//                               MaterialPageRoute(
//                                 builder:
//                                     (context) => RideShareScreen(
//                                       occupiedSeats: sharedDriver.occupiedSeats,
//                                       maxSeats: sharedDriver.maxSeats,
//                                       sharedDriver: sharedDriver,
//                                       seats: sharedDriver.seats,
//                                       selectedCarType: selectedCarType,
//                                       pickupData: {
//                                         'description': widget.pickupAddress,
//                                         'lat': _pickupPosition?.latitude ?? 0.0,
//                                         'lng':
//                                             _pickupPosition?.longitude ?? 0.0,
//                                       },
//                                       destinationData: {
//                                         'description':
//                                             widget.destinationAddress,
//                                         'lat':
//                                             _destinationPosition?.latitude ??
//                                             0.0,
//                                         'lng':
//                                             _destinationPosition?.longitude ??
//                                             0.0,
//                                       },
//                                       pickupAddress: widget.pickupAddress,
//                                       destinationAddress:
//                                           widget.destinationAddress,
//                                     ),
//                               ),
//                             );
//                           }
//                         },
//                         text:
//                             driverController.selectedCarType.value.isEmpty
//                                 ? 'Book'
//                                 : 'Book ${driverController.selectedCarType.value}',
//                       ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
