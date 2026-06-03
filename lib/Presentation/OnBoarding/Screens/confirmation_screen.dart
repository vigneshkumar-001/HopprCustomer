import 'package:flutter/services.dart';
import 'package:hopper/Presentation/Drawer/screens/ride_and_package_history_screen.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:dotted_line/dotted_line.dart';

import 'package:hopper/Core/Consents/app_colors.dart';

import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
import 'package:hopper/uitls/map/google_map.dart';
import 'package:hopper/uitls/map/search_loaction.dart';
import 'package:get/get.dart';

class ConfirmationScreen extends StatefulWidget {
  final AddressModel sender;
  final AddressModel receiver;
  final String? parcelType;
  final String? weight;

  const ConfirmationScreen({
    Key? key,
    required this.sender,
    required this.receiver,
    this.parcelType,
    this.weight,
  }) : super(key: key);

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  final PackageController packageController = Get.put(PackageController());
  String? selectedParcel;
  bool isSendSelected = true;
  final GlobalKey senderKey = GlobalKey();
  final GlobalKey receiverKey = GlobalKey();

  double lineHeight = 100;
  AddressModel? senderData;
  AddressModel? receiverData;

  // ✅ coupon state
  String? _appliedCouponCode;
  double _discountAmount = 0.0;
  double _overrideTotal = 0.0;
  bool _applyingCoupon = false;

  // ✅ amount helpers
  double get _subTotal {
    final amt = packageController.packageDetails.value?.data?.amount;
    if (amt == null) return 0.0;
    return (amt is num)
        ? amt.toDouble()
        : double.tryParse(amt.toString()) ?? 0.0;
  }

  double get _totalAfterDiscount {
    if (_overrideTotal > 0) return _overrideTotal;
    return (_subTotal - _discountAmount).clamp(0, double.infinity);
  }

  String capitalizeFirstLetter(String name) {
    if (name.isEmpty) return '';
    return name[0].toUpperCase() + name.substring(1).toLowerCase();
  }

  List<String> parcelTypes = ['Food', 'Documents', 'Clothes', 'Others'];

