-- Run only through tool/test_database.py in its disposable database.
begin;
do $$ begin
  assert current_database() like 'kaladont_test_%', 'disposable database required';
end $$;
-- Isolate fixtures; rollback restores the runner's dictionary and derived pools.
delete from public.words;
insert into public.words(word, type) values ('telefon', 'imenica');
set local role service_role;
select public.kaladont_refresh_dictionary();
do $$ begin
  assert public.kaladont_count_continuations('on', array['telefon']) = 0;
  assert not exists(select from public.kaladont_start_words),
    'a dead-end noun must not enter the starter pool';
  assert public.kaladont_random_word() is null,
    'an empty viable pool must terminate with null';
  assert exists(select from public.words where word = 'telefon'),
    'refresh must preserve the source dictionary';
  assert exists(select from public.kaladont_dictionary where word = 'telefon'),
    'dead ends remain legal guesses';
end $$;

-- A two-letter word matches itself, but reuse is illegal.
insert into public.words(word, type) values ('ab', 'imenica');
select public.kaladont_refresh_dictionary();
do $$ begin
  assert public.kaladont_count_continuations('ab', '{}') = 1;
  assert public.kaladont_count_continuations('ab', array['ab']) = 0;
  assert not exists(select from public.kaladont_start_words),
    'self-only continuations must not make either noun viable';
  assert public.kaladont_random_word() is null;
end $$;

-- Synthetic spelling fixtures test both positions in each two-letter suffix.
-- Adjectives can continue a starter even though they cannot start themselves.
insert into public.words(word, type, base_word, source_code) values
  ('bedža', 'imenica', '', ''), ('džak', 'pridjev', '', ''),
  ('bedž', 'imenica', '', ''), ('edža', 'pridjev', '', ''),
  ('bolja', 'imenica', '', ''), ('ljama', 'pridjev', '', ''),
  ('bolj', 'imenica', '', ''), ('oljni', 'pridjev', '', ''),
  ('konja', 'imenica', '', ''), ('njaka', 'pridjev', '', ''),
  ('konj', 'imenica', '', ''), ('onja', 'pridjev', '', ''),
  ('badže', 'imenica', '', ''), ('žena', 'pridjev', '', ''),
  ('balje', 'imenica', '', ''), ('banje', 'imenica', '', ''),
  ('jedar', 'pridjev', '', ''), ('akacija', 'pridjev', '', ''),
  ('da', 'imenica', '', ''), ('dabar', 'pridjev', '', ''),
  ('raditi', 'glagol', '', ''), ('tih', 'pridjev', '', ''),
  ('KONJ', 'imenica', 'konj', 'duplicate-source'),
  ('two words', 'imenica', 'original', 'invalid-shape'),
  ('dž', 'imenica', 'original', 'single-letter'),
  ('neprihvatljivo', 'prilog', 'original', 'ineligible-type');
create temporary table source_before_refresh as table public.words;
create temporary table expected_starters(word text, suffix text);
insert into expected_starters values
  ('bedža', 'dža'), ('bedž', 'edž'), ('bolja', 'lja'), ('bolj', 'olj'),
  ('konja', 'nja'), ('konj', 'onj'), ('da', 'da'), ('raditi', 'ti');
select public.kaladont_refresh_dictionary();
do $$ declare picked text; begin
  assert not exists(
    (select word from expected_starters except select word from public.kaladont_start_words)
    union all
    (select word from public.kaladont_start_words except select word from expected_starters)
  ), 'the pool must contain exactly the viable nouns and verbs';
  assert not exists(
    select from expected_starters e
    join public.kaladont_dictionary d using(word)
    where d.suffix <> e.suffix
      or public.kaladont_count_continuations(e.suffix, array[e.word]) = 0
  ), 'each digraph suffix must have a legal unused continuation';
  assert not exists(
    select from public.kaladont_start_words s
    join public.kaladont_dictionary d using(word)
    where public.kaladont_count_continuations(d.suffix, array[d.word]) = 0
  ), 'every starter must permit a first move';
  assert (select min(slot) = 1 and max(slot) = count(*) from public.kaladont_start_words),
    'filter before numbering so slots remain dense';
  assert not exists(
    (table public.words except all table source_before_refresh)
    union all
    (table source_before_refresh except all table public.words)
  ), 'refresh must preserve every source row and all source metadata';
  assert exists(select from public.kaladont_dictionary where word = 'badže'),
    'dead-end nouns remain legal guesses';
  assert (select count(*) from public.kaladont_dictionary where word = 'konj') = 1,
    'duplicate source spellings remain deduplicated in gameplay';
  for i in 1..100 loop
    picked := public.kaladont_random_word();
    assert picked is not null and exists(select from expected_starters where word = picked),
      'random selection must only return viable starters';
  end loop;
end $$;

-- Repeated refreshes remove stale slots, including when the pool becomes empty.
delete from public.words where type = 'pridjev';
select public.kaladont_refresh_dictionary();
do $$ begin
  assert not exists(select from public.kaladont_start_words);
  assert public.kaladont_random_word() is null;
end $$;
rollback;
