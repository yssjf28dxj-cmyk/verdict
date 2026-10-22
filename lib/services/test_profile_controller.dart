import 'package:flutter/foundation.dart';

typedef PrepareTestProfile = Future<void> Function(int slot, {required bool createAccount});

/// Stores only a slot number. Firebase SDK owns credentials for each named app.
class TestProfileController extends ChangeNotifier {
  TestProfileController({
    required this.enabled,
    required this.prepare,
    required this.load,
    required this.save,
  });

  final bool enabled;
  final PrepareTestProfile prepare;
  final Future<int?> Function() load;
  final Future<void> Function(int) save;
  int _selected = 1;
  bool _busy = false;
  int get selected => _selected;
  bool get busy => _busy;

  Future<void> restore() async {
    if (!enabled) return;
    final saved = await load();
    final slot = saved != null && saved >= 1 && saved <= 6 ? saved : 1;
    await prepare(slot, createAccount: false);
    _selected = slot;
  }

  Future<void> switchTo(int slot) async {
    if (!enabled) throw StateError('Test profiles are disabled');
    if (slot < 1 || slot > 6) throw RangeError.range(slot, 1, 6);
    if (_busy || slot == _selected) return;
    _busy = true;
    notifyListeners();
    try {
      // Keep the original session selected until the target is fully ready.
      await prepare(slot, createAccount: true);
      await save(slot);
      _selected = slot;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
