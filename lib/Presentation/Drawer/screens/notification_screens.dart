import 'package:flutter/material.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Core/Utility/empty_state_view.dart';
import 'package:hopper/Presentation/Drawer/controller/notification_controller.dart';
import 'package:hopper/Presentation/Drawer/models/notification_response.dart';
import '../../Authentication/widgets/textFields.dart';
import 'package:get/get.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final NotificationController notificationController =
  Get.put(NotificationController());

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    notificationController.getNotification(isFirstLoad: true);

    _tabController = TabController(length: 4, vsync: this);

    _scrollController.addListener(_paginationListener);
  }

  void _paginationListener() {
    final triggerOffset = 200; // prefetch distance

    if (!notificationController.isMoreLoading.value &&
        _scrollController.position.pixels >
            _scrollController.position.maxScrollExtent - triggerOffset) {
      notificationController.getNotification();
    }
  }


  String getImagePath(String imageType, bool sharedBooking) {
    if (sharedBooking) return AppImages.twoPeople;

    switch (imageType.toLowerCase()) {
      case "bike":
        return AppImages.nCar;
      case "car":
        return AppImages.nCar;
      case "package":
        return AppImages.nPackage;
      case "wallet":
        return AppImages.bWallet;
      case "cancelled":
        return AppImages.nClose;
      default:
        return AppImages.nCar;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
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
                  CustomTextFields.textWithStyles700(
                    'Notifications',
                    fontSize: 20,
                  ),
                  const Spacer(),
                ],
              ),
            ),

            // TabBar
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
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'Ride'),
                  Tab(text: 'Package'),
                  Tab(text: 'Shared'),
                ],
                labelColor: Colors.black,
                unselectedLabelColor: Colors.black,
                indicator: const UnderlineTabIndicator(
                  borderSide: BorderSide(color: Colors.black, width: 3),
                ),
              ),
            ),

            Obx(() {
              return Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildNotificationList(
                      notificationController.notificationData,
                    ),

                    _buildNotificationList(
                      notificationController.notificationData
                          .where((n) => n.bookingType == "Ride")
                          .toList(),
                    ),

                    _buildNotificationList(
                      notificationController.notificationData
                          .where((n) => n.bookingType == "Parcel")
                          .toList(),
                    ),

                    _buildNotificationList(
                      notificationController.notificationData
                          .where((n) => n.sharedBooking == true)
                          .toList(),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationList(List<NotificationData> notifications) {
    return Obx(() {
      if (notificationController.isLoading.value &&
          notificationController.notificationData.isEmpty) {
        return AppLoader.circularLoader();
      }

      if (notifications.isEmpty) {
        final overallEmpty =
            notificationController.notificationData.isEmpty;
        if (notificationController.hasError.value && overallEmpty) {
          return EmptyStateView(
            image: AppImages.errorServer,
            title: "Something went wrong",
            subtitle:
                "We couldn't load your notifications. Please try again.",
            onRetry: () =>
                notificationController.getNotification(isFirstLoad: true),
          );
        }
        return EmptyStateView(
          image: AppImages.emptyNotifications,
          title: "No notifications yet",
          subtitle:
              "Updates about your rides, payments and offers will appear here.",
        );
      }

      return RefreshIndicator(
        onRefresh: () => notificationController.getNotification(isFirstLoad: true),
        child: ListView.builder(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(10),
          itemCount: notifications.length + 1,       itemBuilder: (context, index) {
            if (index == notifications.length) {
              return Obx(() => notificationController.isMoreLoading.value
                  ?   Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: AppLoader.circularLoader()),
              )
                  : const SizedBox());
            }

            final data = notifications[index];

            return buildNotificationCard(
              tittle: data.title.toString() ?? '',
              description: data.message.toString() ?? '',
              id: 'ID: ${data.bookingId}',
              time: data.createdAt.toString(),
              imageType: data.imageType.toString() ?? '',
              sharedBooking: data.sharedBooking ?? false,
            );
          },
        ),
      );
    });
  }

  Widget buildNotificationCard({
    required String tittle,
    required String description,
    required String id,
    required String time,
    required String imageType,
    required bool sharedBooking,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.rideShareContainerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.circularClr,
                child: Image.asset(
                  getImagePath(imageType, sharedBooking),
                  height: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tittle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      id,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          CustomTextFields.textWithImage(
            text: time,
            imagePath: AppImages.clock,
          ),
        ],
      ),
    );
  }
}


