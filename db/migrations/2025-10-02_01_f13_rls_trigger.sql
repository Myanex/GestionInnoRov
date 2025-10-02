-- =====================================================================
-- MIGRACIÓN F1.3 — Pilotos (Hardening RLS + Trigger robusto) — REVISADA
-- Archivo sugerido: db/migrations/2025-10-02_01_f13_rls_trigger.sql
-- Objetivo: que el trigger funcione aunque el rol llamante no tenga SELECT sobre public.centros
-- Cambios clave:
--   • Función del trigger como SECURITY DEFINER, con SET search_path fijo a "pg_catalog, public"
--   • Nombres cualificados (public.centros)
--   • OWNER estable (postgres), REVOKE/GRANT EXECUTE a roles típicos de Supabase
--   • Idempotente; asegura el trigger y su vinculación a la función
-- =====================================================================

BEGIN;
SELECT pg_advisory_xact_lock(74123001);

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL idle_in_transaction_session_timeout = '120s';
SET LOCAL client_min_messages = notice;
SET LOCAL search_path = public, app;

-- STEP 1 — (Re)definir la función del trigger como SECURITY DEFINER con search_path fijo
CREATE OR REPLACE FUNCTION public.fn_pilotos_sync_empresa_from_centro()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.centro_id IS DISTINCT FROM OLD.centro_id THEN
    IF NEW.centro_id IS NULL THEN
      NEW.empresa_id := NULL;
    ELSE
      SELECT ce.empresa_id INTO NEW.empresa_id
      FROM public.centros AS ce
      WHERE ce.id = NEW.centro_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- STEP 1.1 — Establecer OWNER a postgres (idempotente; atrapa errores si no aplica)
DO $$
BEGIN
  BEGIN
    EXECUTE 'ALTER FUNCTION public.fn_pilotos_sync_empresa_from_centro() OWNER TO postgres';
    RAISE NOTICE 'OWNER de la función establecido a postgres';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ALTER FUNCTION OWNER falló/omitido: %', SQLERRM;
  END;
END$$;

-- STEP 1.2 — REVOKE/GRANT EXECUTE (roles típicos de Supabase); opcional: app_user (comentado)
DO $$
BEGIN
  BEGIN
    EXECUTE 'REVOKE ALL ON FUNCTION public.fn_pilotos_sync_empresa_from_centro() FROM PUBLIC';
    RAISE NOTICE 'REVOKE PUBLIC OK';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'REVOKE PUBLIC omitido: %', SQLERRM;
  END;

  -- Conceder EXECUTE a roles estándar si existen
  PERFORM 1;
  BEGIN EXECUTE 'GRANT EXECUTE ON FUNCTION public.fn_pilotos_sync_empresa_from_centro() TO postgres';       EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'GRANT postgres omitido: %', SQLERRM; END;
  BEGIN EXECUTE 'GRANT EXECUTE ON FUNCTION public.fn_pilotos_sync_empresa_from_centro() TO authenticated';  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'GRANT authenticated omitido: %', SQLERRM; END;
  BEGIN EXECUTE 'GRANT EXECUTE ON FUNCTION public.fn_pilotos_sync_empresa_from_centro() TO anon';           EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'GRANT anon omitido: %', SQLERRM; END;
  BEGIN EXECUTE 'GRANT EXECUTE ON FUNCTION public.fn_pilotos_sync_empresa_from_centro() TO service_role';   EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'GRANT service_role omitido: %', SQLERRM; END;

  -- Si tienes un rol de app propio, descomenta la línea siguiente:
  -- BEGIN EXECUTE 'GRANT EXECUTE ON FUNCTION public.fn_pilotos_sync_empresa_from_centro() TO app_user';    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'GRANT app_user omitido: %', SQLERRM; END;
END$$;

-- STEP 2 — Asegurar trigger y su vinculación a la función (idempotente)
DO $$
DECLARE
  v_bound regprocedure;
BEGIN
  SELECT t.tgfoid::regprocedure INTO v_bound
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'pilotos'
    AND t.tgname  = 'tg_pilotos_sync_empresa_from_centro_biu';

  IF v_bound IS NULL THEN
    EXECUTE '
      CREATE TRIGGER tg_pilotos_sync_empresa_from_centro_biu
      BEFORE INSERT OR UPDATE ON public.pilotos
      FOR EACH ROW
      EXECUTE FUNCTION public.fn_pilotos_sync_empresa_from_centro()
    ';
    RAISE NOTICE 'Trigger creado y vinculado a la función';
  ELSIF v_bound <> 'public.fn_pilotos_sync_empresa_from_centro()'::regprocedure THEN
    EXECUTE 'DROP TRIGGER tg_pilotos_sync_empresa_from_centro_biu ON public.pilotos';
    EXECUTE '
      CREATE TRIGGER tg_pilotos_sync_empresa_from_centro_biu
      BEFORE INSERT OR UPDATE ON public.pilotos
      FOR EACH ROW
      EXECUTE FUNCTION public.fn_pilotos_sync_empresa_from_centro()
    ';
    RAISE NOTICE 'Trigger re-vinculado a la función correcta';
  ELSE
    RAISE NOTICE 'Trigger ya vinculado a la función correcta';
  END IF;
END$$;

COMMIT;
