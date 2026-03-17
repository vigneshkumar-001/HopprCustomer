import 'package:flutter/material.dart';
import 'package:hopper/Core/Utility/app_loader.dart';

import 'package:hopper/Core/Utility/app_toasts.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:dotted_line/dotted_line.dart';

import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/Drawer/screens/ride_and_package_history_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/confirmation_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
import 'package:get/get.dart';
import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
import 'package:hopper/uitls/map/google_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hopper/uitls/map/search_loaction.dart';

import '../../../uitls/websocket/socket_io_client.dart' show SocketService;

class PackageScreens extends StatefulWidget {
  const PackageScreens({super.key});

  @override
  State<PackageScreens> createState() => _PackageScreensState();
}

class _PackageScreensState extends State<PackageScreens> {
  final PackageController packageController = Get.put(PackageController());
  final TextEditingController packageWeightController = TextEditingController();
  final TextEditingController packageDescriptionController =
      TextEditingController();
  final TextEditingController packageDeliveryInstructionController =
      TextEditingController();
  bool isSendSelected = true;
  String selectedAddress = 'Collect from';
  bool senderSelected = false;
  bool receiverSelected = false;
  String? selectedParcel;
  bool receiveWithOtp = true;
  AddressModel? senderData;
  AddressModel? receiverData;
  bool parcelError = false;
  String enteredAddress = '';
  String landmark = '';
  String name = 'Add Sender Address';
  String phone = '';
  String recipientAddress = '';
  String recipientMapAddress = '';
  String recipientLandmark = '';
  String recipientName = '';
  String recipientPhone = '';
  int selectedIndex = 0;

  String capitalizeFirstLetter(String name) {
    if (name.isEmpty) return '';
    return name[0].toUpperCase() + name.substring(1).toLowerCase();
  }

  final GlobalKey _senderKey = GlobalKey();
  final GlobalKey _receiverKey = GlobalKey();

