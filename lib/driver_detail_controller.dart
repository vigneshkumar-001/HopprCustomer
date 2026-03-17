import 'package:get/get.dart';
import 'driver_model.dart';

class DriverController extends GetxController {
  RxList<DriverModel> drivers = <DriverModel>[].obs;
  String selectedVehicleType = 'car';

  void updateDriversFromResponse(List<dynamic> responseData) {
    drivers.value =
        responseData
            .where((e) => e['onlineStatus'] == true)
            .map(
              (e) => DriverModel(
                id: e['_id'],
                lat: e['currentLatitude'],
                lng: e['currentLongitude'],
                vehicleType: e['vehicleType'] ?? 'car',
              ),
            )
            .toList();
  }

  void setVehicleType(String type) {
    selectedVehicleType = type;
    update();
  }
}