// import 'package:flutter/material.dart';
// import 'package:hopper/Core/Consents/app_colors.dart';
//
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/Core/Utility/app_loader.dart';
// import 'package:hopper/Presentation/Drawer/controller/notification_controller.dart';
// import 'package:hopper/Presentation/Drawer/models/notification_response.dart';
// import '../../Authentication/widgets/textFields.dart';
// import 'package:get/get.dart';
//
// class NotificationScreen extends StatefulWidget {
//   const NotificationScreen({super.key});
//
//   @override
//   State<NotificationScreen> createState() => _NotificationScreenState();
// }
//
// class _NotificationScreenState extends State<NotificationScreen>
//     with SingleTickerProviderStateMixin {
//   late TabController _tabController;
//   final NotificationController notificationController = Get.put(
//     NotificationController(),
//   );
//   @override
//   void initState() {
//     super.initState();
//     notificationController.getNotification();
//     _tabController = TabController(length: 4, vsync: this);
//   }
//
//   String getImagePath(String imageType, bool sharedBooking) {
//     if (sharedBooking) return AppImages.twoPeople;
//
//     switch (imageType.toLowerCase()) {
//       case "Bike":
//         return AppImages.nCar;
//       case "Car":
//         return AppImages.nCar;
//       case "package":
//         return AppImages.nPackage;
//       case "Wallet":
//         return AppImages.bWallet;
//       case "Cancelled":
//         return AppImages.nClose;
//
//       default:
//         return AppImages.nCar; // default image
//     }
//   }
//
//   @override
//   void dispose() {
//     _tabController.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: SafeArea(
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Header
//             Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
//               child: Row(
//                 children: [
//                   GestureDetector(
//                     onTap: () => Navigator.pop(context),
//                     child: Image.asset(
//                       AppImages.backImage,
//                       height: 19,
//                       width: 19,
//                     ),
//                   ),
//                   const Spacer(),
//                   CustomTextFields.textWithStyles700(
//                     'Notifications',
//                     fontSize: 20,
//                   ),
//                   const Spacer(),
//                 ],
//               ),
//             ),
//
//             // TabBar
//             Container(
//               width: double.infinity,
//               decoration: BoxDecoration(
//                 border: Border(
//                   bottom: BorderSide(
//                     color: AppColors.adminChatContainerColor,
//                     width: 2.5,
//                   ),
//                 ),
//               ),
//               child: TabBar(
//                 controller: _tabController,
//                 tabs: const [
//                   Tab(text: 'All'),
//                   Tab(text: 'Ride'),
//                   Tab(text: 'Package'),
//                   Tab(text: 'Shared'),
//                 ],
//                 labelColor: Colors.black,
//                 unselectedLabelColor: Colors.black,
//                 indicator: const UnderlineTabIndicator(
//                   borderSide: BorderSide(color: Colors.black, width: 3),
//                   insets: EdgeInsets.symmetric(horizontal: 0),
//                 ),
//                 labelStyle: TextStyle(
//                   color: AppColors.drawerT,
//                   fontWeight: FontWeight.w500,
//                   fontSize: 15,
//                 ),
//                 unselectedLabelStyle: TextStyle(
//                   color: AppColors.drawerT,
//                   fontWeight: FontWeight.w500,
//                 ),
//               ),
//             ),
//
//             Obx(() {
//               return Expanded(
//                 child: TabBarView(
//                   controller: _tabController,
//                   children: [
//                     _buildNotificationList(
//                       notificationController.notificationData,
//                     ),
//
//                     _buildNotificationList(
//                       notificationController.notificationData
//                           .where((n) => n.bookingType == "Ride")
//                           .toList(),
//                     ),
//
//                     _buildNotificationList(
//                       notificationController.notificationData
//                           .where((n) => n.bookingType == "Parcel")
//                           .toList(),
//                     ),
//
//                     _buildNotificationList(
//                       notificationController.notificationData
//                           .where((n) => n.sharedBooking == true)
//                           .toList(),
//                     ),
//                   ],
//                 ),
//               );
//             }),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildNotificationList(List<NotificationData> notifications) {
//     return Obx(() {
//       if (notificationController.isLoading.value) {
//         return AppLoader.circularLoader();
//       }
//
//       if (notifications.isEmpty) {
//         return const Center(child: Text("No notifications"));
//       }
//
//       return RefreshIndicator(
//         onRefresh: () => notificationController.getNotification(),
//         child: ListView.builder(
//           physics: BouncingScrollPhysics(),
//           padding: const EdgeInsets.all(10),
//           itemCount: notifications.length,
//           itemBuilder: (context, index) {
//             // final Map<String, String> typeIcons = {
//             //   "Wallet": AppImages.wallet,
//             //   "Bike": AppImages.nPackage,
//             //   "Car": AppImages.nCar,
//             //   "Parcel_arrived": AppImages.nPackage,
//             //   "Cancelled": AppImages.nClose,
//             // };
//             //
//             // final Map<String, Color> typeColors = {
//             //   "Wallet": AppColors.greyDark,
//             //   "Bike": Colors.blue.shade100,
//             //   "Car": AppColors.circularClr,
//             //   "Parcel_arrived": AppColors.circularClr,
//             //   "Cancelled": AppColors.circularClr,
//             // };
//
//             final data = notifications[index];
//             // final iconPath = typeIcons[data.imageType] ?? AppImages.nCar;
//             // final bgColor =
//             //     typeColors[data.imageType] ?? AppColors.rideShareContainerColor;
//             return buildNotificationCard(
//               tittle: data.title,
//               description: data.message,
//               id: 'ID: ${data.bookingId}',
//               time: data.createdAt.toString(),
//               imageType: data.imageType,
//               sharedBooking: data.sharedBooking,
//             );
//           },
//         ),
//       );
//     });
//   }
//
//   Widget buildNotificationCard({
//     required String tittle,
//     required String description,
//     required String id,
//     required String time,
//     required String imageType,
//     required bool sharedBooking,
//   }) {
//     return Container(
//       padding: const EdgeInsets.all(12),
//       margin: const EdgeInsets.only(bottom: 10),
//       decoration: BoxDecoration(
//         border: Border.all(color: AppColors.rideShareContainerColor),
//         borderRadius: BorderRadius.circular(12),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               CircleAvatar(
//                 backgroundColor: AppColors.circularClr,
//                 child: Image.asset(
//                   getImagePath(imageType, sharedBooking),
//                   height: 16,
//                 ),
//               ),
//               const SizedBox(width: 10),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       tittle,
//                       style: const TextStyle(
//                         fontWeight: FontWeight.w600,
//                         fontSize: 14,
//                       ),
//                     ),
//                     Text(
//                       description,
//                       style: TextStyle(
//                         color: Colors.grey.shade600,
//                         fontSize: 12,
//                       ),
//                     ),
//                     Text(
//                       id,
//                       style: TextStyle(
//                         color: Colors.grey.shade600,
//                         fontSize: 12,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 5),
//           CustomTextFields.textWithImage(
//             text: time,
//             imagePath: AppImages.clock,
//           ),
//         ],
//       ),
//     );
//   }
// }
