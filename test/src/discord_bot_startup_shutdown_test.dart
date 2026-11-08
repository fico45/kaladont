@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:discord_bot/src/discord_bot.dart';
import 'package:discord_bot/src/repository/channel_repository.dart';
import 'package:discord_bot/src/services/game_channels.dart';
import 'package:discord_bot/src/services/receipt_retention.dart';
import 'package:nyxx/nyxx.dart';
import 'package:test/test.dart';

import 'discord_bot_test_support.dart';

class _Channels implements ChannelRepository {
  final entered = Completer<void>();
  final result = Completer<Set<GameKey>>();
  @override
  Future<Set<GameKey>> enabledChannels() {
    if (!entered.isCompleted) entered.complete();
    return result.future;
  }

  @override
  Future<void> setEnabled(GameKey key, bool enabled) async {}
}

class _Gateway implements NyxxGateway {
  int closes = 0;
  int listeners = 0;
  final closed = Completer<void>();
  @override
  Future<void> close() async {
    closes++;
    if (!closed.isCompleted) closed.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #onReady) {
      listeners++;
      return const Stream<ReadyEvent>.empty();
    }
    if (invocation.memberName == #onMessageCreate) {
      listeners++;
      return const Stream<MessageCreateEvent>.empty();
    }
    return super.noSuchMethod(invocation);
  }
}

class _Startup {
  final harness = Harness();
  final repository = _Channels();
  final connection = Completer<NyxxGateway>();
  final connecting = Completer<void>();
  final gateway = _Gateway();
  int cleanupCalls = 0;
  late final DiscordBot bot;

  _Startup({bool holdRefresh = false, bool holdConnect = false}) {
    if (!holdRefresh) repository.result.complete({});
    if (!holdConnect) connection.complete(gateway);
    bot = DiscordBot(
      config: harness.bot.config,
      game: harness.service,
      games: harness.games,
      queue: harness.queue,
      channels: GameChannels(repository),
      retention: ReceiptRetention(() async {
        cleanupCalls++;
        return 0;
      }),
      connectGateway: (_) {
        connecting.complete();
        return connection.future;
      },
    );
    addTearDown(bot.close);
  }
}

