import 'dart:io';
import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
import 'package:hopper/Presentation/BookRide/Screens/order_confirm_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:get/get.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/payment_screen.dart';
import 'package:hopper/dummy_screen.dart';

import '../../../Core/Utility/compressImage.dart';

class ConfirmBooking extends StatefulWidget {
  final String? selectedCarType;
  final String? bookingId;
  final Map<String, dynamic> pickupData;
  final Map<String, dynamic> destinationData;
  final String pickupAddress;
  final String destinationAddress;
  final String? carType;
  const ConfirmBooking({
    super.key,
    this.selectedCarType,
    this.bookingId,
    required this.pickupData,
    this.carType,
    required this.destinationData,
    required this.pickupAddress,
    required this.destinationAddress,
  });

  @override
  State<ConfirmBooking> createState() => _ConfirmBookingState();
}

class _ConfirmBookingState extends State<ConfirmBooking> {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destController = TextEditingController();
  DriverSearchController driverController = Get.put(DriverSearchController());
  final PackageController packageController = Get.put(PackageController());

  LatLng? _pickupPosition;
  LatLng? _destinationPosition;
  @override
  @override
  void initState() {
    super.initState();

    _pickupPosition = LatLng(
      widget.pickupData['lat'],
      widget.pickupData['lng'],
    );

    _destinationPosition = LatLng(
      widget.destinationData['lat'],
      widget.destinationData['lng'],
    );
  }

  String formatDistance(double meters) {
    double kilometers = meters / 1000;
    return '${kilometers.toStringAsFixed(1)} Km';
  }

  String formatDuration(int minutes) {
    int hours = minutes ~/ 60;
    int remainingMinutes = minutes % 60;
    return hours > 0
        ? '$hours hr $remainingMinutes min'
        : '$remainingMinutes min';
  }

  @override
  Widget build(BuildContext context) {
    _startController.text = widget.pickupAddress;
    _destController.text = widget.destinationAddress;
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          if (driverController.isLoading.value) {
            return Center(child: AppLoader.appLoader());
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                      Spacer(),

                      CustomTextFields.textWithStyles700(
                        'Confirm Booking',
                        fontSize: 20,
                      ),
                      Spacer(),
                    ],
                  ),
                  SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
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

                          hintStyle: TextStyle(fontSize: 11),
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

                          controller: _destController,

