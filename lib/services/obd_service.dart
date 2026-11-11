import 'dart:async';
import 'package:flutter/services.dart';
import '../models/obd_data.dart';
import '../models/dtc_record.dart';

enum ObdConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class BluetoothDeviceInfo {
  final String name;
  final String address;

  BluetoothDeviceInfo({required this.name, required this.address});

  factory BluetoothDeviceInfo.fromMap(Map<dynamic, dynamic> map) {
    return BluetoothDeviceInfo(
      name: map['name']?.toString() ?? 'OBD-II Device',
      address: map['address']?.toString() ?? '',
    );
  }
}

class ObdService {
  static const MethodChannel _channel = MethodChannel('com.example.gps_speedometer/obd');

  ObdConnectionStatus status = ObdConnectionStatus.disconnected;
  String? connectedDeviceName;
  String? connectedDeviceAddress;
  String? errorMessage;

  bool isMilOn = false;
  int confirmedDtcCount = 0;
  List<DtcCode> lastScannedCodes = [];

  ObdTelemetryData _currentData = const ObdTelemetryData();
  ObdTelemetryData get currentData => _currentData;

  Timer? _pollingTimer;
  final StreamController<ObdTelemetryData> _dataController = StreamController<ObdTelemetryData>.broadcast();
  Stream<ObdTelemetryData> get telemetryStream => _dataController.stream;

