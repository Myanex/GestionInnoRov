-- File: db/migrations/2025-09-28_00_rls_base.sql
-- F0 — RLS base (Paso 1 corregido): helpers, enum, columnas mínimas, ENABLE RLS, policies y triggers

BEGIN;
SELECT pg_advisory_xact_lock(420250928);

-- ========= Esquema utilitario =========
CREATE SCHEMA IF NOT EXISTS app;

-- ========= Enum para movimientos =========
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'modo_transporte_enum') THEN
    CREATE TYPE public.modo_transporte_enum AS ENUM (
      'lancha_rapida','avion','camioneta','auto','helicoptero','barcaza','otro'
    );
  END IF;
END$$;

-- ========= app_perfil (fallback) + auditoría =========
CREATE TABLE IF NOT EXISTS app.app_perfil (
  user_id uuid PRIMARY KEY,
  role text NOT NULL CHECK (role IN ('dev','admin','oficina','centro')),
  empresa_id uuid,
  centro_id uuid,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS app.audit_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  at timestamptz NOT NULL DEFAULT now(),
  actor_id uuid,
  actor_role text,
  action text NOT NULL,
  entity text,
  entity_id uuid,
  meta jsonb
);

-- ========= Helpers de sesión + modo debug =========
CREATE OR REPLACE FUNCTION app.app_set_debug_claims(claims jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM set_config('app.debug_claims', claims::text, true);
END$$;

CREATE OR REPLACE FUNCTION app.app_clear_debug_claims()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM set_config('app.debug_claims', NULL, true);
END$$;

CREATE OR REPLACE FUNCTION app.app_current_perfil()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  dbg text;
  dbg_claims jsonb;
  jwt jsonb;
  uid uuid;
BEGIN
  -- 1) debug (smoke tests)
  dbg := current_setting('app.debug_claims', true);
  IF dbg IS NOT NULL THEN
    dbg_claims := dbg::jsonb;
    RETURN jsonb_build_object(
      'role', lower(coalesce(dbg_claims->>'role','anon')),
      'empresa_id', (dbg_claims->>'empresa_id')::uuid,
      'centro_id', (dbg_claims->>'centro_id')::uuid,
      'user_id', (dbg_claims->>'user_id')::uuid
    );
  END IF;

  -- 2) JWT (Supabase)
  BEGIN jwt := auth.jwt(); EXCEPTION WHEN OTHERS THEN jwt := NULL; END;
  uid := auth.uid();

  IF jwt ? 'role' THEN
    RETURN jsonb_build_object(
      'role', lower(coalesce(jwt->>'role','anon')),
      'empresa_id', CASE WHEN jwt ? 'empresa_id' THEN (jwt->>'empresa_id')::uuid END,
      'centro_id',  CASE WHEN jwt ? 'centro_id'  THEN (jwt->>'centro_id')::uuid END,
      'user_id', uid
    );
  END IF;

  -- 3) Fallback app_perfil
  IF uid IS NOT NULL THEN
    RETURN (
      SELECT jsonb_build_object(
        'role', lower(p.role),
        'empresa_id', p.empresa_id,
        'centro_id', p.centro_id,
        'user_id', uid
      )
      FROM app.app_perfil p
      WHERE p.user_id = uid
    );
  END IF;

  -- 4) Anon
  RETURN jsonb_build_object('role','anon','empresa_id',NULL,'centro_id',NULL,'user_id',NULL);
END$$;

