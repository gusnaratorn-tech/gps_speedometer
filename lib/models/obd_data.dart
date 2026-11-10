class ObdTelemetryData {
  final double rpm;
  final double coolantTemp;
  final double boostBar;
  final double throttlePercent;
  final double fuelLevelPercent;
  final double ecuSpeedKmh;

  const ObdTelemetryData({
    this.rpm = 0.0,
    this.coolantTemp = 90.0,
    this.boostBar = 0.0,
    this.throttlePercent = 0.0,
    this.fuelLevelPercent = 100.0,
    this.ecuSpeedKmh = 0.0,
  });

  bool get isOverheating => coolantTemp > 105.0;
  bool get isRedline => rpm >= 6500.0;

  ObdTelemetryData copyWith({
    double? rpm,
    double? coolantTemp,
    double? boostBar,
    double? throttlePercent,
    double? fuelLevelPercent,
    double? ecuSpeedKmh,
  }) {
    return ObdTelemetryData(
      rpm: rpm ?? this.rpm,
      coolantTemp: coolantTemp ?? this.coolantTemp,
      boostBar: boostBar ?? this.boostBar,
      throttlePercent: throttlePercent ?? this.throttlePercent,
      fuelLevelPercent: fuelLevelPercent ?? this.fuelLevelPercent,
      ecuSpeedKmh: ecuSpeedKmh ?? this.ecuSpeedKmh,
    );
  }
}
