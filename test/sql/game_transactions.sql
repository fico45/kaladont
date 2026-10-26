-- Runs only in a disposable database created by tool/test_database.py.
set role service_role;
do $$ begin
  assert public.kaladont_random_word() is null, 'empty dictionary must terminate';
  assert public.kaladont_count_continuations('on', '{}') = 0;
end $$;
reset role;
insert into public.discord_guilds (guild_id, name) values (1, 'one'), (2, 'two');
insert into public.words (word, type) values
  ('telefon', 'imenica'), ('oniks', 'imenica'), ('ksilofon', 'imenica'),
  ('konj', 'imenica'), ('ljnjiva', 'imenica'), ('ČAŠA', 'imenica');

set role service_role;
do $$
begin
  assert public.kaladont_prefix('ljnjiva') = 'ljnj', 'adjacent digraphs';
  assert public.kaladont_letters('konj') = array['k','o','nj'], 'Croatian letters';
  assert public.kaladont_random_word() is not null, 'random start';
end $$;
reset role;

-- More than one API page, with only later candidates unused.
insert into public.words (word,type)
  select 'ona' || translate(md5(i::text), '0123456789', 'abcdefghij'), 'imenica'
  from generate_series(1,1005) i;
set role service_role;
do $$
declare used text[];
begin
  select array_agg(word) into used from (
    select word from public.words where word like 'on%' and word <> 'oniks' order by word limit 1000
  ) t;
  assert public.kaladont_count_continuations('on', used || array['oniks']) = 5,
    'must see continuations beyond the first 1000 rows';
  assert public.kaladont_count_continuations('ljn', '{}') = 0,
    'prefix must respect adjacent digraphs';
end $$;
reset role;
set role service_role;

do $$
declare s public.kaladont_sessions%rowtype; result text;
begin
  assert public.kaladont_start_game(1,10,'telefon');
  assert not public.kaladont_start_game(1,10,'konj'), 'cannot overwrite active game';
  assert public.kaladont_start_game(1,11,'konj');
  assert public.kaladont_start_game(2,10,'konj');
  select * into s from public.kaladont_sessions where guild_id=1 and channel_id=10;
  result := public.kaladont_commit_turn(1,10,s.game_id,0,100,42,'oniks','Player','',false,false);
  assert result = 'applied';
  assert (select score from public.guild_players where guild_id=1 and discord_user_id=42) = 1;
  assert (select current_word from public.kaladont_sessions where guild_id=1 and channel_id=10) = 'oniks';
  assert (select current_word from public.kaladont_sessions where guild_id=1 and channel_id=11) = 'konj';
  assert (select current_word from public.kaladont_sessions where guild_id=2 and channel_id=10) = 'konj';
  result := public.kaladont_commit_turn(1,10,s.game_id,0,100,42,'oniks','Player','',false,false);
  assert result = 'duplicate';
  assert (select score from public.guild_players where guild_id=1 and discord_user_id=42) = 1;
  result := public.kaladont_commit_turn(1,10,s.game_id,0,101,43,'ksilofon','Other','',false,false);
  assert result = 'conflict', 'stale revision';

  -- A new client/process can resume from the persisted row.
  select * into s from public.kaladont_sessions where guild_id=1 and channel_id=10;
  -- Force score failure: transaction must roll back receipt and session, too.
  begin
    perform public.kaladont_commit_turn(1,10,s.game_id,1,102,43,'ksilofon',null,'',false,false);
    raise exception 'Expected failure';
  exception when not_null_violation then null;
  end;
  assert not exists(select from public.kaladont_turns where message_id=102);
  assert (select revision from public.kaladont_sessions where guild_id=1 and channel_id=10) = 1;
  result := public.kaladont_commit_turn(1,10,s.game_id,1,103,43,'ksilofon','Other','',false,true);
  assert result = 'applied';
  assert not exists(select from public.guild_players where guild_id=1 and discord_user_id=43), 'dev scores';
  assert (select revision from public.kaladont_sessions where guild_id=1 and channel_id=10) = 2;
end $$;

reset role;
insert into public.words values ('njiva','imenica'), ('onja','imenica');
set role service_role;

-- Winning and restarting the same channel cannot accept an old game's version.
do $$
declare old_id uuid; new_id uuid; result text;
begin
  assert public.kaladont_start_game(2,20,'konj');
  select game_id into old_id from public.kaladont_sessions where guild_id=2 and channel_id=20;
  -- konj ends in 'onj', so create a matching terminal word.
  result := public.kaladont_commit_turn(2,20,old_id,0,200,44,'onja','Winner','',true,false);
  assert result='applied';
  assert (select score from public.guild_players where guild_id=2 and discord_user_id=44)=3;
  assert not (select active from public.kaladont_sessions where guild_id=2 and channel_id=20);
  assert public.kaladont_start_game(2,20,'konj');
  select game_id into new_id from public.kaladont_sessions where guild_id=2 and channel_id=20;
  assert old_id <> new_id;
  result := public.kaladont_commit_turn(2,20,old_id,0,201,44,'onja','Winner','',true,false);
  assert result='conflict';
end $$;

-- Restrict every mutating RPC to the trusted bot role.
do $$
begin
  assert not has_function_privilege('anon',
    'public.kaladont_commit_turn(bigint,bigint,uuid,integer,bigint,bigint,text,text,text,boolean,boolean)', 'execute');
  assert not has_function_privilege('authenticated',
    'public.kaladont_start_game(bigint,bigint,text)', 'execute');
end $$;
