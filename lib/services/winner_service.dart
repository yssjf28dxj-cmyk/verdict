class WinnerResult {
  final String winner;
  final int votesA;
  final int votesB;
  final String reason;

  const WinnerResult({
    required this.winner,
    required this.votesA,
    required this.votesB,
    required this.reason,
  });
}

class WinnerService {
  static WinnerResult calculate({
    required int votesA,
    required int votesB,
  }) {
    if (votesA > votesB) {
      return WinnerResult(
        winner: 'БОЕЦ 1',
        votesA: votesA,
        votesB: votesB,
        reason: 'Победа по голосам зрителей',
      );
    }

    if (votesB > votesA) {
      return WinnerResult(
        winner: 'БОЕЦ 2',
        votesA: votesA,
        votesB: votesB,
        reason: 'Победа по голосам зрителей',
      );
    }

    return WinnerResult(
      winner: 'НИЧЬЯ',
      votesA: votesA,
      votesB: votesB,
      reason: 'Количество голосов одинаковое',
    );
  }
}
