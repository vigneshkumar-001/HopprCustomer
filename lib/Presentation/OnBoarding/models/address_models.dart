class AddressModel {
  final String name;
  final String phone;
  final String address;
  final String landmark;
  final String mapAddress;
  final double latitude;
  final double longitude;


  AddressModel({
    required this.name,
    required this.phone,
    required this.address,
    required this.landmark,
    required this.mapAddress,
    required this.latitude,
    required this.longitude,
  });

  @override
  String toString() {
    return 'AddressModel(name: $name, phone: $phone, address: $address, landmark: $landmark, mapAddress: $mapAddress, latitude: $latitude, longitude: $longitude)';
  }
}
