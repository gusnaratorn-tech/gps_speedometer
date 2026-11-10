import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import '../core/sound_generator.dart';

enum VoiceLanguage { th, en }

class VoiceAssistantService {
  final AudioPlayer _player = AudioPlayer();
  bool isEnabled = true;
  VoiceLanguage language = VoiceLanguage.th;

  final Map<VoicePromptType, Uint8List> _audioCache = {};

  VoiceAssistantService() {
    _initAudioCache();
  }

  void _initAudioCache() {
    for (var type in VoicePromptType.values) {
      _audioCache[type] = SoundGenerator.generateVoicePromptTone(type);
    }
  }

  Future<void> speakPrompt(VoicePromptType type, {String? extraInfo}) async {
    if (!isEnabled) return;

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Play synthesized voice alert chime
    final bytes = _audioCache[type];
    if (bytes != null) {
      try {
        await _player.play(BytesSource(bytes), mode: PlayerMode.lowLatency);
      } catch (_) {}
    }
  }

  String getPromptText(VoicePromptType type, {String? extra}) {
    if (language == VoiceLanguage.th) {
      switch (type) {
        case VoicePromptType.overspeed:
          return '⚠️ ระวัง! ขับเร็วเกินความเร็วจำกัด $extra';
        case VoicePromptType.speedCamera:
          return '📷 ระวัง! กล้องตรวจจับความเร็วข้างหน้า $extra';
        case VoicePromptType.dragReady:
          return '🚦 เข้าจุดออกตัวแล้ว เหยียบคันเร่งเพื่อเริ่มจับเวลา';
        case VoicePromptType.dragGo:
          return '🟢 ออกตัวเต็มกำลัง!';
        case VoicePromptType.dragSuccess:
          return '🏁 จับเวลาสำเร็จ! เวลาที่ทำได้ $extra';
        case VoicePromptType.tripFinished:
          return '✅ บันทึกสถิติการเดินทางเรียบร้อยแล้ว $extra';
      }
    } else {
      switch (type) {
        case VoicePromptType.overspeed:
          return '⚠️ Warning: Speed limit exceeded! $extra';
        case VoicePromptType.speedCamera:
          return '📷 Caution: Speed camera ahead! $extra';
        case VoicePromptType.dragReady:
          return '🚦 Staged: Launch vehicle to start timer';
        case VoicePromptType.dragGo:
          return '🟢 GO! Accelerate now!';
        case VoicePromptType.dragSuccess:
          return '🏁 Run completed! 0-100 time: $extra';
        case VoicePromptType.tripFinished:
          return '✅ Trip recorded successfully: $extra';
      }
    }
  }

  void dispose() {
    _player.dispose();
  }
}
