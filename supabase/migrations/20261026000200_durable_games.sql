-- The dictionary table must already exist with text columns word and type.
-- Functions are invoker rights and restricted to the trusted server role.
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

create index if not exists words_kaladont_prefix_idx
  on public.words (public.kaladont_prefix(word), type);

create or replace function public.kaladont_random_word()
returns text language sql volatile security invoker
set search_path = public
as $$
  select lower(word) from public.words
  where type in ('imenica', 'glagol')
    and lower(word) ~ '^[a-zčćđšž]+$'
    and cardinality(public.kaladont_letters(word)) >= 2
  order by random() limit 1;
$$;

create or replace function public.kaladont_count_continuations(p_prefix text, p_used_words text[])
returns bigint language sql stable security invoker
set search_path = public
as $$
  select count(distinct lower(word)) from public.words
  where public.kaladont_prefix(word) = p_prefix
    and type in ('imenica', 'glagol', 'pridjev')
    and lower(word) ~ '^[a-zčćđšž]+$'
    and cardinality(public.kaladont_letters(word)) >= 2
    and not (lower(word) = any(p_used_words));
$$;

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
  insert into public.kaladont_sessions (guild_id, channel_id, current_word, used_words)
  values (p_guild_id, p_channel_id, p_word, array[p_word])
  on conflict (guild_id, channel_id) do update set
    game_id = gen_random_uuid(), revision = 0, current_word = p_word,
    previous_word = null, last_player_id = null, used_words = array[p_word],
    active = true, updated_at = now()
  where not public.kaladont_sessions.active;
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create or replace function public.kaladont_commit_turn(
  p_guild_id bigint, p_channel_id bigint, p_game_id uuid, p_revision integer,
  p_message_id bigint, p_player_id bigint, p_word text, p_username text,
  p_avatar_url text, p_victory boolean, p_is_dev boolean
)
returns text language plpgsql security invoker
set search_path = public
as $$
declare
  s public.kaladont_sessions%rowtype;
  letters text[];
  expected text;
  answers bigint;
  points integer;
begin
  select * into s from public.kaladont_sessions
    where guild_id = p_guild_id and channel_id = p_channel_id for update;
  -- Check receipts after acquiring the channel lock so concurrent deliveries see the committed receipt.
  if exists (select 1 from public.kaladont_turns where message_id = p_message_id) then
    return 'duplicate';
  end if;
  if s.game_id is null or not s.active or s.game_id <> p_game_id or s.revision <> p_revision then
    return 'conflict';
  end if;
  if not exists (select 1 from public.discord_guilds where guild_id = p_guild_id and enabled) then
    raise exception 'Guild is disabled or missing';
  end if;
  letters := public.kaladont_letters(s.current_word);
  expected := array_to_string(letters[cardinality(letters)-1:cardinality(letters)], '');
  if p_word is null or p_word !~ '^[a-zčćđšž]+$' or cardinality(public.kaladont_letters(p_word)) < 2
    or public.kaladont_prefix(p_word) <> expected or p_word = any(s.used_words)
    or (not p_is_dev and s.last_player_id = p_player_id) then
    return 'conflict';
  end if;
  if not exists (select 1 from public.words where lower(word) = p_word
      and type in ('imenica', 'glagol', 'pridjev')) then
    return 'conflict';
  end if;
  letters := public.kaladont_letters(p_word);
  answers := public.kaladont_count_continuations(
    array_to_string(letters[cardinality(letters)-1:cardinality(letters)], ''), s.used_words || p_word);
  if p_victory is distinct from (answers = 0) then return 'conflict'; end if;
  points := case when p_is_dev then 0 when p_victory then 3 else 1 end;
  insert into public.kaladont_turns (message_id, guild_id, channel_id, game_id, player_id, word, points)
    values (p_message_id, p_guild_id, p_channel_id, p_game_id, p_player_id, p_word, points);
  if points > 0 then
    perform public.award_kaladont_points(p_guild_id, p_player_id, points, p_username, p_avatar_url);
  end if;
  update public.kaladont_sessions set
    previous_word = current_word, current_word = p_word, last_player_id = p_player_id,
    used_words = used_words || p_word, revision = revision + 1, active = not p_victory, updated_at = now()
    where guild_id = p_guild_id and channel_id = p_channel_id;
  return 'applied';
end;
$$;

revoke all on function public.kaladont_letters(text), public.kaladont_prefix(text),
  public.kaladont_random_word(), public.kaladont_count_continuations(text,text[]),
  public.kaladont_start_game(bigint,bigint,text),
  public.kaladont_commit_turn(bigint,bigint,uuid,integer,bigint,bigint,text,text,text,boolean,boolean)
  from public, anon, authenticated;
grant execute on function public.kaladont_letters(text), public.kaladont_prefix(text),
  public.kaladont_random_word(), public.kaladont_count_continuations(text,text[]),
  public.kaladont_start_game(bigint,bigint,text),
  public.kaladont_commit_turn(bigint,bigint,uuid,integer,bigint,bigint,text,text,text,boolean,boolean)
  to service_role;
