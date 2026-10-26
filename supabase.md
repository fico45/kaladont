# Supabase setup

The bot requires a server-only secret/service-role API key. Keep it in runtime
secrets. Public anon/authenticated roles cannot execute the bot's mutating RPCs;
RLS is enabled on its guild, player, session and turn tables. The ranking view
uses invoker permissions.

## Dictionary prerequisite

The existing `public.words` table must exist before applying migrations, with at
least `word text` and `type text` columns. Other columns (such as `base_word`,
`source_code` and an ID) are preserved. Import your dictionary separately; the
migrations do not replace or delete its data.

Words are matched case-insensitively. Supported types are `imenica`, `glagol`
and `pridjev`; initial words use the first two types. Counts deduplicate words,
exclude every word used in the game and honor Croatian digraph boundaries.
They run in PostgreSQL, so PostgREST's result-row limit cannot cause false wins.
The prefix index supports continuation lookups. Random selection happens in one
database query and returns an explicit empty result if no playable word exists.

## Apply migrations

For the configured local Supabase project:

```sh
supabase start
supabase migration up --local
supabase migration list --local
```

Apply both files from `supabase/migrations/` in timestamp order. The first adopts
or creates the existing guild/ranking schema without replacing scores; the second
adds durable games. No database reset is needed. If applying through a remote
Supabase SQL Editor, run each file in a transaction, in order, and maintain your
migration history using your normal deployment process. For a linked project,
review `supabase db push --dry-run` before deploying migrations. Stop the old bot
during deployment; its separate scoring calls do not participate in turn receipts.

The migrations create:

| Object | Purpose |
| --- | --- |
| `discord_guilds` | Guild metadata and `enabled` switch |
| `discord_players`, `guild_players` | Player profiles and guild scores |
| `guild_player_rankings` | Tenant-filtered ranking reads |
| `kaladont_sessions` | One durable session per guild/channel; revision and game UUID prevent stale writes |
| `kaladont_turns` | Accepted Discord message IDs and award receipts |
| `kaladont_start_game` | Atomically starts a new game without overwriting an active game |
| `kaladont_commit_turn` | Locks/checks the expected session, records the receipt, awards points and updates the session in one transaction |
| `kaladont_random_word`, `kaladont_count_continuations` | Dictionary selection and exact continuation counts |

A failed transaction changes neither the session nor the score/receipt. Retried
commits with the same Discord message ID return `duplicate`. Concurrent turns
against an old revision return `conflict`. New games get new UUIDs, so an old
turn cannot overwrite a restarted game. Winning sessions remain as inactive
rows and are replaced on the next start. Development-mode turns are durable
but award zero points.

Guild metadata refreshes preserve the `enabled` flag. Setting it to `false`
blocks starting games and committing new turns in that guild. The old
`award_kaladont_points` helper remains for the transactional function and is
restricted to the service role. Deploy the updated bot with these migrations;
do not run an old bot alongside it.

Turn receipts are retained to preserve replay protection. Do not prune them
without choosing an explicit replay/retention policy. Existing legacy tables
(`players`, `servers`, `discord_servers`) are left untouched. Migrate any legacy
scores separately after verifying their guild ownership.

## Verify

```sh
python3 tool/test_database.py
```

This uses an isolated database and does not change development dictionary data
or scores. For a live smoke test, use two guilds and two channels, check independent
rankings, restart the bot during a game, and verify the next turn uses the saved
word. SIGINT/SIGTERM drains current work before closing connections. A saved turn
may lack a Discord reply if the process crashes after the database commit;
response delivery is not transactional with PostgreSQL.
