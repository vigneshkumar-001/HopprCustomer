class RecentLocation {
  final String description;
  final double lat;
  final double lng;

  RecentLocation({
    required this.description,
    required this.lat,
    required this.lng,
  });

  factory RecentLocation.fromJson(Map<String, dynamic> json) {
    return RecentLocation(
      description: json['description'],
      lat: json['lat'],
      lng: json['lng'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'lat': lat,
      'lng': lng,
    };
  }
}
