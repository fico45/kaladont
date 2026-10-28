begin;
insert into public.words(word, type) values
  ('Čaša','pridjev'), ('čaša','imenica'), ('ljnjiva','pridjev'),
  ('lijep','pridjev'), ('a','imenica'), ('dž','imenica'), ('two words','imenica'),
  ('neprihvatljivo','prilog');
set role service_role;
select public.kaladont_refresh_dictionary();
do $$ declare picked text; begin
  assert (select count(*) from public.kaladont_dictionary where word='čaša')=1;
  assert (select can_start from public.kaladont_dictionary where word='čaša');
  assert not (select can_start from public.kaladont_dictionary where word='lijep');
  assert (select prefix from public.kaladont_dictionary where word='ljnjiva')='ljnj';
  assert (select suffix from public.kaladont_dictionary where word='konj')='onj';
  assert not exists(select from public.kaladont_dictionary where word in ('a','dž','two words','neprihvatljivo'));
  assert not has_table_privilege('anon','public.kaladont_dictionary','select');
  assert not has_function_privilege('authenticated','public.kaladont_refresh_dictionary()','execute');
  assert (select count(*)=max(slot) from public.kaladont_start_words);
  assert not exists(select from public.kaladont_start_words s
    join public.kaladont_dictionary d using(word) where not d.can_start);
  for i in 1..100 loop
    picked := public.kaladont_random_word();
    assert exists(select from public.kaladont_dictionary where word=picked and can_start);
  end loop;
end $$;
reset role;
-- Rebuilding after removals leaves no holes or stale entries.
delete from public.words where lower(word)='telefon';
set role service_role;
select public.kaladont_refresh_dictionary();
do $$ begin
  assert not exists(select from public.kaladont_start_words where word='telefon');
  assert (select count(*)=max(slot) from public.kaladont_start_words);
end $$;
rollback;
