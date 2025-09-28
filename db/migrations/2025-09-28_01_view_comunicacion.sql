-- File: db/migrations/2025-09-28_01_view_comunicacion.sql
-- F0 — Paso 2: Vista de comunicación de zona (centro ve otros centros de su zona + pilotos activos/inactivos)
-- Idempotente. Compatible con Supabase.

BEGIN;
SELECT pg_advisory_xact_lock(420250928);

CREATE SCHEMA IF NOT EXISTS app;

-- =========================================================
-- FUNC: app.v_comunicacion_zona()
--  - SECURITY DEFINER para leer maestros_centro/pilotos sin RLS
--  - Aplica filtro por rol/empresa/zona DENTRO de la función
--  - Soporta ausencia de public.pilotos (dev/arranque)
-- =========================================================
CREATE OR REPLACE FUNCTION app.v_comunicacion_zona()
RETURNS TABLE (
  empresa_id uuid,
  zona_id uuid,
  centro_id uuid,
  centro_nombre text,
  piloto_id uuid,
  piloto_nombre text,
  piloto_activo boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role text := app.app_current_perfil()->>'role';
  v_emp  uuid := (app.app_current_perfil()->>'empresa_id')::uuid;
  v_ctr  uuid := (app.app_current_perfil()->>'centro_id')::uuid;
  v_zona uuid;
  pilotos_exist boolean := (to_regclass('public.pilotos') IS NOT NULL);
BEGIN
  -- Si no existe maestros_centro, no hay nada que mostrar
  IF to_regclass('public.maestros_centro') IS NULL THEN
    RETURN;
  END IF;

  -- Zona del centro en sesión (si aplica)
  IF v_ctr IS NOT NULL THEN
    SELECT mc.zona_id INTO v_zona
    FROM public.maestros_centro mc
    WHERE mc.id = v_ctr;
  END IF;

  -- ADMIN / DEV / OFICINA → ven todo el catálogo completo
  IF v_role IN ('admin','dev','oficina') THEN
    IF pilotos_exist THEN
      RETURN QUERY
      SELECT
        mc.empresa_id, mc.zona_id, mc.id, mc.nombre,
        p.id, p.nombre, p.activo
      FROM public.maestros_centro mc
      LEFT JOIN public.pilotos p
        ON p.empresa_id = mc.empresa_id
       AND p.centro_id  = mc.id;
    ELSE
      RETURN QUERY
      SELECT
        mc.empresa_id, mc.zona_id, mc.id, mc.nombre,
        NULL::uuid, NULL::text, NULL::boolean
      FROM public.maestros_centro mc;
    END IF;
    RETURN;
  END IF;

  -- CENTRO → misma empresa y misma zona del centro en sesión
  IF v_role = 'centro' AND v_emp IS NOT NULL AND v_zona IS NOT NULL THEN
    IF pilotos_exist THEN
      RETURN QUERY
      SELECT
        mc.empresa_id, mc.zona_id, mc.id, mc.nombre,
        p.id, p.nombre, p.activo
      FROM public.maestros_centro mc
      LEFT JOIN public.pilotos p
        ON p.empresa_id = mc.empresa_id
       AND p.centro_id  = mc.id
      WHERE mc.empresa_id = v_emp
        AND mc.zona_id = v_zona;
    ELSE
      RETURN QUERY
      SELECT
        mc.empresa_id, mc.zona_id, mc.id, mc.nombre,
        NULL::uuid, NULL::text, NULL::boolean
      FROM public.maestros_centro mc
      WHERE mc.empresa_id = v_emp
        AND mc.zona_id = v_zona;
    END IF;
    RETURN;
  END IF;

  -- Otros roles (anon, etc.) → no retornan filas
  RETURN;
END
$$;

-- Por seguridad, si necesitas restringir EXECUTE:
-- REVOKE ALL ON FUNCTION app.v_comunicacion_zona() FROM PUBLIC;
-- GRANT EXECUTE ON FUNCTION app.v_comunicacion_zona() TO anon, authenticated;

-- =========================================================
-- VIEW: public.v_comunicacion_zona (envoltorio para el frontend)
-- =========================================================
DROP VIEW IF EXISTS public.v_comunicacion_zona;
CREATE VIEW public.v_comunicacion_zona AS
SELECT * FROM app.v_comunicacion_zona();

COMMIT;
