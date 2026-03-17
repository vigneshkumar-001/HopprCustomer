import 'package:flutter/material.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/Drawer/controller/ride_history_controller.dart';
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
        return Center(child: AppLoader.circularLoader());
      } else if (data.isEmpty) {
        return RefreshIndicator(
          onRefresh: () => controller.getRideHistory(isFirstLoad: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(
                height: 300,
                child: Center(child: Text("No Ride found")),
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

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.rideShareContainerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// Title + Status
                  Row(
                    children: [
                      Text(
                        ride.driver?.carType?.toUpperCase() ?? '',
                        style: const TextStyle(
                          fontSize: 14,
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
                          color: Color(
                            int.parse("0xFF${ride.ridehistoryColor}"),
                          ).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          ride.status == 'SUCCESS'
                              ? "Completed"
                              : ride.status.toString(),
                          style: TextStyle(
                            color: Color(
                              int.parse("0xFF${ride.ridehistoryColor}"),
                            ),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: Image.network(
                          ride.driver?.profilePic ?? '',
                          height: 35,
                          width: 35,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) =>
                                  const Icon(Icons.person, size: 35),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        ride.driver?.firstName ?? "",
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  /// Pickup & Drop
                  Stack(
                    children: [
                      Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.circle,
                                size: 12,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  ride.pickupAddress ?? '',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.circle,
                                size: 12,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  ride.dropAddress ?? '',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Positioned(
                        top: 15,
                        left: 6,
                        child: DottedLine(
                          dashColor: Colors.grey,
                          lineLength: 50,
                          direction: Axis.vertical,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  /// Rating & Price
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.orange, size: 20),
                      const SizedBox(width: 4),
                      Text(ride.starRating?.toString() ?? "0"),
                      const Spacer(),
                      CustomTextFields.textWithImage(
                        text: ride.amount?.toString() ?? "",
                        fontSize: 16,
                        imageColors: AppColors.changeButtonColor,
                        colors: AppColors.changeButtonColor,
                        fontWeight: FontWeight.w600,
                        imageSize: 20,
                        imagePath: AppImages.nBlackCurrency,
                      ),
                      // Text(
                      //   ride.amount?.toString() ?? "",
                      //   style: const TextStyle(
                      //     fontSize: 16,
                      //     fontWeight: FontWeight.w700,
                      //   ),
                      // ),
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

  // ============ PARCEL LIST =============
  Widget _buildParcelList() {
    return Obx(() {
      final parcels = controller.parcelHistoryList;

      if (controller.isLoading.value) {
        return Center(child: AppLoader.circularLoader());
      } else if (parcels.isEmpty) {
        return RefreshIndicator(
          onRefresh: () => controller.getRideHistory(isFirstLoad: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(
                height: 300,
                child: Center(child: Text("No Ride found")),
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
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Image.asset(
                      AppImages.backImage,
                      height: 19,
                      width: 19,
                    ),
                  ),
                  const Spacer(),
                  CustomTextFields.textWithStyles700('History', fontSize: 20),
                  const Spacer(),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.adminChatContainerColor,
                    width: 2.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      controller: _tabController,
                      tabs: const [Tab(text: 'Rides'), Tab(text: 'Package')],
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.black,
                      indicator: const UnderlineTabIndicator(
                        borderSide: BorderSide(color: Colors.black, width: 3),
                        insets: EdgeInsets.symmetric(horizontal: 0),
                      ),
                      labelStyle: TextStyle(
                        color: AppColors.drawerT,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                      unselectedLabelStyle: TextStyle(
                        color: AppColors.drawerT,
                        fontWeight: FontWeight.w500,
                      ),
                      dividerColor: Colors.transparent,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {},
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(' '),
                      ),
                    ),
                  ),
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



