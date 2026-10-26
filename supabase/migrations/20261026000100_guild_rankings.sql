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
