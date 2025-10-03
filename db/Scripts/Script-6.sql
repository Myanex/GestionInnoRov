BEGIN;
SELECT pg_advisory_xact_lock(74123001);

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL idle_in_transaction_session_timeout = '120s';
SET LOCAL client_min_messages = notice;
SET LOCAL search_path = public, app;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class c   ON c.oid  = con.conrelid
    JOIN pg_namespace n  ON n.oid  = c.relnamespace
    JOIN pg_class rc  ON rc.oid = con.confrelid
    JOIN pg_namespace rn ON rn.oid = rc.relnamespace
    WHERE con.contype='f'
      AND n.nspname='public'  AND c.relname='perfiles'
      AND rn.nspname='public' AND rc.relname='pilotos'
  LOOP
    EXECUTE format('ALTER TABLE public.perfiles DROP CONSTRAINT %I', r.conname);
    RAISE NOTICE 'FK % eliminada', r.conname;
  END LOOP;
END $$;

COMMIT;
