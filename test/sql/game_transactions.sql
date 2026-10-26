-- Runs only in a disposable database created by tool/test_database.py.
create table public.test_clock as select
  ((floor(extract(epoch from clock_timestamp()) * 1000)::bigint + 60000 - 1420070400000) << 22) as base;
grant select on public.test_clock to service_role;
create function public.test_message(n bigint) returns bigint language sql stable
  as $$ select base + n from public.test_clock $$;
set role service_role;
do $$ begin
  assert public.kaladont_random_word() is null, 'empty dictionary must terminate';
  assert public.kaladont_count_continuations('on', '{}') = 0;
end $$;
reset role;
insert into public.discord_guilds(guild_id,name) values (1,'one'),(2,'two');
insert into public.words(word,type) values
  ('telefon','imenica'),('oniks','imenica'),('ksilofon','imenica'),
  ('konj','imenica'),('ljnjiva','imenica'),('ČAŠA','imenica'),('onja','imenica');
-- More than one API page, with only later candidates unused.
insert into public.words(word,type)
  select 'ona' || translate(md5(i::text), '0123456789', 'abcdefghij'), 'imenica'
  from generate_series(1,1005) i;
set role service_role;
select public.kaladont_refresh_dictionary();
do $$
declare used text[]; r jsonb;
begin
  assert public.kaladont_prefix('ljnjiva')='ljnj';
  assert public.kaladont_letters('konj')=array['k','o','nj'];
  assert public.kaladont_random_word() is not null;
  select array_agg(word) into used from (
    select word from public.words where word like 'ona%' order by word limit 1000
  ) t;
  assert public.kaladont_count_continuations('on', used || array['oniks','onja'])=5;
  assert public.kaladont_count_continuations('ljn','{}')=0;

  assert public.kaladont_start_game(1,10,'telefon');
  assert not public.kaladont_start_game(1,10,'konj');
  perform public.kaladont_set_channel_enabled(1,10,false);
  assert public.kaladont_guess(1,10,public.test_message(89),42,'oniks','Player','',false)->>'status'='channelDisabled';
  assert not public.kaladont_start_game(1,10,'konj'), 're-enable without overwriting session';
  assert (select enabled from public.kaladont_channels where guild_id=1 and channel_id=10);
  assert public.kaladont_start_game(1,11,'konj');
  assert public.kaladont_start_game(2,10,'konj');
  assert public.kaladont_guess(1,10,public.test_message(90),42,'a','Player','',false)->>'status'='invalidWord';
  assert public.kaladont_guess(1,10,public.test_message(91),42,'kuća','Player','',false)->>'status'='wrongPrefix';
  assert public.kaladont_guess(1,10,public.test_message(92),42,'onxyz','Player','',false)->>'status'='unknownWord';
  perform public.kaladont_set_channel_enabled(1,99,true);
  assert public.kaladont_guess(1,99,public.test_message(93),42,'oniks','Player','',false)->>'status'='noActiveGame';
  r := public.kaladont_guess(1,10,public.test_message(100),42,' Oniks ','Player','',false);
  assert r->>'status'='applied';
  assert r->>'word'='oniks';
  assert not r ? 'used_words', 'RPC must return only compact reply data';
  assert (select score from public.guild_players where guild_id=1 and discord_user_id=42)=1;
  assert (select current_word from public.kaladont_sessions where guild_id=1 and channel_id=10)='oniks';
  assert (select current_word from public.kaladont_sessions where guild_id=1 and channel_id=11)='konj';
  assert (select current_word from public.kaladont_sessions where guild_id=2 and channel_id=10)='konj';
  assert public.kaladont_guess(1,10,public.test_message(100),42,'oniks','Player','',false)->>'status'='duplicate';
  assert public.kaladont_guess(1,10,public.test_message(101),42,'ksilofon','Player','',false)->>'status'='samePlayer';
  -- A new client/process resumes the persisted session. Fail scoring to test rollback.
  begin
    perform public.kaladont_guess(1,10,public.test_message(102),43,'ksilofon',null,'',false);
    raise exception 'Expected failure';
  exception when not_null_violation then null;
  end;
  assert not exists(select from public.kaladont_turns where message_id=public.test_message(102));
  assert (select revision from public.kaladont_sessions where guild_id=1 and channel_id=10)=1;
  assert public.kaladont_guess(1,10,public.test_message(103),43,'ksilofon','Other','',true)->>'status'='applied';
  assert not exists(select from public.guild_players where guild_id=1 and discord_user_id=43);
  assert public.kaladont_guess(1,10,public.test_message(104),42,'oniks','Player','',false)->>'status'='reusedWord';
  assert (select revision from public.kaladont_sessions where guild_id=1 and channel_id=10)=2;

  assert public.kaladont_start_game(2,20,'konj');
  r := public.kaladont_guess(2,20,public.test_message(200),44,'onja','Winner','',false);
  assert r->>'status'='victory' and (r->>'answers')::int=0;
  assert (select score from public.guild_players where guild_id=2 and discord_user_id=44)=3;
  assert not (select active from public.kaladont_sessions where guild_id=2 and channel_id=20);
  assert public.kaladont_start_game(2,20,'konj');
  assert public.kaladont_guess(2,20,public.test_message(200),44,'onja','Winner','',false)->>'status'='duplicate';

  assert not has_function_privilege('anon',
    'public.kaladont_guess(bigint,bigint,bigint,bigint,text,text,text,boolean)','execute');
  assert to_regprocedure('public.kaladont_commit_turn(bigint,bigint,uuid,integer,bigint,bigint,text,text,text,boolean,boolean)') is null,
    'fresh schema must not contain the legacy commit RPC';
end $$;
reset role;
update public.discord_guilds set enabled=false where guild_id=2;
set role service_role;
do $$ begin
  assert public.kaladont_guess(2,20,public.test_message(202),44,'onja','Winner','',false)->>'status'='disabled';
end $$;
reset role;
update public.discord_guilds set enabled=true where guild_id=2;
