# Supabase setup

The bot requires a server-only secret/service-role API key. Keep it in runtime
secrets. Bot RPCs and derived dictionary tables are restricted to the service
role; RLS is enabled on application tables. The ranking view uses invoker rights.

## Source dictionary

The initial schema creates `public.words` with `id`, `word`, `base_word`,
`source_code` and `type` columns. Import source words separately after setup;
existing source rows are preserved if the table is already present. The initial
schema starts with an empty dictionary on a fresh project.

The schema builds `kaladont_dictionary`: distinct lowercase eligible words with
precomputed Croatian prefixes/suffixes. Nouns, verbs and adjectives are playable;
only nouns and verbs can start a game. Invalid spellings and words shorter than
two Croatian letters are excluded. Grammatical-form validation is unchanged.
Membership uses primary-key equality; continuation counts use the prefix index.
A dense `kaladont_start_words` pool provides uniform indexed random selection.
An empty pool returns null immediately.

After **every source dictionary import or edit**, rebuild both derived tables:

```sql
select public.kaladont_refresh_dictionary();
```

Run as the database owner or service role. Refreshes are serialized and commit
atomically; a failed refresh leaves the previous dictionary intact. Schedule
imports/rebuilds while the bot is stopped so games do not change dictionaries
mid-turn. The derived tables trade additional fixed database space for lower
CPU use; the full local dictionary added approximately 97 MB including indexes
in the October 2026 measurement. Do not rebuild on each bot startup.

## Apply the initial schema

This application has not been deployed. Its schema is consolidated in one file:
`supabase/migrations/20261026000000_initial_schema.sql`. It creates the final
optimized tables and functions directly, without intermediate versions or the
legacy commit RPC.

For a fresh local Supabase project:

```sh
supabase start
supabase migration up --local
supabase migration list --local
```

Import the dictionary, then run `kaladont_refresh_dictionary()` before playing.
No dictionary import is bundled with the schema. Local database reset discards
imported data, so use it only when intentionally starting over.

The existing development database has already had this schema applied. Its
source dictionary, guilds, scores, sessions and receipts were preserved, existing
game channels were enabled, and local migration history was reconciled to the
single initial version. Do not apply the retired development migrations.

For the first hosted deployment, use `supabase db push --dry-run` to review the
initial schema, then apply it to the linked project through the normal deployment
process. If using the SQL Editor, run the complete file in one transaction and
maintain migration history. Start the current worker after schema setup and the
dictionary import/refresh are complete.

## Gameplay and channels

| Object | Purpose |
| --- | --- |
| `discord_guilds` | Guild metadata and master `enabled` switch |
| `discord_players`, `guild_players` | Profiles and persistent guild scores |
| `guild_player_rankings` | Tenant-filtered ranking reads |
| `kaladont_channels` | Enabled gameplay channels |
| `kaladont_sessions` | Durable state per guild/channel, including current-game start time |
| `kaladont_turns` | Accepted-message receipts and awarded points |
| `kaladont_start_game` | Starts or re-enables a channel without replacing an active game |
| `kaladont_guess` | Validates, deduplicates, counts continuations and commits score/state atomically |
| `kaladont_set_channel_enabled` | Enables/disables a gameplay channel |
| `kaladont_prune_receipts` | Deletes eligible old receipts in bounded batches |

Each word-shaped guess in an enabled channel makes **one RPC**, returning only
an outcome and the fields needed for its reply. The used-word array stays in
PostgreSQL; it is never downloaded for guess validation. Start commands read only
the current word. Database errors propagate rather than treating words as missing.

`/kaladont-start` enables gameplay in its channel and starts or resumes its game.
`/kaladont-disable` disables gameplay there without discarding the session.
These commands use the existing command-access model; this release does not
introduce a new administrator-only permission policy. Rankings do not enable
channels. Threads have their own channel IDs and must be enabled independently.

The worker loads enabled channels at startup using 500-row pages and refreshes
the cache every five minutes. Commands update it immediately after successful
writes. Unconfigured channels are skipped before queueing or contacting Supabase;
queued messages recheck the cache after preceding commands. SQL also enforces
channel/guild enablement, so a stale positive cache cannot bypass a disable.
Direct database enables become visible on refresh or restart. Refresh failures
preserve the last successful cache and are logged.

## Transactions, replay protection and retention

A guess locks its session row. Duplicate Discord message IDs return `duplicate`;
scoring, the receipt and the updated session commit or roll back together. Parallel
guesses validate against the latest locked state. Winning sessions become inactive;
a subsequent start assigns a new UUID and start time. Development-mode guesses
persist with zero points.

Message timestamps are decoded from Discord snowflakes. Messages older than
**24 hours**, more than five minutes in the future, or predating the current
game are ignored. A duplicate receipt takes precedence and produces no reply.
Keep the database clock synchronized. Previously unaccepted guesses are validated
against current state; clients do not submit a revision or claim victory.

The bot runs receipt cleanup at startup and hourly. Each run deletes up to ten
batches of 1,000 receipts, then yields until the next run. Only receipts older than
**30 days** whose game is no longer active are eligible. Active-game receipts,
players, rankings, scores and session used-word lists are preserved. Retained rows
may therefore exceed 30 days for a long-running game or a cleanup backlog.

Cleanup uses an indexed cutoff and skips locked receipts. A failed batch is logged
and retried on the next scheduled run. If the worker is offline, cleanup pauses;
it resumes on startup. For a larger backlog, an owner/service role can call:

```sql
select public.kaladont_prune_receipts(1000);
```

Pruning does not reset scores. The 24-hour replay window remains enforced after
receipts have been removed. PostgreSQL can reuse space from deleted rows after
normal vacuuming; allocated database files need not shrink immediately.

## Verification

```sh
mise exec -- dart test
python3 tool/test_database.py
# Optional full-dictionary timing checks (reads local public.words):
python3 tool/test_database.py --benchmark
```

SQL checks create and drop a disposable database and do not change development
dictionary data or scores. They cover dictionary eligibility/digraphs, exact counts
beyond one API page, duplicate/concurrent turns, rollback, tenant isolation,
channel enablement, retention and stale-message rejection. The benchmark copies
local source words into the disposable database; it is not a hosted load test.

For live verification, use two guilds/channels, check rankings, restart mid-game,
and test disabling/re-enabling a channel. SIGINT/SIGTERM drains queued work and
background maintenance before closing clients. Keep one Gateway worker per token;
replicas still require coordinated event ownership. A crash after a committed
turn can still lose its Discord reply; no durable response outbox is implemented.
