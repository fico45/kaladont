import 'dart:async';

import 'package:discord_bot/src/services/receipt_retention.dart';
import 'package:test/test.dart';

void main() {
  test('cleanup stops when there is no full batch left', () async {
    final batches = [1000, 1000, 4].iterator;
    final retention = ReceiptRetention(() async {
      batches.moveNext();
      return batches.current;
    });
    expect(await retention.run(), 2004);
  });
  test('cleanup limits work per run', () async {
    var calls = 0;
    final retention = ReceiptRetention(() async {
      calls++;
      return 1000;
    });
    expect(await retention.run(), 10000);
    expect(calls, 10);
  });
  test('concurrent cleanup is shared and failure can be retried', () async {
    final pending = Completer<int>();
    var calls = 0;
    final retention = ReceiptRetention(() {
      calls++;
      return pending.future;
    });
    final first = retention.run();
    final second = retention.run();
    pending.complete(0);
    expect(await first, 0);
    expect(await second, 0);
    expect(calls, 1);
    var fail = true;
    final retry = ReceiptRetention(() async {
      if (fail) throw StateError('Offline');
      return 0;
    });
    await expectLater(retry.run(), throwsStateError);
    fail = false;
    expect(await retry.run(), 0);
  });
}
