# Discord Kaladont bot

A Dart Discord Gateway bot for the Croatian word game Kaladont. Each guild and
channel has its own game. Supabase stores sessions, used words, turn receipts,
and guild rankings; active games survive bot restarts.

## Local development

Install [mise](https://mise.jdx.dev/getting-started), then run:

```sh
mise trust
mise install
mise exec -- dart pub get --enforce-lockfile
mise exec -- dart test
```

`mise.toml` pins Dart 3.13.7, matching Docker and CI. Activate mise in your shell
with `eval "$(mise activate zsh)"`, or use `mise exec -- dart ...` explicitly.
VS Code workspace settings select the default mise installation of this SDK.
For a custom mise data directory, find it with `mise where dart` and update
`dart.sdkPath`.

Follow [Supabase setup](supabase.md) before starting the bot. Supply these runtime
environment variables through your shell, deployment secrets, or an ignored
`.vscode/launch.json` that launches `bin/main.dart`:

| Variable | Meaning |
| --- | --- |
| `discordToken` | Discord bot token |
| `supaBaseUrl` | Supabase API URL; local development uses `http://127.0.0.1:54331` |
| `supaBaseAPIKey` | Server-only Supabase secret/service-role key |
| `isDev` | `true` permits consecutive turns by one player and disables scoring; defaults to `false` |

Dart `-D` definitions override runtime environment variables. `.env` files are
not loaded. Credentials are validated before opening network clients.

```sh
mise exec -- dart run bin/main.dart
```

Enable Discord's Message Content Intent in the Developer Portal. Invite the bot
with the bot and application-command scopes, and permit it to view channels,
send messages and embed links.

## Commands and gameplay

- `/kaladont-start` starts a game in the invoking channel, or reports the existing game.
- `/kaladont-ranks` shows the invoking guild's top 25 players.
- Send one dictionary word continuing the last two Croatian letters. `dž`, `lj`
  and `nj` each count as one letter. A word must contain at least two letters.
- Words cannot repeat within a game. Players alternate unless `isDev=true`.
- Accepted words earn one point; a word with no unused continuation earns three
  points and ends the game. Start another game with `/kaladont-start`.

Initial words are nouns or verbs. Guesses and continuations may be nouns, verbs
or adjectives. Dictionary membership does not enforce additional grammatical
form rules. Non-word messages, bots, webhooks and DMs are ignored.

## Message diagnostics

Incoming Gateway messages are logged as JSON to stderr, visible in the VS Code
Debug Console. Each entry includes `process_id`, server `guild_id` and cached
`guild_name` (null when unavailable), `channel_id`, `message_id`, `author_id`,
`content_length`, and whether it will be processed or ignored. Message text is
not logged. Commands, reply delivery and processing failures include server and
channel context too.

After restarting the bot, run `/kaladont-start` in the channel on the new server
and send a word. Look for `Discord message received` and then:

- `noActiveGame`: start a game in that exact server/channel; threads have separate IDs.
- `emptyContent`: Discord supplied no text (also possible for attachment-only messages).
  Check Message Content Intent in the Developer Portal for text messages.
- `invalidWord`: the input is not one word with at least two Croatian letters.
- `duplicateMessage`: that message ID already has a committed turn.
- `Discord reply sent`: Discord accepted the reply.
- A processing/response error: inspect its server/channel IDs and exception type.

If there is no incoming entry at all, check channel visibility and that you are
watching the correct process. For reply failures, check Send Messages and Embed
Links permissions (and Send Messages in Threads when applicable). One bot process
handles all invited servers; two servers do not require two processes using the
same token. The process ID helps distinguish logs when multiple workers run.

## Verification and builds

```sh
mise exec -- dart format --output=none --set-exit-if-changed bin lib test
mise exec -- dart analyze --fatal-infos
mise exec -- dart test
python3 tool/test_database.py
mkdir -p build
mise exec -- dart run nyxx_commands:compile --no-compile --no-format -o build/main.g.dart bin/main.dart
mise exec -- dart compile exe build/main.g.dart -o build/server

docker build -t kaladont .
```

The database test runner uses the existing `supabase_db_kaladont` container by
default, creates an isolated test database, and drops it afterward. Set
`--container NAME` to use another local PostgreSQL container. It checks migrations,
rollback, replay protection, concurrent commits, tenant isolation and dictionary
counts beyond the API row limit. It does not use the development database's data.

GitHub Actions runs formatting, strict analysis, Dart tests, database regressions,
AOT compilation and a Docker build. Codemagic runs the Dart checks and AOT build.

The runtime image runs as UID/GID 65532 with only the executable and Dart runtime
libraries. Pass secrets at runtime, for example using your deployment's secret
manager or `docker run --env-file /absolute/path/to/private.env kaladont`.
No inbound HTTP port is required. Run one Gateway process per Discord bot token;
multiple replicas require deliberate Discord sharding/event ownership. Database
transactions protect turns from stale or duplicate delivery, but do not coordinate
Discord connections or response delivery between replicas.

SIGINT/SIGTERM stops new work, drains queued channel work and closes clients.
A crash can occur after a turn is committed but before its Discord reply is sent;
the committed session and score remain consistent. Turn receipts prevent repeated
awards for the same message. Discord replies are not stored in a durable outbox.

## Code layout

- `bin/main.dart`: configuration, dependency composition and process lifecycle.
- `lib/src/discord_bot.dart`: Discord commands, message filtering and replies.
- `lib/src/services/`: Croatian letter rules, game orchestration and channel queues.
- `lib/src/repository/`: injected dictionary and durable game storage interfaces/adapters.
- `lib/src/model/`: immutable game and ranking models.
- `supabase/migrations/`: schema, dictionary queries and atomic turn/score functions.

Dependencies use constructor injection. Game state is stored in Supabase, so the
former process-local Riverpod providers and their dependency are no longer needed.
