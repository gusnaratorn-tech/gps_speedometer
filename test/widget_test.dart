import 'package:flutter_test/flutter_test.dart';
import 'package:gps_speedometer/main.dart';
import 'package:gps_speedometer/core/sound_generator.dart';
import 'package:gps_speedometer/models/trip_record.dart';
import 'package:gps_speedometer/models/speed_camera.dart';
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

  test('VoiceAssistantService Thai and English prompt formatting', () {
    final assistant = VoiceAssistantService();
    assistant.language = VoiceLanguage.th;
    final thText = assistant.getPromptText(VoicePromptType.overspeed, extra: '80 km/h');
    expect(thText.contains('ระวัง'), isTrue);

    assistant.language = VoiceLanguage.en;
    final enText = assistant.getPromptText(VoicePromptType.overspeed, extra: '80 km/h');
    expect(enText.contains('Warning'), isTrue);
    assistant.dispose();
  });
}
