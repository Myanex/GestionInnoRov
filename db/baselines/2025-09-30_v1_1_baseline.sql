-- =====================================================================
-- BASELINE v1.1 — Snapshot de esquema (public + app)
-- Fecha: 2025-09-30 (TZ America/Santiago)
-- Nota: Archivo de referencia. No ejecutar como migración.
-- - Sin OWNER/GRANT/COMMENT/SET.
-- - CREATE SCHEMA/EXTENSION comentados si aparecen.
-- - DBeaver no exporta RLS policies: se documentan en migraciones.
-- =====================================================================

-- DROP SCHEMA app;

-- CREATE SCHEMA app AUTHORIZATION postgres;
-- app.app_perfil definition

-- Drop table

-- DROP TABLE app.app_perfil;

CREATE TABLE app.app_perfil (
	user_id uuid NOT NULL,
	"role" text NOT NULL,
	empresa_id uuid NULL,
	centro_id uuid NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT app_perfil_pkey PRIMARY KEY (user_id),
	CONSTRAINT app_perfil_role_check CHECK ((role = ANY (ARRAY['dev'::text, 'admin'::text, 'oficina'::text, 'centro'::text])))
);


-- app.audit_event definition

-- Drop table

-- DROP TABLE app.audit_event;

CREATE TABLE app.audit_event (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	"at" timestamptz DEFAULT now() NOT NULL,
	actor_id uuid NULL,
	actor_role text NULL,
	"action" text NOT NULL,
	entity text NULL,
	entity_id uuid NULL,
	meta jsonb NULL,
	CONSTRAINT audit_event_pkey PRIMARY KEY (id)
);



-- DROP FUNCTION app._drop_policies_like(regclass, text);

