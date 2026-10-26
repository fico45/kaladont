#!/usr/bin/env python3
"""Run migrations/regressions in a disposable DB on the specified local container."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import time
from pathlib import Path
import subprocess
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--container', default='supabase_db_kaladont')
parser.add_argument('--benchmark', action='store_true',
                    help='Copy the local source dictionary into the disposable DB and time optimized queries')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
name = 'kaladont_test_' + uuid.uuid4().hex


def sql(database, source):
    subprocess.run(['docker', 'exec', '-i', '-u', 'postgres', args.container,
                    'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', database],
                   input=source, text=True, check=True)


for attempt in range(30):
    ready = subprocess.run(['docker', 'exec', args.container, 'pg_isready', '-U', 'postgres'],
                           capture_output=True)
    if ready.returncode == 0:
        break
    time.sleep(1)
else:
    raise RuntimeError('PostgreSQL did not become ready')

sql('postgres', f'CREATE DATABASE {name};')
try:
    setup = """
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role BYPASSRLS; END IF;
END $$;
GRANT USAGE ON SCHEMA public TO service_role;
"""
    sql(name, setup)
    for migration in sorted((root / 'supabase/migrations').glob('*.sql')):
        sql(name, migration.read_text())
    sql(name, (root / 'test/sql/game_transactions.sql').read_text())
    sql(name, (root / 'test/sql/gameplay_dictionary.sql').read_text())
    sql(name, (root / 'test/sql/receipt_retention.sql').read_text())
    sql(name, "SET ROLE service_role; SELECT public.kaladont_start_game(1,30,'telefon'); SELECT public.kaladont_start_game(1,31,'telefon');")

    def race(channel, message):
        query = f"""SET ROLE service_role;
SELECT public.kaladont_guess(1,{channel},public.test_message({message}),50,'oniks','Race','',false)->>'status';"""
        result = subprocess.run(['docker', 'exec', '-i', '-u', 'postgres', args.container,
                                 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', name],
                                input=query, text=True, capture_output=True, check=True)
        return result.stdout.strip()

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda msg: race(30, msg), [301, 302]))
        assert sorted(results) == ['applied', 'wrongPrefix'], results
        results = list(pool.map(lambda msg: race(31, msg), [303, 303]))
        assert sorted(results) == ['applied', 'duplicate'], results
    sql(name, """DO $$ BEGIN
      ASSERT (SELECT score FROM public.guild_players WHERE guild_id=1 AND discord_user_id=50)=2;
      ASSERT (SELECT count(*) FROM public.kaladont_turns WHERE channel_id IN (30,31))=2;
    END $$;""")
    if args.benchmark:
        dictionary = subprocess.run(
            ['docker', 'exec', '-u', 'postgres', args.container, 'psql', '-X', '-qAt',
             '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-c',
             'COPY (SELECT word,type FROM public.words) TO STDOUT WITH CSV'],
            text=True, capture_output=True, check=True).stdout
        sql(name, 'TRUNCATE public.words;\nCOPY public.words(word,type) FROM STDIN WITH CSV;\n'
            + dictionary + '\\.\nSELECT public.kaladont_refresh_dictionary();')
        sql(name, """
SELECT count(*) AS gameplay_words FROM public.kaladont_dictionary;
SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS total_size
  FROM pg_statio_user_tables WHERE relname IN ('kaladont_dictionary','kaladont_start_words');
EXPLAIN (ANALYZE, BUFFERS) SELECT suffix FROM public.kaladont_dictionary WHERE word='kuća';
EXPLAIN (ANALYZE, BUFFERS) SELECT public.kaladont_count_continuations('ka',ARRAY['kuća']);
EXPLAIN (ANALYZE, BUFFERS) SELECT public.kaladont_random_word();
EXPLAIN (ANALYZE, BUFFERS)
  WITH choice AS MATERIALIZED (
    SELECT 1+floor(random()*(SELECT max(slot) FROM public.kaladont_start_words))::bigint AS slot
  ) SELECT pool.word FROM public.kaladont_start_words pool JOIN choice USING(slot);
""")
    print('Database regression tests passed, including concurrent turns and duplicate delivery.')
finally:
    sql('postgres', f'DROP DATABASE {name} WITH (FORCE);')
