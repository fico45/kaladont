# Kaladont repository guidance

## Purpose and sources of truth

This repository is a standalone Dart Discord Gateway bot for the Croatian word
game Kaladont. It is not a Flutter app or an HTTP server. One worker serves
multiple Discord guilds, with games isolated by `(guild_id, channel_id)` and
rankings isolated by guild. User-facing replies are in Croatian.

Read [README.md](README.md) for development and gameplay,
[supabase.md](supabase.md) for schema/data/deployment details, and
[jenkins.md](jenkins.md) for CI setup. Verify historical notes against current
code. Preserve existing working-tree changes; they may contain work from earlier
tasks. Keep this file current when architecture or workflows change.

## Persistent project documentation

All repository paths in this file are relative to the repository root.
Store working documentation and investigation notes outside the repository, using
the documentation root configured by the user or execution environment. Within
that root, use `<original-repository-folder-name>/` and resolve documentation
paths relative to that repository-specific documentation directory. Do not embed
workstation-specific paths in repository instructions.

- At the start of repository work, read that folder's `README.md` if present,
  then relevant architecture, decisions and work notes.
- Resolve the original checkout through Git worktree metadata when using a
  temporary worktree. Use its original folder name for documentation.
- Record and check the original repository path and remote identity in the
  documentation README before reusing a folder. Determine the remote identity
  from Git metadata (for example, `git remote get-url origin`). Ask how to
  disambiguate if identities conflict; do not combine unrelated repositories
  sharing a folder name.
- After meaningful implementation, investigation or debugging, create/update
  concise notes and the README index. Use `architecture.md`, `decisions.md` and
  `work/YYYY-MM-DD-topic.md` as appropriate; do not create empty placeholders.
- Record the problem, resulting behavior, rationale, relevant code paths,
  verification, commit/PR references when available, and unresolved issues.
  Distinguish completed work from proposals/unverified claims and concurrent
  branch work. Preserve useful history.
- Keep build, product and contributor documentation in the repository. This
  `AGENTS.md`, README and setup guides belong here; task logs belong outside it.
- Never save credentials, secrets or unnecessary personal data in documentation.
  If filesystem permissions prevent access, report the limitation and request
  access; do not silently put working notes inside the repository or claim they
  were saved.

## Toolchain and configuration

- Use the standalone Dart version pinned in `mise.toml` (currently 3.13.7).
  Prefer `mise exec -- dart ...` over a globally installed Flutter/Dart wrapper.
- Keep the SDK pin aligned with Docker, Codemagic, Jenkins and VS Code settings.
  Keep `pubspec.lock` reproducible; do not update unrelated dependencies.
- Nyxx/nyxx_commands command metadata must be generated before AOT compilation.
- Configuration is validated by `lib/src/config.dart` before connecting.
  Exact runtime environment names are `discordToken`, `supaBaseUrl`,
  `supaBaseAPIKey`, and optional `isDev` (defaults to false).
- Dart `-D` definitions override runtime environment variables. `.env` files
  are not loaded. Prefer runtime secrets for deployments.
- `supaBaseAPIKey` must be a server-only Supabase secret/service-role credential.
  Never expose it or the Discord token in clients, logs, Git, build arguments or
  images. Preserve `.dockerignore` exclusions and explicit Docker source copies.

```sh
mise trust
mise install
mise exec -- dart pub get --enforce-lockfile
mise exec -- dart run bin/main.dart
```

Running the bot connects to Discord and registers commands. Unit tests and SQL
regressions do not require a live Discord token.

## Code map and design boundaries

| Path | Responsibility |
| --- | --- |
| `bin/main.dart` | Configuration, dependency composition and process lifecycle |
| `lib/src/discord_bot.dart` | Commands, Gateway filtering, queue dispatch, replies, maintenance timers |
| `lib/src/services/game_service.dart` | Input normalization and mapping database outcomes to replies |
| `lib/src/services/word_rules.dart` | Croatian letters, word shape and prefix/suffix helpers |
| `lib/src/services/channel_queue.dart` | Ordered work per guild/channel; independent channels run concurrently |
| `lib/src/services/game_channels.dart` | Cached enabled-channel configuration |
| `lib/src/services/receipt_retention.dart` | Bounded receipt-cleanup orchestration |
| `lib/src/repository/` | Supabase adapters and repository contracts |
| `lib/src/logging.dart` | Structured JSON logging to stderr |
| `supabase/migrations/` | Source-controlled schema, permissions and authoritative game functions |
| `test/src/`, `test/supabase_compatibility_test.dart` | Dart behavior and HTTP adapter contract tests |
| `test/sql/`, `tool/test_database.py` | Disposable PostgreSQL regressions and optional dictionary benchmark |

