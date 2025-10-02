-- MIGRACIÓN F1.2 — Invertir FK a pilotos(id) → perfiles(id)
-- Semántica: ON UPDATE CASCADE, ON DELETE RESTRICT (conservador)

BEGIN;
SELECT pg_advisory_xact_lock(74123001);

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL idle_in_transaction_session_timeout = '120s';
SET LOCAL client_min_messages = notice;
SET LOCAL search_path = public, app;

-- STEP 0 — Asegurar que pilotos.id NO tenga DEFAULT (por seguridad)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_attrdef d
    JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
    WHERE d.adrelid = 'public.pilotos'::regclass
      AND a.attname = 'id'
  ) THEN
    EXECUTE 'ALTER TABLE public.pilotos ALTER COLUMN id DROP DEFAULT';
    RAISE NOTICE 'DEFAULT eliminado en public.pilotos.id';
  ELSE
    RAISE NOTICE 'Sin DEFAULT en public.pilotos.id (ok)';
  END IF;
END $$;

-- STEP 1 — Crear (si falta) FK nueva: pilotos(id) → perfiles(id)  (NOT VALID, luego VALIDATE)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='pilotos'
      AND con.contype='f'
      AND con.conname='fk_pilotos_id_perfiles'
  ) THEN
    EXECUTE '
      ALTER TABLE public.pilotos
      ADD CONSTRAINT fk_pilotos_id_perfiles
      FOREIGN KEY (id) REFERENCES public.perfiles(id)
      ON UPDATE CASCADE ON DELETE RESTRICT
      NOT VALID
    ';
    RAISE NOTICE 'FK fk_pilotos_id_perfiles creada (NOT VALID)';
  ELSE
    RAISE NOTICE 'FK fk_pilotos_id_perfiles ya existe';
  END IF;
END $$;

-- STEP 1.1 — VALIDATE nueva FK si aún no está validada
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='pilotos'
      AND con.contype='f'
      AND con.conname='fk_pilotos_id_perfiles'
      AND NOT con.convalidated
  ) THEN
    EXECUTE 'ALTER TABLE public.pilotos VALIDATE CONSTRAINT fk_pilotos_id_perfiles';
    RAISE NOTICE 'FK fk_pilotos_id_perfiles VALIDADA';
  ELSE
    RAISE NOTICE 'FK fk_pilotos_id_perfiles ya estaba validada';
  END IF;
END $$;

-- STEP 2 — DROP de la FK antigua (perfiles → pilotos), si existe
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='perfiles'
      AND con.contype='f'
      AND con.conname='fk_perfiles_id_pilotos'
  ) THEN
    EXECUTE 'ALTER TABLE public.perfiles DROP CONSTRAINT fk_perfiles_id_pilotos';
    RAISE NOTICE 'FK fk_perfiles_id_pilotos eliminada';
  ELSE
    RAISE NOTICE 'FK fk_perfiles_id_pilotos no existe (ok)';
  END IF;
END $$;

COMMIT;