  @override
  void initState() {
    super.initState();
    senderData = widget.sender;
    receiverData = widget.receiver;

    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateLineHeight());
  }

  void _calculateLineHeight() {
    final senderBox =
        senderKey.currentContext?.findRenderObject() as RenderBox?;
    final receiverBox =
        receiverKey.currentContext?.findRenderObject() as RenderBox?;

    if (senderBox != null && receiverBox != null) {
      final senderPos = senderBox.localToGlobal(Offset.zero);
      final receiverPos = receiverBox.localToGlobal(Offset.zero);

      final calculatedHeight = receiverPos.dy - senderPos.dy - 30;
      setState(() {
        lineHeight = calculatedHeight > 0 ? calculatedHeight : 0;
      });
    }
  }

  // ✅ Apply/Remove coupon UI
  Future<void> _openCouponSheet() async {
    final TextEditingController _couponCtrl = TextEditingController(
      text: _appliedCouponCode ?? '',
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withOpacity(0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder:
              (ctx, setModalState) => SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 10,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // handle
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // header
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Apply Coupon',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            splashRadius: 22,
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Save more on your delivery — enter a valid coupon below.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black.withOpacity(0.6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // input
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.containerColor.withOpacity(0.7),
                            width: 1.2,
                          ),
                          color: AppColors.commonWhite,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.local_offer_outlined, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _couponCtrl,
                                autofocus: true,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: const InputDecoration(
                                  hintText: 'ENTER COUPON CODE',
                                  border: InputBorder.none,
                                ),
                                onSubmitted: (_) async {
                                  final code = _couponCtrl.text.trim();
                                  if (code.isEmpty) {
                                    AppToasts.customToast(
                                      context,
                                      'Enter a coupon code',
                                    );
                                    return;
                                  }
                                  setModalState(() => _applyingCoupon = true);
                                  await _applyCoupon(code, 'APPLY');
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                              ),
                            ),
                            if (_couponCtrl.text.isNotEmpty)
                              IconButton(
                                splashRadius: 20,
                                tooltip: 'Clear',
                                onPressed:
                                    () => setModalState(
                                      () => _couponCtrl.clear(),
                                    ),
                                icon: const Icon(Icons.clear, size: 18),
                              ),
                            IconButton(
                              splashRadius: 20,
                              tooltip: 'Paste',
                              onPressed: () async {
                                final data = await Clipboard.getData(
                                  'text/plain',
                                );
                                final text = (data?.text ?? '').trim();
                                if (text.isNotEmpty) {
                                  setModalState(() {
                                    _couponCtrl.text = text.toUpperCase();
                                  });
                                }
                              },
                              icon: const Icon(Icons.content_paste, size: 18),
                            ),
                          ],
                        ),
                      ),

                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child:
                            (_appliedCouponCode != null && _discountAmount > 0)
                                ? Container(
                                  key: const ValueKey('applied'),
                                  margin: const EdgeInsets.only(top: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFB2DFDB),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Applied: ${_appliedCouponCode!} - Saved ₹${_discountAmount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                : const SizedBox.shrink(),
                      ),

                      const SizedBox(height: 12),

                      // breakdown
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Column(
                          children: [
                            _priceRow('Subtotal', _subTotal),
                            if (_discountAmount > 0) ...[
                              const SizedBox(height: 6),
                              _priceRow(
                                'Discount',
                                _discountAmount,
                                negative: true,
                              ),
                            ],
                            const Divider(height: 16),
                            _priceRow(
                              'Total payable',
                              _totalAfterDiscount,
                              bold: true,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      /*    Row(
                        children: [
                          if (_appliedCouponCode != null && _discountAmount > 0)
                            Expanded(
                              child: AppButtons.button(
                                hasBorder: true,
                                buttonColor: AppColors.commonWhite,
                                borderColor: AppColors.containerColor,
                                textColor: AppColors.commonBlack,
                                onTap:
                                    _applyingCoupon
                                        ? null
                                        : () async {
                                          // ✅ clear in PARENT so main UI updates immediately
                                          if (mounted) {
                                            setState(() {
                                              _appliedCouponCode = null;
                                              _discountAmount = 0.0;
                                              _overrideTotal = 0.0;
                                            });
                                          }

                                          // optional backend call (ignore result for UI)
                                          try {
                                            final bookingId =
                                                packageController
                                                    .packageDetails
                                                    .value
                                                    ?.data
                                                    ?.bookingId ??
                                                '';
                                            final code =
                                                _couponCtrl.text.trim();
                                            await packageController.applyCoupon(
                                              actionType: 'REMOVE',
                                              code: code,
                                              bookingId: bookingId,
                                            );
                                          } catch (_) {}

                                          if (ctx.mounted) Navigator.pop(ctx);
                                          AppToasts.showSuccess(
                                            'Coupon removed',
                                          );
                                        },
                                text: 'Remove',
                              ),
                            ),
                          if (_appliedCouponCode != null && _discountAmount > 0)
                            const SizedBox(width: 12),
                          Expanded(
                            child: Obx(() {
                              final loading = packageController.isLoading.value;
                              return AppButtons.button(
                                onTap:
                                    loading
                                        ? null
                                        : () async {
                                          final code = _couponCtrl.text.trim();
                                          if (code.isEmpty) {
                                            AppToasts.showError(
                                              'Enter a coupon code',
                                            );
                                            return;
                                          }
                                          await _applyCoupon(code, 'APPLY');
                                          if (ctx.mounted) Navigator.pop(ctx);
                                        },
                                isLoading: loading,
                                text: 'Apply',
                              );
                            }),
                          ),
                        ],
                      ),*/
                      Obx(() {
                        final loading = packageController.isLoading.value;

                        return Row(
                          children: [
                            if (_appliedCouponCode != null &&
                                _discountAmount > 0)
                              Expanded(
                                child: AppButtons.button(
                                  hasBorder: true,
                                  buttonColor: AppColors.commonWhite,
                                  borderColor: AppColors.containerColor,
                                  textColor: AppColors.commonBlack,
                                  onTap:
                                      loading
                                          ? null
                                          : () async {
                                            // ✅ Clear in parent so main UI updates immediately
                                            if (mounted) {
                                              setState(() {
                                                _appliedCouponCode = null;
                                                _discountAmount = 0.0;
                                                _overrideTotal = 0.0;
                                              });
                                            }

                                            // Optional backend call (ignore result for UI)
                                            try {
                                              final bookingId =
                                                  packageController
                                                      .packageDetails
                                                      .value
                                                      ?.data
                                                      ?.bookingId ??
                                                  '';
                                              final code =
                                                  _couponCtrl.text.trim();

                                              await packageController
                                                  .applyCoupon(
                                                    context: context,
                                                    actionType: 'REMOVE',
                                                    code: code,
                                                    bookingId: bookingId,
                                                  );
                                            } catch (_) {}

                                            if (ctx.mounted) Navigator.pop(ctx);
                                            AppToasts.showSuccess(
                                              context,
                                              'Coupon removed',
                                            );
                                          },
                                  isLoading: loading,
                                  text: 'Remove',
                                ),
                              ),
                            if (_appliedCouponCode != null &&
                                _discountAmount > 0)
                              const SizedBox(width: 12),
                            Expanded(
                              child: AppButtons.button(
                                onTap:
                                    loading
                                        ? null
                                        : () async {
                                          final code = _couponCtrl.text.trim();
                                          if (code.isEmpty) {
                                            AppToasts.showError(
                                              context,
                                              'Enter a coupon code',
                                            );
                                            return;
                                          }
                                          await _applyCoupon(code, 'APPLY');
                                          if (ctx.mounted) Navigator.pop(ctx);
                                        },
                                isLoading: loading,
                                text: 'Apply',
                              ),
                            ),
                          ],
                        );
                      }),

                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
        );
      },
    );
  }

  Widget _priceRow(
    String label,
    double amount, {
    bool negative = false,
    bool bold = false,
  }) {
    final String prefix = negative ? '− ' : '';
    final TextStyle left = TextStyle(
      fontSize: 13,
      color: Colors.black.withOpacity(0.85),
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    );
    final TextStyle right = TextStyle(
      fontSize: bold ? 15 : 14,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
      color: negative ? Colors.green : Colors.black,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: left)),
        Text('$prefix₹${amount.toStringAsFixed(2)}', style: right),
      ],
    );
  }

  // ✅ Hardened to always clear on REMOVE
  Future<void> _applyCoupon(String code, String actionType) async {
    try {
      setState(() => _applyingCoupon = true);

      final String? bookingId =
          packageController.packageDetails.value?.data?.bookingId;

      final result = await packageController.applyCoupon(
        context: context,
        actionType: actionType,
        code: code,
        bookingId: bookingId ?? '',
      );

      if (actionType == 'REMOVE') {
        // Always clear locally, regardless of API response
        setState(() {
          _appliedCouponCode = null;
          _discountAmount = 0.0;
          _overrideTotal = 0.0;
        });
        return;
      }

      // APPLY flow
      if (result != null && result.success) {
        setState(() {
          _appliedCouponCode = result.discountCode;
          _discountAmount = result.discountAmount ?? 0;
          _overrideTotal = result.amount ?? 0;
        });
      } else {
        AppToasts.customToast(context, 'Invalid or expired coupon');
      }
    } catch (e) {
      AppToasts.customToast(context, 'Error applying coupon: $e');
    } finally {
      if (mounted) setState(() => _applyingCoupon = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        if (packageController.isConfirmLoading.value) {
          return Center(child: AppLoader.appLoader());
        }
        return SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 25),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                              },
                              child: Image.asset(
                                AppImages.backImage,
                                height: 24,
                              ),
                            ),
                            Center(
                              child: Image.asset(
                                AppImages.hopprPackage,
                                height: 24,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                Get.to(RideAndPackageHistoryScreen());
                              },
                              child: Image.asset(
                                AppImages.history,
                                height: 20,
                                width: 20,
                              ),
                            ),
                            // Stack(
                            //   alignment: Alignment.center,
                            //   children: [
                            //
                            //     Center(
                            //       child: Image.asset(
                            //         AppImages.hopprPackage,
                            //         height: 24,
                            //       ),
                            //     ),
                            //     Positioned(
                            //       right: 0,
                            //       child: InkWell(
                            //         onTap: () {
                            //           Get.to(RideAndPackageHistoryScreen());
                            //         },
                            //         child: Image.asset(
                            //           AppImages.history,
                            //           height: 20,
                            //           width: 20,
                            //         ),
                            //       ),
                            //     ),
                            //   ],
                            // ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        CustomTextFields.textWithStyles700(
                          'Location Details',
                          fontSize: 16,
                        ),
                        const SizedBox(height: 20),
                        Stack(
                          children: [
                            Column(
                              children: [
                                // sender
                                Container(
                                  key: senderKey,
                                  child: PackageContainer.customPlainContainers(
                                    isSelected: senderData != null,
                                    containerColor: AppColors.commonWhite,
                                    leadingImage: AppImages.colorUpArrow,
                                    title:
                                        senderData != null
                                            ? 'Pick up Location'
                                            : 'Collect from',
                                    subTitle:
                                        senderData != null
                                            ? '${senderData!.address}, ${senderData!.landmark}, ${senderData!.mapAddress}'
                                            : AppTexts.addSenderAddress,
                                    userNameAndPhn:
                                        senderData != null
                                            ? '${capitalizeFirstLetter(senderData!.name)} (${senderData!.phone})'
                                            : '',
                                    onEditTap: () async {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) => MapScreen(
                                                cameFromPackage: true,
                                                searchQuery:
                                                    senderData?.mapAddress ??
                                                    '',
                                                initialAddress:
                                                    senderData?.address,
                                                initialLandmark:
                                                    senderData?.landmark,
                                                initialName: senderData?.name,
                                                initialPhone: senderData?.phone,
                                                location:
                                                    senderData != null
                                                        ? LatLng(
                                                          senderData!.latitude,
                                                          senderData!.longitude,
                                                        )
                                                        : null,
                                              ),
                                        ),
                                      );

                                      if (result != null) {
                                        setState(() {
                                          senderData = AddressModel(
                                            name: result['name'],
                                            phone: result['phone'],
                                            address: result['address'],
                                            landmark: result['landmark'],
                                            mapAddress: result['mapAddress'],
                                            latitude:
                                                result['location'].latitude,
                                            longitude:
                                                result['location'].longitude,
                                          );
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
                                              (_) =>
                                                  const CommonLocationSearch(),
                                        ),
                                      );
                                      if (result != null) {
                                        setState(() {
                                          senderData = AddressModel(
                                            name: result['name'],
                                            phone: result['phone'],
                                            address: result['address'],
                                            landmark: result['landmark'],
                                            mapAddress: result['mapAddress'],
                                            latitude:
                                                result['location'].latitude,
                                            longitude:
                                                result['location'].longitude,
                                          );
                                        });
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              _calculateLineHeight();
                                            });
                                      }
                                    },
                                    onClear:
                                        senderData != null
                                            ? () {
                                              setState(() {
                                                senderData = null;
                                              });
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                    _calculateLineHeight();
                                                  });
                                            }
                                            : null,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                // receiver
                                Container(
                                  key: receiverKey,
                                  child: PackageContainer.customPlainContainers(
                                    isSelected: receiverData != null,
                                    containerColor: AppColors.commonBlack,
                                    titleColor: AppColors.commonWhite,
                                    subColor: AppColors.commonWhite.withOpacity(
                                      0.7,
                                    ),
                                    trailingColor: AppColors.commonWhite,
                                    iconColor: AppColors.commonWhite,
                                    leadingImage: AppImages.colorDownArrow,
                                    title:
                                        receiverData != null
                                            ? 'Drop up Location'
                                            : 'Send to',
                                    subTitle:
                                        receiverData != null
                                            ? '${receiverData!.address}, ${receiverData!.landmark}, ${receiverData!.mapAddress}'
                                            : AppTexts.addRecipientAddress,
                                    userNameAndPhn:
                                        receiverData != null
                                            ? '${capitalizeFirstLetter(receiverData!.name)} (${receiverData!.phone})'
                                            : '',
                                    onEditTap: () async {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) => MapScreen(
                                                cameFromPackage: true,
                                                searchQuery:
                                                    receiverData?.mapAddress ??
                                                    '',
                                                initialAddress:
                                                    receiverData?.address,
                                                initialLandmark:
                                                    receiverData?.landmark,
                                                initialName: receiverData?.name,
                                                initialPhone:
                                                    receiverData?.phone,
                                                location:
                                                    receiverData != null
                                                        ? LatLng(
                                                          receiverData!
                                                              .latitude,
                                                          receiverData!
                                                              .longitude,
                                                        )
                                                        : null,
                                              ),
                                        ),
                                      );

                                      if (result != null) {
                                        setState(() {
                                          receiverData = AddressModel(
                                            name: result['name'],
                                            phone: result['phone'],
                                            address: result['address'],
                                            landmark: result['landmark'],
                                            mapAddress: result['mapAddress'],
                                            latitude:
                                                result['location'].latitude,
                                            longitude:
                                                result['location'].longitude,
                                          );
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
                                        setState(() {
                                          receiverData = AddressModel(
                                            name: result['name'],
                                            phone: result['phone'],
                                            address: result['address'],
                                            landmark: result['landmark'],
                                            mapAddress: result['mapAddress'],
                                            latitude:
                                                result['location'].latitude,
                                            longitude:
                                                result['location'].longitude,
                                          );
                                        });
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              _calculateLineHeight();
                                            });
                                      }
                                    },
                                    onClear:
                                        receiverData != null
                                            ? () {
                                              setState(() {
                                                receiverData = null;
                                              });
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                    _calculateLineHeight();
                                                  });
                                            }
                                            : null,
                                  ),
                                ),
                              ],
                            ),
                            Positioned(
                              top: 45,
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

                        const SizedBox(height: 20),

                        // ✅ Apply Coupon tile
                        GestureDetector(
                          onTap: _openCouponSheet,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.resendBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 15.0,
                                horizontal: 15,
                              ),
                              child: Row(
                                children: [
                                  Image.asset(
                                    AppImages.tag,
                                    height: 24,
                                    width: 24,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CustomTextFields.textWithStyles700(
                                          _appliedCouponCode == null
                                              ? 'Apply Coupon'
                                              : 'Coupon: ${_appliedCouponCode!}',
                                          color: AppColors.resendBlue,
                                          fontSize: 15,
                                        ),
                                        if (_appliedCouponCode != null &&
                                            _discountAmount > 0)
                                          Text(
                                            'You saved ₹${_discountAmount.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              color: Colors.green,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (_applyingCoupon)
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    Image.asset(
                                      AppImages.rightArrow,
                                      width: 24,
                                      height: 24,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),
                        CustomTextFields.textWithStyles700(
                          'Order Summary',
                          fontSize: 17,
                        ),
                        const SizedBox(height: 10),

                        // ✅ summary with conditional discount
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.commonBlack.withOpacity(0.1),
                              width: 1.5,
                            ),
                          ),
                          child: ListTile(
                            subtitle: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 5.0,
                              ),
                              child: Column(
                                spacing: 5,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(AppTexts.senderDetails),
                                      Text(
                                        capitalizeFirstLetter(
                                          widget.sender.name ?? '',
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(AppTexts.recipientDetails),
                                      Text(
                                        capitalizeFirstLetter(
                                          widget.receiver.name ?? '',
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(AppTexts.itemType),
                                      Text(widget.parcelType ?? ''),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
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
                                  const SizedBox(height: 8),

                                  Row(
                                    children: [
                                      const Expanded(child: Text('Subtotal')),
                                      CustomTextFields.textWithImage(
                                        text: _subTotal.toStringAsFixed(2),
                                        imagePath: AppImages.nCurrency,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ],
                                  ),
                                  if (_discountAmount > 0) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Discount',
                                            style: TextStyle(
                                              color: Colors.green,
                                            ),
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              '- ',
                                              style: TextStyle(
                                                color: Colors.green,
                                              ),
                                            ),
                                            CustomTextFields.textWithImage(
                                              text: _discountAmount
                                                  .toStringAsFixed(2),
                                              imagePath: AppImages.nCurrency,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child:
                                            CustomTextFields.textWithStyles600(
                                              AppTexts.totalBill,
                                              fontSize: 14,
                                            ),
                                      ),
                                      CustomTextFields.textWithImage(
                                        text: _totalAfterDiscount
                                            .toStringAsFixed(2),
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
                        ),
                        const SizedBox(height: 18),
                        CustomTextFields.textWithStyles700(
                          'Delivery Summary',
                          fontSize: 16,
                        ),
                        const SizedBox(height: 10),
                        _buildPackageSummaryCard(),
                      ],
                    ),
                  ),

                  Container(
                    color: const Color(0xFFF6F7FF).withOpacity(0.7),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          CustomTextFields.textWithStyles700(
                            AppTexts.reviewYourOrderToAvoidCancellations,
                            fontSize: 16,
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () async {
                              const url =
                                  'https://next.fenizotechnologies.com/hoppr/Privacy-Policy/';
                              if (await canLaunchUrl(Uri.parse(url))) {
                                await launchUrl(
                                  Uri.parse(url),
                                  mode: LaunchMode.inAppWebView,
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not open Privacy Policy',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.commonWhite,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.commonBlack.withOpacity(0.1),
                                  width: 1.5,
                                ),
                              ),
                              child: ListTile(
                                subtitle: Column(
                                  spacing: 5,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child:
                                              CustomTextFields.textWithStylesSmall(
                                                AppTexts.readPolicy,
                                              ),
                                        ),
                                      ],
                                    ),
                                    CustomTextFields.textWithStyles600(
                                      'Read Policy',
                                      color: AppColors.resendBlue,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 25),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
      bottomNavigationBar: Obx(() {
        if (packageController.isConfirmLoading.value) {
          return const SizedBox.shrink();
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            child: AppButtons.button(
              onTap: () async {
                final String? bookingId =
                    packageController.packageDetails.value?.data?.bookingId;

                packageController.sendPackageDriverRequest(
                  discountCode: _appliedCouponCode ?? '',
                  bookingId: bookingId ?? '',
                  receiverData: receiverData!,
                  senderData: senderData!,
                  // Optionally pass coupon info:
                  // couponCode: _appliedCouponCode,
                  // discountAmount: _discountAmount,
                  // finalAmount: _totalAfterDiscount,
                );
              },
              text: 'Confirm Booking',
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPackageSummaryCard() {
    final amountText = _totalAfterDiscount.toStringAsFixed(2);
    final parcelLabel =
        (widget.parcelType == null || widget.parcelType!.trim().isEmpty)
            ? 'Package'
            : widget.parcelType!.trim();
    final weightLabel =
        (widget.weight == null || widget.weight!.trim().isEmpty)
            ? 'Not added'
            : widget.weight!.trim();
    final senderAddress =
        widget.sender.mapAddress.isNotEmpty
            ? widget.sender.mapAddress
            : widget.sender.address;
    final receiverAddress =
        widget.receiver.mapAddress.isNotEmpty
            ? widget.receiver.mapAddress
            : widget.receiver.address;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.containerColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.commonBlack.withOpacity(0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: AppColors.commonWhite,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: AppColors.commonBlack,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomTextFields.textWithStyles700(
                        parcelLabel,
                        fontSize: 16,
                      ),
                      const SizedBox(height: 4),
                      CustomTextFields.textWithStylesSmall(
                        'Delivery details at a glance',
                        colors: AppColors.commonBlack.withOpacity(0.65),
                      ),
                    ],
                  ),
                ),
                CustomTextFields.textWithImage(
                  text: amountText,
                  imagePath: AppImages.nBlackCurrency,
                  fontWeight: FontWeight.w900,
                  colors: AppColors.commonBlack,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildSummaryChip(
                  icon: Icons.scale_rounded,
                  label: weightLabel,
                ),
                _buildSummaryChip(
                  icon: Icons.local_shipping_outlined,
                  label: parcelLabel,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildSummaryAddressRow(
              iconPath: AppImages.circleStart,
              title: 'Pickup',
              value: senderAddress,
            ),
            const SizedBox(height: 10),
            _buildSummaryAddressRow(
              iconPath: AppImages.rectangleDest,
              title: 'Drop',
              value: receiverAddress,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.commonWhite,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.commonBlack),
          const SizedBox(width: 8),
          CustomTextFields.textWithStyles600(label, fontSize: 13),
        ],
      ),
    );
  }

  Widget _buildSummaryAddressRow({
    required String iconPath,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Image.asset(iconPath, height: 16, width: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomTextFields.textWithStyles600(title, fontSize: 13),
              const SizedBox(height: 2),
              CustomTextFields.textWithStylesSmall(
                value,
                maxLines: 2,
                colors: AppColors.commonBlack.withOpacity(0.65),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
