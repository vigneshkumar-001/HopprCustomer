import 'package:flutter/material.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Core/Utility/empty_state_view.dart';
import 'package:hopper/Core/Utility/skeleton_loaders.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/Drawer/controller/ride_history_controller.dart';
import 'package:hopper/Presentation/Drawer/screens/ride_details_screen.dart';
import 'package:hopper/Presentation/Drawer/utils/ride_history_format.dart';
import 'package:get/get.dart';

class RideAndPackageHistoryScreen extends StatefulWidget {
  final int initialTabIndex; // 0 = Rides, 1 = Package

  const RideAndPackageHistoryScreen({super.key, this.initialTabIndex = 0});

  @override
  State<RideAndPackageHistoryScreen> createState() =>
      _RideAndPackageHistoryScreenState();
}

class _RideAndPackageHistoryScreenState
    extends State<RideAndPackageHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final RideHistoryController controller = Get.find<RideHistoryController>();
  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    controller.getRideHistory(isFirstLoad: true);
    controller.scrollController.addListener(_paginationListener);
  }
  @override
  void dispose() {
    controller.scrollController.removeListener(_paginationListener);
    _tabController.dispose();
    super.dispose();
  }

  void _paginationListener() {
    const triggerOffset = 200; // prefetch distance

    if (!controller.isMoreLoading.value &&
        controller.scrollController.position.pixels >
            controller.scrollController.position.maxScrollExtent - triggerOffset) {
      controller.getRideHistory();
    }
  }

  Widget _buildRideList() {
    return Obx(() {
      final data = controller.rideHistoryList;

      if (controller.isLoading.value) {
        return SkeletonLoaders.rideHistory();
      } else if (data.isEmpty) {
        return RefreshIndicator(
          onRefresh: () => controller.getRideHistory(isFirstLoad: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: 360,
                child: controller.hasError.value
                    ? EmptyStateView(
                        image: AppImages.errorServer,
                        title: "Something went wrong",
                        subtitle:
                            "We couldn't load your rides. Please try again.",
                        onRetry: () =>
                            controller.getRideHistory(isFirstLoad: true),
                      )
                    : EmptyStateView(
                        image: AppImages.emptyRides,
                        title: "No rides yet",
                        subtitle:
                            "Your completed rides will appear here once you take your first trip.",
                      ),
              ),
            ],
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: () => controller.getRideHistory(isFirstLoad: true),
        child: ListView.builder(
          controller: controller.scrollController,

          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: data.length + 1,

          itemBuilder: (context, index) {
            if (index == data.length) {
              return controller.isMoreLoading.value
                  ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(child: AppLoader.circularLoader()),
                  )
                  : const SizedBox.shrink();
            }

            final ride = data[index];
            final driverName =
                '${ride.driver?.firstName ?? ''} ${ride.driver?.lastName ?? ''}'
                    .trim();
            final statusLabel = prettyStatus(ride.status);
            final isCancelled =
                statusLabel.toLowerCase().contains('cancel') ||
                statusLabel.toLowerCase().contains('fail');
            final statusClr =
                isCancelled
                    ? const Color(0xFFF04438) // refined red
                    : const Color(0xFF12B76A); // fresh emerald
            final statusIcon =
                isCancelled ? Icons.close_rounded : Icons.check_rounded;

            return TweenAnimationBuilder<double>(
              key: ValueKey(ride.id ?? ride.bookingId ?? index),
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 260 + (index % 8) * 55),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) {
                return Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 16),
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(14, index == 0 ? 14 : 6, 14, 6),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black.withOpacity(0.05)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        Get.to(
                          () => RideDetailsScreen(ride: ride),
                          transition: Transition.rightToLeft,
                          duration: const Duration(milliseconds: 300),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top: thumbnail + drop address / driver + amount
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Vehicle photo in a soft tinted thumbnail
                                Container(
                                  width: 64,
                                  height: 64,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.containerColor1,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Image.asset(
                                    vehicleAssetForType(ride.driver?.carType),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ride.dropAddress ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          height: 1.25,
                                        ),
                                      ),
                                      if (driverName.isNotEmpty) ...[
                                        const SizedBox(height: 5),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.person_outline_rounded,
                                              size: 14,
                                              color: AppColors.textColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                driverName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: AppColors.textColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                CustomTextFields.textWithImage(
                                  text: (ride.amount ?? '').toString(),
                                  fontSize: 16,
                                  imageColors: AppColors.commonBlack,
                                  colors: AppColors.commonBlack,
                                  fontWeight: FontWeight.w800,
                                  imageSize: 16,
                                  imagePath: AppImages.nBlackCurrency,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: Colors.black.withOpacity(0.05),
                            ),
                            const SizedBox(height: 10),
                            // Footer: date + status pill
                            Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 14,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    formatRideDateShort(ride.createdAt),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusClr.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        statusIcon,
                                        size: 13,
                                        color: statusClr,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        statusLabel,
                                        style: TextStyle(
                                          color: statusClr,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }

  // ============ PARCEL LIST =============
  Widget _buildParcelList() {
    return Obx(() {
      final parcels = controller.parcelHistoryList;

      if (controller.isLoading.value) {
        return SkeletonLoaders.parcelHistory();
      } else if (parcels.isEmpty) {
        return RefreshIndicator(
          onRefresh: () => controller.getRideHistory(isFirstLoad: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: 360,
                child: controller.hasError.value
                    ? EmptyStateView(
                        image: AppImages.errorServer,
                        title: "Something went wrong",
                        subtitle:
                            "We couldn't load your deliveries. Please try again.",
                        onRetry: () =>
                            controller.getRideHistory(isFirstLoad: true),
                      )
                    : EmptyStateView(
                        image: AppImages.emptyDeliveries,
                        title: "No deliveries yet",
                        subtitle:
                            "Your package deliveries will appear here once you send your first parcel.",
                      ),
              ),
            ],
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: () => controller.getRideHistory(isFirstLoad: true),
        child: ListView.builder(
          controller: controller.scrollController, // 🔥 FIXED
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: parcels.length + 1,
          itemBuilder: (context, index) {
            if (index == parcels.length) {
              return controller.isMoreLoading.value
                  ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                  : const SizedBox.shrink();
            }

            final parcel = parcels[index];

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.rideShareContainerColor),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        parcel.parcelType ?? "Parcel",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          parcel.status == 'SUCCESS'
                              ? "Completed"
                              : parcel.status.toString() ?? '',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.more_vert, size: 20),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Pickup & Drop
                  // Time
                  Row(
                    children: [
                      Text(
                        parcel.rideDurationFormatted.toString() ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.carTypeColor,
                        ),
                      ),
                      // const Icon(
                      //   Icons.arrow_right_alt_sharp,
                      //   size: 15,
                      //   color: Colors.grey,
                      // ),
                      // Text(
                      //   "",
                      //   style: TextStyle(
                      //     fontSize: 13,
                      //     color: AppColors.carTypeColor,
                      //   ),
                      // ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      CustomTextFields.textWithStyles600(
                        parcel.fromContactName.toString().toUpperCase() ?? '',
                        fontSize: 12,
                      ),
                      Icon(
                        Icons.arrow_right_alt_sharp,
                        size: 15,
                        color: AppColors.commonBlack,
                      ),
                      CustomTextFields.textWithStyles600(
                        ' ${parcel.toContactName.toString().toUpperCase() ?? ''}',
                        fontSize: 12,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Stack(
                    children: [
                      Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.circle,
                                  color: Colors.green,
                                  size: 12,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Pickup Address',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      parcel.pickupAddress ?? "",
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 5),
                                child: Icon(
                                  Icons.circle,
                                  color: Colors.orange,
                                  size: 12,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Delivery Address',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      parcel.dropAddress ?? "",
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Positioned(
                        top: 16,
                        left: 5,
                        child: DottedLine(
                          direction: Axis.vertical,
                          lineLength: 55,
                          dashLength: 3,
                          dashColor: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.orange, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        parcel.starRating?.toString() ?? "0",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      CustomTextFields.textWithImage(
                        text: parcel.total.toString() ?? "",
                        fontSize: 16,
                        imageColors: AppColors.changeButtonColor,
                        colors: AppColors.changeButtonColor,
                        fontWeight: FontWeight.w600,
                        imageSize: 20,
                        imagePath: AppImages.nBlackCurrency,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
    });
  }

  // =============== BUILD ===============
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          children: [
            // White header + tab zone (cards below sit on a light grey bg).
            Container(
              color: Colors.white,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 16, 4),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Text(
                          'History',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: Colors.black,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.black,
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    dividerColor: Colors.transparent,
                    tabs: const [Tab(text: 'Rides'), Tab(text: 'Package')],
                  ),
                  Container(height: 1, color: AppColors.containerColor1),
                ],
              ),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildRideList(), _buildParcelList()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}