Use constructor injection and the existing service/repository boundaries. Game
state lives in PostgreSQL; do not reintroduce process-local authoritative game
state, global clients or Riverpod providers. No Supabase Auth, Storage, Realtime
subscription or Edge Function is currently used by the bot.

## Gameplay invariants

- A word continues the last two **Croatian letters** of the previous word.
  `dž`, `lj` and `nj` each count as one letter. Keep Dart and SQL behavior aligned;
  do not replace this with raw string slicing. Two-letter words are supported.
- Normalize guesses to lowercase and trim whitespace. Ignore malformed input
  locally before contacting Supabase.
- Starting words are nouns or verbs. Guesses/continuations may also be adjectives.
  Additional grammatical-form constraints are not implemented; do not silently
  introduce different game rules while optimizing queries.
- Words cannot repeat within a game. Players alternate unless `isDev=true`.
  Normal accepted turns earn one point; a terminal word earns three and ends
  the game. Development turns persist but award zero points.
- Keep source dictionary rows lossless. Eligibility and deduplication belong in
  the derived gameplay dictionary, not destructive filtering of `public.words`.

## Database and performance invariants

- Each validly shaped guess in an enabled channel makes **one**
  `kaladont_guess` RPC. PostgreSQL locks the session, validates the guess, counts
  continuations, records the receipt, awards points and updates state atomically.
- Return compact reply data. Keep `used_words` in PostgreSQL; do not download it
  for guess validation or upload it for a separate continuation request.
- Preserve rollback, tenant isolation and duplicate Discord message protection.
  A new game gets a new UUID/start timestamp. Concurrent guesses validate the
  latest locked state. Do not restore separate score/state writes or the retired
  `kaladont_commit_turn` RPC.
- Use indexed normalized equality against `kaladont_dictionary.word` and the
  stored prefix/suffix fields. Avoid `ILIKE`/`lower(word)` source-table scans on
  the turn path. Exact server-side continuation counts must not depend on the
  PostgREST result-page limit.
- Random starters use a dense `kaladont_start_words` pool and indexed slot
  selection. Preserve contiguous slots and evaluate the random choice once.
  Do not restore a full dictionary `ORDER BY random()` or an unbounded retry loop.
- After source dictionary edits/imports, explicitly run:

  ```sql
  select public.kaladont_refresh_dictionary();
  ```

  Stop the worker during source updates/rebuilds. Refresh rebuilds both derived
  tables atomically; do not rebuild on every startup.
- Preserve RLS, explicit role grants/revocations, invoker-rights functions and
  the invoker-rights ranking view. Public/anonymous/authenticated roles must not
  gain access to trusted bot RPCs. Keep credentials server-side.

## Channel filtering, replay and retention

- `/kaladont-start` enables its channel and starts or resumes its saved game.
  `/kaladont-disable` disables gameplay without discarding the session.
  `/kaladont-ranks` reads guild rankings without enabling a channel. These
  commands use the existing access model; no new administrator-only policy has
  been implemented. Threads have separate channel IDs.
- Ignore DMs, bots, webhooks and unconfigured channels before queueing/database
  work. Recheck channel enablement after earlier queued commands.
- Enabled channels load before Gateway connection using 500-row pages, refresh
  every five minutes, and update immediately after successful command writes.
  Preserve generation protection against stale refreshes overwriting commands.
  SQL remains authoritative; failed refreshes preserve the last known cache.
- Decode creation timestamps from Discord snowflakes. Ignore messages older
  than 24 hours, more than five minutes in the future, or before the game began.
  Retained duplicate receipts produce no additional reply or score.
- Cleanup runs at startup and hourly, at most ten 1,000-row batches per run.
  Delete only receipts older than 30 days whose game is no longer active.
  Preserve active-game receipts, scores, players and session used-word lists.
- Keep the cleanup cutoff indexed, candidates **MATERIALIZED**, and
  `FOR UPDATE ... SKIP LOCKED`. A plain `DELETE ... IN (SELECT ... LIMIT ...)`
  previously exceeded the batch limit under a different PostgreSQL query plan.
  Keep the strict batch-size regression.
- Cleanup pauses while the worker is offline and retries on later runs after
  failures. Large backlogs and long active games can retain older receipts.
  Deletion/vacuum permits storage reuse without guaranteeing immediate file
  shrinkage. Do not prune receipts without preserving replay protections.

## Supabase setup and first deployment

