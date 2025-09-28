-- File: db/migrations/2025-09-28_00a_bootstrap_maestros.sql
-- Paso 0a — Bootstrap de catálogos mínimos: maestros_empresa / maestros_centro
-- Crea tablas base + ENABLE RLS + policies (consistentes con F0). Idempotente.

BEGIN;
SELECT pg_advisory_xact_lock(420250928);

-- ====== Tablas ======
CREATE TABLE IF NOT EXISTS public.maestros_empresa (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.maestros_centro (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid REFERENCES public.maestros_empresa(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  zona_id uuid,
  nombre text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Índices útiles
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='maestros_centro_empresa_id_idx') THEN
    EXECUTE 'CREATE INDEX maestros_centro_empresa_id_idx ON public.maestros_centro(empresa_id)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='maestros_centro_zona_id_idx') THEN
    EXECUTE 'CREATE INDEX maestros_centro_zona_id_idx ON public.maestros_centro(zona_id)';
  END IF;
END$$;

-- ====== ENABLE RLS ======
ALTER TABLE public.maestros_empresa ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maestros_centro  ENABLE ROW LEVEL SECURITY;

-- ====== Utilidad: drop de policies por prefijo (igual que F0) ======
CREATE SCHEMA IF NOT EXISTS app;

CREATE OR REPLACE FUNCTION app._drop_policies_like(p_table regclass, p_prefix text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_schema text;
  v_table  text;
  pol record;
BEGIN
  SELECT n.nspname, c.relname INTO v_schema, v_table
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.oid = p_table;

  FOR pol IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = v_schema
      AND tablename  = v_table
      AND policyname LIKE (p_prefix || '%')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %s', pol.policyname, p_table::text);
  END LOOP;
END$$;

-- ====== Policies (alineadas con F0) ======
DO $policies$
BEGIN
  -- maestros_empresa
  PERFORM app._drop_policies_like('public.maestros_empresa','f0_');

  CREATE POLICY f0_me_admin_dev_all ON public.maestros_empresa
    FOR ALL USING (app.app_is_role('admin') OR app.app_is_role('dev'))
    WITH CHECK (true);

  CREATE POLICY f0_me_oficina_all ON public.maestros_empresa
    FOR ALL USING (app.app_is_role('oficina'))
    WITH CHECK (app.app_is_role('oficina'));

  CREATE POLICY f0_me_centro_select ON public.maestros_empresa
    FOR SELECT USING (app.app_is_role('centro') AND id = app.app_empresa_id());

  -- maestros_centro
  PERFORM app._drop_policies_like('public.maestros_centro','f0_');

  CREATE POLICY f0_mc_admin_dev_all ON public.maestros_centro
    FOR ALL USING (app.app_is_role('admin') OR app.app_is_role('dev'))
    WITH CHECK (true);

  CREATE POLICY f0_mc_oficina_all ON public.maestros_centro
    FOR ALL USING (app.app_is_role('oficina'))
    WITH CHECK (app.app_is_role('oficina'));

  -- centro: solo su centro (lectura). Los otros centros de la zona se expondrán por la vista del Paso 2.
  CREATE POLICY f0_mc_centro_select_self ON public.maestros_centro
    FOR SELECT USING (app.app_is_role('centro') AND id = app.app_centro_id());
END
$policies$;

COMMIT;
