import 'package:flutter_test/flutter_test.dart';
import 'package:gps_speedometer/main.dart';
import 'package:gps_speedometer/core/sound_generator.dart';
import 'package:gps_speedometer/models/trip_record.dart';
import 'package:gps_speedometer/models/speed_camera.dart';
import 'package:gps_speedometer/models/obd_data.dart';
import 'package:gps_speedometer/models/dtc_record.dart';
import 'package:gps_speedometer/services/obd_service.dart';
import 'package:gps_speedometer/services/voice_assistant.dart';

void main() {
  testWidgets('SpeedometerApp smoke and initial render test', (WidgetTester tester) async {
    await tester.pumpWidget(const SpeedometerApp());
    expect(find.text('SPEEDOMETER'), findsOneWidget);
    expect(find.text('START TRIP'), findsOneWidget);
    expect(find.text('Gauge'), findsOneWidget);
    expect(find.text('Digital'), findsOneWidget);
    expect(find.text('HUD'), findsOneWidget);
    expect(find.text('Drag'), findsOneWidget);
    expect(find.text('Map & Trail'), findsOneWidget);
    expect(find.text('Dashcam'), findsOneWidget);
    expect(find.text('OBD Cockpit'), findsOneWidget);
    expect(find.text('DTC Scanner'), findsOneWidget);
  });

  test('ObdTelemetryData calculations and overheating flags', () {
    const normalData = ObdTelemetryData(
      rpm: 3200.0,
      coolantTemp: 90.0,
      boostBar: 0.8,
    );
    expect(normalData.isOverheating, isFalse);
    expect(normalData.isRedline, isFalse);

    final hotData = normalData.copyWith(coolantTemp: 108.5);
    expect(hotData.isOverheating, isTrue);

    final redlineData = normalData.copyWith(rpm: 7200.0);
    expect(redlineData.isRedline, isTrue);
  });

  test('TripRecord JSON Serialization & Deserialization test', () {
    final record = TripRecord(
      id: '123456',
      dateTimeFormatted: '10/11/2026 15:30',
      distanceMeters: 14200.5,
      durationSeconds: 1250,
      maxSpeed: 115.0,
      avgSpeed: 52.4,
      unit: 'km/h',
      bestZeroHundredSec: 7.82,
      peakG: 0.64,
      fuelLiters: 1.25,
      tripCost: 48.0,
    );

    final json = record.toJson();
    expect(json['id'], '123456');
    expect(json['bestZeroHundredSec'], 7.82);
    expect(json['fuelLiters'], 1.25);

    final fromJson = TripRecord.fromJson(json);
    expect(fromJson.id, record.id);
    expect(fromJson.distanceMeters, record.distanceMeters);
    expect(fromJson.tripCost, 48.0);
    expect(fromJson.peakG, 0.64);
  });

  test('SpeedCameraZone model serialization test', () {
    final cam = SpeedCameraZone(
      id: 'cam_99',
      name: 'Highway 7 Camera',
      latitude: 13.72,
      longitude: 100.58,
      speedLimit: 120.0,
    );
    final json = cam.toJson();
    expect(json['name'], 'Highway 7 Camera');
    final restored = SpeedCameraZone.fromJson(json);
    expect(restored.speedLimit, 120.0);
  });

  test('SoundGenerator generates valid 44-byte WAV header', () {
    final tone = SoundGenerator.generateTone(SoundToneStyle.cyberpunk);
    expect(tone.length, greaterThan(1000));
    // RIFF header
    expect(String.fromCharCodes(tone.sublist(0, 4)), 'RIFF');
    // WAVE header
    expect(String.fromCharCodes(tone.sublist(8, 12)), 'WAVE');
  });

  test('VoiceAssistantService Thai and English prompt formatting including Engine Overheat', () {
    final assistant = VoiceAssistantService();
    assistant.language = VoiceLanguage.th;
    final thText = assistant.getPromptText(VoicePromptType.overspeed, extra: '80 km/h');
    expect(thText.contains('ระวัง'), isTrue);

    final thOverheat = assistant.getPromptText(VoicePromptType.engineOverheat, extra: '108°C');
    expect(thOverheat.contains('ร้อนจัด'), isTrue);

    assistant.language = VoiceLanguage.en;
    final enText = assistant.getPromptText(VoicePromptType.overspeed, extra: '80 km/h');
    expect(enText.contains('Warning'), isTrue);

    final enOverheat = assistant.getPromptText(VoicePromptType.engineOverheat, extra: '108°C');
    expect(enOverheat.contains('Danger'), isTrue);
    assistant.dispose();
  });

  test('SAE J1979 DTC hex decoder decodes standard codes properly', () {
    expect(ObdService.decodeDtcBytePair('0102'), 'P0102');
    expect(ObdService.decodeDtcBytePair('0300'), 'P0300');
    expect(ObdService.decodeDtcBytePair('0420'), 'P0420');
    expect(ObdService.decodeDtcBytePair('4120'), 'C0120');
    expect(ObdService.decodeDtcBytePair('8100'), 'B0100');
    expect(ObdService.decodeDtcBytePair('C120'), 'U0120');
    expect(ObdService.decodeDtcBytePair('0000'), isNull);
  });

  test('ObdService.parseDtcResponse extracts Mode 03 & 07 DTC codes', () {
    // Mode 03 response with P0102 and P0300
    const rawMode03 = '43 01 02 03 00 00 00';
    final codes = ObdService.parseDtcResponse(rawMode03, isPending: false);
    expect(codes.length, 2);
    expect(codes[0].code, 'P0102');
    expect(codes[0].isPending, isFalse);
    expect(codes[1].code, 'P0300');

    // Mode 07 pending response with U0120
    const rawMode07 = '47 C1 20 00 00';
    final pendingCodes = ObdService.parseDtcResponse(rawMode07, isPending: true);
    expect(pendingCodes.length, 1);
    expect(pendingCodes[0].code, 'U0120');
    expect(pendingCodes[0].isPending, isTrue);

    // Empty or no data
    expect(ObdService.parseDtcResponse('NO DATA'), isEmpty);
    expect(ObdService.parseDtcResponse('43 00 00'), isEmpty);
  });

  test('DtcDiagnosticReport serialization and auto-archive test', () {
    const report = DtcDiagnosticReport(
      id: 'rep_12345',
      timestampFormatted: '10/11/2026 16:00',
      milActive: true,
      codes: [
        DtcCode(code: 'P0300', isPending: false),
        DtcCode(code: 'P0171', isPending: true),
      ],
    );

    final json = report.toJson();
    expect(json['id'], 'rep_12345');
    expect(json['milActive'], isTrue);
    expect((json['codes'] as List).length, 2);

    final restored = DtcDiagnosticReport.fromJson(json);
    expect(restored.id, 'rep_12345');
    expect(restored.codes[0].code, 'P0300');
    expect(restored.codes[1].isPending, isTrue);
    expect(restored.codes[0].googleSearchUrl.contains('P0300'), isTrue);
  });
}
