set local role service_role;
do $$ begin
  assert (select count(*) from public.kaladont_start_words) = 1;
  assert (select word = 'telefon' and slot = 1 from public.kaladont_start_words),
    'migration must rebuild existing pools without a manual refresh';
  assert exists(select from public.kaladont_dictionary where word = 'ab'),
    'self-only starter remains a legal guess';
  assert not has_function_privilege('anon', 'public.kaladont_refresh_dictionary()', 'EXECUTE');
  assert not has_function_privilege('authenticated', 'public.kaladont_refresh_dictionary()', 'EXECUTE');
  perform public.kaladont_refresh_dictionary();
end $$;
reset role;
do $$ begin
  assert not exists(
    (table public.words except all table upgrade_source)
    union all
    (table upgrade_source except all table public.words)
  ), 'upgrade must preserve source data';
end $$;
