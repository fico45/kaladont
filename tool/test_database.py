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
CREATE TABLE public.words (word text NOT NULL, type text NOT NULL);
GRANT USAGE ON SCHEMA public TO service_role;
GRANT SELECT ON public.words TO service_role;
"""
    sql(name, setup)
    for migration in sorted((root / 'supabase/migrations').glob('*.sql')):
        sql(name, migration.read_text())
    sql(name, (root / 'test/sql/game_transactions.sql').read_text())
    sql(name, "SET ROLE service_role; SELECT public.kaladont_start_game(1,30,'telefon'); SELECT public.kaladont_start_game(1,31,'telefon');")

    def race(channel, message):
        query = f"""SET ROLE service_role;
SELECT public.kaladont_commit_turn(1,{channel},
 (SELECT game_id FROM public.kaladont_sessions WHERE guild_id=1 AND channel_id={channel}),
 0,{message},50,'oniks','Race','',false,false);"""
        result = subprocess.run(['docker', 'exec', '-i', '-u', 'postgres', args.container,
                                 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', name],
                                input=query, text=True, capture_output=True, check=True)
        return result.stdout.strip()

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda msg: race(30, msg), [301, 302]))
        assert sorted(results) == ['applied', 'conflict'], results
        results = list(pool.map(lambda msg: race(31, msg), [303, 303]))
        assert sorted(results) == ['applied', 'duplicate'], results
    sql(name, """DO $$ BEGIN
      ASSERT (SELECT score FROM public.guild_players WHERE guild_id=1 AND discord_user_id=50)=2;
      ASSERT (SELECT count(*) FROM public.kaladont_turns WHERE channel_id IN (30,31))=2;
    END $$;""")
    print('Database regression tests passed, including concurrent turns and duplicate delivery.')
finally:
    sql('postgres', f'DROP DATABASE {name} WITH (FORCE);')
