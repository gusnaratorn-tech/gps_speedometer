import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const SpeedometerApp());
}

// -------------------------------------------------------------
// THEME & SOUND CONFIGURATION
// -------------------------------------------------------------
class AppThemeOption {
  final String name;
  final Color primary;
  final Color secondary;
  final Color background;
  final Color cardBackground;

  const AppThemeOption({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.background,
    required this.cardBackground,
  });
}

const List<AppThemeOption> kAvailableThemes = [
  AppThemeOption(
    name: 'Cyberpunk Neon',
    primary: Color(0xFF00F0FF),
    secondary: Color(0xFFFF3B30),
    background: Color(0xFF070B14),
    cardBackground: Color(0xFF0D1527),
  ),
  AppThemeOption(
    name: 'Racing Red',
    primary: Color(0xFFFF2A6D),
    secondary: Color(0xFFFFD600),
    background: Color(0xFF0B0609),
    cardBackground: Color(0xFF1B0B14),
  ),
  AppThemeOption(
    name: 'Electric Lime',
    primary: Color(0xFF00FF66),
    secondary: Color(0xFFFF3B30),
    background: Color(0xFF050E08),
    cardBackground: Color(0xFF091C10),
  ),
  AppThemeOption(
    name: 'Sunset Gold',
    primary: Color(0xFFFFB800),
    secondary: Color(0xFFFF3B30),
    background: Color(0xFF0E0B05),
    cardBackground: Color(0xFF1F170A),
  ),
];

enum SoundToneStyle {
  cyberpunk,
  supercar,
  scifi,
  sportBell,
}

const Map<SoundToneStyle, String> kSoundToneLabels = {
  SoundToneStyle.cyberpunk: 'Cyberpunk Beep (950Hz)',
  SoundToneStyle.supercar: 'Supercar Chime (Dual Tone)',
  SoundToneStyle.scifi: 'Sci-Fi Arcade (Arpeggio)',
  SoundToneStyle.sportBell: 'Sport Bell (A5 Harmonic)',
};

// -------------------------------------------------------------
// SPEED CAMERA POI MODEL
// -------------------------------------------------------------
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
}

// -------------------------------------------------------------
// TRIP RECORD MODEL & LOCAL PERSISTENCE
// -------------------------------------------------------------
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