void main() {
  test(
    'shutdown before start never fetches connects or launches cleanup',
    () async {
      final s = _Startup(holdRefresh: true, holdConnect: true);
      s.bot.requestShutdown();
      s.bot.requestShutdown();
      await s.bot.start();
      await s.bot.close();
      expect(s.repository.entered.isCompleted, isFalse);
      expect(s.connecting.isCompleted, isFalse);
      expect(s.cleanupCalls, 0);
    },
  );

  test('late refresh success cannot resume startup', () async {
    final s = _Startup(holdRefresh: true, holdConnect: true);
    final starting = s.bot.start();
    await s.repository.entered.future;
    s.bot.requestShutdown();
    await starting.timeout(const Duration(seconds: 1));
    s.repository.result.complete({key});
    await Future<void>.delayed(Duration.zero);
    expect(s.connecting.isCompleted, isFalse);
    expect(s.cleanupCalls, 0);
  });

  test('late refresh failure is observed after shutdown', () async {
    final s = _Startup(holdRefresh: true, holdConnect: true);
    final starting = s.bot.start();
    await s.repository.entered.future;
    s.bot.requestShutdown();
    await starting;
    s.repository.result.completeError(StateError('offline'));
    await Future<void>.delayed(Duration.zero);
    expect(s.connecting.isCompleted, isFalse);
  });

  test('late connection failure is observed after shutdown', () async {
    final s = _Startup(holdConnect: true);
    final starting = s.bot.start();
    await s.connecting.future;
    s.bot.requestShutdown();
    await starting;
    s.connection.completeError(StateError('offline'));
    await Future<void>.delayed(Duration.zero);
    expect(s.gateway.listeners, 0);
    expect(s.cleanupCalls, 0);
  });

  test('connection failure without shutdown still propagates', () async {
    final s = _Startup(holdConnect: true);
    final failure = expectLater(s.bot.start(), throwsStateError);
    await s.connecting.future;
    s.connection.completeError(StateError('offline'));
    await failure;
    expect(s.cleanupCalls, 0);
  });

  test(
    'shutdown racing with connection completion never installs listeners',
    () async {
      final s = _Startup(holdConnect: true);
      final starting = s.bot.start();
      await s.connecting.future;
      s.connection.complete(s.gateway);
      s.bot.requestShutdown();
      await starting;
      await s.bot.close();
      expect(s.gateway.closes, 1);
      expect(s.gateway.listeners, 0);
      expect(s.cleanupCalls, 0);
    },
  );

  test(
    'successful startup creates timers which requestShutdown cancels',
    () async {
      final s = _Startup();
      final timers = <Timer>[];
      await runZoned(
        s.bot.start,
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createPeriodicTimer(zone, duration, callback);
            timers.add(timer);
            return timer;
          },
        ),
      );
      expect(timers, hasLength(2));
      expect(timers.every((timer) => timer.isActive), isTrue);
      expect(s.gateway.listeners, 2);
      expect(s.cleanupCalls, 1);
      s.bot.requestShutdown();
      expect(timers.every((timer) => !timer.isActive), isTrue);
      await s.bot.close();
      expect(s.gateway.closes, 1);
    },
  );

  test(
    'requestShutdown then concurrent closes share normal queue drain',
    () async {
      final s = _Startup();
      await s.bot.start();
      final gate = Completer<void>();
      final entered = Completer<void>();
      final work = s.harness.queue.run(key, () {
        entered.complete();
        return gate.future;
      });
      await entered.future;
      s.bot.requestShutdown();
      final first = s.bot.close();
      final second = s.bot.close();
      try {
        expect(identical(first, second), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(s.gateway.closes, 0);
      } finally {
        gate.complete();
        await Future.wait([work, first, second]);
      }
      expect(s.gateway.closes, 1);
      await s.bot.close();
      expect(s.gateway.closes, 1);
    },
  );

  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    test('$signal exits process with a stalled initial HTTP fetch', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final entered = Completer<void>();
      server.listen((request) {
        if (!entered.isCompleted) entered.complete();
        // Deliberately never respond. No Discord connection can be reached.
      });
      final process = await Process.start(
        Platform.resolvedExecutable,
        ['run', 'bin/main.dart'],
        environment: {
          'discordToken': 'offline',
          'supaBaseUrl': 'http://127.0.0.1:${server.port}',
          'supaBaseAPIKey': 'offline',
        },
      );
      final output = process.stdout.drain<void>();
      final errors = process.stderr.drain<void>();
      try {
        await entered.future.timeout(const Duration(seconds: 15));
        expect(process.kill(signal), isTrue);
        expect(await process.exitCode.timeout(const Duration(seconds: 3)), 0);
      } finally {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
        await server.close(force: true);
        await Future.wait([output, errors]);
      }
    }, skip: Platform.isWindows);
  }

  test(
    'shutdown interrupts blocked connect and closes its late client',
    () async {
      final h = Harness();
      final entered = Completer<void>();
      final connection = Completer<NyxxGateway>();
      final gateway = _Gateway();
      final bot = DiscordBot(
        config: h.bot.config,
        game: h.service,
        games: h.games,
        queue: h.queue,
        channels: h.channels,
        retention: h.bot.retention,
        connectGateway: (_) {
          entered.complete();
          return connection.future;
        },
      );
      final starting = bot.start();
      await entered.future;
      bot.requestShutdown();
      await starting.timeout(const Duration(milliseconds: 200));
      await bot.close();
      connection.complete(gateway);
      await gateway.closed.future.timeout(const Duration(milliseconds: 200));
      expect(gateway.closes, 1);
      expect(gateway.listeners, 0);
    },
  );
  test(
    'close interrupts startup while initial refresh remains blocked',
    () async {
      final h = Harness();
      final channels = _Channels();
      final bot = DiscordBot(
        config: h.bot.config,
        game: h.service,
        games: h.games,
        queue: h.queue,
        channels: GameChannels(channels),
        retention: h.bot.retention,
      );
      final starting = bot.start();
      await channels.entered.future;
      await bot.close();
      await starting.timeout(const Duration(milliseconds: 200));
      expect(channels.result.isCompleted, isFalse);
    },
  );
}
