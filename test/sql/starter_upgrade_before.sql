-- The runner wraps the populated upgrade in a transaction and rolls it back.
do $$ begin
  assert current_database() like 'kaladont_test_%';
end $$;
insert into public.words(word, type) values
  ('telefon', 'imenica'), ('oniks', 'pridjev'), ('ab', 'imenica');
select public.kaladont_refresh_dictionary();
do $$ begin
  assert (select count(*) from public.kaladont_start_words) = 2,
    'baseline must include the self-only starter before upgrading';
end $$;
create temporary table upgrade_source as table public.words;
