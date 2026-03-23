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
        AppToasts.showErrorGlobal(
          "Location data is missing",
          title: "Error",
        );
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
                             AppToasts.showInfoGlobal(
                               'Please select a car before proceeding.',
                               title: 'Info',
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
                              AppToasts.showInfoGlobal(
                                'Please select a shared car option first.',
                                title: 'Info',
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
