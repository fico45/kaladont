-- Stop the worker before applying: this migration rebuilds the derived dictionary.
-- Source words, sessions, scores and receipts are preserved.

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
    select row_number() over (order by d.word), d.word
    from public.kaladont_dictionary d
    where d.can_start
      and exists (
        select 1 from public.kaladont_dictionary c
        where c.prefix = d.suffix
          and c.word <> d.word
      );
  analyze public.kaladont_dictionary;
  analyze public.kaladont_start_words;
end;
$$;

-- CREATE OR REPLACE preserves the existing service-only grants.
select public.kaladont_refresh_dictionary();
