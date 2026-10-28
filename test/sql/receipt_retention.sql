begin;
-- One old receipt from an active game must survive; completed games may be pruned.
update public.kaladont_turns set created_at=now()-interval '31 days'
  where message_id in (public.test_message(100),public.test_message(200));
insert into public.kaladont_turns(message_id,guild_id,channel_id,game_id,player_id,word,points,created_at)
select ((floor(extract(epoch from now()-interval '31 days')*1000)::bigint-1420070400000)<<22)+n,
  1,11,gen_random_uuid(),42,'onja',3,now()-interval '31 days'
from generate_series(700,701) n;
insert into public.kaladont_turns(message_id,guild_id,channel_id,game_id,player_id,word,points,created_at)
values(public.test_message(702),1,11,gen_random_uuid(),42,'onja',3,now()-interval '29 days');
set role service_role;
do $$ declare removed integer; old_message bigint; recent_message bigint; future_message bigint; begin
  begin
    perform public.kaladont_prune_receipts(10001);
    raise exception 'Expected invalid batch';
  exception when raise_exception then
    assert sqlerrm='Batch size must be between 1 and 10000';
  end;
  removed := public.kaladont_prune_receipts(1);
  assert removed=1, format('Expected one eligible receipt, removed %s',removed);
  assert public.kaladont_prune_receipts(1000)=2;
  assert public.kaladont_prune_receipts(1000)=0;
  assert exists(select from public.kaladont_turns where message_id=public.test_message(100)), 'active-game receipt';
  assert not exists(select from public.kaladont_turns where message_id=public.test_message(200)), 'completed-game receipt';
  assert exists(select from public.kaladont_turns where message_id=public.test_message(702)), 'within retention';
  assert (select score from public.guild_players where guild_id=1 and discord_user_id=42)=1;

  old_message := ((floor(extract(epoch from now()-interval '31 days')*1000)::bigint-1420070400000)<<22)+700;
  assert not exists(select from public.kaladont_turns where message_id=old_message);
  -- Even a game that has been active longer than the replay window rejects old messages.
  update public.kaladont_sessions set started_at=now()-interval '40 days' where guild_id=1 and channel_id=11;
  assert public.kaladont_guess(1,11,old_message,42,'onja','Replay','',false)->>'status'='staleMessage';
  assert not exists(select from public.kaladont_turns where message_id=old_message);
  -- A recent message predating the new game must also be rejected.
  update public.kaladont_sessions set started_at=now() where guild_id=1 and channel_id=11;
  recent_message := ((floor(extract(epoch from now()-interval '10 minutes')*1000)::bigint-1420070400000)<<22);
  assert public.kaladont_guess(1,11,recent_message,42,'onja','Replay','',false)->>'status'='staleMessage';
  future_message := ((floor(extract(epoch from now()+interval '10 minutes')*1000)::bigint-1420070400000)<<22);
  assert public.kaladont_guess(1,11,future_message,42,'onja','Replay','',false)->>'status'='staleMessage';
  assert public.kaladont_guess(1,11,0,42,'onja','Replay','',false)->>'status'='staleMessage';
  assert (select revision from public.kaladont_sessions where guild_id=1 and channel_id=11)=0;
  assert not has_function_privilege('anon','public.kaladont_prune_receipts(integer)','execute');
end $$;
rollback;
