-- Initial schema for Kaladont. No prior deployed schema is required.
-- Import source words separately, then call kaladont_refresh_dictionary().
create table if not exists public.words (
  id bigint generated always as identity primary key,
  word text not null,
  base_word text not null default '',
  source_code text not null default '',
  type text not null
);
alter table public.words enable row level security;
revoke all on public.words from public, anon, authenticated;
grant all on public.words to service_role;
grant usage, select on sequence public.words_id_seq to service_role;

create table if not exists public.discord_guilds (
  guild_id bigint primary key,
  name text not null,
  icon_url text,
  enabled boolean not null default true,
  default_channel_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.discord_players (
  discord_user_id bigint primary key,
  username text not null,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.guild_players (
  guild_id bigint not null references public.discord_guilds(guild_id)
    on delete cascade,
  discord_user_id bigint not null references public.discord_players(discord_user_id)
    on delete cascade,
  score integer not null default 0 check (score >= 0),
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (guild_id, discord_user_id)
);

create index if not exists guild_players_ranking_idx
  on public.guild_players (guild_id, score desc);

create or replace view public.guild_player_rankings as
select
  gp.guild_id,
  gp.discord_user_id,
  p.username,
  p.avatar_url,
  gp.score
from public.guild_players gp
join public.discord_players p using (discord_user_id);

create or replace function public.award_kaladont_points(
  p_guild_id bigint,
  p_discord_user_id bigint,
  p_points integer,
  p_username text,
  p_avatar_url text
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if p_points <= 0 then
    raise exception 'Points must be positive';
  end if;

  insert into public.discord_players (
    discord_user_id,
    username,
    avatar_url,
    updated_at
  ) values (
    p_discord_user_id,
    p_username,
    nullif(p_avatar_url, ''),
    now()
  )
  on conflict (discord_user_id) do update set
    username = excluded.username,
    avatar_url = excluded.avatar_url,
    updated_at = now();

  insert into public.guild_players (
    guild_id,
    discord_user_id,
    score,
    updated_at
  ) values (
    p_guild_id,
    p_discord_user_id,
    p_points,
    now()
  )
  on conflict (guild_id, discord_user_id) do update set
    score = public.guild_players.score + excluded.score,
    updated_at = now();
end;
$$;

alter table public.discord_guilds enable row level security;
alter table public.discord_players enable row level security;
alter table public.guild_players enable row level security;
alter view public.guild_player_rankings set (security_invoker = true);
revoke all on function public.award_kaladont_points(bigint,bigint,integer,text,text) from public, anon, authenticated;
grant execute on function public.award_kaladont_points(bigint,bigint,integer,text,text) to service_role;

grant all on public.discord_guilds, public.discord_players, public.guild_players to service_role;
grant select on public.guild_player_rankings to service_role;

create or replace function public.kaladont_letters(p_word text)
returns text[] language sql immutable strict parallel safe
set search_path = public
as $$
  select array_agg(m[1]) from regexp_matches(lower(p_word), 'dž|lj|nj|.', 'g') m;
$$;

create or replace function public.kaladont_prefix(p_word text)
returns text language sql immutable strict parallel safe
set search_path = public
as $$ select array_to_string((public.kaladont_letters(p_word))[1:2], ''); $$;

create table if not exists public.kaladont_sessions (
  guild_id bigint not null references public.discord_guilds(guild_id) on delete cascade,
  channel_id bigint not null,
  game_id uuid not null default gen_random_uuid(),
  revision integer not null default 0,
  current_word text not null,
  previous_word text,
  last_player_id bigint,
  used_words text[] not null,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  started_at timestamptz not null default date_trunc('milliseconds', clock_timestamp()),
  primary key (guild_id, channel_id)
);
create table if not exists public.kaladont_turns (
  message_id bigint primary key,
  guild_id bigint not null references public.discord_guilds(guild_id) on delete cascade,
  channel_id bigint not null,
  game_id uuid not null,
  player_id bigint not null,
  word text not null,
  points integer not null,
  created_at timestamptz not null default now()
);
alter table public.kaladont_sessions enable row level security;
alter table public.kaladont_turns enable row level security;
grant all on public.kaladont_sessions, public.kaladont_turns to service_role;

create table if not exists public.kaladont_dictionary (
  word text primary key,
  prefix text not null,
  suffix text not null,
  can_start boolean not null
);
create index if not exists kaladont_dictionary_prefix_idx on public.kaladont_dictionary(prefix);
alter table public.kaladont_dictionary enable row level security;
revoke all on public.kaladont_dictionary from public, anon, authenticated;
grant all on public.kaladont_dictionary to service_role;

create table if not exists public.kaladont_start_words (
  slot bigint primary key,
  word text not null unique
);
alter table public.kaladont_start_words enable row level security;
revoke all on public.kaladont_start_words from public, anon, authenticated;
grant all on public.kaladont_start_words to service_role;

create table if not exists public.kaladont_channels (
  guild_id bigint not null references public.discord_guilds(guild_id) on delete cascade,
  channel_id bigint not null,
  enabled boolean not null default true,
  primary key(guild_id, channel_id)
);
alter table public.kaladont_channels enable row level security;
revoke all on public.kaladont_channels from public, anon, authenticated;
grant all on public.kaladont_channels to service_role;

create index if not exists kaladont_turns_retention_idx on public.kaladont_turns(created_at, message_id);

create or replace function public.kaladont_refresh_dictionary()
returns void language plpgsql security invoker
set search_path = public
as $$
begin
  lock table public.kaladont_dictionary in share row exclusive mode;
  lock table public.kaladont_start_words in share row exclusive mode;
  delete from public.kaladont_start_words;
  delete from public.kaladont_dictionary;
  insert into public.kaladont_dictionary(word, prefix, suffix, can_start)
  select word, array_to_string(letters[1:2], ''),
    array_to_string(letters[cardinality(letters)-1:cardinality(letters)], ''), can_start
  from (
    select lower(word) as word, public.kaladont_letters(lower(word)) as letters,
      bool_or(type in ('imenica', 'glagol')) as can_start
    from public.words
    where type in ('imenica', 'glagol', 'pridjev')
      and lower(word) ~ '^[a-zčćđšž]+$'
    group by lower(word)
  ) candidates
  where cardinality(letters) >= 2;
  insert into public.kaladont_start_words(slot, word)
    select row_number() over (order by word), word
    from public.kaladont_dictionary where can_start;
  analyze public.kaladont_dictionary;
  analyze public.kaladont_start_words;
end;
$$;

create or replace function public.kaladont_random_word()
returns text language sql volatile security invoker
set search_path = public
as $$
  -- Materialize the choice so random() is evaluated exactly once, not per row.
  -- Both max(slot) and slot equality use the primary key. One statement/snapshot
  -- sees a consistent pool even while a dictionary refresh commits.
  with choice as materialized (
    select 1 + floor(random() * (select max(slot) from public.kaladont_start_words))::bigint as slot
  )
  select pool.word from public.kaladont_start_words pool join choice using(slot);
$$;
create or replace function public.kaladont_count_continuations(p_prefix text, p_used_words text[])
returns bigint language sql stable security invoker
set search_path = public
as $$
  select count(*) from public.kaladont_dictionary
  where prefix = p_prefix and not (word = any(p_used_words));
$$;

create function public.kaladont_set_channel_enabled(p_guild_id bigint, p_channel_id bigint, p_enabled boolean)
returns void language plpgsql security invoker
set search_path = public
as $$
begin
  if p_enabled and not exists(select from public.discord_guilds where guild_id=p_guild_id and enabled) then
    raise exception 'Guild is disabled or missing';
  end if;
  insert into public.kaladont_channels(guild_id,channel_id,enabled)
    values(p_guild_id,p_channel_id,p_enabled)
    on conflict(guild_id,channel_id) do update set enabled=excluded.enabled;
end;
$$;
revoke all on function public.kaladont_set_channel_enabled(bigint,bigint,boolean) from public, anon, authenticated;
grant execute on function public.kaladont_set_channel_enabled(bigint,bigint,boolean) to service_role;

create or replace function public.kaladont_start_game(p_guild_id bigint, p_channel_id bigint, p_word text)
returns boolean language plpgsql security invoker
set search_path = public
as $$
declare affected integer;
begin
  if not exists (select 1 from public.discord_guilds where guild_id = p_guild_id and enabled) then
    raise exception 'Guild is disabled or missing';
  end if;
  if p_word is null or p_word !~ '^[a-zčćđšž]+$' or cardinality(public.kaladont_letters(p_word)) < 2 then
    raise exception 'Invalid starting word';
  end if;
  perform public.kaladont_set_channel_enabled(p_guild_id, p_channel_id, true);
  insert into public.kaladont_sessions (guild_id, channel_id, current_word, used_words)
  values (p_guild_id, p_channel_id, p_word, array[p_word])
  on conflict (guild_id, channel_id) do update set
    game_id = gen_random_uuid(), revision = 0, current_word = p_word,
    previous_word = null, last_player_id = null, started_at = date_trunc('milliseconds', clock_timestamp()), used_words = array[p_word],
    active = true, updated_at = now()
  where not public.kaladont_sessions.active;
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create or replace function public.kaladont_guess(
  p_guild_id bigint, p_channel_id bigint, p_message_id bigint, p_player_id bigint,
  p_word text, p_username text, p_avatar_url text, p_is_dev boolean
)
returns jsonb language plpgsql security invoker
set search_path = public
as $$
declare
  s public.kaladont_sessions%rowtype;
  letters text[];
  expected text;
  next_prefix text;
  answers bigint;
  points integer;
  message_time timestamptz;
begin
  select * into s from public.kaladont_sessions
    where guild_id = p_guild_id and channel_id = p_channel_id for update;
  if exists (select 1 from public.kaladont_turns where message_id = p_message_id) then
    return jsonb_build_object('status', 'duplicate');
  end if;
  if not exists (select 1 from public.kaladont_channels
    where guild_id=p_guild_id and channel_id=p_channel_id and enabled) then
    return jsonb_build_object('status', 'channelDisabled');
  end if;
  if s.game_id is null or not s.active then
    return jsonb_build_object('status', 'noActiveGame');
  end if;
  if not exists (select 1 from public.discord_guilds where guild_id = p_guild_id and enabled) then
    return jsonb_build_object('status', 'disabled');
  end if;
  -- The timestamp comes from Discord's message snowflake, never a caller-supplied date.
  if p_message_id is null or p_message_id <= 0 then
    return jsonb_build_object('status', 'staleMessage');
  end if;
  message_time := to_timestamp(((p_message_id >> 22) + 1420070400000)::double precision / 1000);
  if message_time < clock_timestamp() - interval '24 hours'
    or message_time > clock_timestamp() + interval '5 minutes'
    or message_time < s.started_at then
    return jsonb_build_object('status', 'staleMessage');
  end if;
  p_word := lower(btrim(p_word));
  if p_word is null or p_word !~ '^[a-zčćđšž]+$'
    or cardinality(public.kaladont_letters(p_word)) < 2 then
    return jsonb_build_object('status', 'invalidWord');
  end if;
  letters := public.kaladont_letters(s.current_word);
  expected := array_to_string(letters[cardinality(letters)-1:cardinality(letters)], '');
  if public.kaladont_prefix(p_word) <> expected then
    return jsonb_build_object('status', 'wrongPrefix', 'word', s.current_word);
  end if;
  if not p_is_dev and s.last_player_id = p_player_id then
    return jsonb_build_object('status', 'samePlayer', 'word', s.current_word);
  end if;
  if p_word = any(s.used_words) then
    return jsonb_build_object('status', 'reusedWord');
  end if;
  select suffix into next_prefix from public.kaladont_dictionary where word = p_word;
  if not found then
    return jsonb_build_object('status', 'unknownWord', 'expected', expected);
  end if;
  answers := public.kaladont_count_continuations(next_prefix, s.used_words || p_word);
  points := case when p_is_dev then 0 when answers = 0 then 3 else 1 end;
  insert into public.kaladont_turns(message_id, guild_id, channel_id, game_id, player_id, word, points)
    values(p_message_id, p_guild_id, p_channel_id, s.game_id, p_player_id, p_word, points);
  if points > 0 then
    perform public.award_kaladont_points(p_guild_id, p_player_id, points, p_username, p_avatar_url);
  end if;
  update public.kaladont_sessions set
    previous_word = current_word, current_word = p_word, last_player_id = p_player_id,
    used_words = used_words || p_word, revision = revision + 1, active = answers <> 0, updated_at = now()
    where guild_id = p_guild_id and channel_id = p_channel_id;
  return jsonb_build_object('status', case when answers=0 then 'victory' else 'applied' end,
    'word', p_word, 'answers', answers);
end;
$$;
create function public.kaladont_prune_receipts(p_batch_size integer default 1000)
returns integer language plpgsql security invoker
set search_path = public
as $$
declare removed integer;
begin
  if p_batch_size is null or p_batch_size < 1 or p_batch_size > 10000 then
    raise exception 'Batch size must be between 1 and 10000';
  end if;
  with candidates as materialized (
    select t.message_id from public.kaladont_turns t
    where t.created_at < statement_timestamp() - interval '30 days'
      and not exists(select from public.kaladont_sessions s where s.guild_id=t.guild_id
        and s.channel_id=t.channel_id and s.game_id=t.game_id and s.active)
    order by t.created_at, t.message_id limit p_batch_size
    for update of t skip locked
  )
  delete from public.kaladont_turns t using candidates c
    where t.message_id=c.message_id;
  get diagnostics removed = row_count;
  return removed;
end;
$$;
revoke all on function public.kaladont_prune_receipts(integer) from public, anon, authenticated;
grant execute on function public.kaladont_prune_receipts(integer) to service_role;

revoke all on function public.kaladont_letters(text), public.kaladont_prefix(text),
  public.kaladont_refresh_dictionary(), public.kaladont_random_word(),
  public.kaladont_count_continuations(text,text[]),
  public.kaladont_start_game(bigint,bigint,text),
  public.kaladont_guess(bigint,bigint,bigint,bigint,text,text,text,boolean)
  from public, anon, authenticated;
grant execute on function public.kaladont_letters(text), public.kaladont_prefix(text),
  public.kaladont_refresh_dictionary(), public.kaladont_random_word(),
  public.kaladont_count_continuations(text,text[]),
  public.kaladont_start_game(bigint,bigint,text),
  public.kaladont_guess(bigint,bigint,bigint,bigint,text,text,text,boolean)
  to service_role;

select public.kaladont_refresh_dictionary();

revoke all on public.discord_guilds, public.discord_players, public.guild_players,
  public.guild_player_rankings, public.kaladont_sessions, public.kaladont_turns
  from public, anon, authenticated;
