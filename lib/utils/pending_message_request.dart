import 'dart:math';

class MessageRequest {
  const MessageRequest(this.text, this.id);
  final String text;
  final String id;
}

/// A timeout may follow a successful commit. Reuse the ID for a manual retry of
/// the same text, but use a fresh ID for a new draft or a confirmed new message.
class PendingMessageRequest {
  PendingMessageRequest({String Function()? createId}) : _createId = createId ?? _randomId;
  final String Function() _createId;
  MessageRequest? _pending;

  MessageRequest forText(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) throw ArgumentError('Message is empty');
    if (_pending?.text != normalized) _pending = MessageRequest(normalized, _createId());
    return _pending!;
  }

  void confirmed(MessageRequest request) {
    if (_pending?.id == request.id) _pending = null;
  }

  static String _randomId() {
    final random = Random.secure();
    return List.generate(20, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
