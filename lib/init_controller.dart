import 'package:get/get.dart';
import 'package:hopper/Presentation/Authentication/controller/authController.dart';
import 'package:hopper/Presentation/Authentication/controller/network_handling_controller.dart';
import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
import 'package:hopper/Presentation/Drawer/controller/profle_cotroller.dart';
import 'package:hopper/Presentation/Drawer/controller/ride_history_controller.dart';
import 'package:hopper/driver_detail_controller.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';

import 'Presentation/Authentication/controller/location_gate_controller.dart';

Future<void> initController() async {
  // Register dependencies needed by other controllers first.
  Get.lazyPut<RideHistoryController>(() => RideHistoryController(), fenix: true);

  // Immediately available controllers.
  Get.put(AuthController(), permanent: true);
  Get.put(NetworkController(), permanent: true);
  Get.put(PackageController(), permanent: true);
  Get.put(ProfleCotroller(), permanent: true);

  // Lazy controllers.
  Get.lazyPut<DriverController>(() => DriverController());
  Get.lazyPut<DriverSearchController>(() => DriverSearchController());
  Get.put(LocationGateController(), permanent: true);
}