  Future<List<BluetoothDeviceInfo>> getPairedDevices() async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getPairedDevices');
      if (result == null) return [];
      return result.map((e) => BluetoothDeviceInfo.fromMap(e as Map<dynamic, dynamic>)).toList();
    } catch (e) {
      errorMessage = e.toString();
      return [];
    }
  }

  Future<bool> connect(String address, String name) async {
    try {
      status = ObdConnectionStatus.connecting;
      connectedDeviceName = name;
      connectedDeviceAddress = address;

      final bool? success = await _channel.invokeMethod('connect', {'address': address});
      if (success == true) {
        status = ObdConnectionStatus.connected;
        errorMessage = null;
        _startPolling();
        return true;
      } else {
        status = ObdConnectionStatus.error;
        errorMessage = 'Failed to connect to $name';
        return false;
      }
    } catch (e) {
      status = ObdConnectionStatus.error;
      errorMessage = e.toString();
      return false;
    }
  }

  Future<void> disconnect() async {
    _pollingTimer?.cancel();
    try {
      await _channel.invokeMethod('disconnect');
    } catch (_) {}
    status = ObdConnectionStatus.disconnected;
    connectedDeviceName = null;
    connectedDeviceAddress = null;
    _currentData = const ObdTelemetryData();
    _dataController.add(_currentData);
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    // Fast polling cycle for real-time engine metrics
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (status != ObdConnectionStatus.connected) {
        timer.cancel();
        return;
      }
      await _pollNextPids();
    });
  }

  int _cycle = 0;
  Future<void> _pollNextPids() async {
    _cycle++;
    try {
      // 1. High frequency: RPM (every 200ms)
      final rpmStr = await _channel.invokeMethod<String>('queryPid', {'pid': '010C'});
      double? parsedRpm = _parseRpm(rpmStr);
      if (parsedRpm != null) {
        _currentData = _currentData.copyWith(rpm: parsedRpm);
      }

      // 2. Medium frequency: Boost / MAP & Throttle (every 400ms)
      if (_cycle % 2 == 0) {
        final boostStr = await _channel.invokeMethod<String>('queryPid', {'pid': '010B'});
        double? parsedBoost = _parseBoost(boostStr);
        if (parsedBoost != null) {
          _currentData = _currentData.copyWith(boostBar: parsedBoost);
        }

        final tpsStr = await _channel.invokeMethod<String>('queryPid', {'pid': '0111'});
        double? parsedTps = _parseThrottle(tpsStr);
        if (parsedTps != null) {
          _currentData = _currentData.copyWith(throttlePercent: parsedTps);
        }
      }

      // 3. Lower frequency: Coolant Temp (every 1000ms)
      if (_cycle % 5 == 0) {
        final tempStr = await _channel.invokeMethod<String>('queryPid', {'pid': '0105'});
        double? parsedTemp = _parseCoolantTemp(tempStr);
        if (parsedTemp != null) {
          _currentData = _currentData.copyWith(coolantTemp: parsedTemp);
        }

        final fuelStr = await _channel.invokeMethod<String>('queryPid', {'pid': '012F'});
        double? parsedFuel = _parseFuel(fuelStr);
        if (parsedFuel != null) {
          _currentData = _currentData.copyWith(fuelLevelPercent: parsedFuel);
        }
      }

      _dataController.add(_currentData);
    } catch (_) {}
  }

  // ELM327 Hex Parsers
  static double? _parseRpm(String? raw) {
    if (raw == null) return null;
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('410C');
    if (idx != -1 && clean.length >= idx + 8) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      final b = int.tryParse(clean.substring(idx + 6, idx + 8), radix: 16);
      if (a != null && b != null) {
        return ((a * 256) + b) / 4.0;
      }
    }
    return null;
  }

  static double? _parseCoolantTemp(String? raw) {
    if (raw == null) return null;
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('4105');
    if (idx != -1 && clean.length >= idx + 6) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      if (a != null) {
        return (a - 40).toDouble();
      }
    }
    return null;
  }

  static double? _parseBoost(String? raw) {
    if (raw == null) return null;
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('410B');
    if (idx != -1 && clean.length >= idx + 6) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      if (a != null) {
        // MAP in kPa -> relative boost in Bar (1 atm ~ 101.3 kPa)
        return (a - 101.3) / 100.0;
      }
    }
    return null;
  }

  static double? _parseThrottle(String? raw) {
    if (raw == null) return null;
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('4111');
    if (idx != -1 && clean.length >= idx + 6) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      if (a != null) {
        return (a * 100.0) / 255.0;
      }
    }
    return null;
  }

  static double? _parseFuel(String? raw) {
    if (raw == null) return null;
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('412F');
    if (idx != -1 && clean.length >= idx + 6) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      if (a != null) {
        return (a * 100.0) / 255.0;
      }
    }
    return null;
  }

  // --- Diagnostic Trouble Codes (DTC) Operations ---

  Future<bool> checkMilStatus() async {
    try {
      final res = await _channel.invokeMethod<String>('queryPid', {'pid': '0101'});
      if (res != null) {
        final clean = res.replaceAll(' ', '').toUpperCase();
        final idx = clean.indexOf('4101');
        if (idx != -1 && clean.length >= idx + 6) {
          final byteA = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
          if (byteA != null) {
            isMilOn = (byteA & 0x80) != 0;
            confirmedDtcCount = byteA & 0x7F;
            return isMilOn;
          }
        }
      }
    } catch (_) {}
    return isMilOn;
  }

  Future<List<DtcCode>> readDiagnosticTroubleCodes() async {
    final bool wasPolling = _pollingTimer != null && _pollingTimer!.isActive;
    _pollingTimer?.cancel();

    final List<DtcCode> result = [];
    final Set<String> codeSet = {};

    try {
      await checkMilStatus();

      // Query Mode 03: Stored Confirmed DTCs
      final storedRaw = await _channel.invokeMethod<String>('queryPid', {'pid': '03'});
      final storedCodes = parseDtcResponse(storedRaw, isPending: false);
      for (var c in storedCodes) {
        if (!codeSet.contains(c.code)) {
          codeSet.add(c.code);
          result.add(c);
        }
      }

      await Future.delayed(const Duration(milliseconds: 150));

      // Query Mode 07: Pending DTCs
      final pendingRaw = await _channel.invokeMethod<String>('queryPid', {'pid': '07'});
      final pendingCodes = parseDtcResponse(pendingRaw, isPending: true);
      for (var c in pendingCodes) {
        if (!codeSet.contains(c.code)) {
          codeSet.add(c.code);
          result.add(c);
        }
      }

      lastScannedCodes = List.from(result);
    } catch (_) {
    } finally {
      if (wasPolling && status == ObdConnectionStatus.connected) {
        _startPolling();
      }
    }

    return result;
  }

  Future<bool> clearDiagnosticTroubleCodes() async {
    final bool wasPolling = _pollingTimer != null && _pollingTimer!.isActive;
    _pollingTimer?.cancel();

    try {
      // Send Mode 04 to ECU
      final res = await _channel.invokeMethod<String>('queryPid', {'pid': '04'});
      final clean = res?.replaceAll(' ', '').toUpperCase() ?? '';
      final bool success = clean.contains('44') || clean.contains('OK') || clean.isEmpty;

      if (success) {
        lastScannedCodes.clear();
        isMilOn = false;
        confirmedDtcCount = 0;
      }
      return success;
    } catch (_) {
      return false;
    } finally {
      if (wasPolling && status == ObdConnectionStatus.connected) {
        _startPolling();
      }
    }
  }

  static List<DtcCode> parseDtcResponse(String? raw, {bool isPending = false}) {
    if (raw == null || raw.isEmpty) return [];
    final upper = raw.toUpperCase().replaceAll(' ', '').replaceAll('\r', '').replaceAll('\n', '');
    if (upper.contains('NODATA') || upper.contains('ERROR')) {
      return [];
    }

    final List<DtcCode> codes = [];
    final Set<String> seen = {};

    final targetPrefix = isPending ? '47' : '43';
    int searchIdx = 0;
    while (searchIdx < upper.length) {
      final idx = upper.indexOf(targetPrefix, searchIdx);
      if (idx == -1) break;

      int startOffset = idx + 2;
      for (int i = startOffset; i + 4 <= upper.length; i += 4) {
        final pair = upper.substring(i, i + 4);
        if (pair == '0000') continue;
        if (!RegExp(r'^[0-9A-F]{4}$').hasMatch(pair)) break;

        final decoded = decodeDtcBytePair(pair);
        if (decoded != null && !seen.contains(decoded)) {
          seen.add(decoded);
          codes.add(DtcCode(code: decoded, isPending: isPending));
        }
      }
      searchIdx = idx + 2;
    }
    return codes;
  }

  static String? decodeDtcBytePair(String twoByteHex) {
    if (twoByteHex.length != 4) return null;
    final byteA = int.tryParse(twoByteHex.substring(0, 2), radix: 16);
    if (byteA == null) return null;

    final typeBits = (byteA >> 6) & 0x03;
    final charPrefix = const ['P', 'C', 'B', 'U'][typeBits];
    final secondDigit = (byteA >> 4) & 0x03;
    final thirdDigit = (byteA & 0x0F).toRadixString(16).toUpperCase();
    final fourthFifthDigits = twoByteHex.substring(2, 4).toUpperCase();

    final code = '$charPrefix$secondDigit$thirdDigit$fourthFifthDigits';
    if (code == 'P0000' || code == 'C0000' || code == 'B0000' || code == 'U0000') {
      return null;
    }
    return code;
  }

  void dispose() {
    _pollingTimer?.cancel();
    _dataController.close();
  }
}
