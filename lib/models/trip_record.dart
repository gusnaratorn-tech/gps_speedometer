class TripRecord {
  final String id;
  final String dateTimeFormatted;
  final double distanceMeters;
  final int durationSeconds;
  final double maxSpeed;
  final double avgSpeed;
  final String unit;
  final double? bestZeroHundredSec;
  final double? peakG;
  final double? fuelLiters;
  final double? tripCost;

  TripRecord({
    required this.id,
    required this.dateTimeFormatted,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.maxSpeed,
    required this.avgSpeed,
    required this.unit,
    this.bestZeroHundredSec,
    this.peakG,
    this.fuelLiters,
    this.tripCost,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'dateTimeFormatted': dateTimeFormatted,
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'maxSpeed': maxSpeed,
        'avgSpeed': avgSpeed,
        'unit': unit,
        'bestZeroHundredSec': bestZeroHundredSec,
        'peakG': peakG,
        'fuelLiters': fuelLiters,
        'tripCost': tripCost,
      };

  factory TripRecord.fromJson(Map<String, dynamic> json) => TripRecord(
        id: json['id'] as String,
        dateTimeFormatted: json['dateTimeFormatted'] as String,
        distanceMeters: (json['distanceMeters'] as num).toDouble(),
        durationSeconds: (json['durationSeconds'] as num).toInt(),
        maxSpeed: (json['maxSpeed'] as num).toDouble(),
        avgSpeed: (json['avgSpeed'] as num).toDouble(),
        unit: json['unit'] as String? ?? 'km/h',
        bestZeroHundredSec: json['bestZeroHundredSec'] != null
            ? (json['bestZeroHundredSec'] as num).toDouble()
            : null,
        peakG: json['peakG'] != null ? (json['peakG'] as num).toDouble() : null,
        fuelLiters: json['fuelLiters'] != null
            ? (json['fuelLiters'] as num).toDouble()
            : null,
        tripCost: json['tripCost'] != null
            ? (json['tripCost'] as num).toDouble()
            : null,
      );
}
