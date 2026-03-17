class PopularPlace {
  final String name;
  final String address;
  final double lat;
  final double lng;

  PopularPlace({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  factory PopularPlace.fromJson(Map<String, dynamic> json) {
    return PopularPlace(
      name: json['name'],
      address: json['vicinity'],
      lat: json['geometry']['location']['lat'],
      lng: json['geometry']['location']['lng'],
    );
  }
}
