class DebateLobby {
  final String id;
  final String creatorId;
  final String opponentId;

  final int? creatorTime;
  final int? opponentTime;

  final bool creatorReady;
  final bool opponentReady;

  final bool started;

  DebateLobby({
    required this.id,
    required this.creatorId,
    required this.opponentId,
    this.creatorTime,
    this.opponentTime,
    this.creatorReady = false,
    this.opponentReady = false,
    this.started = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'creatorId': creatorId,
      'opponentId': opponentId,
      'creatorTime': creatorTime,
      'opponentTime': opponentTime,
      'creatorReady': creatorReady,
      'opponentReady': opponentReady,
      'started': started,
    };
  }

  factory DebateLobby.fromMap(String id, Map<String, dynamic> data) {
    return DebateLobby(
      id: id,
      creatorId: data['creatorId'] ?? '',
      opponentId: data['opponentId'] ?? '',
      creatorTime: data['creatorTime'],
      opponentTime: data['opponentTime'],
      creatorReady: data['creatorReady'] ?? false,
      opponentReady: data['opponentReady'] ?? false,
      started: data['started'] ?? false,
    );
  }
}