CREATE OR REPLACE FUNCTION app.app_is_role(p_role text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$ SELECT lower(coalesce(app.app_current_perfil()->>'role','')) = lower(coalesce(p_role,'')); $$;

CREATE OR REPLACE FUNCTION app.app_empresa_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$ SELECT (app.app_current_perfil()->>'empresa_id')::uuid $$;

CREATE OR REPLACE FUNCTION app.app_centro_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$ SELECT (app.app_current_perfil()->>'centro_id')::uuid $$;

-- ========= Utilidad: asegurar columnas (FIX usa pg_attribute) =========
CREATE OR REPLACE FUNCTION app._ensure_column(p_table regclass, p_col text, p_type text, p_default text, p_nullable boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = p_table
      AND attname = p_col
      AND NOT attisdropped
  ) THEN
    EXECUTE format(
      'ALTER TABLE %s ADD COLUMN %I %s %s %s',
      p_table::text,
      p_col,
      p_type,
      CASE WHEN p_default IS NOT NULL THEN 'DEFAULT '||p_default ELSE '' END,
      CASE WHEN p_nullable THEN '' ELSE 'NOT NULL' END
    );
  END IF;
END$$;

-- ========= Asegurar columnas mínimas =========
DO $$
DECLARE t regclass;
BEGIN
  -- maestros
  IF to_regclass('public.maestros_empresa') IS NOT NULL THEN
    PERFORM app._ensure_column('public.maestros_empresa','id','uuid','gen_random_uuid()',false);
  END IF;

  IF to_regclass('public.maestros_centro') IS NOT NULL THEN
    PERFORM app._ensure_column('public.maestros_centro','id','uuid','gen_random_uuid()',false);
    PERFORM app._ensure_column('public.maestros_centro','empresa_id','uuid',NULL,true);
    PERFORM app._ensure_column('public.maestros_centro','zona_id','uuid',NULL,true);
  END IF;

  -- productivas
  FOREACH t IN ARRAY ARRAY[
    'public.componentes'::regclass,
    'public.equipos'::regclass,
    'public.equipo_componente'::regclass,
    'public.movimientos'::regclass,
    'public.prestamos'::regclass,
    'public.bitacora'::regclass
  ] LOOP
    IF t IS NOT NULL THEN
      PERFORM app._ensure_column(t,'id','uuid','gen_random_uuid()',false);
      PERFORM app._ensure_column(t,'empresa_id','uuid',NULL,true);
      PERFORM app._ensure_column(t,'created_at','timestamptz','now()',true);
      PERFORM app._ensure_column(t,'updated_at','timestamptz',NULL,true);
    END IF;
  END LOOP;

  -- Asignables a centro
  FOREACH t IN ARRAY ARRAY[
    'public.componentes'::regclass,
    'public.equipos'::regclass,
    'public.prestamos'::regclass,
    'public.bitacora'::regclass
  ] LOOP
    IF t IS NOT NULL THEN
      PERFORM app._ensure_column(t,'centro_id','uuid',NULL,true);
    END IF;
  END LOOP;

  -- Movimientos: campos adicionales
  IF to_regclass('public.movimientos') IS NOT NULL THEN
    PERFORM app._ensure_column('public.movimientos','origen_centro_id','uuid',NULL,true);
    PERFORM app._ensure_column('public.movimientos','destino_centro_id','uuid',NULL,true);
    PERFORM app._ensure_column('public.movimientos','responsable_envio_id','uuid',NULL,true);
    PERFORM app._ensure_column('public.movimientos','responsable_recepcion_id','uuid',NULL,true);
    PERFORM app._ensure_column('public.movimientos','modo_transporte','modo_transporte_enum',NULL,true);
  END IF;
END$$;

-- ========= ENABLE RLS =========
DO $$
BEGIN
  IF to_regclass('public.maestros_empresa') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.maestros_empresa ENABLE ROW LEVEL SECURITY';
  END IF;
  IF to_regclass('public.maestros_centro') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.maestros_centro ENABLE ROW LEVEL SECURITY';
  END IF;
  IF to_regclass('public.componentes') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.componentes ENABLE ROW LEVEL SECURITY';
  END IF;
  IF to_regclass('public.equipos') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.equipos ENABLE ROW LEVEL SECURITY';
  END IF;
  IF to_regclass('public.equipo_componente') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.equipo_componente ENABLE ROW LEVEL SECURITY';
  END IF;
  IF to_regclass('public.movimientos') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.movimientos ENABLE ROW LEVEL SECURITY';
  END IF;
  IF to_regclass('public.prestamos') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.prestamos ENABLE ROW LEVEL SECURITY';
  END IF;
  IF to_regclass('public.bitacora') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.bitacora ENABLE ROW LEVEL SECURITY';
  END IF;
END$$;

-- ========= Drop/create policies (FIX: usa policyname) =========
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

DO $policies$
BEGIN
  -- ===== maestros_empresa =====
  IF to_regclass('public.maestros_empresa') IS NOT NULL THEN
    PERFORM app._drop_policies_like('public.maestros_empresa','f0_');
    CREATE POLICY f0_me_admin_dev_all ON public.maestros_empresa
      FOR ALL USING (app.app_is_role('admin') OR app.app_is_role('dev'))
      WITH CHECK (true);
    CREATE POLICY f0_me_oficina_all ON public.maestros_empresa
      FOR ALL USING (app.app_is_role('oficina'))
      WITH CHECK (app.app_is_role('oficina'));
    CREATE POLICY f0_me_centro_select ON public.maestros_empresa
      FOR SELECT USING (app.app_is_role('centro') AND id = app.app_empresa_id());
  END IF;

  -- ===== maestros_centro =====
  IF to_regclass('public.maestros_centro') IS NOT NULL THEN
    PERFORM app._drop_policies_like('public.maestros_centro','f0_');
    CREATE POLICY f0_mc_admin_dev_all ON public.maestros_centro
      FOR ALL USING (app.app_is_role('admin') OR app.app_is_role('dev'))
      WITH CHECK (true);
    CREATE POLICY f0_mc_oficina_all ON public.maestros_centro
      FOR ALL USING (app.app_is_role('oficina'))
      WITH CHECK (app.app_is_role('oficina'));
    CREATE POLICY f0_mc_centro_select_self ON public.maestros_centro
      FOR SELECT USING (app.app_is_role('centro') AND id = app.app_centro_id());
    -- (otros centros de la zona se expondrán vía vista en Paso 2)
  END IF;

  -- ===== componentes =====
  IF to_regclass('public.componentes') IS NOT NULL THEN
    PERFORM app._drop_policies_like('public.componentes','f0_');
    CREATE POLICY f0_comp_admin_dev_all ON public.componentes
      FOR ALL USING (app.app_is_role('admin') OR app.app_is_role('dev'))
      WITH CHECK (true);
    CREATE POLICY f0_comp_oficina_all ON public.componentes
      FOR ALL USING (app.app_is_role('oficina'))
      WITH CHECK (app.app_is_role('oficina'));
    CREATE POLICY f0_comp_centro_select ON public.componentes
      FOR SELECT USING (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND centro_id = app.app_centro_id()
      );
  END IF;

  -- ===== equipos =====
  IF to_regclass('public.equipos') IS NOT NULL THEN
    PERFORM app._drop_policies_like('public.equipos','f0_');
    CREATE POLICY f0_eq_admin_dev_all ON public.equipos
      FOR ALL USING (app.app_is_role('admin') OR app.app_is_role('dev'))
      WITH CHECK (true);
    CREATE POLICY f0_eq_oficina_all ON public.equipos
      FOR ALL USING (app.app_is_role('oficina'))
      WITH CHECK (app.app_is_role('oficina'));
    CREATE POLICY f0_eq_centro_select ON public.equipos
      FOR SELECT USING (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND centro_id = app.app_centro_id()
      );
  END IF;

  -- ===== equipo_componente =====
  IF to_regclass('public.equipo_componente') IS NOT NULL THEN
    PERFORM app._drop_policies_like('public.equipo_componente','f0_');
    CREATE POLICY f0_ec_admin_dev_all ON public.equipo_componente
      FOR ALL USING (app.app_is_role('admin') OR app.app_is_role('dev'))
      WITH CHECK (true);
    CREATE POLICY f0_ec_oficina_all ON public.equipo_componente
      FOR ALL USING (app.app_is_role('oficina'))
      WITH CHECK (app.app_is_role('oficina'));
    CREATE POLICY f0_ec_centro_select ON public.equipo_componente
      FOR SELECT USING (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND EXISTS (
          SELECT 1 FROM public.equipos e
          WHERE e.id = equipo_id AND e.centro_id = app.app_centro_id()
        )
      );
  END IF;

  -- ===== movimientos =====
  IF to_regclass('public.movimientos') IS NOT NULL THEN
    PERFORM app._drop_policies_like('public.movimientos','f0_');
    CREATE POLICY f0_mov_admin_dev_all ON public.movimientos
      FOR ALL USING (app.app_is_role('admin') OR app.app_is_role('dev'))
      WITH CHECK (true);
    CREATE POLICY f0_mov_oficina_all ON public.movimientos
      FOR ALL USING (app.app_is_role('oficina'))
      WITH CHECK (app.app_is_role('oficina'));
    CREATE POLICY f0_mov_centro_select_participa ON public.movimientos
      FOR SELECT USING (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND (origen_centro_id = app.app_centro_id() OR destino_centro_id = app.app_centro_id())
      );
  END IF;

  -- ===== prestamos (CRUD intracentro) =====
  IF to_regclass('public.prestamos') IS NOT NULL THEN
    PERFORM app._drop_policies_like('public.prestamos','f0_');
    CREATE POLICY f0_pres_admin_dev_all ON public.prestamos
      FOR ALL USING (app.app_is_role('admin') OR app.app_is_role('dev'))
      WITH CHECK (true);
    CREATE POLICY f0_pres_oficina_all ON public.prestamos
      FOR ALL USING (app.app_is_role('oficina'))
      WITH CHECK (app.app_is_role('oficina'));

    CREATE POLICY f0_pres_centro_select ON public.prestamos
      FOR SELECT USING (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND centro_id = app.app_centro_id()
      );
    CREATE POLICY f0_pres_centro_insert ON public.prestamos
      FOR INSERT WITH CHECK (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND centro_id = app.app_centro_id()
      );
    CREATE POLICY f0_pres_centro_update ON public.prestamos
      FOR UPDATE USING (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND centro_id = app.app_centro_id()
      ) WITH CHECK (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND centro_id = app.app_centro_id()
      );
    CREATE POLICY f0_pres_centro_delete ON public.prestamos
      FOR DELETE USING (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND centro_id = app.app_centro_id()
      );
  END IF;

  -- ===== bitacora (RW centro propio) =====
  IF to_regclass('public.bitacora') IS NOT NULL THEN
    PERFORM app._drop_policies_like('public.bitacora','f0_');
    CREATE POLICY f0_bit_admin_dev_all ON public.bitacora
      FOR ALL USING (app.app_is_role('admin') OR app.app_is_role('dev'))
      WITH CHECK (true);
    CREATE POLICY f0_bit_oficina_all ON public.bitacora
      FOR ALL USING (app.app_is_role('oficina'))
      WITH CHECK (app.app_is_role('oficina'));

    CREATE POLICY f0_bit_centro_select ON public.bitacora
      FOR SELECT USING (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND centro_id = app.app_centro_id()
      );
    CREATE POLICY f0_bit_centro_insert ON public.bitacora
      FOR INSERT WITH CHECK (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND centro_id = app.app_centro_id()
      );
    CREATE POLICY f0_bit_centro_update ON public.bitacora
      FOR UPDATE USING (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND centro_id = app.app_centro_id()
      ) WITH CHECK (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND centro_id = app.app_centro_id()
      );
    CREATE POLICY f0_bit_centro_delete ON public.bitacora
      FOR DELETE USING (
        app.app_is_role('centro')
        AND empresa_id = app.app_empresa_id()
        AND centro_id = app.app_centro_id()
      );
  END IF;
END
$policies$;

-- ========= Triggers mínimos (prestamos enforce + auditoría) =========
CREATE OR REPLACE FUNCTION app.tr_prestamos_enforce_perfil()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE rol text := app.app_current_perfil()->>'role';
BEGIN
  IF rol = 'centro' THEN
    NEW.empresa_id := app.app_empresa_id();
    NEW.centro_id  := app.app_centro_id();
  END IF;
  RETURN NEW;
END$$;

CREATE OR REPLACE FUNCTION app.tr_audit_event()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO app.audit_event(actor_id, actor_role, action, entity, entity_id, meta)
  VALUES (
    (app.app_current_perfil()->>'user_id')::uuid,
    app.app_current_perfil()->>'role',
    TG_TABLE_NAME || ':' || TG_OP,
    TG_TABLE_NAME,
    COALESCE(NEW.id, OLD.id),
    jsonb_build_object('new', to_jsonb(NEW), 'old', to_jsonb(OLD))
  );
  RETURN COALESCE(NEW, OLD);
END$$;

DO $$
BEGIN
  IF to_regclass('public.prestamos') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'tr_prestamos_enforce_perfil_biu') THEN
      EXECUTE 'DROP TRIGGER tr_prestamos_enforce_perfil_biu ON public.prestamos';
    END IF;
    EXECUTE 'CREATE TRIGGER tr_prestamos_enforce_perfil_biu
             BEFORE INSERT OR UPDATE ON public.prestamos
             FOR EACH ROW EXECUTE FUNCTION app.tr_prestamos_enforce_perfil()';

    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'tr_audit_prestamos_cud') THEN
      EXECUTE 'DROP TRIGGER tr_audit_prestamos_cud ON public.prestamos';
    END IF;
    EXECUTE 'CREATE TRIGGER tr_audit_prestamos_cud
             AFTER INSERT OR UPDATE OR DELETE ON public.prestamos
             FOR EACH ROW EXECUTE FUNCTION app.tr_audit_event()';
  END IF;

  IF to_regclass('public.bitacora') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'tr_audit_bitacora_cud') THEN
      EXECUTE 'DROP TRIGGER tr_audit_bitacora_cud ON public.bitacora';
    END IF;
    EXECUTE 'CREATE TRIGGER tr_audit_bitacora_cud
             AFTER INSERT OR UPDATE OR DELETE ON public.bitacora
             FOR EACH ROW EXECUTE FUNCTION app.tr_audit_event()';
  END IF;
END$$;

COMMIT;