  double lineHeight = 110;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateLineHeight());
  }

  List<String> parcelTypes = [
    'Food',
    'Medicines',
    'Groceries',
    'Documents',
    'Electronics',
    'Other',
  ];
  void _calculateLineHeight() {
    final senderBox =
        _senderKey.currentContext?.findRenderObject() as RenderBox?;
    final receiverBox =
        _receiverKey.currentContext?.findRenderObject() as RenderBox?;

    if (senderBox != null && receiverBox != null) {
      final senderPos = senderBox.localToGlobal(Offset.zero);
      final receiverPos = receiverBox.localToGlobal(Offset.zero);

      final calculatedHeight = receiverPos.dy - senderPos.dy - 30;
      setState(() {
        lineHeight = calculatedHeight > 0 ? calculatedHeight : 0;
      });
    }
  }

  bool isWithin1Km(double lat1, double lon1, double lat2, double lon2) {
    final distanceInMeters = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    return distanceInMeters < 1000;
  }

  @override
  Widget build(BuildContext context) {
    final pickUpData = isSendSelected ? senderData : receiverData;
    final dropOffData = isSendSelected ? receiverData : senderData;

    return WillPopScope(
      onWillPop: () async {
        return await false;
      },
      child: Scaffold(
        body: Obx(() {
          if (packageController.isLoading.value) {
            return Center(child: AppLoader.appLoader());
          }
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 25,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(
                          child: Image.asset(
                            AppImages.hopprPackage,
                            height: 24,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          child: InkWell(
                            onTap: () {
                              Get.to(() => const RideAndPackageHistoryScreen(initialTabIndex: 1)); // 1 = Package
                            },
                            child: Image.asset(
                              AppImages.history,
                              height: 20,
                              width: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 30),

                    PackageContainer.customContainers(
                      isSendSelected: isSendSelected,
                      onSelectionChanged: (selected) {
                        setState(() {
                          isSendSelected = selected;
                        });
                      },
                    ),
                    SizedBox(height: 20),
                    CustomTextFields.textWithStyles700(
                      fontSize: 16,
                      AppTexts.sendOrReceiveParcel,
                    ),
                    const SizedBox(height: 20),
                    Stack(
                      children: [
                        Column(
                          children: [
                            Container(
                              key: _senderKey,
                              child: PackageContainer.customPlainContainers(
                                onEditTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => MapScreen(
                                            cameFromPackage: true,
                                            searchQuery:
                                                pickUpData?.mapAddress ?? '',
                                            initialAddress: pickUpData?.address,
                                            initialLandmark:
                                                pickUpData?.landmark,
                                            initialName: pickUpData?.name,
                                            initialPhone: pickUpData?.phone,
                                            location:
                                                pickUpData != null
                                                    ? LatLng(
                                                      pickUpData.latitude,
                                                      pickUpData.longitude,
                                                    )
                                                    : null,
                                          ),
                                    ),
                                  );

                                  if (result != null) {
                                    final loc = result['location'];
                                    if (receiverData != null &&
                                        isWithin1Km(
                                          receiverData!.latitude,
                                          receiverData!.longitude,
                                          loc.latitude,
                                          loc.longitude,
                                        )) {
                                      AppToasts.customToast(
                                        context,
                                        "Pickup and drop locations cannot be the same or within 1km.",
                                      );
                                      return;
                                    }

                                    setState(() {
                                      if (isSendSelected) {
                                        senderData = AddressModel(
                                          name: result['name'],
                                          phone: result['phone'],
                                          address: result['address'],
                                          landmark: result['landmark'],
                                          mapAddress: result['mapAddress'],
                                          latitude: loc.latitude,
                                          longitude: loc.longitude,
                                        );
                                      } else {
                                        receiverData = AddressModel(
                                          name: result['name'],
                                          phone: result['phone'],
                                          address: result['address'],
                                          landmark: result['landmark'],
                                          mapAddress: result['mapAddress'],
                                          latitude: loc.latitude,
                                          longitude: loc.longitude,
                                        );
                                      }
                                    });

                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _calculateLineHeight();
                                        });
                                  }
                                },

                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => const CommonLocationSearch(),
                                    ),
                                  );

                                  if (result != null) {
                                    final loc = result['location'];
                                    if (receiverData != null &&
                                        isWithin1Km(
                                          receiverData!.latitude,
                                          receiverData!.longitude,
                                          loc.latitude,
                                          loc.longitude,
                                        )) {
                                      AppToasts.customToast(
                                        context,
                                        "Pickup and drop locations cannot be the same or within 1km.",
                                      );
                                      return;
                                    }

                                    setState(() {
                                      if (isSendSelected) {
                                        senderData = AddressModel(
                                          name: result['name'],
                                          phone: result['phone'],
                                          address: result['address'],
                                          landmark: result['landmark'],
                                          mapAddress: result['mapAddress'],
                                          latitude: loc.latitude,
                                          longitude: loc.longitude,
                                        );
                                      } else {
                                        receiverData = AddressModel(
                                          name: result['name'],
                                          phone: result['phone'],
                                          address: result['address'],
                                          landmark: result['landmark'],
                                          mapAddress: result['mapAddress'],
                                          latitude: loc.latitude,
                                          longitude: loc.longitude,
                                        );
                                      }
                                    });

                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _calculateLineHeight();
                                        });
                                  }
                                },
                                onClear:
                                    pickUpData != null
                                        ? () {
                                          setState(() {
                                            if (isSendSelected) {
                                              senderData = null;
                                            } else {
                                              receiverData = null;
                                            }
                                          });
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                _calculateLineHeight();
                                              });
                                        }
                                        : null,
                                isSelected: pickUpData != null,
                                containerColor: AppColors.commonWhite,
                                leadingImage: AppImages.colorUpArrow,
                                title:
                                    pickUpData == null
                                        ? 'Collect from'
                                        : 'Pick up Location',
                                subTitle:
                                    pickUpData == null
                                        ? 'Add Sender Address'
                                        : '${pickUpData!.address}, ${pickUpData!.landmark}, ${pickUpData!.mapAddress}',
                                userNameAndPhn:
                                    pickUpData == null
                                        ? ''
                                        : '${capitalizeFirstLetter(pickUpData.name)} (${pickUpData.phone})',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              key: _receiverKey,
                              child: PackageContainer.customPlainContainers(
                                onEditTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => MapScreen(
                                            type: 'receiver',
                                            cameFromPackage: true,
                                            searchQuery:
                                                dropOffData?.mapAddress ?? '',
                                            initialAddress:
                                                dropOffData?.address,
                                            initialLandmark:
                                                dropOffData?.landmark,
                                            initialName: dropOffData?.name,
                                            initialPhone: dropOffData?.phone,
                                            location:
                                                dropOffData != null
                                                    ? LatLng(
                                                      dropOffData.latitude,
                                                      dropOffData.longitude,
                                                    )
                                                    : null,
                                          ),
                                    ),
                                  );

                                  if (result != null) {
                                    final loc = result['location'];
                                    if (senderData != null &&
                                        isWithin1Km(
                                          senderData!.latitude,
                                          senderData!.longitude,
                                          loc.latitude,
                                          loc.longitude,
                                        )) {
                                      AppToasts.customToast(
                                        context,
                                        "Pickup and drop locations cannot be the same or within 1km.",
                                      );
                                      return;
                                    }

                                    setState(() {
                                      if (isSendSelected) {
                                        receiverData = AddressModel(
                                          name: result['name'],
                                          phone: result['phone'],
                                          address: result['address'],
                                          landmark: result['landmark'],
                                          mapAddress: result['mapAddress'],
                                          latitude: loc.latitude,
                                          longitude: loc.longitude,
                                        );
                                      } else {
                                        senderData = AddressModel(
                                          name: result['name'],
                                          phone: result['phone'],
                                          address: result['address'],
                                          landmark: result['landmark'],
                                          mapAddress: result['mapAddress'],
                                          latitude: loc.latitude,
                                          longitude: loc.longitude,
                                        );
                                      }
                                    });

                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _calculateLineHeight();
                                        });
                                  }
                                },

                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => const CommonLocationSearch(
                                            type: 'receiver',
                                          ),
                                    ),
                                  );

                                  if (result != null) {
                                    final loc = result['location'];
                                    if (senderData != null &&
                                        isWithin1Km(
                                          senderData!.latitude,
                                          senderData!.longitude,
                                          loc.latitude,
                                          loc.longitude,
                                        )) {
                                      AppToasts.customToast(
                                        context,
                                        "Pickup and drop locations cannot be the same or within 1km.",
                                      );
                                      return;
                                    }

                                    setState(() {
                                      if (isSendSelected) {
                                        receiverData = AddressModel(
                                          name: result['name'],
                                          phone: result['phone'],
                                          address: result['address'],
                                          landmark: result['landmark'],
                                          mapAddress: result['mapAddress'],
                                          latitude: loc.latitude,
                                          longitude: loc.longitude,
                                        );
                                      } else {
                                        senderData = AddressModel(
                                          name: result['name'],
                                          phone: result['phone'],
                                          address: result['address'],
                                          landmark: result['landmark'],
                                          mapAddress: result['mapAddress'],
                                          latitude: loc.latitude,
                                          longitude: loc.longitude,
                                        );
                                      }
                                    });

                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _calculateLineHeight();
                                        });
                                  }
                                },
                                onClear:
                                    dropOffData != null
                                        ? () {
                                          setState(() {
                                            if (isSendSelected) {
                                              receiverData = null;
                                            } else {
                                              senderData = null;
                                            }
                                          });
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                _calculateLineHeight();
                                              });
                                        }
                                        : null,
                                isSelected: dropOffData != null,
                                containerColor: AppColors.commonBlack,
                                titleColor: AppColors.commonWhite,
                                subColor: AppColors.commonWhite.withOpacity(
                                  0.7,
                                ),
                                trailingColor: AppColors.commonWhite,
                                iconColor: AppColors.commonWhite,
                                title:
                                    dropOffData == null
                                        ? 'Send to'
                                        : 'Drop up Location',
                                subTitle:
                                    dropOffData == null
                                        ? AppTexts.addRecipientAddress
                                        : '${dropOffData.address}, ${dropOffData.landmark}, ${dropOffData.mapAddress}',
                                leadingImage: AppImages.colorDownArrow,
                                userNameAndPhn:
                                    dropOffData == null
                                        ? ''
                                        : '${capitalizeFirstLetter(dropOffData.name)} (${dropOffData.phone})',
                              ),
                            ),
                          ],
                        ),

                        Positioned(
                          top: 47,
                          left: 24,
                          child: SizedBox(
                            height: lineHeight,
                            child: DottedLine(
                              direction: Axis.vertical,
                              lineLength: lineHeight,
                              dashLength: 4,

                              dashColor: AppColors.dotLineColor,
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 20),
                    if (senderData != null && receiverData != null) ...[
                      CustomTextFields.textWithStyles600(
                        'Parcel type *',
                        fontSize: 16,
                      ),
                      SizedBox(height: 10),
                      GridView.count(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.8,
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        children:
                            parcelTypes.map((title) {
                              final isSelected = selectedParcel == title;

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    selectedParcel = isSelected ? null : title;
                                    parcelError =
                                        false; // clear error on selection
                                    AppLogger.log.i(
                                      "Selected Parcel: $selectedParcel",
                                    );
                                  });
                                },
                                child: Container(
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color:
                                        isSelected
                                            ? AppColors.choiceChipColor
                                                .withOpacity(0.1)
                                            : AppColors.commonWhite,
                                    border: Border.all(
                                      color:
                                          isSelected
                                              ? AppColors.choiceChipColor
                                              : AppColors.containerColor,
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color:
                                          isSelected
                                              ? AppColors.choiceChipColor
                                              : Colors.black,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                      if (parcelError)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            "Please select a parcel type",
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 16),

                      CustomTextFields.textAndField(
                        type: TextInputType.number,
                        controller: packageWeightController,
                        tittle: 'Package weight',
                        hintText: 'Eg., 10kg , 20kg',
                      ),
                      const SizedBox(height: 12),
                      CustomTextFields.textAndField(
                        controller: packageDescriptionController,
                        tittle: 'Descriptional (Optional)',
                        hintText: 'Eg., Glass Item',
                      ),
                      const SizedBox(height: 12),
                      CustomTextFields.textAndField(
                        controller: packageDeliveryInstructionController,
                        tittle: 'Delivery Instruction',
                        hintText:
                            'Eg., Glass Items are here Please keep it safe',
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () {
                          // setState(() {
                          //   receiveWithOtp = !receiveWithOtp;
                          // });
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color:
                                    receiveWithOtp
                                        ? const Color(0xFF357AE9)
                                        : Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color:
                                      receiveWithOtp
                                          ? const Color(0xFF357AE9)
                                          : Colors.grey.shade400,
                                  width: 2,
                                ),
                              ),
                              child:
                                  receiveWithOtp
                                      ? const Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                      : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  // setState(() {
                                  //   receiveWithOtp = !receiveWithOtp;
                                  // });
                                },
                                child: CustomTextFields.textWithStyles600(
                                  'Receive parcel with OTP',
                                  color: AppColors.commonBlack,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Stack(
                      //   children: [
                      //     Container(
                      //       width: double.infinity,
                      //       padding: const EdgeInsets.symmetric(
                      //         vertical: 14,
                      //         horizontal: 40,
                      //       ),
                      //       child: Text(
                      //         AppTexts.receiveParcelWithOTP,
                      //         style: const TextStyle(
                      //           fontSize: 14,
                      //           fontWeight: FontWeight.w600,
                      //           color: Colors.black,
                      //         ),
                      //       ),
                      //     ),
                      //     Positioned(
                      //       left: 0,
                      //       top: 0,
                      //       bottom: 0,
                      //       child: Center(
                      //         child: GestureDetector(
                      //           onTap: () {
                      //             setState(() {
                      //               receiveWithOtp = !receiveWithOtp;
                      //             });
                      //           },
                      //           child: Container(
                      //             width: 22,
                      //             height: 22,
                      //             decoration: BoxDecoration(
                      //               border: Border.all(
                      //                 color:
                      //                     receiveWithOtp
                      //                         ? const Color(0xFF357AE9)
                      //                         : Colors.grey.shade400,
                      //                 width: 2,
                      //               ),
                      //               borderRadius: BorderRadius.circular(4),
                      //               color:
                      //                   receiveWithOtp
                      //                       ? const Color(0xFF357AE9)
                      //                       : Colors.white,
                      //             ),
                      //             child:
                      //                 receiveWithOtp
                      //                     ? const Icon(
                      //                       Icons.check,
                      //                       size: 16,
                      //                       color: Colors.white,
                      //                     )
                      //                     : null,
                      //           ),
                      //         ),
                      //       ),
                      //     ),
                      //   ],
                      // ),
                      const SizedBox(height: 20),
                    ],

                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.commonWhite,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.commonBlack.withOpacity(0.1),
                          width: 1.5,
                        ),
                      ),
                      child: ListTile(
                        title: CustomTextFields.textWithStyles600(
                          AppTexts.thingsToKeepInMind,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5.0),
                          child: Column(
                            spacing: 5,
                            children: [
                              Row(
                                children: [
                                  Image.asset(AppImages.pencilBike, height: 20),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(AppTexts.fitOnaTwoWheeler),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Image.asset(AppImages.emptyBox, height: 20),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(AppTexts.avoidSendingExpensive),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Image.asset(
                                    AppImages.avoidDrinks,
                                    height: 20,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(child: Text(AppTexts.noAlcohol)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),

        bottomNavigationBar:
            senderData != null && receiverData != null
                ? Obx(() {
                  if (packageController.isLoading.value) {
                    return SizedBox.shrink();
                  }
                  return SafeArea(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: AppButtons.button(
                        onTap: () async {
                          final String weight = packageWeightController.text;
                          final String deliveryInstruction =
                              packageDeliveryInstructionController.text;
                          final String description =
                              packageDescriptionController.text;
                          setState(() {
                            parcelError = selectedParcel == null;
                          });
                          if (parcelError) return;
                          final results = await packageController
                              .packageAddressDetails(
                                description: description,
                                deliveryInstruction: deliveryInstruction,
                                weight: weight,
                                selectedParcel: selectedParcel!,
                                senderData: senderData!,
                                receiverData: receiverData!,
                              );
                          AppLogger.log.i(
                            "Sender Data: ${senderData?.latitude}",
                          );
                          AppLogger.log.i("Receiver Data: $receiverData");
                          AppLogger.log.i("Selected Parcel: $selectedParcel");
                          AppLogger.log.i("  results: $results");
                          results != null
                              ? Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => ConfirmationScreen(
                                        parcelType: selectedParcel,
                                        sender: senderData!,
                                        receiver: receiverData!,
                                      ),
                                ),
                              )
                              : null;
                        },
                        text: 'Checkout',
                      ),
                    ),
                  );
                })
                : SizedBox.shrink(),
      ),
    );
  }
}
