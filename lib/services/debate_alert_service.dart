import 'package:vibration/vibration.dart';

class DebateAlertService {
  static bool vibrationEnabled = true;
  static bool dangerFlashEnabled = true;

  static Future<void> vibrateShort() async {
    if (!vibrationEnabled) return;

    final hasVibrator = await Vibration.hasVibrator();
    if (!hasVibrator) return;

    await Vibration.vibrate(duration: 120);
  }

  static Future<void> vibrateFinal() async {
    if (!vibrationEnabled) return;

    final hasVibrator = await Vibration.hasVibrator();
    if (!hasVibrator) return;

    await Vibration.vibrate(pattern: [0, 120, 80, 180]);
  }
}
