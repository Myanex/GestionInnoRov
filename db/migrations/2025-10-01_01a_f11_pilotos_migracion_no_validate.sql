-- =====================================================================
-- Migración F1.1 · Pilotos (Identidad 1:1 + Hardening)
-- Archivo: db/migrations/2025-10-01_01_f11_pilotos_migracion.sql
-- Modo: TRANSACCIONAL + bloqueos prudentes (Supabase friendly)
-- =====================================================================

BEGIN;
SELECT pg_advisory_xact_lock(74123001);
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL idle_in_transaction_session_timeout = '120s';
SET LOCAL client_min_messages = notice;
SET LOCAL search_path = public, app;

-- STEP: 0. Sanity checks (opcionales, no detienen)
-- (No DDL aquí; confiar en preflight)

-- STEP: 1. Quitar DEFAULT de public.pilotos.id si existe (idempotente)
DO $$
DECLARE v_has_default boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_attrdef ad
    JOIN pg_attribute a ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'pilotos'
      AND a.attname = 'id'
  ) INTO v_has_default;

  IF v_has_default THEN
    EXECUTE 'ALTER TABLE public.pilotos ALTER COLUMN id DROP DEFAULT';
    RAISE NOTICE 'DEFAULT en public.pilotos.id eliminado';
  ELSE
    RAISE NOTICE 'Sin DEFAULT en public.pilotos.id (ok)';
  END IF;
END$$;

-- STEP: 2. FK 1:1 desde perfiles(id) hacia pilotos(id) (NOT VALID + VALIDATE)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='perfiles'
      AND con.contype='f'
      AND con.conname='fk_perfiles_id_pilotos'
  ) THEN
    EXECUTE '
      ALTER TABLE public.perfiles
      ADD CONSTRAINT fk_perfiles_id_pilotos
      FOREIGN KEY (id)
      REFERENCES public.pilotos(id)
      ON UPDATE CASCADE
      ON DELETE RESTRICT
      NOT VALID
    ';
    RAISE NOTICE 'FK fk_perfiles_id_pilotos creada en estado NOT VALID';
  ELSE
    RAISE NOTICE 'FK fk_perfiles_id_pilotos ya existe (ok)';
  END IF;
END$$;

-- STEP: 2.1 VALIDATE CONSTRAINT si estaba NOT VALID
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
      AND NOT con.convalidated
  ) THEN
    EXECUTE 'ALTER TABLE public.perfiles VALIDATE CONSTRAINT fk_perfiles_id_pilotos';
    RAISE NOTICE 'FK fk_perfiles_id_pilotos VALIDADA';
  END IF;
END$$;

-- STEP: 3. Trigger para materializar empresa_id desde centro_id en public.pilotos
-- Nota: SECURITY INVOKER por defecto. Si RLS bloquea lecturas a public.centros
-- en entornos de app, considerar en una fase futura SECURITY DEFINER + permisos.
CREATE OR REPLACE FUNCTION public.tg_pilotos_sync_empresa_from_centro()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.centro_id IS DISTINCT FROM OLD.centro_id THEN
    IF NEW.centro_id IS NULL THEN
      NEW.empresa_id := NULL;
    ELSE
      SELECT ce.empresa_id
      INTO NEW.empresa_id
      FROM public.centros ce
      WHERE ce.id = NEW.centro_id;
    END IF;
  END IF;
  RETURN NEW;
END
$fn$;

-- STEP: 3.1 Crear trigger si no existe
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public'
      AND c.relname='pilotos'
      AND t.tgname='tg_pilotos_sync_empresa_from_centro_biu'
  ) THEN
    EXECUTE '
      CREATE TRIGGER tg_pilotos_sync_empresa_from_centro_biu
      BEFORE INSERT OR UPDATE ON public.pilotos
      FOR EACH ROW
      EXECUTE FUNCTION public.tg_pilotos_sync_empresa_from_centro()
    ';
    RAISE NOTICE 'Trigger tg_pilotos_sync_empresa_from_centro_biu creado';
  ELSE
    RAISE NOTICE 'Trigger tg_pilotos_sync_empresa_from_centro_biu ya existe (ok)';
  END IF;
END$$;

-- STEP: 4. Índices útiles (idempotentes)
CREATE INDEX IF NOT EXISTS ix_pilotos_empresa_id ON public.pilotos(empresa_id);
CREATE INDEX IF NOT EXISTS ix_pilotos_centro_id  ON public.pilotos(centro_id);

/*
-- STEP (opcional, comentado): Índice por expresión para rut normalizado si se consulta mucho
-- CREATE INDEX IF NOT EXISTS ix_pilotos_rut_norm
--   ON public.pilotos ((lower(regexp_replace(coalesce(rut,''),'[^0-9kK]','','g'))));
*/

COMMIT;