- Read project, API, port and PostgreSQL settings from
  `supabase/config.toml`. Use `supabase status` to discover the running
  development instance instead of assuming a hostname, port or container name.
- The current baseline is
  `supabase/migrations/20261026000000_initial_schema.sql`. It creates the final
  schema directly, including an empty source dictionary. Retired intermediate
  development migrations are not needed.
- Inspect migration history in the target environment before applying changes.
  Do not infer deployment state from a different developer's database or from
  historical work notes.
- For a fresh project, apply the baseline, import dictionary data, refresh the
  derived tables, configure the worker's cloud URL/service credential and verify
  gameplay. Schema application alone does not transfer dictionary rows, scores,
  sessions or runtime secrets. An empty dictionary cannot start games.
- After a baseline is deployed, use new forward migrations for schema changes.
  Do not rewrite deployed history or reset populated databases to apply changes.
  Check the target environment explicitly before applying SQL.

```sh
supabase start
supabase migration up --local
supabase migration list --local
```

Do not use `supabase db reset` as a routine fix: imported dictionary data and
existing games/scores would be lost. Follow `supabase.md` for detailed setup.

## Verification and builds

Run checks appropriate to the change. Documentation-only changes do not require
starting the bot, rebuilding containers or rerunning gameplay tests. For Dart or
SQL changes, use the relevant checks below and report what actually ran.

```sh
mise exec -- dart format --output=none --set-exit-if-changed bin lib test
mise exec -- dart analyze --fatal-infos
mise exec -- dart test
python3 tool/test_database.py
```

The SQL runner creates/drops a disposable database in the selected PostgreSQL
container; it does not reset the development database. Tests cover atomic rollback,
duplicate/concurrent turns, guild/channel isolation, dictionary rules/counts,
channel configuration, bounded retention and stale replay. Docker access is
required. Select an isolated PostgreSQL container with `--container NAME`.
The optional `--benchmark` copies source dictionary data from the selected
container into the disposable database; timings are not a production load test.

Generate command metadata before AOT; keep generated outputs under ignored
`build/` and do not edit or commit them:

```sh
mkdir -p build
mise exec -- dart run nyxx_commands:compile --no-compile --no-format -o build/main.g.dart bin/main.dart
mise exec -- dart compile exe build/main.g.dart -o build/server
docker build -t kaladont .
```

When command signatures or registration change, verify metadata generation/AOT.
When changing rules or transactions, keep Dart/SQL regressions aligned and test
behavior rather than reproducing the implementation in mocks.

## Deployment, observability and known limits

- Deploy one always-running worker per bot token with a restart policy. No
  inbound HTTP port is required. Multiple guilds do not require multiple workers.
  Additional replicas require coordinated Discord sharding/event ownership;
  database locking alone does not coordinate Gateway connections or replies.
- Docker builds AOT and runs as UID/GID 65532 using the Dart runtime libraries.
  Supply secrets at runtime. Enable Message Content Intent in Discord and allow
  viewing channels, sending messages and embed links, including in threads.
- Preserve graceful shutdown: stop accepting work/timers, drain queues and
  background maintenance, then dispose clients. Failed channel work must not
  poison the queue or drop subsequent turns.
- Log structured JSON to stderr with guild/channel/message/process context.
  Do not log message contents, tokens or credential-bearing exception URLs.
  For missing messages, check receipt/ignore diagnostics, exact channel/thread,
  Message Content Intent and channel permissions before changing game rules.
- PostgreSQL state and Discord delivery are separate. A crash after commit can
  lose the reply while preserving score/state. No durable reply outbox exists.
- `Jenkinsfile` defines format, analysis, Dart tests, isolated SQL tests, AOT and
  Docker checks. Codemagic runs Dart checks/AOT but not SQL tests. GitHub's Dart
  workflow currently resolves dependencies only; do not assume it runs tests.
- `.github/workflows/build-and-deploy.yml` is legacy: it passes secrets as build
  arguments and starts a container without the current runtime configuration.
  Align runtime secret injection before relying on it for deployment. Do not
  treat the existence of this workflow as evidence of a working deployment.
- Scaling depends on activity, game length and peak concurrency, not merely
  guild/member counts. Discord players are ordinary database rows and do not
  consume Supabase Auth MAUs in this architecture. Measure database/index growth,
  outbound bytes per turn, CPU and latency; verify current official Supabase
  pricing before quoting quotas or costs. There is no measured production
  throughput guarantee.
- Keep environment-specific row counts, database sizes, benchmarks and deployment
  history in the configured shared documentation. Re-measure in the target
  environment; do not treat past development timings as production guarantees.
