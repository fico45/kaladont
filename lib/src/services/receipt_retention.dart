final class ReceiptRetention {
  final Future<int> Function() pruneBatch;
  Future<int>? _running;

  ReceiptRetention(this.pruneBatch);

  Future<int> run() => _running ??= _run().whenComplete(() {
    _running = null;
  });

  Future<int> _run() async {
    var removed = 0;
    // Bound each hourly run to 10,000 deletions; avoid monopolizing the database.
    for (var batch = 0; batch < 10; batch++) {
      final count = await pruneBatch();
      removed += count;
      if (count < 1000) break;
    }
    return removed;
  }
}