class TripStorageService {
  static const String _fileName = 'trip_history.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<TripRecord>> loadTrips() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> list = jsonDecode(content) as List<dynamic>;
      return list.map((e) => TripRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveTrip(TripRecord trip) async {
    try {
      final trips = await loadTrips();
      trips.insert(0, trip);
      final file = await _getFile();
      final jsonStr = jsonEncode(trips.map((e) => e.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (_) {}
  }

  static Future<void> deleteTrip(String id) async {
    try {
      final trips = await loadTrips();
      trips.removeWhere((t) => t.id == id);
      final file = await _getFile();
      final jsonStr = jsonEncode(trips.map((e) => e.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

// -------------------------------------------------------------
// SOUND SYNTHESIZER (PCM WAV FOR MULTIPLE STYLES)
// -------------------------------------------------------------
Uint8List _generateSoundTone(SoundToneStyle style) {
  const int sampleRate = 44100;
  final double duration = style == SoundToneStyle.supercar ? 0.20 : 0.14;
  final int numSamples = (sampleRate * duration).toInt();
  final int dataSize = numSamples * 2;
  final int fileSize = 36 + dataSize;
  final buffer = ByteData(44 + dataSize);

  // RIFF header
  buffer.setUint8(0, 0x52); // R
  buffer.setUint8(1, 0x49); // I
  buffer.setUint8(2, 0x46); // F
  buffer.setUint8(3, 0x46); // F
  buffer.setUint32(4, fileSize, Endian.little);
  buffer.setUint8(8, 0x57);  // W
  buffer.setUint8(9, 0x41);  // A
  buffer.setUint8(10, 0x56); // V
  buffer.setUint8(11, 0x45); // E

  // fmt chunk
  buffer.setUint8(12, 0x66); // f
  buffer.setUint8(13, 0x6D); // m
  buffer.setUint8(14, 0x74); // t
  buffer.setUint8(15, 0x20); // space
  buffer.setUint32(16, 16, Endian.little);
  buffer.setUint16(20, 1, Endian.little); // PCM
  buffer.setUint16(22, 1, Endian.little); // mono
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, sampleRate * 2, Endian.little);
  buffer.setUint16(32, 2, Endian.little);
  buffer.setUint16(34, 16, Endian.little);

  // data chunk
  buffer.setUint8(36, 0x64); // d
  buffer.setUint8(37, 0x61); // a
  buffer.setUint8(38, 0x74); // t
  buffer.setUint8(39, 0x61); // a
  buffer.setUint32(40, dataSize, Endian.little);

  int offset = 44;
  for (int i = 0; i < numSamples; i++) {
    double t = i / sampleRate;
    double progress = i / numSamples;
    double envelope = 1.0;
    if (progress < 0.12) {
      envelope = progress / 0.12;
    } else if (progress > 0.8) {
      envelope = (1.0 - progress) / 0.2;
    }

    double sampleVal = 0.0;
    switch (style) {
      case SoundToneStyle.cyberpunk:
        sampleVal = sin(2 * pi * 950 * t);
        break;
      case SoundToneStyle.supercar:
        sampleVal = 0.55 * sin(2 * pi * 1150 * t) + 0.45 * sin(2 * pi * 780 * t);
        break;
      case SoundToneStyle.scifi:
        double freq = 650 + 650 * progress;
        sampleVal = sin(2 * pi * freq * t);
        break;
      case SoundToneStyle.sportBell:
        double decay = exp(-3.5 * progress);
        sampleVal = sin(2 * pi * 880 * t) * decay;
        break;
    }

    int pcm = (sampleVal * 28000 * envelope).clamp(-32768, 32767).toInt();
    buffer.setInt16(offset, pcm, Endian.little);
    offset += 2;
  }

  return buffer.buffer.asUint8List();
}

class SpeedometerApp extends StatefulWidget {
  const SpeedometerApp({super.key});

  @override
  State<SpeedometerApp> createState() => _SpeedometerAppState();
}

class _SpeedometerAppState extends State<SpeedometerApp> {
  int _themeIndex = 0;

  void _changeTheme(int index) {
    setState(() {
      _themeIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = kAvailableThemes[_themeIndex];

    return MaterialApp(
      title: 'GPS Speedometer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: theme.background,
        colorScheme: ColorScheme.dark(
          primary: theme.primary,
          secondary: theme.secondary,
        ),
      ),
      home: SpeedometerHomeScreen(
        currentTheme: theme,
        themeIndex: _themeIndex,
        onThemeChanged: _changeTheme,
      ),
    );
  }
}

class SpeedometerHomeScreen extends StatefulWidget {
  final AppThemeOption currentTheme;
  final int themeIndex;
  final ValueChanged<int> onThemeChanged;

  const SpeedometerHomeScreen({
    super.key,
    required this.currentTheme,
    required this.themeIndex,
    required this.onThemeChanged,
  });

  @override
  State<SpeedometerHomeScreen> createState() => _SpeedometerHomeScreenState();
}

enum DragRunState { idle, readyToLaunch, running, finished }

class _SpeedometerHomeScreenState extends State<SpeedometerHomeScreen> {
  static const MethodChannel _wakelockChannel =
      MethodChannel('com.example.gps_speedometer/wakelock');
  static const MethodChannel _pipChannel =
      MethodChannel('com.example.gps_speedometer/pip');

  // RepaintBoundary Key for Telemetry Card Sharing
  final GlobalKey _shareCardKey = GlobalKey();

  // State Metrics
  double _rawSpeedMs = 0.0;
  double _currentSpeed = 0.0; // In selected unit
  double _maxSpeed = 0.0;
  double _avgSpeed = 0.0;
  double _totalDistanceMeters = 0.0;
  int _elapsedSeconds = 0;

  // Additional GPS Sensors
  double _heading = 0.0;
  double _altitude = 0.0;
  double _accuracy = 0.0;

  // UX & Tabs
  bool _isTracking = false;
  bool _isHudFlipped = false;
  bool _isHudFullscreen = false;
  int _activeTab = 0; // 0: Gauge, 1: Digital, 2: HUD, 3: Performance (Drag)

  // Settings
  String _unit = 'km/h'; // 'km/h', 'mph', 'knots'
  double _speedLimit = 80.0;
  double _maxGaugeScale = 260.0;
  bool _audioAlertEnabled = true;
  bool _vibrationAlertEnabled = true;
  SoundToneStyle _soundStyle = SoundToneStyle.cyberpunk;

  // Fuel Economy & Cost Settings
  double _fuelConsumptionKmPerL = 14.5; // km/L
  double _fuelPricePerLiter = 38.50; // THB or currency unit

  // Speed Camera Alert Settings
  bool _speedCameraAlertEnabled = true;
  final List<SpeedCameraZone> _speedCameras = [
    SpeedCameraZone(id: 'c1', name: 'Expressway Camera 1', latitude: 13.7563, longitude: 100.5018, speedLimit: 90),
    SpeedCameraZone(id: 'c2', name: 'Ring Road Radar', latitude: 13.8000, longitude: 100.5500, speedLimit: 80),
  ];
  SpeedCameraZone? _nearbySpeedCamera;
  double? _cameraDistanceMeters;

  // Streams & Timers
  StreamSubscription<Position>? _positionStream;
  Timer? _tripTimer;
  Timer? _alertPulseTimer;
  final List<double> _speedRecords = [];
  final List<double> _recentSpeedPoints = [];
  Position? _lastPosition;

  // -----------------------------------------------------------
  // PERFORMANCE / DRAG TEST STATE
  // -----------------------------------------------------------
  DragRunState _dragState = DragRunState.idle;
  DateTime? _dragStartTime;
  Timer? _dragWatchTimer;
  double _dragElapsedSec = 0.0;
  double? _time0To60;
  double? _time0To100;
  double? _timeQuarterMile;
  double? _quarterMileTrapSpeed;
  double _dragDistanceMeters = 0.0;
  Position? _dragLastPosition;
  double _currentGForce = 0.0;
  double _peakGForce = 0.0;
  double _lastSpeedForGMs = 0.0;
  DateTime _lastGTime = DateTime.now();
  int _treeLightStage = 0;

  // Audio Player & Audio Buffers
  late final AudioPlayer _audioPlayer;
  late Uint8List _currentToneBytes;
  late final Uint8List _highBeepBytes;
  bool _isAlertPulsing = false;

  @override
  void initState() {
    super.initState();
    _currentToneBytes = _generateSoundTone(_soundStyle);
    _highBeepBytes = _generateSoundTone(SoundToneStyle.supercar);
    _audioPlayer = AudioPlayer();
    _checkLocationPermission();
  }

  @override
  void dispose() {
    _setScreenAwake(false);
    _positionStream?.cancel();
    _tripTimer?.cancel();
    _dragWatchTimer?.cancel();
    _alertPulseTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // Native Android Wakelock
  Future<void> _setScreenAwake(bool awake) async {
    try {
      await _wakelockChannel.invokeMethod(awake ? 'enable' : 'disable');
    } catch (_) {}
  }

  // Native Android Picture-in-Picture (Floating Overlay)
  Future<void> _enterPictureInPicture() async {
    try {
      await _pipChannel.invokeMethod('enterPip');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Floating PiP mode is supported on Android 8.0+ devices.'),
          ),
        );
      }
    }
  }

  void _syncWakelockState() {
    final shouldKeepAwake = _isTracking || _activeTab == 2 || _activeTab == 3;
    _setScreenAwake(shouldKeepAwake);
  }

  double _convertSpeed(double speedMs) {
    if (speedMs < 0.3) return 0.0;
    switch (_unit) {
      case 'mph':
        return speedMs * 2.23694;
      case 'knots':
        return speedMs * 1.94384;
      case 'km/h':
      default:
        return speedMs * 3.6;
    }
  }

  String _formatDistance(double meters) {
    if (_unit == 'mph') {
      final miles = meters / 1609.344;
      return '${miles.toStringAsFixed(2)} mi';
    } else if (_unit == 'knots') {
      final nm = meters / 1852.0;
      return '${nm.toStringAsFixed(2)} nm';
    } else {
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(2)} km';
    }
  }

  double get _consumedFuelLiters {
    final distanceKm = _totalDistanceMeters / 1000.0;
    if (_fuelConsumptionKmPerL <= 0) return 0.0;
    return distanceKm / _fuelConsumptionKmPerL;
  }

  double get _tripFuelCost {
    return _consumedFuelLiters * _fuelPricePerLiter;
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      if (!mounted) return;

      _rawSpeedMs = position.speed >= 0 ? position.speed : 0.0;
      final speedInUnit = _convertSpeed(_rawSpeedMs);

      // G-force calculation
      final now = DateTime.now();
      final dt = now.difference(_lastGTime).inMilliseconds / 1000.0;
      if (dt > 0.1) {
        final dv = _rawSpeedMs - _lastSpeedForGMs;
        final accel = dv / dt;
        final rawG = accel / 9.80665;
        _currentGForce = (_currentGForce * 0.7) + (rawG * 0.3);
        if (_currentGForce > _peakGForce) {
          _peakGForce = _currentGForce;
        }
        _lastSpeedForGMs = _rawSpeedMs;
        _lastGTime = now;
      }

      // Speed Camera Proximity Check
      _checkSpeedCameraProximity(position);

      setState(() {
        _currentSpeed = speedInUnit;
        _heading = position.heading;
        _altitude = position.altitude;
        _accuracy = position.accuracy;

        _recentSpeedPoints.add(speedInUnit);
        if (_recentSpeedPoints.length > 35) {
          _recentSpeedPoints.removeAt(0);
        }

        if (_isTracking) {
          if (speedInUnit > _maxSpeed) _maxSpeed = speedInUnit;

          if (_lastPosition != null) {
            double distance = Geolocator.distanceBetween(
              _lastPosition!.latitude,
              _lastPosition!.longitude,
              position.latitude,
              position.longitude,
            );
            if (speedInUnit > 0.5) {
              _totalDistanceMeters += distance;
            }
          }
          _lastPosition = position;
        }

        _processPerformanceDrag(position, speedInUnit);
        _handleSpeedAlertCheck();
      });
    });
  }

  void _checkSpeedCameraProximity(Position position) {
    if (!_speedCameraAlertEnabled || _speedCameras.isEmpty) {
      _nearbySpeedCamera = null;
      _cameraDistanceMeters = null;
      return;
    }

    SpeedCameraZone? closest;
    double minDistance = double.infinity;

    for (var cam in _speedCameras) {
      double dist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        cam.latitude,
        cam.longitude,
      );
      if (dist < 800.0 && dist < minDistance) {
        minDistance = dist;
        closest = cam;
      }
    }

    _nearbySpeedCamera = closest;
    _cameraDistanceMeters = closest != null ? minDistance : null;
  }

  void _addCustomSpeedCameraHere() {
    if (_lastPosition == null) return;
    final newCam = SpeedCameraZone(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Custom Radar #${_speedCameras.length + 1}',
      latitude: _lastPosition!.latitude,
      longitude: _lastPosition!.longitude,
      speedLimit: _speedLimit,
    );
    setState(() {
      _speedCameras.add(newCam);
    });
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: widget.currentTheme.cardBackground,
        content: Text('Marked Speed Camera at current GPS location (Limit: ${_speedLimit.toInt()} $_unit)'),
      ),
    );
  }

  void _armPerformanceTest() {
    setState(() {
      _dragState = DragRunState.readyToLaunch;
      _dragStartTime = null;
      _dragElapsedSec = 0.0;
      _time0To60 = null;
      _time0To100 = null;
      _timeQuarterMile = null;
      _quarterMileTrapSpeed = null;
      _dragDistanceMeters = 0.0;
      _dragLastPosition = null;
      _peakGForce = 0.0;
      _treeLightStage = 1;
    });
    _syncWakelockState();
    HapticFeedback.mediumImpact();
  }

  void _resetPerformanceTest() {
    _dragWatchTimer?.cancel();
    setState(() {
      _dragState = DragRunState.idle;
      _dragStartTime = null;
      _dragElapsedSec = 0.0;
      _time0To60 = null;
      _time0To100 = null;
      _timeQuarterMile = null;
      _quarterMileTrapSpeed = null;
      _dragDistanceMeters = 0.0;
      _dragLastPosition = null;
      _peakGForce = 0.0;
      _treeLightStage = 0;
    });
  }

  void _processPerformanceDrag(Position position, double currentSpeedKmh) {
    if (_activeTab != 3) return;

    double speedKmh = _rawSpeedMs * 3.6;

    if (_dragState == DragRunState.idle && speedKmh < 1.0) {
      _dragState = DragRunState.readyToLaunch;
      _treeLightStage = 1;
    }

    if (_dragState == DragRunState.readyToLaunch && speedKmh > 1.8) {
      _dragState = DragRunState.running;
      _dragStartTime = DateTime.now();
      _dragLastPosition = position;
      _treeLightStage = 3;
      HapticFeedback.heavyImpact();
      if (_audioAlertEnabled) {
        _audioPlayer.play(BytesSource(_currentToneBytes), mode: PlayerMode.lowLatency);
      }

      _dragWatchTimer?.cancel();
      _dragWatchTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
        if (_dragState != DragRunState.running || !mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _dragElapsedSec = DateTime.now().difference(_dragStartTime!).inMilliseconds / 1000.0;
        });
      });
    }

    if (_dragState == DragRunState.running && _dragStartTime != null) {
      if (_dragLastPosition != null) {
        double d = Geolocator.distanceBetween(
          _dragLastPosition!.latitude,
          _dragLastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        _dragDistanceMeters += d;
      }
      _dragLastPosition = position;

      double elapsed = DateTime.now().difference(_dragStartTime!).inMilliseconds / 1000.0;
      _dragElapsedSec = elapsed;

      if (_time0To60 == null && speedKmh >= 60.0) {
        _time0To60 = elapsed;
        HapticFeedback.lightImpact();
      }

      if (_time0To100 == null && speedKmh >= 100.0) {
        _time0To100 = elapsed;
        HapticFeedback.heavyImpact();
        if (_audioAlertEnabled) {
          _audioPlayer.play(BytesSource(_highBeepBytes), mode: PlayerMode.lowLatency);
        }
      }

      if (_timeQuarterMile == null && _dragDistanceMeters >= 402.3) {
        _timeQuarterMile = elapsed;
        _quarterMileTrapSpeed = speedKmh;
      }

      if (_time0To100 != null && (_timeQuarterMile != null || speedKmh < 10.0 || elapsed > 30.0)) {
        _dragState = DragRunState.finished;
        _dragWatchTimer?.cancel();
        HapticFeedback.vibrate();
      }
    }
  }

  void _handleSpeedAlertCheck() {
    bool isOverLimit = _currentSpeed > _speedLimit && _isTracking;

    if (isOverLimit) {
      if (!_isAlertPulsing) {
        _startAlertPulsing();
      }
    } else {
      if (_isAlertPulsing) {
        _stopAlertPulsing();
      }
    }
  }

  void _startAlertPulsing() {
    _isAlertPulsing = true;
    _playSingleAlert();

    _alertPulseTimer?.cancel();
    double margin = _currentSpeed - _speedLimit;
    int intervalMs = margin > 25 ? 500 : (margin > 12 ? 850 : 1200);

    _alertPulseTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (!_isAlertPulsing || !mounted) {
        timer.cancel();
        return;
      }
      _playSingleAlert();
    });
  }

  void _stopAlertPulsing() {
    _isAlertPulsing = false;
    _alertPulseTimer?.cancel();
    _alertPulseTimer = null;
  }

  Future<void> _playSingleAlert() async {
    if (_vibrationAlertEnabled) {
      HapticFeedback.heavyImpact();
    }
    if (_audioAlertEnabled) {
      try {
        await _audioPlayer.play(BytesSource(_currentToneBytes), mode: PlayerMode.lowLatency);
      } catch (_) {}
    }
  }

  void _toggleTrip() {
    setState(() {
      _isTracking = !_isTracking;
      _syncWakelockState();

      if (_isTracking) {
        _tripTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return;
          setState(() {
            _elapsedSeconds++;
            if (_currentSpeed > 1) {
              _speedRecords.add(_currentSpeed);
              _avgSpeed = _speedRecords.reduce((a, b) => a + b) / _speedRecords.length;
            }
          });
        });
      } else {
        _tripTimer?.cancel();
        _stopAlertPulsing();
        _saveCurrentTripIfValid();
      }
    });
  }

  Future<void> _saveCurrentTripIfValid() async {
    if (_totalDistanceMeters > 50 || _elapsedSeconds > 15) {
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final record = TripRecord(
        id: now.millisecondsSinceEpoch.toString(),
        dateTimeFormatted: dateStr,
        distanceMeters: _totalDistanceMeters,
        durationSeconds: _elapsedSeconds,
        maxSpeed: _maxSpeed,
        avgSpeed: _avgSpeed,
        unit: _unit,
        bestZeroHundredSec: _time0To100,
        peakG: _peakGForce,
        fuelLiters: _consumedFuelLiters,
        tripCost: _tripFuelCost,
      );

      await TripStorageService.saveTrip(record);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: widget.currentTheme.cardBackground,
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: widget.currentTheme.primary, size: 18),
                const SizedBox(width: 8),
                const Text('Trip saved to History Logbook', style: TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _resetTrip() {
    _saveCurrentTripIfValid();
    setState(() {
      _isTracking = false;
      _syncWakelockState();
      _tripTimer?.cancel();
      _stopAlertPulsing();
      _currentSpeed = 0.0;
      _maxSpeed = 0.0;
      _avgSpeed = 0.0;
      _totalDistanceMeters = 0.0;
      _elapsedSeconds = 0;
      _speedRecords.clear();
      _recentSpeedPoints.clear();
      _lastPosition = null;
    });
  }

  String _formatDuration(int seconds) {
    int h = seconds ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    int s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _getCardinalDirection(double heading) {
    if (heading < 0) return '--';
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    int index = ((heading + 22.5) % 360 ~/ 45);
    return directions[index];
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.currentTheme;
    bool isOverLimit = _currentSpeed > _speedLimit && _isTracking;

    // Fullscreen HUD Mode for Windshield Projection
    if (_isHudFullscreen && _activeTab == 2) {
      return GestureDetector(
        onTap: () => setState(() => _isHudFullscreen = false),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: _buildHudView(isOverLimit, theme),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.cardBackground,
        elevation: 0,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gps_fixed, color: theme.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              'SPEEDOMETER',
              style: TextStyle(
                color: theme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.picture_in_picture_alt_outlined, color: theme.primary),
            tooltip: 'Floating PiP Overlay',
            onPressed: _enterPictureInPicture,
          ),
          IconButton(
            icon: Icon(Icons.history_rounded, color: theme.primary),
            tooltip: 'Trip History & Share',
            onPressed: _showTripHistoryModal,
          ),
          IconButton(
            icon: Icon(Icons.tune, color: theme.primary),
            tooltip: 'Settings',
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Tabs Bar (Gauge, Digital, HUD, Drag)
            Container(
              color: theme.cardBackground.withOpacity(0.6),
              child: Row(
                children: [
                  _buildTabItem(0, 'Gauge', Icons.speed, theme),
                  _buildTabItem(1, 'Digital', Icons.pin, theme),
                  _buildTabItem(2, 'HUD', Icons.flip, theme),
                  _buildTabItem(3, 'Drag', Icons.sports_score_rounded, theme),
                ],
              ),
            ),

            // Speed Limit Warning Alert Banner
            if (isOverLimit)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: theme.secondary.withOpacity(0.95),
                  boxShadow: [
                    BoxShadow(
                      color: theme.secondary.withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'SPEED LIMIT EXCEEDED! (${_currentSpeed.toStringAsFixed(0)} / ${_speedLimit.toStringAsFixed(0)} $_unit)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),

            // Speed Camera Radar Alert Banner
            if (_nearbySpeedCamera != null && _cameraDistanceMeters != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
                color: const Color(0xFFFF9900),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.camera_alt, color: Colors.black, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '📷 ${_nearbySpeedCamera!.name.toUpperCase()} IN ${_cameraDistanceMeters!.toStringAsFixed(0)}m (LIMIT ${_nearbySpeedCamera!.speedLimit.toInt()} $_unit)',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11.5),
                    ),
                  ],
                ),
              ),

            // Telemetry Compass / GPS / G-Force Bar
            Container(
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: theme.cardBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTelemetryBadge(
                    icon: Icons.explore_outlined,
                    label: 'Heading',
                    value: '${_heading.toStringAsFixed(0)}° ${_getCardinalDirection(_heading)}',
                    color: theme.primary,
                  ),
                  _buildTelemetryBadge(
                    icon: Icons.terrain_outlined,
                    label: 'Altitude',
                    value: '${_altitude.toStringAsFixed(0)} m',
                    color: theme.primary,
                  ),
                  _buildTelemetryBadge(
                    icon: Icons.speed,
                    label: 'G-Force',
                    value: '${_currentGForce >= 0 ? '+' : ''}${_currentGForce.toStringAsFixed(2)}G',
                    color: _currentGForce.abs() > 0.4 ? theme.secondary : theme.primary,
                  ),
                  _buildTelemetryBadge(
                    icon: Icons.satellite_alt_outlined,
                    label: 'GPS Signal',
                    value: _accuracy > 0 ? '±${_accuracy.toStringAsFixed(1)}m' : 'Locking...',
                    color: _accuracy < 10 && _accuracy > 0 ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                ],
              ),
            ),

            // Main Active View (Gauge, Digital, HUD, or Drag Performance)
            Expanded(
              child: Center(
                child: _activeTab == 0
                    ? _buildGaugeView(isOverLimit, theme)
                    : _activeTab == 1
                        ? _buildDigitalView(isOverLimit, theme)
                        : _activeTab == 2
                            ? _buildHudView(isOverLimit, theme)
                            : _buildPerformanceDragView(theme),
              ),
            ),

            // Real-Time Speed Telemetry Sparkline Graph (Shown on tabs 0, 1)
            if (_recentSpeedPoints.isNotEmpty && (_activeTab == 0 || _activeTab == 1))
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: theme.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'REAL-TIME SPEED TELEMETRY',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Text(
                          '${_currentSpeed.toStringAsFixed(1)} $_unit',
                          style: TextStyle(
                            color: theme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 40,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: SpeedHistoryGraphPainter(
                          history: _recentSpeedPoints,
                          maxScale: _maxGaugeScale,
                          speedLimit: _speedLimit,
                          lineColor: isOverLimit ? theme.secondary : theme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Metrics Cards Grid (Shown on tabs 0, 1, 2)
            if (_activeTab != 3)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 2.1,
                  children: [
                    _buildMetricTile('Max Speed', '${_maxSpeed.toStringAsFixed(0)} $_unit', Icons.arrow_upward, theme),
                    _buildMetricTile('Avg Speed', '${_avgSpeed.toStringAsFixed(0)} $_unit', Icons.show_chart, theme),
                    _buildMetricTile('Distance', _formatDistance(_totalDistanceMeters), Icons.straighten, theme),
                    _buildMetricTile('Duration', _formatDuration(_elapsedSeconds), Icons.timer, theme),
                    _buildMetricTile('Est. Fuel', '${_consumedFuelLiters.toStringAsFixed(2)} L', Icons.local_gas_station, theme),
                    _buildMetricTile('Trip Cost', '${_tripFuelCost.toStringAsFixed(1)} ฿', Icons.attach_money, theme),
                  ],
                ),
              ),

            const SizedBox(height: 4),

            // Bottom Trip Control & Share Card Action
            if (_activeTab != 3)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isTracking ? const Color(0xFFEF4444) : theme.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 4,
                        ),
                        onPressed: _toggleTrip,
                        icon: Icon(_isTracking ? Icons.pause : Icons.play_arrow),
                        label: Text(
                          _isTracking ? 'PAUSE TRIP' : 'START TRIP',
                          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: theme.cardBackground,
                        padding: const EdgeInsets.all(13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.share, color: Colors.white70),
                      tooltip: 'Telemetry Share Card',
                      onPressed: _showLiveShareCardModal,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: theme.cardBackground,
                        padding: const EdgeInsets.all(13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                      tooltip: 'Reset & Save Trip',
                      onPressed: _resetTrip,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  // PERFORMANCE / DRAG RACING VIEW
  // -----------------------------------------------------------
  Widget _buildPerformanceDragView(AppThemeOption theme) {
    String statusTitle;
    Color statusColor;
    switch (_dragState) {
      case DragRunState.idle:
        statusTitle = 'COME TO A COMPLETE STOP (0 km/h)';
        statusColor = Colors.white54;
        break;
      case DragRunState.readyToLaunch:
        statusTitle = 'STAGED - LAUNCH WHEN READY!';
        statusColor = const Color(0xFFFFD600);
        break;
      case DragRunState.running:
        statusTitle = 'ACCELERATING... PUSH IT!';
        statusColor = const Color(0xFF00FF66);
        break;
      case DragRunState.finished:
        statusTitle = 'RUN COMPLETE!';
        statusColor = theme.primary;
        break;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildDragTreeLights(theme),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withOpacity(0.5)),
            ),
            child: Text(
              statusTitle,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),

          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  const Text('TIMER', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                  Text(
                    '${_dragElapsedSec.toStringAsFixed(2)}s',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                      color: _dragState == DragRunState.running ? const Color(0xFF00FF66) : Colors.white,
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  const Text('SPEED', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                  Text(
                    _currentSpeed.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                      color: theme.primary,
                    ),
                  ),
                  Text(_unit, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _buildDragSplitCard(
                  title: '0 - 60 km/h',
                  time: _time0To60,
                  icon: Icons.timer_outlined,
                  theme: theme,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDragSplitCard(
                  title: '0 - 100 km/h',
                  time: _time0To100,
                  icon: Icons.sports_score,
                  theme: theme,
                  isHighlight: true,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _buildDragSplitCard(
                  title: '1/4 Mile (402m)',
                  time: _timeQuarterMile,
                  extra: _quarterMileTrapSpeed != null ? '@ ${_quarterMileTrapSpeed!.toStringAsFixed(0)} km/h' : null,
                  icon: Icons.flag_outlined,
                  theme: theme,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDragSplitCard(
                  title: 'Peak Acceleration',
                  time: null,
                  customValue: '+${_peakGForce.toStringAsFixed(2)} G',
                  icon: Icons.bolt,
                  theme: theme,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _armPerformanceTest,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('ARM / RE-ARM', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: theme.cardBackground,
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.share, color: Colors.white70),
                tooltip: 'Share Drag Card',
                onPressed: _showLiveShareCardModal,
              ),
              const SizedBox(width: 6),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: theme.cardBackground,
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.clear, color: Colors.white70),
                onPressed: _resetPerformanceTest,
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildDragTreeLights(AppThemeOption theme) {
    bool isPreStage = _treeLightStage >= 1;
    bool isAmber = _treeLightStage >= 2;
    bool isGreen = _treeLightStage >= 3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF050811),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTreeLightDot('PRE', const Color(0xFFFF9900), isPreStage),
          const SizedBox(width: 12),
          _buildTreeLightDot('STAGED', const Color(0xFFFFCC00), isAmber),
          const SizedBox(width: 12),
          _buildTreeLightDot('GO', const Color(0xFF00FF66), isGreen),
        ],
      ),
    );
  }

  Widget _buildTreeLightDot(String label, Color activeColor, bool isActive) {
    return Column(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? activeColor : activeColor.withOpacity(0.15),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withOpacity(0.8),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDragSplitCard({
    required String title,
    required double? time,
    String? customValue,
    String? extra,
    required IconData icon,
    required AppThemeOption theme,
    bool isHighlight = false,
  }) {
    String display = customValue ?? (time != null ? '${time.toStringAsFixed(2)}s' : '--');
    Color activeColor = isHighlight ? theme.primary : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlight ? theme.primary.withOpacity(0.4) : Colors.white.withOpacity(0.06),
          width: isHighlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: isHighlight ? theme.primary : Colors.white38),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: isHighlight ? theme.primary : Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            display,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
              color: activeColor,
            ),
          ),
          if (extra != null)
            Text(
              extra,
              style: const TextStyle(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  Widget _buildTelemetryBadge({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 8.5, fontWeight: FontWeight.w600),
            ),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTabItem(int index, String label, IconData icon, AppThemeOption theme) {
    bool isSelected = _activeTab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _activeTab = index);
          _syncWakelockState();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? theme.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
            color: isSelected ? theme.primary.withOpacity(0.08) : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: isSelected ? theme.primary : Colors.white54),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? theme.primary : Colors.white54,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGaugeView(bool isOverLimit, AppThemeOption theme) {
    return SizedBox(
      width: 320,
      height: 320,
      child: CustomPaint(
        painter: SpeedometerGaugePainter(
          speed: _currentSpeed,
          maxScale: _maxGaugeScale,
          speedLimit: _speedLimit,
          isOverLimit: isOverLimit,
          unit: _unit,
          primaryColor: theme.primary,
          secondaryColor: theme.secondary,
        ),
      ),
    );
  }

  Widget _buildDigitalView(bool isOverLimit, AppThemeOption theme) {
    final activeColor = isOverLimit ? theme.secondary : theme.primary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _currentSpeed.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 98,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
            color: activeColor,
            shadows: [
              Shadow(
                color: activeColor.withOpacity(0.6),
                blurRadius: 28,
              ),
            ],
          ),
        ),
        Text(
          _unit.toUpperCase(),
          style: const TextStyle(fontSize: 22, color: Colors.white70, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: theme.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            'LIMIT: ${_speedLimit.toStringAsFixed(0)} $_unit',
            style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildHudView(bool isOverLimit, AppThemeOption theme) {
    final activeColor = isOverLimit ? theme.secondary : theme.primary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..scale(_isHudFlipped ? -1.0 : 1.0, 1.0),
          child: Column(
            children: [
              Text(
                _currentSpeed.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 116,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  color: activeColor,
                  shadows: [
                    Shadow(color: activeColor.withOpacity(0.8), blurRadius: 36),
                  ],
                ),
              ),
              Text(
                _unit.toUpperCase(),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: activeColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_heading.toStringAsFixed(0)}° ${_getCardinalDirection(_heading)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.cardBackground,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => setState(() => _isHudFlipped = !_isHudFlipped),
              icon: const Icon(Icons.flip, size: 16),
              label: Text(_isHudFlipped ? 'Normal View' : 'Mirror Flip', style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.cardBackground,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => setState(() => _isHudFullscreen = true),
              icon: const Icon(Icons.fullscreen, size: 16),
              label: const Text('Fullscreen HUD', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile(String title, String value, IconData icon, AppThemeOption theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.primary, size: 17),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w600)),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------
  // RACING TELEMETRY SHARE CARD MODAL
  // -----------------------------------------------------------
  void _showLiveShareCardModal() {
    final theme = widget.currentTheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.share, color: theme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text('Racing Telemetry Card', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Renderable Share Card
            RepaintBoundary(
              key: _shareCardKey,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.cardBackground, theme.background],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.primary.withOpacity(0.6), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: theme.primary.withOpacity(0.2), blurRadius: 16, spreadRadius: 2),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.sports_motorsports, color: theme.primary, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              'GPS SPEEDOMETER TELEMETRY',
                              style: TextStyle(
                                color: theme.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          DateTime.now().toString().substring(0, 16),
                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 20),

                    // Big Stats Highlights
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildShareCardStat('TOP SPEED', '${_maxSpeed.toStringAsFixed(0)} $_unit', theme.secondary),
                        _buildShareCardStat('AVG SPEED', '${_avgSpeed.toStringAsFixed(0)} $_unit', theme.primary),
                        _buildShareCardStat('DISTANCE', _formatDistance(_totalDistanceMeters), Colors.white),
                        _buildShareCardStat('DURATION', _formatDuration(_elapsedSeconds), Colors.white),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Additional Telemetry
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildShareSubStat('0-100 km/h', _time0To100 != null ? '${_time0To100!.toStringAsFixed(2)}s' : '--'),
                          _buildShareSubStat('Peak Accel', '+${_peakGForce.toStringAsFixed(2)} G'),
                          _buildShareSubStat('Est. Fuel', '${_consumedFuelLiters.toStringAsFixed(1)} L'),
                          _buildShareSubStat('Est. Cost', '${_tripFuelCost.toStringAsFixed(0)} ฿'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Share & Export Actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _exportCardAsImage,
                    icon: const Icon(Icons.download),
                    label: const Text('SAVE IMAGE / EXPORT', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _exportGpxFile,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('GPX / CSV', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareCardStat(String title, String val, Color color) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildShareSubStat(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8.5)),
        Text(val, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Future<void> _exportCardAsImage() async {
    try {
      RenderRepaintBoundary boundary =
          _shareCardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/telemetry_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: widget.currentTheme.cardBackground,
            content: Text('Saved Telemetry Card to:\n${file.path}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to render image: $e')),
        );
      }
    }
  }

  Future<void> _exportGpxFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final gpxFile = File('${dir.path}/trip_${DateTime.now().millisecondsSinceEpoch}.gpx');

      final gpxContent = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="GPS Speedometer App">
  <metadata>
    <time>${DateTime.now().toUtc().toIso8601String()}</time>
    <desc>Distance: ${_totalDistanceMeters.toStringAsFixed(0)}m, Max Speed: ${_maxSpeed.toStringAsFixed(1)} $_unit</desc>
  </metadata>
  <trk>
    <name>GPS Speedometer Track</name>
    <trkseg>
      <trkpt lat="${_lastPosition?.latitude ?? 0.0}" lon="${_lastPosition?.longitude ?? 0.0}">
        <ele>${_altitude.toStringAsFixed(1)}</ele>
        <time>${DateTime.now().toUtc().toIso8601String()}</time>
        <speed>${_rawSpeedMs.toStringAsFixed(2)}</speed>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

      await gpxFile.writeAsString(gpxContent);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: widget.currentTheme.cardBackground,
            content: Text('Exported GPX file to:\n${gpxFile.path}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  // -----------------------------------------------------------
  // TRIP HISTORY MODAL
  // -----------------------------------------------------------
  void _showTripHistoryModal() async {
    final theme = widget.currentTheme;
    final trips = await TripStorageService.loadTrips();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          double totalKm = trips.fold(0.0, (acc, t) => acc + (t.distanceMeters / 1000.0));
          int totalSec = trips.fold(0, (acc, t) => acc + t.durationSeconds);
          double totalCost = trips.fold(0.0, (acc, t) => acc + (t.tripCost ?? 0.0));

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) => Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.history, color: theme.primary, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Trip History Logbook',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      if (trips.isNotEmpty)
                        TextButton(
                          onPressed: () async {
                            await TripStorageService.clearAll();
                            setModalState(() => trips.clear());
                          },
                          child: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('Trips', style: TextStyle(color: Colors.white38, fontSize: 10)),
                          Text('${trips.length}', style: TextStyle(color: theme.primary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        children: [
                          const Text('Distance', style: TextStyle(color: Colors.white38, fontSize: 10)),
                          Text('${totalKm.toStringAsFixed(1)} km', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        children: [
                          const Text('Duration', style: TextStyle(color: Colors.white38, fontSize: 10)),
                          Text(_formatDuration(totalSec), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        children: [
                          const Text('Cost', style: TextStyle(color: Colors.white38, fontSize: 10)),
                          Text('${totalCost.toStringAsFixed(0)} ฿', style: TextStyle(color: theme.secondary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12),
                Expanded(
                  child: trips.isEmpty
                      ? const Center(
                          child: Text(
                            'No recorded trips yet.\nStart a trip to log stats!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38, fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: trips.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final t = trips[idx];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.background,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withOpacity(0.06)),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: theme.primary.withOpacity(0.12),
                                    child: Icon(Icons.directions_car, color: theme.primary, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.dateTimeFormatted,
                                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              '${(t.distanceMeters / 1000).toStringAsFixed(2)} km',
                                              style: TextStyle(color: theme.primary, fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Top: ${t.maxSpeed.toStringAsFixed(0)} ${t.unit}',
                                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                                            ),
                                            const SizedBox(width: 8),
                                            if (t.tripCost != null)
                                              Text(
                                                '${t.tripCost!.toStringAsFixed(0)} ฿',
                                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                                              ),
                                          ],
                                        ),
                                        if (t.bestZeroHundredSec != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              '🏁 Best 0-100: ${t.bestZeroHundredSec!.toStringAsFixed(2)}s',
                                              style: const TextStyle(color: Color(0xFF00FF66), fontSize: 10.5, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
                                    onPressed: () async {
                                      await TripStorageService.deleteTrip(t.id);
                                      setModalState(() => trips.removeAt(idx));
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // -----------------------------------------------------------
  // SETTINGS DIALOG (UNITS, SOUNDS, FUEL & SPEED CAMERAS)
  // -----------------------------------------------------------
  void _showSettingsDialog() {
    final theme = widget.currentTheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardBackground,
        title: Row(
          children: [
            Icon(Icons.tune, color: theme.primary, size: 20),
            const SizedBox(width: 8),
            Text('App Settings', style: TextStyle(color: theme.primary, fontSize: 18)),
          ],
        ),
        content: StatefulBuilder(
          builder: (context, setModalState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Unit Switcher
                const Text('Speed Unit:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'km/h', label: Text('km/h', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: 'mph', label: Text('mph', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: 'knots', label: Text('knots', style: TextStyle(fontSize: 12))),
                  ],
                  selected: {_unit},
                  onSelectionChanged: (Set<String> newSelection) {
                    final selected = newSelection.first;
                    setModalState(() => _unit = selected);
                    setState(() {
                      _unit = selected;
                      if (_unit == 'mph') {
                        _speedLimit = 55.0;
                        _maxGaugeScale = 160.0;
                      } else if (_unit == 'knots') {
                        _speedLimit = 45.0;
                        _maxGaugeScale = 140.0;
                      } else {
                        _speedLimit = 80.0;
                        _maxGaugeScale = 260.0;
                      }
                    });
                  },
                ),
                const SizedBox(height: 14),

                // Speed Limit Slider
                Text('Speed Limit Warning: ${_speedLimit.toInt()} $_unit',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                Slider(
                  value: _speedLimit,
                  min: 20,
                  max: _maxGaugeScale * 0.85,
                  divisions: 25,
                  activeColor: theme.primary,
                  onChanged: (val) {
                    setModalState(() => _speedLimit = val);
                    setState(() => _speedLimit = val);
                  },
                ),
                const SizedBox(height: 6),

                // Sound Theme Selector
                const Text('Audio Alert Tone Style:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButtonFormField<SoundToneStyle>(
                  dropdownColor: theme.cardBackground,
                  value: _soundStyle,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: SoundToneStyle.values.map((s) {
                    return DropdownMenuItem(
                      value: s,
                      child: Text(kSoundToneLabels[s]!, style: const TextStyle(fontSize: 12, color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() => _soundStyle = val);
                      setState(() {
                        _soundStyle = val;
                        _currentToneBytes = _generateSoundTone(val);
                      });
                      _audioPlayer.play(BytesSource(_currentToneBytes), mode: PlayerMode.lowLatency);
                    }
                  },
                ),
                const SizedBox(height: 10),

                // Sound Alert & Vibration
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: theme.primary,
                  title: const Text('Sound Alert (Pulsing Beep)', style: TextStyle(fontSize: 13, color: Colors.white)),
                  value: _audioAlertEnabled,
                  onChanged: (val) {
                    setModalState(() => _audioAlertEnabled = val);
                    setState(() => _audioAlertEnabled = val);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: theme.primary,
                  title: const Text('Vibration Feedback', style: TextStyle(fontSize: 13, color: Colors.white)),
                  value: _vibrationAlertEnabled,
                  onChanged: (val) {
                    setModalState(() => _vibrationAlertEnabled = val);
                    setState(() => _vibrationAlertEnabled = val);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: theme.primary,
                  title: const Text('Speed Camera & Radar Alerts', style: TextStyle(fontSize: 13, color: Colors.white)),
                  value: _speedCameraAlertEnabled,
                  onChanged: (val) {
                    setModalState(() => _speedCameraAlertEnabled = val);
                    setState(() => _speedCameraAlertEnabled = val);
                  },
                ),

                const Divider(color: Colors.white12),

                // Fuel Economy Settings
                const Text('Fuel Cost Estimator:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _fuelConsumptionKmPerL.toString(),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'Economy (km/L)',
                          labelStyle: TextStyle(fontSize: 11),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null && parsed > 0) {
                            setState(() => _fuelConsumptionKmPerL = parsed);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        initialValue: _fuelPricePerLiter.toString(),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'Price (฿/L)',
                          labelStyle: TextStyle(fontSize: 11),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null && parsed > 0) {
                            setState(() => _fuelPricePerLiter = parsed);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Mark Camera Button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.primary,
                    side: BorderSide(color: theme.primary.withOpacity(0.5)),
                  ),
                  onPressed: () {
                    _addCustomSpeedCameraHere();
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.add_location_alt, size: 16),
                  label: const Text('Mark Speed Camera Here', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text('CLOSE', style: TextStyle(color: theme.primary, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// REAL-TIME SPEED TELEMETRY GRAPH PAINTER
// -------------------------------------------------------------
class SpeedHistoryGraphPainter extends CustomPainter {
  final List<double> history;
  final double maxScale;
  final double speedLimit;
  final Color lineColor;

  SpeedHistoryGraphPainter({
    required this.history,
    required this.maxScale,
    required this.speedLimit,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final width = size.width;
    final height = size.height;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, height * 0.5), Offset(width, height * 0.5), gridPaint);

    double limitY = height - (speedLimit / maxScale).clamp(0.0, 1.0) * height;
    final limitPaint = Paint()
      ..color = Colors.redAccent.withOpacity(0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, limitY), Offset(width, limitY), limitPaint);

    final path = Path();
    final fillPath = Path();

    double stepX = history.length > 1 ? width / (history.length - 1) : width;

    for (int i = 0; i < history.length; i++) {
      double x = i * stepX;
      double normalized = (history[i] / maxScale).clamp(0.0, 1.0);
      double y = height - (normalized * (height - 6)) - 3;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo((history.length - 1) * stepX, height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lineColor.withOpacity(0.25), lineColor.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, width, height));
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant SpeedHistoryGraphPainter oldDelegate) {
    return true;
  }
}

// -------------------------------------------------------------
// SPEEDOMETER GAUGE PAINTER (ANALOG DIAL & NEON NEEDLE)
// -------------------------------------------------------------
class SpeedometerGaugePainter extends CustomPainter {
  final double speed;
  final double maxScale;
  final double speedLimit;
  final bool isOverLimit;
  final String unit;
  final Color primaryColor;
  final Color secondaryColor;

  SpeedometerGaugePainter({
    required this.speed,
    required this.maxScale,
    required this.speedLimit,
    required this.isOverLimit,
    required this.unit,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;

    const startAngle = 135 * (pi / 180);
    const sweepAngle = 270 * (pi / 180);

    // 1. Dial Background
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF0F172A), Color(0xFF050811)],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.1));
    canvas.drawCircle(center, radius * 1.05, bgPaint);

    // 2. Base Dial Track Arc
    final baseTrackPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius * 0.84), startAngle, sweepAngle, false, baseTrackPaint);

    // 3. Warning Zone Arc (top 25%)
    final warnPaint = Paint()
      ..color = secondaryColor.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.84),
      startAngle + sweepAngle * 0.75,
      sweepAngle * 0.25,
      false,
      warnPaint,
    );

    // 4. Active Progress Arc
    final clampedSpeed = speed.clamp(0.0, maxScale);
    final activeSweep = sweepAngle * (clampedSpeed / maxScale);
    final progressPaint = Paint()
      ..color = isOverLimit ? secondaryColor : primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);

    if (activeSweep > 0.01) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius * 0.84), startAngle, activeSweep, false, progressPaint);
    }

    // 5. Ticks & Numbers
    final tickStep = (maxScale / 12).round();
    int tickCount = (maxScale / tickStep).round();

    for (int i = 0; i <= tickCount; i++) {
      double angle = startAngle + (i / tickCount) * sweepAngle;
      bool isMajor = i % 2 == 0;
      double innerR = isMajor ? radius * 0.88 : radius * 0.92;
      double outerR = radius * 0.96;

      Offset p1 = center + Offset(cos(angle) * innerR, sin(angle) * innerR);
      Offset p2 = center + Offset(cos(angle) * outerR, sin(angle) * outerR);

      final tickPaint = Paint()
        ..color = isMajor ? primaryColor.withOpacity(0.8) : const Color(0xFF334155)
        ..strokeWidth = isMajor ? 3 : 1.5;
      canvas.drawLine(p1, p2, tickPaint);

      if (isMajor) {
        double textR = radius * 0.70;
        Offset textPos = center + Offset(cos(angle) * textR, sin(angle) * textR);
        final tp = TextPainter(
          text: TextSpan(
            text: '${i * tickStep}',
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, textPos - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // 6. Pointer Needle
    double needleAngle = startAngle + activeSweep;
    final needlePaint = Paint()
      ..color = isOverLimit ? secondaryColor : Colors.white
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    Offset needleTip = center + Offset(cos(needleAngle) * (radius * 0.88), sin(needleAngle) * (radius * 0.88));
    canvas.drawLine(center, needleTip, needlePaint);

    canvas.drawCircle(center, 9, Paint()..color = const Color(0xFF0F172A));
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = isOverLimit ? secondaryColor : primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // 7. Digital Speed in Center
    final speedTextPainter = TextPainter(
      text: TextSpan(
        text: speed.toStringAsFixed(0),
        style: TextStyle(
          fontSize: 54,
          fontWeight: FontWeight.w900,
          fontFamily: 'monospace',
          color: isOverLimit ? secondaryColor : primaryColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    speedTextPainter.paint(
      canvas,
      center - Offset(speedTextPainter.width / 2, speedTextPainter.height / 2 + 10),
    );

    // 8. Unit Label Under Digital Speed
    final unitTextPainter = TextPainter(
      text: TextSpan(
        text: unit,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white54,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitTextPainter.paint(
      canvas,
      Offset(center.dx - unitTextPainter.width / 2, center.dy + speedTextPainter.height / 2 - 4),
    );
  }

  @override
  bool shouldRepaint(covariant SpeedometerGaugePainter oldDelegate) {
    return oldDelegate.speed != speed ||
        oldDelegate.isOverLimit != isOverLimit ||
        oldDelegate.maxScale != maxScale ||
        oldDelegate.speedLimit != speedLimit ||
        oldDelegate.unit != unit ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
