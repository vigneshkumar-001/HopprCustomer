class PopularPlace {
  final String name;
  final String address;
  final double lat;
  final double lng;

  /// Category key derived from the Google place `types` (e.g. 'airport',
  /// 'train', 'mall', 'hospital', 'place'). Drives the icon shown in the UI.
  final String category;

  PopularPlace({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.category = 'place',
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