                          hintStyle: TextStyle(fontSize: 11),
                          imgHeight: 17,
                          containerColor: AppColors.commonWhite,
                          leadingImage: AppImages.rectangleDest,
                          title: 'Enter destination',
                          readOnly: true,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 30),
                  Container(
                    decoration: BoxDecoration(color: AppColors.containerColor),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        spacing: 7,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CustomTextFields.textWithStylesSmall('Your Ride'),
                            ],
                          ),

                          Row(
                            children: [
                              CustomTextFields.textWithStyles600(
                                '${widget.selectedCarType ?? ''}  ',
                                fontSize: 18,
                              ),
                              Icon(Icons.circle, size: 7),
                              CustomTextFields.textWithStyles600(
                                '  Ride Alone',
                                fontSize: 18,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 30),
                  CustomTextFields.textWithStyles700(
                    'Price Details',
                    fontSize: 20,
                  ),
                  SizedBox(height: 15),
                  Obx(() {
                    final booking = driverController.carBooking.value;
                    final fareBreakdown = booking?.fareBreakdown;
                    final fare =
                        (fareBreakdown != null && fareBreakdown.isNotEmpty)
                            ? fareBreakdown.first
                            : null;
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.commonBlack.withOpacity(0.1),
                          width: 1.5,
                        ),
                      ),
                      child: ListTile(
                        subtitle: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5.0),
                          child: Column(
                            spacing: 5,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.baseFare)),
                                  CustomTextFields.textWithImage(
                                    text:
                                        booking?.baseFare.toString() ?? '',
                                    imagePath: AppImages.nCurrency,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),
                              /*   Row(
                                children: [
                                  Expanded(child: Text(AppTexts.serviceFare)),
                                  CustomTextFields.textWithImage(
                                    text:
                                        driverController
                                            .carBooking
                                            .value
                                            ?.serviceFare
                                            .toString() ??
                                        "",

                                    imagePath: AppImages.nCurrency,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),*/
                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.distanceFare)),
                                  CustomTextFields.textWithImage(
                                    text:
                                        fare?.distanceFare.toString() ??
                                        "",

                                    imagePath: AppImages.nCurrency,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.pickupFare)),
                                  CustomTextFields.textWithImage(
                                    text:
                                        fare?.pickupFare.toString() ??
                                        "",

                                    imagePath: AppImages.nCurrency,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.bookingFee)),
                                  CustomTextFields.textWithImage(
                                    text:
                                        fare?.bookingFee.toString() ??
                                        "",

                                    imagePath: AppImages.nCurrency,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.timeFare)),
                                  CustomTextFields.textWithImage(
                                    text:
                                        fare?.timeFare.toString() ??
                                        "",

                                    imagePath: AppImages.nCurrency,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),
                              SizedBox(height: 3),
                              SizedBox(
                                height: 2,
                                child: DottedLine(
                                  direction: Axis.horizontal,
                                  lineLength: double.infinity,
                                  lineThickness: 1.4,
                                  dashLength: 4.0,
                                  dashColor: Colors.grey.shade400,
                                ),
                              ),
                              SizedBox(height: 3),
                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.estTime)),
                                  CustomTextFields.textWithImage(
                                    text: formatDuration(
                                      driverController
                                              .carBooking
                                              .value
                                              ?.duration ??
                                          0,
                                    ),

                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),

                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.totalKm)),
                                  CustomTextFields.textWithImage(
                                    text: formatDistance(
                                      (driverController
                                                  .carBooking
                                                  .value
                                                  ?.distance ??
                                              0)
                                          .toDouble(),
                                    ),

                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),
                              SizedBox(height: 3),
                              SizedBox(
                                height: 2,
                                child: DottedLine(
                                  direction: Axis.horizontal,
                                  lineLength: double.infinity,
                                  lineThickness: 1.4,
                                  dashLength: 4.0,
                                  dashColor: Colors.grey.shade400,
                                ),
                              ),
                              SizedBox(height: 3),

                              Row(
                                children: [
                                  Expanded(
                                    child: CustomTextFields.textWithStyles600(
                                      AppTexts.total,
                                      fontSize: 14,
                                    ),
                                  ),

                                  CustomTextFields.textWithImage(
                                    text:
                                        booking?.amount.toString() ??
                                        '',

                                    imagePath: AppImages.nBlackCurrency,
                                    fontWeight: FontWeight.w900,
                                    colors: AppColors.commonBlack,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  SizedBox(height: 10),
                  CustomTextFields.textWithStylesSmall(
                    maxLines: 2,
                    'By confirming, you agree to our Terms of Service and Cancellation Policy',
                  ),
                ],
              ),
            ),
          );
        }),
      ),

      bottomNavigationBar: Obx(() {
        return driverController.isLoading.value
            ? const SizedBox.shrink()
            : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                child: AppButtons.button(
                  onTap: () async {

                    /*         final allData = driverController.carBooking.value;

                    String? result = await driverController.sendDriverRequest(
                      carType: widget.carType ?? '',
                      pickupLatitude: allData?.fromLatitude ?? 0.0,
                      pickupLongitude: allData?.fromLongitude ?? 0.0,
                      dropLatitude: allData?.toLatitude ?? 0.0,
                      dropLongitude: allData?.toLongitude ?? 0.0,
                      bookingId: allData?.bookingId.toString() ?? '',
                      context: context,
                    );
                    AppLogger.log.i(result);
                    if (result != null) {
                      driverController.selectedCarType.value = '';
                      // Navigator.push(
                      //   context,
                      //   MaterialPageRoute(
                      //     builder:
                      //         (context) => DummyScreen(
                      //           pickupData: {
                      //             'description': widget.pickupAddress,
                      //             'lat': _pickupPosition?.latitude ?? 0.0,
                      //             'lng': _pickupPosition?.longitude ?? 0.0,
                      //           },
                      //           destinationData: {
                      //             'description': widget.destinationAddress,
                      //             'lat': _destinationPosition?.latitude ?? 0.0,
                      //             'lng': _destinationPosition?.longitude ?? 0.0,
                      //           },
                      //           pickupAddress: widget.pickupAddress,
                      //           destinationAddress: widget.destinationAddress,
                      //         ),
                      //   ),
                      // );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => OrderConfirmScreen(
                                carType: widget.carType ?? '',
                                bookingId: allData?.bookingId.toString() ?? '',
                                baseFare: allData?.baseFare ?? 0.0,
                                bookingFee:
                                    allData?.fareBreakdown[0].bookingFee,
                                pickupFare:
                                    allData?.fareBreakdown[0].pickupFare,
                                timeFare: allData?.fareBreakdown[0].timeFare,
                                distanceFare:
                                    allData?.fareBreakdown[0].distanceFare,
                                serviceFare: allData?.serviceFare ?? 0.0,
                                pickupData: {
                                  'description': widget.pickupAddress,
                                  'lat': _pickupPosition?.latitude ?? 0.0,
                                  'lng': _pickupPosition?.longitude ?? 0.0,
                                },
                                destinationData: {
                                  'description': widget.destinationAddress,
                                  'lat': _destinationPosition?.latitude ?? 0.0,
                                  'lng': _destinationPosition?.longitude ?? 0.0,
                                },
                                pickupAddress: widget.pickupAddress,
                                destinationAddress: widget.destinationAddress,
                              ),
                        ),
                      );
                    }*/
                   
                    await _showPhotoConfirmationDialog(context);
                  },
                  text: 'Confirm',
                  rightImagePath: AppImages.nBlackCurrency,
                  rightImagePathText:
                      driverController.carBooking.value?.amount ?? 0,
                ),
              ),
            );
      }),
    );
  }


  Future<void> _showPhotoConfirmationDialog(BuildContext context) async {
    File? capturedImage;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppColors.commonWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Text(
                "Photo Verification Required",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (capturedImage == null)
                    const Icon(
                      Icons.camera_alt_rounded,
                      size: 60,
                      color: Colors.black,
                    )
                  else
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: FileImage(capturedImage!),
                    ),
                  const SizedBox(height: 15),
                  Text(
                    capturedImage == null
                        ? "To confirm your booking, we need to take a quick selfie for verification."
                        : "Preview your selfie. If it looks good, upload it to continue, or retake it.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                  if (capturedImage != null)
                    TextButton.icon(
                      onPressed: () async {
                        // Retake selfie
                        final image = await _captureSelfie();
                        if (image != null) {
                          setState(() => capturedImage = image);
                        }
                      },
                      icon: const Icon(Icons.refresh, color: Colors.black),
                      label: const Text(
                        "Retake",
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                ],
              ),
              actions: [
                if (capturedImage == null)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    if (capturedImage == null) {
                      final image = await _captureSelfie();
                      if (image != null) setState(() => capturedImage = image);
                    } else {
                      setState(() => _isLoading = true); // start loader
                      try {
                        final success = await _uploadPhotoAndBook(
                          capturedImage!,
                        );
                        if (success) {
                          Navigator.pop(context); // Close dialog
                          final allData = driverController.carBooking.value;
                          final fareBreakdown = allData?.fareBreakdown;
                          final fare =
                              (fareBreakdown != null && fareBreakdown.isNotEmpty)
                                  ? fareBreakdown.first
                                  : null;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => OrderConfirmScreen(
                                    carType: widget.carType ?? '',
                                    bookingId:
                                        allData?.bookingId.toString() ?? '',
                                    baseFare: allData?.baseFare ?? 0.0,
                                    bookingFee: fare?.bookingFee ?? 0.0,
                                    pickupFare: fare?.pickupFare ?? 0.0,
                                    timeFare: fare?.timeFare ?? 0.0,
                                    distanceFare: fare?.distanceFare ?? 0.0,
                                    serviceFare: allData?.serviceFare ?? 0.0,
                                    pickupData: {
                                      'description': widget.pickupAddress,
                                      'lat': _pickupPosition?.latitude ?? 0.0,
                                      'lng': _pickupPosition?.longitude ?? 0.0,
                                    },
                                    destinationData: {
                                      'description': widget.destinationAddress,
                                      'lat':
                                          _destinationPosition?.latitude ?? 0.0,
                                      'lng':
                                          _destinationPosition?.longitude ??
                                          0.0,
                                    },
                                    pickupAddress: widget.pickupAddress,
                                    destinationAddress:
                                        widget.destinationAddress,
                                  ),
                            ),
                          );
                        }
                      } finally {
                        setState(() => _isLoading = false);
                      }
                    }
                  },
                  child:
                      _isLoading
                          ? const Center(
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                          : Text(
                            capturedImage == null
                                ? "Take Photo"
                                : "Upload and Confirm Booking",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _isLoading = false;
  Future<bool> _uploadPhotoAndBook(File image) async {
    try {
      printImageSize(image, label: "Before Upload (input)");
      final File uploadFile =
          (await compressImage(image, quality: 70)) ?? image;
      printImageSize(uploadFile, label: "Uploading File"); // ✅ ADD THIS
      final uploadResult = await packageController.submitProfileData(
        bookingId: widget.bookingId ?? '',
        frontImageFile: uploadFile,
        context: context,
      );
      if (uploadResult == null || uploadResult.isEmpty) {
        return false;
      }

      // Send booking request
      final allData = driverController.carBooking.value;
      String? result = await driverController.sendDriverRequest(
        carType: widget.carType ?? '',
        pickupLatitude: allData?.fromLatitude ?? 0.0,
        pickupLongitude: allData?.fromLongitude ?? 0.0,
        dropLatitude: allData?.toLatitude ?? 0.0,
        dropLongitude: allData?.toLongitude ?? 0.0,
        bookingId: allData?.bookingId.toString() ?? '',
        context: context,
      );
      return result != null && result.isNotEmpty;
    } catch (e) {
      debugPrint("Error uploading photo or sending booking: $e");
      return false;
    }
  }

  Future<File?> _captureSelfie() async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 100, // keep original here; we'll compress ourselves
    );

    if (photo == null) return null;

    final original = File(photo.path);
    printImageSize(original, label: "Original Image");
    // Compress it
    final compressed = await compressImage(
      original,
      quality: 70,
      minWidth: 1080,
      minHeight: 1080,
    );
    if (compressed != null) {
      printImageSize(compressed, label: "Compressed Image");
    }

    return compressed ?? original; // fallback to original if compression fails
  }

  // Future<File?> _captureSelfie() async {

  //   final ImagePicker picker = ImagePicker();
  //   final XFile? photo = await picker.pickImage(
  //     source: ImageSource.camera,
  //     preferredCameraDevice: CameraDevice.front,
  //   );
  //   if (photo == null) return null;
  //   return File(photo.path);
  // }

}
