/// Counts public server-owned shards without exposing individual ballots.
class VoteTotals {
  const VoteTotals(this.votes1, this.votes2);
  final int votes1;
  final int votes2;

  factory VoteTotals.fromShards(Iterable<Map<String, dynamic>> shards) {
    int read(dynamic value) => value is num && value.isFinite && value >= 0 &&
        value == value.toInt() ? value.toInt() : 0;
    var a = 0;
    var b = 0;
    for (final shard in shards) {
      a += read(shard['votes1']);
      b += read(shard['votes2']);
    }
    return VoteTotals(a, b);
  }
}
