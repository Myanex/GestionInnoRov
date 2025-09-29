-- File: db/migrations/2025-09-29_03_merge_maestros_to_canonic.sql
-- Fusión segura: maestros_* → canónicas (empresas/centros), actualización de vista/función y alias como vistas.
-- Idempotente y transaccional.

BEGIN;
SELECT pg_advisory_xact_lock(420250930);

CREATE SCHEMA IF NOT EXISTS app;

-- ========= Utilidad: merge genérico por intersección de columnas =========
CREATE OR REPLACE FUNCTION app._merge_copy_missing_rows(p_src regclass, p_tgt regclass, p_pk text DEFAULT 'id')
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  cols text;
  n_inserted int := 0;
BEGIN
  -- Si alguna no existe, nada que hacer
  IF p_src IS NULL OR p_tgt IS NULL THEN
    RETURN 0;
  END IF;

  -- Construir lista de columnas comunes (intersección) presentes en ambas
  SELECT string_agg(quote_ident(c_src.column_name), ',')
  INTO cols
  FROM information_schema.columns c_src
  JOIN information_schema.columns c_tgt
    ON c_tgt.table_schema = split_part(p_tgt::text,'.',1)
   AND c_tgt.table_name   = split_part(p_tgt::text,'.',2)
   AND c_tgt.column_name  = c_src.column_name
  WHERE c_src.table_schema = split_part(p_src::text,'.',1)
    AND c_src.table_name   = split_part(p_src::text,'.',2);

  IF cols IS NULL OR position(quote_ident(p_pk) IN cols) = 0 THEN
    -- No hay columnas comunes o no está la PK: abortar silenciosamente
    RETURN 0;
  END IF;

  EXECUTE format(
    'INSERT INTO %s (%s)
     SELECT %s FROM %s s
     WHERE NOT EXISTS (
       SELECT 1 FROM %s t WHERE t.%I = s.%I
     )',
     p_tgt::text, cols, cols, p_src::text, p_tgt::text, p_pk, p_pk
  );

  GET DIAGNOSTICS n_inserted = ROW_COUNT;
  RETURN n_inserted;
END$$;

-- ========= 0) Detectar situación actual =========
DO $$
DECLARE
  has_emp boolean := (to_regclass('public.empresas') IS NOT NULL);
  has_ctr boolean := (to_regclass('public.centros')  IS NOT NULL);
  has_me  boolean := (to_regclass('public.maestros_empresa') IS NOT NULL);
  has_mc  boolean := (to_regclass('public.maestros_centro')  IS NOT NULL);
BEGIN
  IF NOT has_emp OR NOT has_ctr THEN
    RAISE EXCEPTION 'Se requieren tablas canónicas public.empresas y public.centros antes de fusionar.';
  END IF;

  -- No abortamos si coexisten: ahora haremos merge + alias.
END$$;

-- ========= 1) MERGE: maestros_* → canónicas (insertar faltantes por id) =========
SELECT app._merge_copy_missing_rows('public.maestros_empresa','public.empresas','id');
SELECT app._merge_copy_missing_rows('public.maestros_centro','public.centros','id');

-- ========= 2) RLS en canónicas (enable + policies F0) =========
DO $$
BEGIN
  -- ENABLE RLS
  EXECUTE 'ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY';
  EXECUTE 'ALTER TABLE public.centros  ENABLE ROW LEVEL SECURITY';
END$$;

