import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sound effects enum for type-safe API
enum SFX {
  bell, // Boxing bell — round start/end
  tick, // Ticking — last 5 seconds
  victory, // Victory fanfare — WIN
  defeat, // Defeat tone — LOSS
  whoosh, // Message sent
  click, // Vote cast / button tap
}

/// Singleton sound service with graceful missing-file handling.
///
/// Usage:
///   await SoundService.instance.warmUp();
///   SoundService.instance.play(SFX.bell);
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  static const String _prefKey = 'sound_enabled';

  final AudioPlayer _player = AudioPlayer();
  bool _soundEnabled = true;
  bool _initialized = false;

  /// Map SFX to asset file names
  static const Map<SFX, String> _assetMap = {
    SFX.bell: 'sounds/bell.mp3',
    SFX.tick: 'sounds/tick.mp3',
    SFX.victory: 'sounds/victory.mp3',
    SFX.defeat: 'sounds/defeat.mp3',
    SFX.whoosh: 'sounds/whoosh.mp3',
    SFX.click: 'sounds/click.mp3',
  };

  bool get soundEnabled => _soundEnabled;

  /// Initialize and load user preference
  Future<void> warmUp() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _soundEnabled = prefs.getBool(_prefKey) ?? true;
      await _player.setReleaseMode(ReleaseMode.stop);
    } catch (e) {
      debugPrint('[SoundService] warmUp error: $e');
    }
  }

  /// Toggle sound on/off and persist
  Future<void> toggle() async {
    _soundEnabled = !_soundEnabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, _soundEnabled);
    } catch (e) {
      debugPrint('[SoundService] toggle error: $e');
    }
  }

  /// Set sound enabled state explicitly
  Future<void> setEnabled(bool enabled) async {
    _soundEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, _soundEnabled);
    } catch (e) {
      debugPrint('[SoundService] setEnabled error: $e');
    }
  }

  /// Play a sound effect. Gracefully handles missing files.
  Future<void> play(SFX sound) async {
    try {
      if (!_initialized) {
        await warmUp();
      }
      if (!_soundEnabled) return;

      final asset = _assetMap[sound];
      if (asset == null) return;

      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (e) {
      debugPrint(
        '[SoundService] Sound file missing or error: ${sound.name} - $e',
      );
    }
  }

  /// Stop any currently playing sound
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Dispose the player (call on app shutdown if needed)
  void dispose() {
    _player.dispose();
  }
}
