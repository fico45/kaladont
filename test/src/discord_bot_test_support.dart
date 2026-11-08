// VM-only harness: invoke the real private handlers without connecting a Gateway.
// Keep private-symbol access here until DiscordBot exposes an offline event seam.
import 'dart:async';
import 'dart:mirrors';

import 'package:discord_bot/src/config.dart';
import 'package:discord_bot/src/discord_bot.dart';
import 'package:discord_bot/src/model/game_key.dart';
import 'package:discord_bot/src/model/player.dart';
import 'package:discord_bot/src/repository/channel_repository.dart';
import 'package:discord_bot/src/repository/dictionary_repository.dart';
import 'package:discord_bot/src/repository/game_repository.dart';
import 'package:discord_bot/src/services/channel_queue.dart';
import 'package:discord_bot/src/services/game_channels.dart';
import 'package:discord_bot/src/services/game_service.dart';
import 'package:discord_bot/src/services/receipt_retention.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';

export 'package:discord_bot/src/model/game_key.dart';
export 'package:discord_bot/src/model/player.dart';
export 'package:discord_bot/src/repository/game_repository.dart';

const key = GameKey(guildId: 1, channelId: 10);
const retryMessage =
    'Usluga trenutačno nije dostupna. Pokušajte ponovno. Ako je potez već spremljen, provjerite trenutačni niz.';

final class TestGames implements GameRepository {
  String? current;
  bool started = true;
  bool failStart = false;
  bool failGuess = false;
  bool failUpsert = false;
  final calls = <String>[];
  final guesses = <Guess>[];
  final development = <bool>[];
  final starts = <(GameKey, String)>[];
  final ranks = <int>[];
  final guilds = <(int, String, String?)>[];
  List<Player> players = [];
  Future<void>? startGate;
  final startEntered = Completer<void>();
  TurnResult result = const TurnResult(
    TurnStatus.applied,
    word: 'oniks',
    answers: 1,
  );
  @override
  Future<String?> currentWord(GameKey key) async {
    calls.add('current');
    return current;
  }

  @override
  Future<bool> start(GameKey key, String word) async {
    calls.add('start');
    starts.add((key, word));
    if (!startEntered.isCompleted) startEntered.complete();
    await startGate;
    if (failStart) throw StateError('start failed');
    return started;
  }

  @override
  Future<TurnResult> guess(Guess guess, {required bool isDev}) async {
    calls.add('guess');
    guesses.add(guess);
    development.add(isDev);
    if (failGuess) throw StateError('guess failed');
    return result;
  }

  @override
  Future<void> upsertGuild({
    required int id,
    required String name,
    String? iconUrl,
  }) async {
    calls.add('guild');
    guilds.add((id, name, iconUrl));
    if (failUpsert) throw StateError('guild failed');
  }

  @override
  Future<List<Player>> ranking(int guildId) async {
    calls.add('ranking');
    ranks.add(guildId);
    return players;
  }
}

final class TestDictionary implements DictionaryRepository {
  String? word = 'telefon';
  int calls = 0;
  @override
  Future<String> randomWord() async {
    calls++;
    if (word == null) throw const EmptyDictionaryException();
    return word!;
  }
}

final class TestChannels implements ChannelRepository {
  final writes = <(GameKey, bool)>[];
  Set<GameKey> enabled = {};
  bool fail = false;
  bool failRefresh = false;
  @override
  Future<Set<GameKey>> enabledChannels() async {
    if (failRefresh) throw StateError('refresh failed');
    return enabled;
  }

  @override
  Future<void> setEnabled(GameKey key, bool enabled) async {
    writes.add((key, enabled));
    if (fail) throw StateError('channel failed');
  }
}

class TestMessage implements Message {
  final int messageId;
  final String text;
  final TestTextChannel textChannel;
  TestMessage(this.textChannel, {this.messageId = 42, this.text = ' Oniks '});
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return switch (invocation.memberName) {
      #id => Snowflake(messageId),
      #content => text,
      #channel => textChannel,
      #author => TestUser(),
      #webhookId => null,
      _ => super.noSuchMethod(invocation),
    };
  }
}