-- Drop policies por prefijo en tabla dada
CREATE OR REPLACE FUNCTION app._drop_policies_like(p_table regclass, p_prefix text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_schema text; v_table text; pol record;
BEGIN
  SELECT n.nspname, c.relname INTO v_schema, v_table
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.oid = p_table;

  FOR pol IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname=v_schema AND tablename=v_table AND policyname LIKE (p_prefix||'%')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %s', pol.policyname, p_table::text);
  END LOOP;
END$$;

DO $pol$
BEGIN
  -- empresas
  PERFORM app._drop_policies_like('public.empresas','f0_');
  CREATE POLICY f0_emp_admin_dev_all ON public.empresas
    FOR ALL USING (app.app_is_role('admin') OR app.app_is_role('dev')) WITH CHECK (true);
  CREATE POLICY f0_emp_oficina_all   ON public.empresas
    FOR ALL USING (app.app_is_role('oficina')) WITH CHECK (app.app_is_role('oficina'));
  CREATE POLICY f0_emp_centro_select ON public.empresas
    FOR SELECT USING (app.app_is_role('centro') AND id = app.app_empresa_id());

  -- centros
  PERFORM app._drop_policies_like('public.centros','f0_');
  CREATE POLICY f0_ctr_admin_dev_all ON public.centros
    FOR ALL USING (app.app_is_role('admin') OR app.app_is_role('dev')) WITH CHECK (true);
  CREATE POLICY f0_ctr_oficina_all   ON public.centros
    FOR ALL USING (app.app_is_role('oficina')) WITH CHECK (app.app_is_role('oficina'));
  CREATE POLICY f0_ctr_centro_select_self ON public.centros
    FOR SELECT USING (app.app_is_role('centro') AND id = app.app_centro_id());
END
$pol$;

-- ========= 3) Actualizar función/vista de comunicación para usar canónicas =========
-- (Reescribe a partir de la versión F0 pero referenciando public.centros)
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
  IF to_regclass('public.centros') IS NULL THEN
    RETURN;
  END IF;

  IF v_ctr IS NOT NULL THEN
    SELECT c.zona_id INTO v_zona FROM public.centros c WHERE c.id = v_ctr;
  END IF;

  IF v_role IN ('admin','dev','oficina') THEN
    IF pilotos_exist THEN
      RETURN QUERY
      SELECT
        c.empresa_id, c.zona_id, c.id, c.nombre,
        p.id, p.nombre, p.activo
      FROM public.centros c
      LEFT JOIN public.pilotos p
        ON p.empresa_id = c.empresa_id
       AND p.centro_id  = c.id;
    ELSE
      RETURN QUERY
      SELECT
        c.empresa_id, c.zona_id, c.id, c.nombre,
        NULL::uuid, NULL::text, NULL::boolean
      FROM public.centros c;
    END IF;
    RETURN;
  END IF;

  IF v_role = 'centro' AND v_emp IS NOT NULL AND v_zona IS NOT NULL THEN
    IF pilotos_exist THEN
      RETURN QUERY
      SELECT
        c.empresa_id, c.zona_id, c.id, c.nombre,
        p.id, p.nombre, p.activo
      FROM public.centros c
      LEFT JOIN public.pilotos p
        ON p.empresa_id = c.empresa_id
       AND p.centro_id  = c.id
      WHERE c.empresa_id = v_emp
        AND c.zona_id = v_zona;
    ELSE
      RETURN QUERY
      SELECT
        c.empresa_id, c.zona_id, c.id, c.nombre,
        NULL::uuid, NULL::text, NULL::boolean
      FROM public.centros c
      WHERE c.empresa_id = v_emp
        AND c.zona_id = v_zona;
    END IF;
    RETURN;
  END IF;

  RETURN;
END
$$;

DROP VIEW IF EXISTS public.v_comunicacion_zona;
CREATE VIEW public.v_comunicacion_zona AS
SELECT * FROM app.v_comunicacion_zona();

-- ========= 4) Renombrar maestros_* a backup y crear vistas alias =========
DO $$
DECLARE
  ts text := to_char(now(),'YYYYMMDD_HH24MI');
BEGIN
  -- maestros_empresa → backup + view alias
  IF to_regclass('public.maestros_empresa') IS NOT NULL
     AND (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.maestros_empresa')) = 'r' THEN
    EXECUTE format('ALTER TABLE public.maestros_empresa RENAME TO maestros_empresa_bak_%s', ts);
    EXECUTE 'CREATE VIEW public.maestros_empresa AS SELECT * FROM public.empresas';
  ELSIF to_regclass('public.maestros_empresa') IS NULL THEN
    -- si no existe, asegúrate de que el alias exista
    IF to_regclass('public.empresas') IS NOT NULL THEN
      EXECUTE 'CREATE VIEW IF NOT EXISTS public.maestros_empresa AS SELECT * FROM public.empresas';
    END IF;
  END IF;

  -- maestros_centro → backup + view alias
  IF to_regclass('public.maestros_centro') IS NOT NULL
     AND (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.maestros_centro')) = 'r' THEN
    EXECUTE format('ALTER TABLE public.maestros_centro RENAME TO maestros_centro_bak_%s', ts);
    EXECUTE 'CREATE VIEW public.maestros_centro AS SELECT * FROM public.centros';
  ELSIF to_regclass('public.maestros_centro') IS NULL THEN
    IF to_regclass('public.centros') IS NOT NULL THEN
      EXECUTE 'CREATE VIEW IF NOT EXISTS public.maestros_centro AS SELECT * FROM public.centros';
    END IF;
  END IF;
END$$;

COMMIT;