CREATE OR REPLACE FUNCTION app._drop_policies_like(p_table regclass, p_prefix text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
END$function$
;

-- DROP FUNCTION app._ensure_column(regclass, text, text, text, bool);

CREATE OR REPLACE FUNCTION app._ensure_column(p_table regclass, p_col text, p_type text, p_default text, p_nullable boolean)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
END$function$
;

-- DROP FUNCTION app._merge_copy_missing_rows(regclass, regclass, text);

CREATE OR REPLACE FUNCTION app._merge_copy_missing_rows(p_src regclass, p_tgt regclass, p_pk text DEFAULT 'id'::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
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
END$function$
;

-- DROP FUNCTION app._slugify(text);

CREATE OR REPLACE FUNCTION app._slugify(txt text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT regexp_replace(lower(trim(coalesce(txt,''))), '[^a-z0-9]+', '-', 'g')
$function$
;

-- DROP FUNCTION app.app_centro_id();

CREATE OR REPLACE FUNCTION app.app_centro_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$ SELECT (app.app_current_perfil()->>'centro_id')::uuid $function$
;

-- DROP FUNCTION app.app_clear_debug_claims();

CREATE OR REPLACE FUNCTION app.app_clear_debug_claims()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  PERFORM set_config('app.debug_claims', NULL, false); -- <-- sesión
END$function$
;

-- DROP FUNCTION app.app_current_perfil();

CREATE OR REPLACE FUNCTION app.app_current_perfil()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
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
END$function$
;

-- DROP FUNCTION app.app_empresa_id();

CREATE OR REPLACE FUNCTION app.app_empresa_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$ SELECT (app.app_current_perfil()->>'empresa_id')::uuid $function$
;

-- DROP FUNCTION app.app_is_role(text);

CREATE OR REPLACE FUNCTION app.app_is_role(p_role text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$ SELECT lower(coalesce(app.app_current_perfil()->>'role','')) = lower(coalesce(p_role,'')); $function$
;

-- DROP FUNCTION app.app_set_debug_claims(jsonb);

CREATE OR REPLACE FUNCTION app.app_set_debug_claims(claims jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  PERFORM set_config('app.debug_claims', claims::text, false); -- <-- sesión
END$function$
;

-- DROP FUNCTION app.tg__set_updated_at();

CREATE OR REPLACE FUNCTION app.tg__set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    BEGIN
      NEW.updated_at := now();
      RETURN NEW;
    END
    $function$
;

-- DROP FUNCTION app.tg_pilotos_sync_empresa();

CREATE OR REPLACE FUNCTION app.tg_pilotos_sync_empresa()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_empresa uuid;
BEGIN
  IF NEW.centro_id IS NULL THEN
    NEW.empresa_id := NULL;
    RETURN NEW;
  END IF;

  SELECT c.empresa_id INTO v_empresa
  FROM public.centros c
  WHERE c.id = NEW.centro_id;

  IF v_empresa IS NULL THEN
    RAISE EXCEPTION 'Centro % no tiene empresa asociada (centros.empresa_id = NULL)', NEW.centro_id;
  END IF;

  NEW.empresa_id := v_empresa;
  RETURN NEW;
END
$function$
;

-- DROP FUNCTION app.tr_audit_event();

CREATE OR REPLACE FUNCTION app.tr_audit_event()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
END$function$
;

-- DROP FUNCTION app.tr_prestamos_enforce_perfil();

CREATE OR REPLACE FUNCTION app.tr_prestamos_enforce_perfil()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE rol text := app.app_current_perfil()->>'role';
BEGIN
  IF rol = 'centro' THEN
    NEW.empresa_id := app.app_empresa_id();
    NEW.centro_id  := app.app_centro_id();
  END IF;
  RETURN NEW;
END$function$
;

-- DROP FUNCTION app.v_comunicacion_zona();

CREATE OR REPLACE FUNCTION app.v_comunicacion_zona()
 RETURNS TABLE(empresa_id uuid, zona_id uuid, centro_id uuid, centro_nombre text, piloto_id uuid, piloto_nombre text, piloto_activo boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER

AS $function$
DECLARE
  v_role text := app.app_current_perfil()->>'role';
  v_emp  uuid := (app.app_current_perfil()->>'empresa_id')::uuid;
  v_ctr  uuid := (app.app_current_perfil()->>'centro_id')::uuid;
  v_zona uuid;

  pilotos_exist boolean := (to_regclass('public.pilotos') IS NOT NULL);
  col_nombre boolean := false;
  col_activo boolean := false;
BEGIN
  -- Requisito base
  IF to_regclass('public.centros') IS NULL THEN
    RETURN;
  END IF;

  -- Detectar columnas presentes en pilotos (si existe)
  IF pilotos_exist THEN
    SELECT
      EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='pilotos' AND column_name='nombre'),
      EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='pilotos' AND column_name='activo')
    INTO col_nombre, col_activo;
  END IF;

  -- Zona del centro en sesión (si aplica)
  IF v_ctr IS NOT NULL THEN
    SELECT c.zona_id INTO v_zona FROM public.centros c WHERE c.id = v_ctr;
  END IF;

  -- ADMIN/DEV/OFICINA → todo
  IF v_role IN ('admin','dev','oficina') THEN
    IF pilotos_exist THEN
      IF col_nombre AND col_activo THEN
        RETURN QUERY
        SELECT c.empresa_id, c.zona_id, c.id, c.nombre,
               p.id, p.nombre, p.activo
        FROM public.centros c
        LEFT JOIN public.pilotos p
               ON p.centro_id = c.id;
      ELSIF col_nombre AND NOT col_activo THEN
        RETURN QUERY
        SELECT c.empresa_id, c.zona_id, c.id, c.nombre,
               p.id, p.nombre, NULL::boolean
        FROM public.centros c
        LEFT JOIN public.pilotos p
               ON p.centro_id = c.id;
      ELSE
        RETURN QUERY
        SELECT c.empresa_id, c.zona_id, c.id, c.nombre,
               p.id, NULL::text, NULL::boolean
        FROM public.centros c
        LEFT JOIN public.pilotos p
               ON p.centro_id = c.id;
      END IF;
    ELSE
      RETURN QUERY
      SELECT c.empresa_id, c.zona_id, c.id, c.nombre,
             NULL::uuid, NULL::text, NULL::boolean
      FROM public.centros c;
    END IF;
    RETURN;
  END IF;

  -- CENTRO → misma empresa y zona
  IF v_role = 'centro' AND v_emp IS NOT NULL AND v_zona IS NOT NULL THEN
    IF pilotos_exist THEN
      IF col_nombre AND col_activo THEN
        RETURN QUERY
        SELECT c.empresa_id, c.zona_id, c.id, c.nombre,
               p.id, p.nombre, p.activo
        FROM public.centros c
        LEFT JOIN public.pilotos p
               ON p.centro_id = c.id
        WHERE c.empresa_id = v_emp
          AND c.zona_id = v_zona;
      ELSIF col_nombre AND NOT col_activo THEN
        RETURN QUERY
        SELECT c.empresa_id, c.zona_id, c.id, c.nombre,
               p.id, p.nombre, NULL::boolean
        FROM public.centros c
        LEFT JOIN public.pilotos p
               ON p.centro_id = c.id
        WHERE c.empresa_id = v_emp
          AND c.zona_id = v_zona;
      ELSE
        RETURN QUERY
        SELECT c.empresa_id, c.zona_id, c.id, c.nombre,
               p.id, NULL::text, NULL::boolean
        FROM public.centros c
        LEFT JOIN public.pilotos p
               ON p.centro_id = c.id
        WHERE c.empresa_id = v_emp
          AND c.zona_id = v_zona;
      END IF;
    ELSE
      RETURN QUERY
      SELECT c.empresa_id, c.zona_id, c.id, c.nombre,
             NULL::uuid, NULL::text, NULL::boolean
      FROM public.centros c
      WHERE c.empresa_id = v_emp
        AND c.zona_id = v_zona;
    END IF;
    RETURN;
  END IF;

  -- Otros roles → sin filas
  RETURN;
END
$function$
;

-- DROP FUNCTION app.v_comunicacion_zona_as(jsonb);

CREATE OR REPLACE FUNCTION app.v_comunicacion_zona_as(claims jsonb)
 RETURNS TABLE(empresa_id uuid, centro_id uuid, zona_id uuid, piloto_id uuid, piloto_nombre text, piloto_activo boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER

AS $function$
BEGIN
  PERFORM app_set_debug_claims(claims);
  RETURN QUERY SELECT * FROM app.v_comunicacion_zona_v2();
END;
$function$
;

-- DROP FUNCTION app.v_comunicacion_zona_v2();

CREATE OR REPLACE FUNCTION app.v_comunicacion_zona_v2()
 RETURNS TABLE(empresa_id uuid, centro_id uuid, zona_id uuid, piloto_id uuid, piloto_nombre text, piloto_activo boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER

AS $function$
BEGIN
  RETURN QUERY
  SELECT
    c.empresa_id,
    c.id           AS centro_id,
    c.zona_id,                 -- comenta esta línea si no existe en tu schema
    p.id           AS piloto_id,
    p.nombre       AS piloto_nombre,
    p.activo       AS piloto_activo
  FROM public.centros  c
  LEFT JOIN public.pilotos p
    ON p.centro_id = c.id
  WHERE
    (app_is_role('admin') OR app_is_role('dev') OR app_is_role('oficina'))
    OR (
      app_is_role('centro')
      AND c.empresa_id = app_empresa_id()
      AND c.id         = app_centro_id()
    );
END;
$function$
;

-- DROP SCHEMA public;

-- CREATE SCHEMA public AUTHORIZATION pg_database_owner;

-- DROP TYPE public."actividad_bitacora";

CREATE TYPE public."actividad_bitacora" AS ENUM (
	'extraccion_mortalidad',
	'inspeccion_redes_loberas',
	'inspeccion_redes_peceras',
	'inspeccion',
	'otro',
	'condicion_puerto_cerrado');

-- DROP TYPE public."componente_condicion";

CREATE TYPE public."componente_condicion" AS ENUM (
	'normal',
	'falla_menor',
	'falla_mayor',
	'en_reparacion',
	'enredado',
	'baja');

-- DROP TYPE public."componente_tipo";

CREATE TYPE public."componente_tipo" AS ENUM (
	'rov',
	'controlador',
	'umbilical',
	'sensor',
	'grabber');

-- DROP TYPE public."componente_ubicacion";

CREATE TYPE public."componente_ubicacion" AS ENUM (
	'bodega',
	'centro',
	'asignado_a_equipo',
	'en_transito',
	'reparacion_externa');

-- DROP TYPE public."equipo_condicion";

CREATE TYPE public."equipo_condicion" AS ENUM (
	'normal',
	'falta_componente',
	'en_reparacion',
	'enredado',
	'baja');

-- DROP TYPE public."equipo_estado";

CREATE TYPE public."equipo_estado" AS ENUM (
	'vigente',
	'no_vigente');

-- DROP TYPE public."equipo_rol";

CREATE TYPE public."equipo_rol" AS ENUM (
	'principal',
	'backup');

-- DROP TYPE public."equipo_ubicacion";

CREATE TYPE public."equipo_ubicacion" AS ENUM (
	'bodega',
	'centro',
	'en_transito',
	'reparacion_externa');

-- DROP TYPE public."equipo_usado";

CREATE TYPE public."equipo_usado" AS ENUM (
	'principal',
	'backup');

-- DROP TYPE public."estado_activo_inactivo";

CREATE TYPE public."estado_activo_inactivo" AS ENUM (
	'activo',
	'inactivo');

-- DROP TYPE public."estado_puerto";

CREATE TYPE public."estado_puerto" AS ENUM (
	'abierto',
	'restringido',
	'cerrado');

-- DROP TYPE public."jornada";

CREATE TYPE public."jornada" AS ENUM (
	'am',
	'pm');

-- DROP TYPE public."lugar_operacion";

CREATE TYPE public."lugar_operacion" AS ENUM (
	'centro',
	'bodega',
	'oficina',
	'reparacion_externa');

-- DROP TYPE public."modo_transporte_enum";

CREATE TYPE public."modo_transporte_enum" AS ENUM (
	'lancha_rapida',
	'avion',
	'camioneta',
	'auto',
	'helicoptero',
	'barcaza',
	'otro');

-- DROP TYPE public."movimiento_estado";

CREATE TYPE public."movimiento_estado" AS ENUM (
	'pendiente',
	'en_transito',
	'recibido',
	'cancelado');

-- DROP TYPE public."movimiento_tipo";

CREATE TYPE public."movimiento_tipo" AS ENUM (
	'ingreso',
	'traslado',
	'devolucion',
	'baja');

-- DROP TYPE public."objeto_movimiento";

CREATE TYPE public."objeto_movimiento" AS ENUM (
	'equipo',
	'componente');

-- DROP TYPE public."operatividad";

CREATE TYPE public."operatividad" AS ENUM (
	'operativo',
	'no_operativo',
	'restringido');

-- DROP TYPE public."piloto_estado";

CREATE TYPE public."piloto_estado" AS ENUM (
	'con_centro',
	'sin_centro');

-- DROP TYPE public."piloto_situacion";

CREATE TYPE public."piloto_situacion" AS ENUM (
	'en_turno',
	'descanso',
	'licencia',
	'vacaciones',
	'sin_centro',
	'en_spot');

-- DROP TYPE public."prestamo_estado";

CREATE TYPE public."prestamo_estado" AS ENUM (
	'activo',
	'devuelto',
	'definitivo');

-- DROP TYPE public."rol_componente_en_equipo";

CREATE TYPE public."rol_componente_en_equipo" AS ENUM (
	'rov',
	'controlador',
	'umbilical',
	'sensor',
	'grabber');

-- DROP TYPE public."rol_usuario";

CREATE TYPE public."rol_usuario" AS ENUM (
	'dev',
	'admin',
	'oficina',
	'centro');

-- DROP SEQUENCE public.pilotos_codigo_seq;

CREATE SEQUENCE public.pilotos_codigo_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 9223372036854775807
	START 1
	CACHE 1
	NO CYCLE;-- public.empresas definition

-- Drop table

-- DROP TABLE public.empresas;

CREATE TABLE public.empresas (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	nombre text NOT NULL,
	slug text NOT NULL,
	display_name text NULL,
	estado public."estado_activo_inactivo" DEFAULT 'activo'::estado_activo_inactivo NOT NULL,
	is_demo bool DEFAULT false NOT NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT empresas_nombre_key UNIQUE (nombre),
	CONSTRAINT empresas_pkey PRIMARY KEY (id),
	CONSTRAINT empresas_slug_key UNIQUE (slug)
);

-- Table Triggers

create trigger empresas_touch_updated_at before
update
    on
    public.empresas for each row execute function fn_touch_updated_at();


-- public.maestros_empresa_bak_20250929_1547 definition

-- Drop table

-- DROP TABLE public.maestros_empresa_bak_20250929_1547;

CREATE TABLE public.maestros_empresa_bak_20250929_1547 (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	nombre text NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT maestros_empresa_pkey PRIMARY KEY (id)
);


-- public.maestros_centro_bak_20250929_1547 definition

-- Drop table

-- DROP TABLE public.maestros_centro_bak_20250929_1547;

CREATE TABLE public.maestros_centro_bak_20250929_1547 (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	empresa_id uuid NULL,
	zona_id uuid NULL,
	nombre text NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT maestros_centro_pkey PRIMARY KEY (id),
	CONSTRAINT maestros_centro_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.maestros_empresa_bak_20250929_1547(id) ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX maestros_centro_empresa_id_idx ON public.maestros_centro_bak_20250929_1547 USING btree (empresa_id);
CREATE INDEX maestros_centro_zona_id_idx ON public.maestros_centro_bak_20250929_1547 USING btree (zona_id);


-- public.zonas definition

-- Drop table

-- DROP TABLE public.zonas;

CREATE TABLE public.zonas (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	nombre text NOT NULL,
	slug text NOT NULL,
	empresa_id uuid NOT NULL,
	is_demo bool DEFAULT false NOT NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT zonas_empresa_nombre_uk UNIQUE (empresa_id, nombre),
	CONSTRAINT zonas_empresa_slug_uk UNIQUE (empresa_id, slug),
	CONSTRAINT zonas_id_empresa_uk UNIQUE (id, empresa_id),
	CONSTRAINT zonas_pkey PRIMARY KEY (id),
	CONSTRAINT zonas_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id) ON DELETE CASCADE
);

-- Table Triggers

create trigger zonas_touch_updated_at before
update
    on
    public.zonas for each row execute function fn_touch_updated_at();


-- public.centros definition

-- Drop table

-- DROP TABLE public.centros;

CREATE TABLE public.centros (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	nombre text NOT NULL,
	slug text NOT NULL,
	empresa_id uuid NOT NULL,
	zona_id uuid NOT NULL,
	estado public."estado_activo_inactivo" DEFAULT 'activo'::estado_activo_inactivo NOT NULL,
	is_demo bool DEFAULT false NOT NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT centros_nombre_key UNIQUE (nombre),
	CONSTRAINT centros_pkey PRIMARY KEY (id),
	CONSTRAINT centros_slug_key UNIQUE (slug),
	CONSTRAINT centros_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id) ON DELETE RESTRICT,
	CONSTRAINT centros_zona_empresa_fk FOREIGN KEY (zona_id,empresa_id) REFERENCES public.zonas(id,empresa_id),
	CONSTRAINT centros_zona_id_fkey FOREIGN KEY (zona_id) REFERENCES public.zonas(id) ON DELETE RESTRICT
);

-- Table Triggers

create trigger centros_touch_updated_at before
update
    on
    public.centros for each row execute function fn_touch_updated_at();


-- public.componentes definition

-- Drop table

-- DROP TABLE public.componentes;

CREATE TABLE public.componentes (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	empresa_id uuid NOT NULL,
	zona_id uuid NULL,
	centro_id uuid NULL,
	tipo public."componente_tipo" NOT NULL,
	codigo text NOT NULL,
	estado public."estado_activo_inactivo" DEFAULT 'activo'::estado_activo_inactivo NOT NULL,
	fecha_activo timestamptz NULL,
	fecha_inactivo timestamptz NULL,
	motivo_inactivo text NULL,
	serie text NOT NULL,
	"operatividad" public."operatividad" DEFAULT 'operativo'::operatividad NOT NULL,
	condicion public."componente_condicion" DEFAULT 'normal'::componente_condicion NOT NULL,
	ubicacion public."componente_ubicacion" NULL,
	ubicacion_detalle text NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT componentes_baja_ubicacion_ck CHECK ((NOT ((condicion = 'baja'::componente_condicion) AND (ubicacion IS NOT NULL)))),
	CONSTRAINT componentes_codigo_key UNIQUE (codigo),
	CONSTRAINT componentes_pkey PRIMARY KEY (id),
	CONSTRAINT componentes_serie_key UNIQUE (serie),
	CONSTRAINT componentes_centro_id_fkey FOREIGN KEY (centro_id) REFERENCES public.centros(id),
	CONSTRAINT componentes_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id),
	CONSTRAINT componentes_zona_id_fkey FOREIGN KEY (zona_id) REFERENCES public.zonas(id)
);

-- Table Triggers

create trigger componentes_touch_updated_at before
update
    on
    public.componentes for each row execute function fn_touch_updated_at();
create trigger tg_componentes_au_disolver_equipo_si_baja_rov after
update
    on
    public.componentes for each row execute function tg_fn_componentes_au_disolver_equipo_si_baja_rov();


-- public.config_centro definition

-- Drop table

-- DROP TABLE public.config_centro;

CREATE TABLE public.config_centro (
	centro_id uuid NOT NULL,
	hora_corte time DEFAULT '23:59:00'::time without time zone NOT NULL,
	ventana_edicion_horas int4 DEFAULT 24 NOT NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT config_centro_pkey PRIMARY KEY (centro_id),
	CONSTRAINT config_centro_centro_id_fkey FOREIGN KEY (centro_id) REFERENCES public.centros(id) ON DELETE CASCADE
);

-- Table Triggers

create trigger config_centro_touch_updated_at before
update
    on
    public.config_centro for each row execute function fn_touch_updated_at();


-- public.equipos definition

-- Drop table

-- DROP TABLE public.equipos;

CREATE TABLE public.equipos (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	empresa_id uuid NOT NULL,
	zona_id uuid NULL,
	centro_id uuid NULL,
	codigo text NOT NULL,
	estado public."equipo_estado" DEFAULT 'vigente'::equipo_estado NOT NULL,
	fecha_activo timestamptz NULL,
	fecha_inactivo timestamptz NULL,
	motivo_inactivo text NULL,
	"operatividad" public."operatividad" DEFAULT 'operativo'::operatividad NOT NULL,
	condicion public."equipo_condicion" DEFAULT 'normal'::equipo_condicion NOT NULL,
	rol public."equipo_rol" NULL,
	ubicacion public."equipo_ubicacion" NULL,
	ubicacion_detalle text NULL,
	rov_componente_id uuid NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT equipos_baja_ubicacion_ck CHECK ((NOT ((condicion = 'baja'::equipo_condicion) AND (ubicacion IS NOT NULL)))),
	CONSTRAINT equipos_codigo_key UNIQUE (codigo),
	CONSTRAINT equipos_pkey PRIMARY KEY (id),
	CONSTRAINT equipos_centro_id_fkey FOREIGN KEY (centro_id) REFERENCES public.centros(id),
	CONSTRAINT equipos_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id),
	CONSTRAINT equipos_rov_componente_id_fkey FOREIGN KEY (rov_componente_id) REFERENCES public.componentes(id),
	CONSTRAINT equipos_zona_id_fkey FOREIGN KEY (zona_id) REFERENCES public.zonas(id)
);

-- Table Triggers

create trigger equipos_touch_updated_at before
update
    on
    public.equipos for each row execute function fn_touch_updated_at();


-- public.perfiles definition

-- Drop table

-- DROP TABLE public.perfiles;

CREATE TABLE public.perfiles (
	id uuid NOT NULL,
	rol public."rol_usuario" NOT NULL,
	empresa_id uuid NULL,
	centro_id uuid NULL,
	nombre text NULL,
	email text NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT perfiles_pkey PRIMARY KEY (id),
	CONSTRAINT perfiles_rol_check CHECK ((rol = ANY (ARRAY['admin'::rol_usuario, 'dev'::rol_usuario, 'oficina'::rol_usuario, 'centro'::rol_usuario]))),
	CONSTRAINT perfiles_centro_id_fkey FOREIGN KEY (centro_id) REFERENCES public.centros(id),
	CONSTRAINT perfiles_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id)
);
CREATE UNIQUE INDEX perfiles_email_uk ON public.perfiles USING btree (email) WHERE (email IS NOT NULL);

-- Table Triggers

create trigger perfiles_touch_updated_at before
update
    on
    public.perfiles for each row execute function fn_touch_updated_at();


-- public.pilotos definition

-- Drop table

-- DROP TABLE public.pilotos;

CREATE TABLE public.pilotos (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	nombre text NOT NULL,
	apellido_paterno text NOT NULL,
	apellido_materno text NULL,
	rut text NOT NULL,
	email text NOT NULL,
	centro_id uuid NULL,
	estado public."piloto_estado" NULL,
	situacion public."piloto_situacion" NULL,
	fecha_contratacion date NULL,
	fecha_desvinculacion date NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	codigo text DEFAULT 'PIL-'::text || lpad(nextval('pilotos_codigo_seq'::regclass)::text, 6, '0'::text) NULL,
	empresa_id uuid NULL,
	alias text NULL,
	telefono text NULL,
	turno text NULL,
	notas text NULL,
	created_by uuid NULL,
	updated_by uuid NULL,
	activo bool DEFAULT true NOT NULL,
	CONSTRAINT pilotos_email_key UNIQUE (email),
	CONSTRAINT pilotos_pkey PRIMARY KEY (id),
	CONSTRAINT pilotos_rut_key UNIQUE (rut),
	CONSTRAINT pilotos_centro_fk FOREIGN KEY (centro_id) REFERENCES public.centros(id) ON DELETE SET NULL DEFERRABLE,
	CONSTRAINT pilotos_empresa_fk FOREIGN KEY (empresa_id) REFERENCES public.empresas(id) ON DELETE RESTRICT DEFERRABLE
);
CREATE INDEX idx_pilotos_activo ON public.pilotos USING btree (activo);
CREATE INDEX idx_pilotos_centro_id ON public.pilotos USING btree (centro_id);
CREATE INDEX idx_pilotos_empresa_id ON public.pilotos USING btree (empresa_id);
CREATE INDEX pilotos_centro_idx ON public.pilotos USING btree (centro_id);
CREATE UNIQUE INDEX pilotos_codigo_unq ON public.pilotos USING btree (codigo);
CREATE INDEX pilotos_empresa_idx ON public.pilotos USING btree (empresa_id);
CREATE UNIQUE INDEX pilotos_unq_empresa_nombre ON public.pilotos USING btree (empresa_id, nombre);
CREATE UNIQUE INDEX uidx_pilotos_centro_nombre ON public.pilotos USING btree (centro_id, lower(nombre)) WHERE (nombre IS NOT NULL);

-- Table Triggers

create trigger pilotos_set_timestamp before
update
    on
    public.pilotos for each row execute function tg_set_timestamp();
create trigger pilotos_touch_updated_at before
update
    on
    public.pilotos for each row execute function fn_touch_updated_at();
create trigger trg_pilotos_set_updated_at before
update
    on
    public.pilotos for each row execute function tg__set_updated_at();
create trigger trg_pilotos_sync_empresa before
insert
    or
update
    of centro_id,
    empresa_id on
    public.pilotos for each row execute function tg_pilotos_sync_empresa();


-- public.prestamos definition

-- Drop table

-- DROP TABLE public.prestamos;

CREATE TABLE public.prestamos (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	estado public."prestamo_estado" DEFAULT 'activo'::prestamo_estado NOT NULL,
	equipo_origen_id uuid NOT NULL,
	equipo_destino_id uuid NOT NULL,
	componente_id uuid NOT NULL,
	responsable_id uuid NOT NULL,
	motivo text NOT NULL,
	fecha_prestamo timestamptz DEFAULT now() NOT NULL,
	fecha_devuelto timestamptz NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	empresa_id uuid NULL,
	centro_id uuid NULL,
	CONSTRAINT prestamos_pkey PRIMARY KEY (id),
	CONSTRAINT prestamos_componente_id_fkey FOREIGN KEY (componente_id) REFERENCES public.componentes(id),
	CONSTRAINT prestamos_equipo_destino_id_fkey FOREIGN KEY (equipo_destino_id) REFERENCES public.equipos(id),
	CONSTRAINT prestamos_equipo_origen_id_fkey FOREIGN KEY (equipo_origen_id) REFERENCES public.equipos(id),
	CONSTRAINT prestamos_responsable_id_fkey FOREIGN KEY (responsable_id) REFERENCES public.perfiles(id)
);
CREATE UNIQUE INDEX prestamos_activo_por_componente_uk ON public.prestamos USING btree (componente_id) WHERE (estado = 'activo'::prestamo_estado);

-- Table Triggers

create trigger prestamos_touch_updated_at before
update
    on
    public.prestamos for each row execute function fn_touch_updated_at();
create trigger tr_audit_prestamos_cud after
insert
    or
delete
    or
update
    on
    public.prestamos for each row execute function tr_audit_event();
create trigger tr_prestamos_enforce_perfil_biu before
insert
    or
update
    on
    public.prestamos for each row execute function tr_prestamos_enforce_perfil();


-- public.bitacora definition

-- Drop table

-- DROP TABLE public.bitacora;

CREATE TABLE public.bitacora (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	fecha date NOT NULL,
	"jornada" public."jornada" NULL,
	empresa_id uuid NOT NULL,
	zona_id uuid NULL,
	centro_id uuid NOT NULL,
	piloto_id uuid NOT NULL,
	"estado_puerto" public."estado_puerto" NULL,
	"equipo_usado" public."equipo_usado" DEFAULT 'principal'::equipo_usado NULL,
	comentarios text NULL,
	motivo_atraso text NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT bitacora_pkey PRIMARY KEY (id),
	CONSTRAINT bitacora_centro_id_fkey FOREIGN KEY (centro_id) REFERENCES public.centros(id),
	CONSTRAINT bitacora_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES public.empresas(id),
	CONSTRAINT bitacora_piloto_id_fkey FOREIGN KEY (piloto_id) REFERENCES public.perfiles(id),
	CONSTRAINT bitacora_zona_id_fkey FOREIGN KEY (zona_id) REFERENCES public.zonas(id)
);

-- Table Triggers

create trigger bitacora_touch_updated_at before
update
    on
    public.bitacora for each row execute function fn_touch_updated_at();
create trigger tr_audit_bitacora_cud after
insert
    or
delete
    or
update
    on
    public.bitacora for each row execute function tr_audit_event();


-- public.bitacora_items definition

-- Drop table

-- DROP TABLE public.bitacora_items;

CREATE TABLE public.bitacora_items (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	bitacora_id uuid NOT NULL,
	actividad public."actividad_bitacora" NOT NULL,
	detalle text NULL,
	"equipo_usado" public."equipo_usado" DEFAULT 'principal'::equipo_usado NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT bitacora_items_pkey PRIMARY KEY (id),
	CONSTRAINT bitacora_items_bitacora_id_fkey FOREIGN KEY (bitacora_id) REFERENCES public.bitacora(id) ON DELETE CASCADE
);

-- Table Triggers

create trigger bitacora_items_touch_updated_at before
update
    on
    public.bitacora_items for each row execute function fn_touch_updated_at();


-- public.equipo_componente definition

-- Drop table

-- DROP TABLE public.equipo_componente;

CREATE TABLE public.equipo_componente (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	equipo_id uuid NOT NULL,
	componente_id uuid NOT NULL,
	rol_componente public."rol_componente_en_equipo" NOT NULL,
	fecha_asignacion timestamptz DEFAULT now() NOT NULL,
	fecha_desasignacion timestamptz NULL,
	empresa_id uuid NULL,
	created_at timestamptz DEFAULT now() NULL,
	updated_at timestamptz NULL,
	CONSTRAINT equipo_componente_pkey PRIMARY KEY (id),
	CONSTRAINT equipo_componente_componente_id_fkey FOREIGN KEY (componente_id) REFERENCES public.componentes(id) ON DELETE RESTRICT,
	CONSTRAINT equipo_componente_equipo_id_fkey FOREIGN KEY (equipo_id) REFERENCES public.equipos(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX equipo_comp_componente_vigente_uk ON public.equipo_componente USING btree (componente_id) WHERE (fecha_desasignacion IS NULL);
CREATE UNIQUE INDEX equipo_comp_rov_vigente_por_equipo_uk ON public.equipo_componente USING btree (equipo_id) WHERE ((fecha_desasignacion IS NULL) AND (rol_componente = 'rov'::rol_componente_en_equipo));
CREATE UNIQUE INDEX equipo_comp_unico_roles_basicos_uk ON public.equipo_componente USING btree (equipo_id, rol_componente) WHERE ((fecha_desasignacion IS NULL) AND (rol_componente = ANY (ARRAY['controlador'::rol_componente_en_equipo, 'umbilical'::rol_componente_en_equipo])));

-- Table Triggers

create trigger tg_equipo_componente_ai_sync after
insert
    or
update
    on
    public.equipo_componente for each row execute function tg_fn_equipo_componente_ai_sync();
create trigger tg_equipo_componente_biu_enforce before
insert
    or
update
    on
    public.equipo_componente for each row execute function tg_fn_equipo_componente_biu_enforce();


-- public.movimientos definition

-- Drop table

-- DROP TABLE public.movimientos;

CREATE TABLE public.movimientos (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	tipo public."movimiento_tipo" NOT NULL,
	estado public."movimiento_estado" DEFAULT 'pendiente'::movimiento_estado NOT NULL,
	objeto public."objeto_movimiento" NOT NULL,
	equipo_id uuid NULL,
	componente_id uuid NULL,
	origen_tipo public."lugar_operacion" NOT NULL,
	origen_detalle text NOT NULL,
	destino_tipo public."lugar_operacion" NOT NULL,
	destino_detalle text NOT NULL,
	responsable_origen_id uuid NOT NULL,
	responsable_destino_id uuid NULL,
	nota text NULL,
	fecha_creado timestamptz DEFAULT now() NOT NULL,
	fecha_envio timestamptz NULL,
	fecha_recepcion timestamptz NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	empresa_id uuid NULL,
	origen_centro_id uuid NULL,
	destino_centro_id uuid NULL,
	responsable_envio_id uuid NULL,
	responsable_recepcion_id uuid NULL,
	modo_transporte public."modo_transporte_enum" NULL,
	CONSTRAINT movimientos_objeto_xor_ck CHECK ((((objeto = 'equipo'::objeto_movimiento) AND (equipo_id IS NOT NULL) AND (componente_id IS NULL)) OR ((objeto = 'componente'::objeto_movimiento) AND (componente_id IS NOT NULL) AND (equipo_id IS NULL)))),
	CONSTRAINT movimientos_pkey PRIMARY KEY (id),
	CONSTRAINT movimientos_componente_id_fkey FOREIGN KEY (componente_id) REFERENCES public.componentes(id),
	CONSTRAINT movimientos_equipo_id_fkey FOREIGN KEY (equipo_id) REFERENCES public.equipos(id),
	CONSTRAINT movimientos_responsable_destino_id_fkey FOREIGN KEY (responsable_destino_id) REFERENCES public.perfiles(id),
	CONSTRAINT movimientos_responsable_origen_id_fkey FOREIGN KEY (responsable_origen_id) REFERENCES public.perfiles(id)
);

-- Table Triggers

create trigger movimientos_touch_updated_at before
update
    on
    public.movimientos for each row execute function fn_touch_updated_at();


-- public.piloto_situaciones definition

-- Drop table

-- DROP TABLE public.piloto_situaciones;

CREATE TABLE public.piloto_situaciones (
	id uuid DEFAULT gen_random_uuid() NOT NULL,
	piloto_id uuid NOT NULL,
	situacion public."piloto_situacion" NOT NULL,
	fecha_inicio timestamptz NOT NULL,
	fecha_fin timestamptz NULL,
	motivo text NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT piloto_situaciones_pkey PRIMARY KEY (id),
	CONSTRAINT piloto_situaciones_piloto_id_fkey FOREIGN KEY (piloto_id) REFERENCES public.pilotos(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX piloto_situacion_vigente_uk ON public.piloto_situaciones USING btree (piloto_id) WHERE (fecha_fin IS NULL);

-- Table Triggers

create trigger piloto_situaciones_touch_updated_at before
update
    on
    public.piloto_situaciones for each row execute function fn_touch_updated_at();


-- public.maestros_centro source

CREATE OR REPLACE VIEW public.maestros_centro
AS SELECT id,
    nombre,
    slug,
    empresa_id,
    zona_id,
    estado,
    is_demo,
    created_at,
    updated_at
   FROM centros;


-- public.maestros_empresa source

CREATE OR REPLACE VIEW public.maestros_empresa
AS SELECT id,
    nombre,
    slug,
    display_name,
    estado,
    is_demo,
    created_at,
    updated_at
   FROM empresas;


-- public.v_comunicacion_zona source

CREATE OR REPLACE VIEW public.v_comunicacion_zona
AS SELECT empresa_id,
    centro_id,
    zona_id,
    piloto_id,
    piloto_nombre,
    piloto_activo
   FROM v_comunicacion_zona_v2() v_comunicacion_zona_v2(empresa_id, centro_id, zona_id, piloto_id, piloto_nombre, piloto_activo);


-- public.v_comunicacion_zona_bak_20250929124943 source

CREATE OR REPLACE VIEW public.v_comunicacion_zona_bak_20250929124943
AS SELECT empresa_id,
    centro_id,
    count(*) AS pilotos_total,
    count(*) FILTER (WHERE estado::text = 'con_centro'::text) AS pilotos_con_centro,
    count(*) FILTER (WHERE estado::text = 'sin_centro'::text) AS pilotos_sin_centro,
    jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'ap_pat', apellido_paterno, 'rut', rut, 'estado', estado::text, 'codigo', codigo) ORDER BY nombre) AS pilotos_json
   FROM pilotos p
  GROUP BY empresa_id, centro_id;



-- DROP FUNCTION public.app_centro_id();

CREATE OR REPLACE FUNCTION public.app_centro_id()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_claims jsonb;
  v_text   text;
  v_uuid   uuid;
BEGIN
  BEGIN
    v_claims := current_setting('request.jwt.claims', true)::jsonb;
  EXCEPTION WHEN others THEN
    v_claims := NULL;
  END;

  v_text := COALESCE(v_claims->>'centro_id', current_setting('app.centro_id', true));
  IF v_text IS NULL OR v_text = '' THEN
    RETURN NULL;
  END IF;

  BEGIN
    v_uuid := v_text::uuid;
  EXCEPTION WHEN others THEN
    RETURN NULL;
  END;

  RETURN v_uuid;
END
$function$
;

-- DROP FUNCTION public.app_clear_debug_claims();

CREATE OR REPLACE FUNCTION public.app_clear_debug_claims()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  PERFORM set_config('app.role', '', true);
  PERFORM set_config('app.empresa_id', '', true);
  PERFORM set_config('app.centro_id', '', true);
END
$function$
;

-- DROP FUNCTION public.app_empresa_id();

CREATE OR REPLACE FUNCTION public.app_empresa_id()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_claims jsonb;
  v_text   text;
  v_uuid   uuid;
BEGIN
  BEGIN
    v_claims := current_setting('request.jwt.claims', true)::jsonb;
  EXCEPTION WHEN others THEN
    v_claims := NULL;
  END;

  v_text := COALESCE(v_claims->>'empresa_id', current_setting('app.empresa_id', true));
  IF v_text IS NULL OR v_text = '' THEN
    RETURN NULL;
  END IF;

  BEGIN
    v_uuid := v_text::uuid;
  EXCEPTION WHEN others THEN
    RETURN NULL;
  END;

  RETURN v_uuid;
END
$function$
;

-- DROP FUNCTION public.app_is_role(text);

CREATE OR REPLACE FUNCTION public.app_is_role(target text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_role   text;
  v_claims jsonb;
BEGIN
  BEGIN
    v_claims := current_setting('request.jwt.claims', true)::jsonb;
  EXCEPTION WHEN others THEN
    v_claims := NULL;
  END;

  v_role := COALESCE(
    NULLIF(COALESCE(v_claims->>'role', current_setting('app.role', true)), ''),
    NULL
  );

  RETURN v_role = target;
END
$function$
;

-- DROP FUNCTION public.app_set_debug_claims(jsonb);

CREATE OR REPLACE FUNCTION public.app_set_debug_claims(p jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  r text := COALESCE(p->>'role', NULL);
  e text := COALESCE(p->>'empresa_id', NULL);
  c text := COALESCE(p->>'centro_id', NULL);
BEGIN
  IF r IS NOT NULL THEN
    PERFORM set_config('app.role', r, true);
  END IF;
  IF e IS NOT NULL THEN
    PERFORM set_config('app.empresa_id', e, true);
  END IF;
  IF c IS NOT NULL THEN
    PERFORM set_config('app.centro_id', c, true);
  END IF;
END
$function$
;

-- DROP FUNCTION public.fn_equipo_disolver_por_baja_rov(uuid, uuid);

CREATE OR REPLACE FUNCTION public.fn_equipo_disolver_por_baja_rov(_equipo_id uuid, _rov_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_centro uuid;
BEGIN
  -- Cerrar todas las asignaciones vigentes del equipo
  UPDATE public.equipo_componente ec

   WHERE ec.equipo_id = _equipo_id
     AND ec.fecha_desasignacion IS NULL;

  -- Denormalización: limpiar referencia a ROV y marcar equipo como no vigente
  UPDATE public.equipos e

         condicion = COALESCE(e.condicion, 'baja'),
         rov_componente_id = NULL,
         updated_at = now()
   WHERE e.id = _equipo_id;

  -- Reubicar componentes sin equipo vigente → centro del equipo
  SELECT e.centro_id INTO v_centro FROM public.equipos e WHERE e.id = _equipo_id;

  UPDATE public.componentes c

         ubicacion_detalle = v_centro,
         updated_at = now()
   WHERE c.id IN (
         SELECT ec2.componente_id
         FROM public.equipo_componente ec2
         WHERE ec2.equipo_id = _equipo_id
       )
     AND NOT EXISTS (
         SELECT 1 FROM public.equipo_componente ec3
         WHERE ec3.componente_id = c.id
           AND ec3.fecha_desasignacion IS NULL
       );

  RAISE NOTICE 'F2:R7 equipo disuelto por ROV en baja (equipo_id=%, rov_id=%)', _equipo_id, _rov_id;
END;
$function$
;

-- DROP FUNCTION public.fn_equipo_sync_rov_denorm(uuid);

CREATE OR REPLACE FUNCTION public.fn_equipo_sync_rov_denorm(_equipo_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  _rov_actual uuid;
  _rov_vigente uuid;
BEGIN
  SELECT e.rov_componente_id INTO _rov_actual
  FROM public.equipos e
  WHERE e.id = _equipo_id;

  SELECT ec.componente_id
    INTO _rov_vigente
  FROM public.equipo_componente ec
  WHERE ec.equipo_id = _equipo_id
    AND ec.rol_componente = 'rov'
    AND ec.fecha_desasignacion IS NULL
  ORDER BY ec.fecha_asignacion DESC
  LIMIT 1;

  IF _rov_actual IS DISTINCT FROM _rov_vigente THEN
    UPDATE public.equipos

           updated_at = now()
     WHERE id = _equipo_id;
  END IF;
END;
$function$
;

-- DROP FUNCTION public.fn_equipo_validar_asignacion(uuid, uuid, rol_componente_en_equipo);

CREATE OR REPLACE FUNCTION public.fn_equipo_validar_asignacion(_equipo_id uuid, _componente_id uuid, _rol rol_componente_en_equipo)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_estado_equipo public.equipo_estado;
  v_condicion public.componente_condicion;
  v_operatividad public.operatividad;
  v_es_rov boolean := (_rol = 'rov');
  v_es_basico boolean := (_rol IN ('controlador','umbilical'));
  v_ya_existe integer;
BEGIN
  -- R4: equipo debe estar vigente
  SELECT e.estado INTO v_estado_equipo
  FROM public.equipos e
  WHERE e.id = _equipo_id;

  IF v_estado_equipo IS DISTINCT FROM 'vigente' THEN
    RAISE EXCEPTION 'F2:R4 equipo no vigente no admite asignaciones'
      USING ERRCODE = '23514', HINT = 'Cambie estado del equipo a vigente o cierre la asignación.';
  END IF;

  -- R5: componente no asignable si condicion='baja' o operatividad en {'no_operativo','en_reparacion'}
  SELECT c.condicion, c.operatividad INTO v_condicion, v_operatividad
  FROM public.componentes c
  WHERE c.id = _componente_id;

  IF v_condicion = 'baja'
     OR v_operatividad::text IN ('no_operativo','en_reparacion') THEN
    RAISE EXCEPTION 'F2:R5 componente no asignable por condicion/operatividad'
      USING ERRCODE = '23514', HINT = 'Solo componentes operativos o restringidos pueden asignarse.';
  END IF;

  -- R1: único ROV vigente por equipo
  IF v_es_rov THEN
    SELECT count(*) INTO v_ya_existe
    FROM public.equipo_componente ec
    WHERE ec.equipo_id = _equipo_id
      AND ec.rol_componente = 'rov'
      AND ec.fecha_desasignacion IS NULL
      AND ec.componente_id <> _componente_id;
    IF v_ya_existe > 0 THEN
      RAISE EXCEPTION 'F2:R1 unico ROV vigente por equipo'
        USING ERRCODE = '23514', HINT = 'Desasigne el ROV anterior o disuelva el equipo.';
    END IF;
  END IF;

  -- R2: máximo 1 controlador y 1 umbilical
  IF v_es_basico THEN
    SELECT count(*) INTO v_ya_existe
    FROM public.equipo_componente ec
    WHERE ec.equipo_id = _equipo_id
      AND ec.rol_componente = _rol
      AND ec.fecha_desasignacion IS NULL
      AND ec.componente_id <> _componente_id;
    IF v_ya_existe > 0 THEN
      RAISE EXCEPTION 'F2:R2 max 1 controlador/umbilical por equipo'
        USING ERRCODE = '23514', HINT = 'Cierre la asignación vigente del mismo rol antes de crear otra.';
    END IF;
  END IF;
END;
$function$
;

-- DROP FUNCTION public.fn_touch_updated_at();

CREATE OR REPLACE FUNCTION public.fn_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$
;

-- DROP FUNCTION public.tg_fn_componentes_au_disolver_equipo_si_baja_rov();

CREATE OR REPLACE FUNCTION public.tg_fn_componentes_au_disolver_equipo_si_baja_rov()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_equipo uuid;
BEGIN
  -- Aplica si el componente es un ROV y su condicion pasa a 'baja' (comparación por texto)
  IF NEW.tipo::text = 'rov'
     AND NEW.condicion::text = 'baja'
     AND (OLD.condicion IS DISTINCT FROM NEW.condicion) THEN

    SELECT ec.equipo_id INTO v_equipo
    FROM public.equipo_componente ec
    WHERE ec.componente_id = NEW.id
      AND ec.rol_componente = 'rov'
      AND ec.fecha_desasignacion IS NULL
    LIMIT 1;

    IF v_equipo IS NOT NULL THEN
      PERFORM public.fn_equipo_disolver_por_baja_rov(v_equipo, NEW.id);
      RAISE NOTICE 'F2:R7 equipo disuelto por ROV en baja (equipo_id=%, rov_id=%)', v_equipo, NEW.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;

-- DROP FUNCTION public.tg_fn_equipo_componente_ai_sync();

CREATE OR REPLACE FUNCTION public.tg_fn_equipo_componente_ai_sync()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_quedan_vigentes integer;
  v_centro uuid;
  v_equipo_old uuid := COALESCE(OLD.equipo_id, NEW.equipo_id);
  v_equipo_new uuid := NEW.equipo_id;
  v_comp uuid := COALESCE(NEW.componente_id, OLD.componente_id);
BEGIN
  -- Siempre sincronizar denormalización del ROV del equipo afectado
  PERFORM public.fn_equipo_sync_rov_denorm(v_equipo_new);
  IF v_equipo_old IS DISTINCT FROM v_equipo_new THEN
    PERFORM public.fn_equipo_sync_rov_denorm(v_equipo_old);
  END IF;

  -- R6: Ubicaciones de componente según asignación/desasignación
  IF NEW.fecha_desasignacion IS NULL THEN
    -- Al quedar vigente en un equipo
    UPDATE public.componentes c

           ubicacion_detalle = v_equipo_new,
           updated_at = now()
     WHERE c.id = v_comp;
  ELSE
    -- Al desasignar: si ya no queda NINGUNA vigente para ese componente → mover a centro del equipo
    SELECT count(*) INTO v_quedan_vigentes
    FROM public.equipo_componente ec
    WHERE ec.componente_id = v_comp
      AND ec.fecha_desasignacion IS NULL;

    IF v_quedan_vigentes = 0 THEN
      SELECT e.centro_id INTO v_centro FROM public.equipos e WHERE e.id = v_equipo_old;
      UPDATE public.componentes c

             ubicacion_detalle = v_centro,
             updated_at = now()
       WHERE c.id = v_comp;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;

-- DROP FUNCTION public.tg_fn_equipo_componente_biu_enforce();

CREATE OR REPLACE FUNCTION public.tg_fn_equipo_componente_biu_enforce()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Solo validamos cuando la fila resultante queda VIGENTE (fecha_desasignacion IS NULL)
  IF (TG_OP = 'INSERT' AND NEW.fecha_desasignacion IS NULL)
     OR (TG_OP = 'UPDATE' AND NEW.fecha_desasignacion IS NULL) THEN
    PERFORM public.fn_equipo_validar_asignacion(NEW.equipo_id, NEW.componente_id, NEW.rol_componente);
  END IF;

  -- R9: dejar que el índice único parcial actúe si hay carrera.
  RETURN NEW;
END;
$function$
;

-- DROP FUNCTION public.tg_set_timestamp();

CREATE OR REPLACE FUNCTION public.tg_set_timestamp()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END$function$
;