class TestUser implements User {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      switch (invocation.memberName) {
        #id => Snowflake(2),
        #username => 'Player',
        #avatar => TestAvatar(),
        #isBot => false,
        _ => super.noSuchMethod(invocation),
      };
}

class TestAvatar implements CdnAsset {
  @override
  dynamic noSuchMethod(Invocation invocation) => invocation.memberName == #url
      ? Uri.parse('https://example.invalid/avatar.png')
      : super.noSuchMethod(invocation);
}

class TestGuild implements Guild {
  final int guildId;
  TestGuild(this.guildId);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      switch (invocation.memberName) {
        #id => Snowflake(guildId),
        #name => 'Test guild',
        #icon => null,
        _ => super.noSuchMethod(invocation),
      };
}

class TestTextChannel implements TextChannel {
  final int channelId;
  final sent = <MessageBuilder>[];
  bool failSend = false;
  TestTextChannel(this.channelId);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #id) return Snowflake(channelId);
    if (invocation.memberName == #sendMessage) {
      sent.add(invocation.positionalArguments.single as MessageBuilder);
      return failSend
          ? Future<Message>.error(StateError('delivery failed'))
          : Future<Message>.value(TestMessage(this));
    }
    return super.noSuchMethod(invocation);
  }
}

class TestContext implements ChatContext {
  final TestTextChannel textChannel;
  final int? guildId;
  final replies = <MessageBuilder>[];
  TestContext(this.textChannel, {this.guildId = 1});
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #guild) {
      return guildId == null ? null : TestGuild(guildId!);
    }
    if (invocation.memberName == #channel) return textChannel;
    if (invocation.memberName == #respond) {
      replies.add(invocation.positionalArguments.single as MessageBuilder);
      return Future<Message>.value(TestMessage(textChannel));
    }
    return super.noSuchMethod(invocation);
  }
}

class TestEvent implements MessageCreateEvent {
  final TestMessage payload;
  final int guildIdValue;
  TestEvent(this.payload, {this.guildIdValue = 1});
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      switch (invocation.memberName) {
        #guildId => Snowflake(guildIdValue),
        #message => payload,
        _ => super.noSuchMethod(invocation),
      };
}

final class Harness {
  final games = TestGames();
  final dictionary = TestDictionary();
  final repository = TestChannels();
  final queue = ChannelQueue();
  final channel = TestTextChannel(10);
  late final channels = GameChannels(repository);
  late final context = TestContext(channel);
  late final GameService service;
  late final DiscordBot bot;
  Harness({bool isDev = false}) {
    service = GameService(dictionary: dictionary, games: games, isDev: isDev);
    bot = DiscordBot(
      config: AppConfig(
        supabaseUrl: 'https://example.invalid',
        supabaseApiKey: 'unused',
        discordToken: 'unused',
        isDev: isDev,
      ),
      game: service,
      games: games,
      queue: queue,
      channels: channels,
      retention: ReceiptRetention(() async => 0),
    );
  }
  Symbol symbol(String name) => MirrorSystem.getSymbol(
    name,
    reflectClass(DiscordBot).owner as LibraryMirror,
  );
  Future<void> invoke(
    String name, [
    List<Object?> args = const [],
    Map<Symbol, Object?> named = const {},
  ]) async {
    await (reflect(bot).invoke(symbol(name), args, named).reflectee
        as Future<void>);
  }

  void field(String name, Object? value) =>
      reflect(bot).setField(symbol(name), value);
  Future<void> command({
    bool start = true,
    bool disable = false,
    TestContext? using,
  }) => invoke(
    '_command',
    [using ?? context],
    {#startGame: start, #disableChannel: disable},
  );
  Future<void> enable() async {
    repository.enabled = {key};
    await channels.refresh();
  }

  Future<void> message({String text = ' Oniks ', int id = 42}) => invoke(
    '_message',
    [TestEvent(TestMessage(channel, text: text, messageId: id))],
  );
}
