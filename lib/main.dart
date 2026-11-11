import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import 'core/themes.dart';
import 'core/sound_generator.dart';
import 'models/trip_record.dart';
import 'models/speed_camera.dart';
import 'models/obd_data.dart';
import 'models/dtc_record.dart';
import 'services/trip_storage.dart';
import 'services/voice_assistant.dart';
import 'services/obd_service.dart';
import 'ui/widgets/gauge_painter.dart';
import 'ui/widgets/telemetry_graph.dart';
import 'ui/widgets/tree_lights.dart';
import 'ui/widgets/map_canvas.dart';
import 'ui/widgets/dashcam_overlay.dart';
import 'ui/widgets/tachometer_painter.dart';

void main() {
  runApp(const SpeedometerApp());
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

  final GlobalKey _shareCardKey = GlobalKey();

  // State Metrics
  double _rawSpeedMs = 0.0;
  double _currentSpeed = 0.0;
  double _maxSpeed = 0.0;
  double _avgSpeed = 0.0;
  double _totalDistanceMeters = 0.0;
  int _elapsedSeconds = 0;

  // GPS Sensors
  double _heading = 0.0;
  double _altitude = 0.0;
  double _accuracy = 0.0;

  // UI Modes & Tabs (0: Gauge, 1: Digital, 2: HUD, 3: Drag, 4: Map, 5: Dashcam)
  int _activeTab = 0;
  bool _isTracking = false;
  bool _isHudFlipped = false;
  bool _isHudFullscreen = false;
  bool _isSplitCockpit = false;

  // Settings
  String _unit = 'km/h';
  double _speedLimit = 80.0;
  double _maxGaugeScale = 260.0;
  bool _audioAlertEnabled = true;
  bool _vibrationAlertEnabled = true;
  SoundToneStyle _soundStyle = SoundToneStyle.cyberpunk;

  // Fuel Economy
  double _fuelConsumptionKmPerL = 14.5;
  double _fuelPricePerLiter = 38.50;

  // Speed Cameras
  bool _speedCameraAlertEnabled = true;
  final List<SpeedCameraZone> _speedCameras = [
    SpeedCameraZone(id: 'c1', name: 'Expressway Camera 1', latitude: 13.7563, longitude: 100.5018, speedLimit: 90),
    SpeedCameraZone(id: 'c2', name: 'Ring Road Radar', latitude: 13.8000, longitude: 100.5500, speedLimit: 80),
  ];
  SpeedCameraZone? _nearbySpeedCamera;
  double? _cameraDistanceMeters;

  // Location & Breadcrumbs
  StreamSubscription<Position>? _positionStream;
  Timer? _tripTimer;
  Timer? _alertPulseTimer;
  final List<double> _speedRecords = [];
  final List<double> _recentSpeedPoints = [];
  final List<Position> _breadcrumbs = [];
  Position? _lastPosition;

  // Drag Racing Performance
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

  // OBD-II Bluetooth & Telemetry
  late final ObdService _obdService;
  ObdTelemetryData _obdData = const ObdTelemetryData();
  StreamSubscription<ObdTelemetryData>? _obdSubscription;
  DateTime? _lastOverheatAlertTime;

  // DTC Engine Diagnostics
  bool _isScanningDtc = false;
  bool _isClearingDtc = false;
  List<DtcCode> _detectedDtcCodes = [];
  bool _milActive = false;
  String? _dtcStatusMessage;
  final List<DtcDiagnosticReport> _savedDiagnosticReports = [];

  // Audio & Voice Services
  late final AudioPlayer _audioPlayer;
  late final VoiceAssistantService _voiceAssistant;
  late Uint8List _currentToneBytes;
  bool _isAlertPulsing = false;

  @override
  void initState() {
    super.initState();
    _currentToneBytes = SoundGenerator.generateTone(_soundStyle);
    _audioPlayer = AudioPlayer();
    _voiceAssistant = VoiceAssistantService();
    _obdService = ObdService();
    _obdSubscription = _obdService.telemetryStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _obdData = data;
      });
      _handleOverheatSafetyCheck(data);
    });
    _checkLocationPermission();
  }

  @override
  void dispose() {
    _setScreenAwake(false);
    _positionStream?.cancel();
    _tripTimer?.cancel();
    _dragWatchTimer?.cancel();
    _alertPulseTimer?.cancel();
    _obdSubscription?.cancel();
    _obdService.dispose();
    _audioPlayer.dispose();
    _voiceAssistant.dispose();
    super.dispose();
  }

  void _handleOverheatSafetyCheck(ObdTelemetryData data) {
    if (data.isOverheating) {
      final now = DateTime.now();
      if (_lastOverheatAlertTime == null || now.difference(_lastOverheatAlertTime!).inSeconds >= 8) {
        _lastOverheatAlertTime = now;
        _voiceAssistant.speakPrompt(VoicePromptType.engineOverheat, extraInfo: '${data.coolantTemp.toInt()} °C');
        HapticFeedback.heavyImpact();
      }
    }
  }

  Future<void> _setScreenAwake(bool awake) async {
    try {
      await _wakelockChannel.invokeMethod(awake ? 'enable' : 'disable');
    } catch (_) {}
  }

  Future<void> _enterPictureInPicture() async {
    try {
      await _pipChannel.invokeMethod('enterPip');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PiP mode is supported on Android 8.0+ devices.')),
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

  double get _tripFuelCost => _consumedFuelLiters * _fuelPricePerLiter;

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

      _checkSpeedCameraProximity(position);

      setState(() {
        _currentSpeed = speedInUnit;
        _heading = position.heading;
        _altitude = position.altitude;
        _accuracy = position.accuracy;

        // Keep rolling speed graph
        _recentSpeedPoints.add(speedInUnit);
        if (_recentSpeedPoints.length > 35) {
          _recentSpeedPoints.removeAt(0);
        }

        // Add GPS Breadcrumb point
        if (speedInUnit > 0.5) {
          _breadcrumbs.add(position);
          if (_breadcrumbs.length > 250) {
            _breadcrumbs.removeAt(0);
          }
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

    if (closest != null && (_nearbySpeedCamera == null || minDistance < 500)) {
      _voiceAssistant.speakPrompt(VoicePromptType.speedCamera, extraInfo: '${closest.speedLimit.toInt()} $_unit');
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
    _voiceAssistant.speakPrompt(VoicePromptType.dragReady);
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
      _voiceAssistant.speakPrompt(VoicePromptType.dragGo);

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
        _voiceAssistant.speakPrompt(VoicePromptType.dragSuccess, extraInfo: '${elapsed.toStringAsFixed(2)}s');
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
        _voiceAssistant.speakPrompt(VoicePromptType.overspeed);
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
      _voiceAssistant.speakPrompt(VoicePromptType.tripFinished, extraInfo: '${(_totalDistanceMeters / 1000).toStringAsFixed(1)} km');

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
            icon: Icon(_isSplitCockpit ? Icons.view_agenda : Icons.view_agenda_outlined, color: theme.primary),
            tooltip: 'Toggle Split Cockpit',
            onPressed: () => setState(() => _isSplitCockpit = !_isSplitCockpit),
          ),
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
            // Top Navigation Tabs (6 Views)
            Container(
              color: theme.cardBackground.withOpacity(0.6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTabItem(0, 'Gauge', Icons.speed, theme),
                    _buildTabItem(1, 'Digital', Icons.pin, theme),
                    _buildTabItem(2, 'HUD', Icons.flip, theme),
                    _buildTabItem(3, 'Drag', Icons.sports_score_rounded, theme),
                    _buildTabItem(4, 'Map & Trail', Icons.map_outlined, theme),
                    _buildTabItem(5, 'Dashcam', Icons.videocam_outlined, theme),
                    _buildTabItem(6, 'OBD Cockpit', Icons.directions_car_filled, theme),
                    _buildTabItem(7, 'DTC Scanner', Icons.health_and_safety, theme),
                  ],
                ),
              ),
            ),

            // Engine Overheat Warning Banner (OBD-II Safety Alert)
            if (_obdData.isOverheating)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF1744),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF1744).withOpacity(0.6),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '🔥 ENGINE OVERHEAT! COOLANT AT ${_obdData.coolantTemp.toStringAsFixed(0)} °C (> 105 °C)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                        letterSpacing: 1.1,
                      ),
                    ),
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

            // Speed Camera Radar Banner
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
              margin: const EdgeInsets.fromLTRB(16, 5, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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

            // Main Active View or Cockpit Split Screen
            Expanded(
              child: _isSplitCockpit
                  ? Column(
                      children: [
                        Expanded(
                          flex: 1,
                          child: InteractiveMapCanvas(
                            currentPosition: _lastPosition,
                            heading: _heading,
                            breadcrumbs: _breadcrumbs,
                            speedCameras: _speedCameras,
                            theme: theme,
                            isMiniMap: true,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Center(child: _buildDigitalView(isOverLimit, theme)),
                        ),
                      ],
                    )
                  : Center(
                      child: _buildActiveTabView(isOverLimit, theme),
                    ),
            ),

            // Real-Time Speed Sparkline Graph (Shown on tabs 0, 1)
            if (_recentSpeedPoints.isNotEmpty && (_activeTab == 0 || _activeTab == 1) && !_isSplitCockpit)
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

            // Metrics Cards Grid
            if (_activeTab != 3 && _activeTab != 4 && _activeTab != 5 && _activeTab != 6 && _activeTab != 7)
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

            // Bottom Trip Controls
            if (_activeTab != 3 && _activeTab != 7)
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

  Widget _buildActiveTabView(bool isOverLimit, AppThemeOption theme) {
    switch (_activeTab) {
      case 0:
        return _buildGaugeView(isOverLimit, theme);
      case 1:
        return _buildDigitalView(isOverLimit, theme);
      case 2:
        return _buildHudView(isOverLimit, theme);
      case 3:
        return _buildPerformanceDragView(theme);
      case 4:
        return InteractiveMapCanvas(
          currentPosition: _lastPosition,
          heading: _heading,
          breadcrumbs: _breadcrumbs,
          speedCameras: _speedCameras,
          theme: theme,
        );
      case 5:
        return DashcamOverlayWidget(
          speed: _currentSpeed,
          unit: _unit,
          heading: _heading,
          gForce: _currentGForce,
          speedLimit: _speedLimit,
          theme: theme,
        );
      case 6:
        return _buildObdCockpitView(theme);
      case 7:
        return _buildDtcScannerView(theme);
      default:
        return _buildGaugeView(isOverLimit, theme);
    }
  }

  Widget _buildTabItem(int index, String label, IconData icon, AppThemeOption theme) {
    bool isSelected = _activeTab == index;
    return InkWell(
      onTap: () {
        setState(() => _activeTab = index);
        _syncWakelockState();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? theme.primary : Colors.white54),
            const SizedBox(width: 5),
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
        const SizedBox(height: 10),
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
          DragTreeLights(stage: _treeLightStage),
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

  Widget _buildObdCockpitView(AppThemeOption theme) {
    final bool isConnected = _obdService.status == ObdConnectionStatus.connected;
    final bool isConnecting = _obdService.status == ObdConnectionStatus.connecting;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          // 1. Bluetooth Connection Status Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isConnected ? Colors.greenAccent.withOpacity(0.4) : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: isConnected ? Colors.greenAccent : (isConnecting ? Colors.orangeAccent : Colors.white54),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isConnected
                            ? (_obdService.connectedDeviceName ?? 'ELM327 OBD-II')
                            : (isConnecting ? 'CONNECTING...' : 'OBD-II DISCONNECTED'),
                        style: TextStyle(
                          color: isConnected ? Colors.greenAccent : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        isConnected
                            ? (_obdService.connectedDeviceAddress ?? 'SPP 00001101-0000-1000-8000-00805F9B34FB')
                            : 'Pair ELM327 in Android Settings then Connect',
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                if (isConnected)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF5252),
                      side: const BorderSide(color: Color(0xFFFF5252)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: () async {
                      await _obdService.disconnect();
                      setState(() {});
                    },
                    child: const Text('DISCONNECT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: isConnecting ? null : _showBluetoothScannerSheet,
                    icon: isConnecting
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.bluetooth_searching, size: 14),
                    label: Text(
                      isConnecting ? 'LINKING...' : 'SCAN & LINK',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 2. Shift Light Bar
          _buildShiftLightBar(_obdData.rpm),

          const SizedBox(height: 10),

          // 3. Tachometer Dial
          SizedBox(
            width: 250,
            height: 250,
            child: CustomPaint(
              painter: TachometerGaugePainter(
                rpm: _obdData.rpm,
                maxRpm: 9000.0,
                redlineRpm: 6500.0,
                primaryColor: theme.primary,
                secondaryColor: theme.secondary,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 4. ECU Telemetry Gauges Grid
          Row(
            children: [
              // Coolant Temp
              Expanded(
                child: _buildObdMetricCard(
                  title: 'COOLANT TEMP',
                  value: '${_obdData.coolantTemp.toStringAsFixed(0)} °C',
                  subtitle: _obdData.isOverheating
                      ? '⚠️ OVERHEAT (>105°C)'
                      : (_obdData.coolantTemp > 95 ? 'HIGH (>95°C)' : 'OPTIMAL (80-95°C)'),
                  icon: Icons.thermostat,
                  valueColor: _obdData.isOverheating
                      ? const Color(0xFFFF1744)
                      : (_obdData.coolantTemp > 95 ? Colors.orangeAccent : Colors.greenAccent),
                  progress: (_obdData.coolantTemp / 130.0).clamp(0.0, 1.0),
                  progressColor: _obdData.isOverheating ? const Color(0xFFFF1744) : theme.primary,
                  theme: theme,
                ),
              ),
              const SizedBox(width: 10),
              // Boost Pressure
              Expanded(
                child: _buildObdMetricCard(
                  title: 'BOOST / MAP',
                  value: '${_obdData.boostBar.toStringAsFixed(2)} Bar',
                  subtitle: _obdData.boostBar > 0 ? 'TURBO BOOST' : 'VACUUM',
                  icon: Icons.compress,
                  valueColor: theme.primary,
                  progress: ((_obdData.boostBar + 1.0) / 3.0).clamp(0.0, 1.0),
                  progressColor: theme.primary,
                  theme: theme,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              // Throttle (TPS)
              Expanded(
                child: _buildObdMetricCard(
                  title: 'THROTTLE (TPS)',
                  value: '${_obdData.throttlePercent.toStringAsFixed(0)} %',
                  subtitle: 'ACCELERATOR PEDAL',
                  icon: Icons.electric_bolt,
                  valueColor: Colors.white,
                  progress: (_obdData.throttlePercent / 100.0).clamp(0.0, 1.0),
                  progressColor: theme.primary,
                  theme: theme,
                ),
              ),
              const SizedBox(width: 10),
              // Fuel Level
              Expanded(
                child: _buildObdMetricCard(
                  title: 'FUEL LEVEL',
                  value: '${_obdData.fuelLevelPercent.toStringAsFixed(0)} %',
                  subtitle: 'TANK LEVEL',
                  icon: Icons.local_gas_station,
                  valueColor: _obdData.fuelLevelPercent < 15 ? Colors.redAccent : Colors.white,
                  progress: (_obdData.fuelLevelPercent / 100.0).clamp(0.0, 1.0),
                  progressColor: _obdData.fuelLevelPercent < 15 ? Colors.redAccent : Colors.greenAccent,
                  theme: theme,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Speed Cross-Calibration: GPS vs ECU
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.cardBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('GPS SPEED', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      '${_currentSpeed.toStringAsFixed(0)} $_unit',
                      style: TextStyle(color: theme.primary, fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                Container(height: 24, width: 1, color: Colors.white12),
                Column(
                  children: [
                    const Text('ECU SPEED (OBD)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      '${_obdData.ecuSpeedKmh.toStringAsFixed(0)} km/h',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftLightBar(double rpm) {
    final bool isRedline = rpm >= 6500;
    // 8 LEDs: 3 green (2000, 3000, 4000), 2 yellow (5000, 5800), 3 red (6500, 7200, 8000)
    final thresholds = [2000, 3000, 4000, 5000, 5800, 6500, 7200, 8000];
    final colors = [
      Colors.greenAccent,
      Colors.greenAccent,
      Colors.greenAccent,
      Colors.amberAccent,
      Colors.amberAccent,
      const Color(0xFFFF2A6D),
      const Color(0xFFFF2A6D),
      const Color(0xFFFF2A6D),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF070B14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRedline ? const Color(0xFFFF2A6D) : Colors.white10,
          width: isRedline ? 2 : 1,
        ),
        boxShadow: isRedline
            ? [
                BoxShadow(
                  color: const Color(0xFFFF2A6D).withOpacity(0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(8, (i) {
          final bool active = rpm >= thresholds[i];
          final Color col = colors[i];
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 12,
              decoration: BoxDecoration(
                color: active ? col : col.withOpacity(0.12),
                borderRadius: BorderRadius.circular(3),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: col.withOpacity(0.8),
                          blurRadius: 8,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildObdMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color valueColor,
    required double progress,
    required Color progressColor,
    required AppThemeOption theme,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
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
              Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
              Icon(icon, color: progressColor, size: 16),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 9.5, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showBluetoothScannerSheet() async {
    final theme = widget.currentTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FutureBuilder<List<BluetoothDeviceInfo>>(
              future: _obdService.getPairedDevices(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 250,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final devices = snapshot.data ?? [];

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.bluetooth_searching, color: theme.primary, size: 22),
                              const SizedBox(width: 8),
                              const Text(
                                'OBD-II Bluetooth Adapters',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white54),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Select your paired ELM327 / OBD-II device to establish RFCOMM telemetry link:',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      if (devices.isEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.cardBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.amberAccent, size: 20),
                                  SizedBox(width: 8),
                                  Text('No Paired OBD-II Devices', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                '1. Plug your ELM327 adapter into your car OBD-II port.\n2. Open Android Settings -> Bluetooth.\n3. Pair with "OBDII" (PIN: 1234 or 0000).\n4. Return here and tap Refresh.',
                                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: theme.primary),
                            onPressed: () => setSheetState(() {}),
                            icon: const Icon(Icons.refresh),
                            label: const Text('REFRESH PAIRED DEVICES'),
                          ),
                        ),
                      ] else ...[
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: devices.length,
                            separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                            itemBuilder: (context, index) {
                              final dev = devices[index];
                              final bool isThisConnected = _obdService.connectedDeviceAddress == dev.address &&
                                  _obdService.status == ObdConnectionStatus.connected;

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isThisConnected ? Colors.greenAccent.withOpacity(0.2) : theme.cardBackground,
                                  child: Icon(
                                    Icons.directions_car,
                                    color: isThisConnected ? Colors.greenAccent : theme.primary,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  dev.name,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                subtitle: Text(
                                  dev.address,
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                                trailing: isThisConnected
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.greenAccent.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.greenAccent),
                                        ),
                                        child: const Text('LINKED', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                                      )
                                    : ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: theme.primary,
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        ),
                                        onPressed: () async {
                                          Navigator.pop(ctx);
                                          setState(() {});
                                          final ok = await _obdService.connect(dev.address, dev.name);
                                          if (mounted) {
                                            setState(() {});
                                            ScaffoldMessenger.of(this.context).showSnackBar(
                                              SnackBar(
                                                backgroundColor: ok ? Colors.green[800] : Colors.red[800],
                                                content: Text(ok ? 'Connected to ${dev.name}' : 'Failed to connect: ${_obdService.errorMessage ?? "Check device"}'),
                                              ),
                                            );
                                          }
                                        },
                                        child: const Text('CONNECT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDtcScannerView(AppThemeOption theme) {
    final bool isConnected = _obdService.status == ObdConnectionStatus.connected;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Connection Warning Banner if disconnected
          if (!isConnected)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bluetooth_disabled, color: Colors.amberAccent, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'OBD-II Bluetooth Disconnected. Connect your ELM327 adapter to scan ECU trouble codes.',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: _showBluetoothScannerSheet,
                    child: const Text('LINK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          // 2. Check Engine Light (MIL) Status Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _milActive ? const Color(0xFF451A03) : theme.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _milActive ? const Color(0xFFF59E0B) : Colors.white12,
                width: _milActive ? 2 : 1,
              ),
              boxShadow: _milActive
                  ? [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withOpacity(0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _milActive ? const Color(0xFFF59E0B) : Colors.white10,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _milActive ? Icons.warning_rounded : Icons.check_circle_outline,
                    color: _milActive ? Colors.black : Colors.greenAccent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _milActive ? 'MALFUNCTION INDICATOR LAMP (MIL) ON' : 'CHECK ENGINE LIGHT OFF',
                        style: TextStyle(
                          color: _milActive ? const Color(0xFFF59E0B) : Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _milActive
                            ? 'ECU has detected active faults requiring attention.'
                            : 'Normal operating status. No confirmed engine MIL flagged.',
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 3. Scan & Clear Control Buttons Bar
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isScanningDtc || _isClearingDtc ? null : _scanDtcCodes,
                  icon: _isScanningDtc
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.search, size: 18),
                  label: Text(
                    _isScanningDtc ? 'INTERROGATING ECU...' : 'SCAN ENGINE CODES',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF5252),
                    side: BorderSide(
                      color: _detectedDtcCodes.isNotEmpty ? const Color(0xFFFF5252) : Colors.white24,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: (_detectedDtcCodes.isEmpty || _isScanningDtc || _isClearingDtc)
                      ? null
                      : () => _confirmAndClearDtcCodes(theme),
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text(
                    'CLEAR DTC',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                ),
              ),
            ],
          ),

          if (_dtcStatusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _dtcStatusMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],

          const SizedBox(height: 14),

          // 4. Detected DTC Code Cards List
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DETECTED TROUBLE CODES (${_detectedDtcCodes.length})',
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
              ),
              if (_savedDiagnosticReports.isNotEmpty)
                GestureDetector(
                  onTap: _showDiagnosticHistoryModal,
                  child: Row(
                    children: [
                      Icon(Icons.history, color: theme.primary, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Saved Reports (${_savedDiagnosticReports.length})',
                        style: TextStyle(color: theme.primary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          if (_detectedDtcCodes.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              decoration: BoxDecoration(
                color: theme.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Icon(Icons.verified, color: theme.primary.withOpacity(0.5), size: 48),
                  const SizedBox(height: 10),
                  const Text(
                    'No Trouble Codes Stored',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap "SCAN ENGINE CODES" to request Mode 03 & Mode 07 diagnostics from your vehicle ECU.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 11.5),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _detectedDtcCodes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final dtc = _detectedDtcCodes[index];
                return _buildDtcCodeCard(dtc, theme);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDtcCodeCard(DtcCode dtc, AppThemeOption theme) {
    Color systemColor = const Color(0xFFF97316);
    if (dtc.code.startsWith('C')) systemColor = const Color(0xFF3B82F6);
    if (dtc.code.startsWith('B')) systemColor = const Color(0xFFA855F7);
    if (dtc.code.startsWith('U')) systemColor = const Color(0xFF10B981);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: systemColor.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: systemColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: systemColor),
                    ),
                    child: Text(
                      dtc.code,
                      style: TextStyle(
                        color: systemColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        fontFamily: 'monospace',
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: dtc.isPending ? Colors.amber.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      dtc.isPending ? 'PENDING' : 'CONFIRMED',
                      style: TextStyle(
                        color: dtc.isPending ? Colors.amberAccent : const Color(0xFFFF5252),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16, color: Colors.white54),
                tooltip: 'Copy Code & Description',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '${dtc.code}: ${dtc.description}'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied ${dtc.code} to clipboard')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dtc.system,
            style: TextStyle(color: systemColor.withOpacity(0.9), fontSize: 10, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            dtc.description,
            style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primary,
              side: BorderSide(color: theme.primary.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () {
              _showDtcWebSearchDialog(dtc, theme);
            },
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('SEARCH ONLINE REPAIR GUIDES', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDtcWebSearchDialog(DtcCode dtc, AppThemeOption theme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardBackground,
        title: Row(
          children: [
            Icon(Icons.search, color: theme.primary, size: 20),
            const SizedBox(width: 8),
            Text('Online Lookup: ${dtc.code}', style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dtc.description, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 14),
            const Text('Google Search Query URL:', style: TextStyle(color: Colors.white38, fontSize: 10)),
            const SizedBox(height: 4),
            SelectableText(
              dtc.googleSearchUrl,
              style: TextStyle(color: theme.primary, fontSize: 11, decoration: TextDecoration.underline),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('COPY SEARCH URL'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: dtc.googleSearchUrl));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search URL copied to clipboard')),
              );
            },
          ),
          TextButton(
            child: const Text('CLOSE'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  Future<void> _scanDtcCodes() async {
    if (_obdService.status != ObdConnectionStatus.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect OBD-II Bluetooth device first.'),
        ),
      );
      return;
    }

    setState(() {
      _isScanningDtc = true;
      _dtcStatusMessage = 'Interrogating ECU Mode 01, 03, 07...';
    });
    HapticFeedback.mediumImpact();

    try {
      final codes = await _obdService.readDiagnosticTroubleCodes();
      if (!mounted) return;
      setState(() {
        _detectedDtcCodes = codes;
        _milActive = _obdService.isMilOn;
        _isScanningDtc = false;
        _dtcStatusMessage = codes.isEmpty
            ? 'Scan complete: No Diagnostic Trouble Codes found.'
            : 'Scan complete: Found ${codes.length} trouble code(s).';
      });
      HapticFeedback.lightImpact();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanningDtc = false;
        _dtcStatusMessage = 'Scan failed: $e';
      });
    }
  }

  Future<void> _confirmAndClearDtcCodes(AppThemeOption theme) async {
    if (_obdService.status != ObdConnectionStatus.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect OBD-II device first.')),
      );
      return;
    }

    // 1. Auto-Archive Diagnostic Health Report before Clear (User-Requested Requirement)
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final report = DtcDiagnosticReport(
      id: now.millisecondsSinceEpoch.toString(),
      timestampFormatted: dateStr,
      milActive: _milActive,
      codes: List.from(_detectedDtcCodes),
    );
    setState(() {
      _savedDiagnosticReports.insert(0, report);
    });

    // 2. Show safety confirmation dialog with checklist
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardBackground,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFF5252), size: 22),
            SizedBox(width: 8),
            Text('Clear Engine Codes', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.archive, color: Colors.greenAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Report Auto-Archived: ${_detectedDtcCodes.length} codes saved to History before clearing.',
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ Critical Safety Checklist:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              '• Ignition Switch ON (Key ON / ACC)\n• Engine OFF (เครื่องยนต์ต้องดับอยู่)\n• Do NOT unplug OBD-II adapter during command',
              style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
            ),
            const SizedBox(height: 10),
            const Text(
              'Mode 04 will turn off Check Engine Light (MIL) and reset ECU readiness monitors.',
              style: TextStyle(color: Colors.white38, fontSize: 10.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _isClearingDtc = true;
                _dtcStatusMessage = 'Sending Mode 04 Clear DTC to ECU...';
              });
              final success = await _obdService.clearDiagnosticTroubleCodes();
              if (!mounted) return;
              setState(() {
                _isClearingDtc = false;
                if (success) {
                  _detectedDtcCodes.clear();
                  _milActive = false;
                  _dtcStatusMessage = '✅ Mode 04 Succeeded: DTCs cleared & MIL reset.';
                } else {
                  _dtcStatusMessage = '❌ Clear command failed: Check engine switch state.';
                }
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: success ? Colors.green[800] : Colors.red[800],
                  content: Text(success ? 'Check Engine DTCs cleared successfully!' : 'Failed to clear DTCs from ECU.'),
                ),
              );
            },
            child: const Text('CONFIRM CLEAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDiagnosticHistoryModal() {
    final theme = widget.currentTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.history, color: theme.primary, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Archived Diagnostic Reports',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_savedDiagnosticReports.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Text('No archived diagnostic reports yet.', style: TextStyle(color: Colors.white38)),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _savedDiagnosticReports.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                    itemBuilder: (context, idx) {
                      final r = _savedDiagnosticReports[idx];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.cardBackground,
                          child: Icon(Icons.description, color: theme.primary, size: 20),
                        ),
                        title: Text(
                          'Scan: ${r.timestampFormatted}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: Text(
                          '${r.codes.length} DTCs found • MIL: ${r.milActive ? "ON" : "OFF"}\nCodes: ${r.codes.map((c) => c.code).join(", ")}',
                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 16, color: Colors.white54),
                          tooltip: 'Copy Report',
                          onPressed: () {
                            final text = 'Diagnostic Report (${r.timestampFormatted})\nCodes: ${r.codes.map((c) => "${c.code} - ${c.description}").join("\n")}';
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Report copied to clipboard')),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
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
                        _currentToneBytes = SoundGenerator.generateTone(val);
                      });
                      _audioPlayer.play(BytesSource(_currentToneBytes), mode: PlayerMode.lowLatency);
                    }
                  },
                ),
                const SizedBox(height: 10),
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
                  title: const Text('Voice Assistant (ไทย / EN)', style: TextStyle(fontSize: 13, color: Colors.white)),
                  value: _voiceAssistant.isEnabled,
                  onChanged: (val) {
                    setModalState(() => _voiceAssistant.isEnabled = val);
                    setState(() => _voiceAssistant.isEnabled = val);
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
