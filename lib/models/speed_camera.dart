class SpeedCameraZone {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double speedLimit;

  SpeedCameraZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.speedLimit,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'speedLimit': speedLimit,
      };

  factory SpeedCameraZone.fromJson(Map<String, dynamic> json) => SpeedCameraZone(
        id: json['id'] as String,
        name: json['name'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        speedLimit: (json['speedLimit'] as num).toDouble(),
      );
}
