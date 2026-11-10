import 'dart:math';
import 'dart:typed_data';

enum SoundToneStyle {
  cyberpunk,
  supercar,
  scifi,
  sportBell,
}

enum VoicePromptType {
  overspeed,
  speedCamera,
  dragReady,
  dragGo,
  dragSuccess,
  tripFinished,
}

const Map<SoundToneStyle, String> kSoundToneLabels = {
  SoundToneStyle.cyberpunk: 'Cyberpunk Beep (950Hz)',
  SoundToneStyle.supercar: 'Supercar Chime (Dual Tone)',
  SoundToneStyle.scifi: 'Sci-Fi Arcade (Arpeggio)',
  SoundToneStyle.sportBell: 'Sport Bell (A5 Harmonic)',
};

class SoundGenerator {
  static Uint8List generateTone(SoundToneStyle style) {
    const int sampleRate = 44100;
    final double duration = style == SoundToneStyle.supercar ? 0.20 : 0.14;
    final int numSamples = (sampleRate * duration).toInt();
    final int dataSize = numSamples * 2;
    final int fileSize = 36 + dataSize;
    final buffer = ByteData(44 + dataSize);

    // RIFF Header
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

  static Uint8List generateVoicePromptTone(VoicePromptType type) {
    const int sampleRate = 44100;
    double duration = 0.25;
    if (type == VoicePromptType.dragSuccess) duration = 0.35;
    if (type == VoicePromptType.speedCamera) duration = 0.30;

    final int numSamples = (sampleRate * duration).toInt();
    final int dataSize = numSamples * 2;
    final int fileSize = 36 + dataSize;
    final buffer = ByteData(44 + dataSize);

    buffer.setUint8(0, 0x52);
    buffer.setUint8(1, 0x49);
    buffer.setUint8(2, 0x46);
    buffer.setUint8(3, 0x46);
    buffer.setUint32(4, fileSize, Endian.little);
    buffer.setUint8(8, 0x57);
    buffer.setUint8(9, 0x41);
    buffer.setUint8(10, 0x56);
    buffer.setUint8(11, 0x45);

    buffer.setUint8(12, 0x66);
    buffer.setUint8(13, 0x6D);
    buffer.setUint8(14, 0x74);
    buffer.setUint8(15, 0x20);
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, 1, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);

    buffer.setUint8(36, 0x64);
    buffer.setUint8(37, 0x61);
    buffer.setUint8(38, 0x74);
    buffer.setUint8(39, 0x61);
    buffer.setUint32(40, dataSize, Endian.little);

    int offset = 44;
    for (int i = 0; i < numSamples; i++) {
      double t = i / sampleRate;
      double progress = i / numSamples;
      double envelope = sin(pi * progress);

      double sampleVal = 0.0;
      switch (type) {
        case VoicePromptType.overspeed:
          sampleVal = sin(2 * pi * 880 * t) + 0.5 * sin(2 * pi * 1760 * t);
          break;
        case VoicePromptType.speedCamera:
          sampleVal = sin(2 * pi * 1050 * t) * (progress < 0.5 ? 1.0 : 0.7);
          break;
        case VoicePromptType.dragReady:
          sampleVal = sin(2 * pi * 600 * t);
          break;
        case VoicePromptType.dragGo:
          sampleVal = sin(2 * pi * 1200 * t);
          break;
        case VoicePromptType.dragSuccess:
          double f = progress < 0.5 ? 987.77 : 1318.51; // B5 -> E6 triumph chord
          sampleVal = sin(2 * pi * f * t);
          break;
        case VoicePromptType.tripFinished:
          double f = progress < 0.5 ? 784.0 : 1046.5; // G5 -> C6
          sampleVal = sin(2 * pi * f * t);
          break;
      }

      int pcm = (sampleVal * 26000 * envelope).clamp(-32768, 32767).toInt();
      buffer.setInt16(offset, pcm, Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }
}
