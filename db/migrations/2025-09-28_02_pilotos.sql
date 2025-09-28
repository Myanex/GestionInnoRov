-- F1 — Catálogos (Pilotos) · FIX ensure columnas antes de FKs
-- Archivo: db/migrations/2025-09-28_02_pilotos.sql

BEGIN;
SELECT pg_advisory_xact_lock(10002); -- F1 lock

-- STEP: Crear tabla si no existe (estructura base)
CREATE TABLE IF NOT EXISTS public.pilotos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- columnas clave se asegurarán abajo con ADD COLUMN IF NOT EXISTS
  nombre        text NOT NULL,
  alias         text NULL,
  estado        text NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo','inactivo','baja')),
  telefono      text NULL,
  email         text NULL,
  turno         text NULL,
  notas         text NULL,

  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid NULL,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  updated_by    uuid NULL
);

-- STEP: Asegurar columnas requeridas (para entornos donde la tabla ya existía)
-- Nota: empresa_id se deja NULLABLE por compatibilidad; en F2 haremos backfill + NOT NULL.
ALTER TABLE public.pilotos
  ADD COLUMN IF NOT EXISTS empresa_id uuid NULL,
  ADD COLUMN IF NOT EXISTS centro_id  uuid NULL;

-- Código legible: si no existe la columna 'codigo', la agregamos como STORED generated
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='pilotos' AND column_name='codigo'
  ) THEN
    ALTER TABLE public.pilotos
    ADD COLUMN codigo text
      GENERATED ALWAYS AS (
        'PIL-' || lpad(to_char(extract(epoch from coalesce(created_at, now()))::bigint % 1000000, 'FM999999'), 6, '0')
      ) STORED;
  END IF;
END$$;

-- STEP: Trigger updated_at
CREATE OR REPLACE FUNCTION public.tg_set_timestamp()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='pilotos_set_timestamp') THEN
    CREATE TRIGGER pilotos_set_timestamp
    BEFORE UPDATE ON public.pilotos
    FOR EACH ROW
    EXECUTE FUNCTION public.tg_set_timestamp();
  END IF;
END$$;

-- STEP: Índices (ya existen columnas)
CREATE INDEX IF NOT EXISTS pilotos_empresa_idx ON public.pilotos (empresa_id);
CREATE INDEX IF NOT EXISTS pilotos_centro_idx  ON public.pilotos (centro_id);
CREATE UNIQUE INDEX IF NOT EXISTS pilotos_unq_empresa_nombre ON public.pilotos (empresa_id, nombre);

-- STEP: FKs opcionales (solo si existen tablas referenciadas)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='empresas')
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pilotos_empresa_fk') THEN
    ALTER TABLE public.pilotos
      ADD CONSTRAINT pilotos_empresa_fk
      FOREIGN KEY (empresa_id) REFERENCES public.empresas(id)
      ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='centros')
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pilotos_centro_fk') THEN
    ALTER TABLE public.pilotos
      ADD CONSTRAINT pilotos_centro_fk
      FOREIGN KEY (centro_id) REFERENCES public.centros(id)
      ON DELETE SET NULL DEFERRABLE INITIALLY IMMEDIATE;
  END IF;
END$$;

-- STEP: RLS (limpieza y recreación de policies f1_)
ALTER TABLE public.pilotos ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE pol record;
BEGIN
  FOR pol IN
    SELECT polname FROM pg_policy
    WHERE polrelid='public.pilotos'::regclass AND polname LIKE 'f1_%'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.pilotos;', pol.polname);
  END LOOP;
END$$;

-- Helpers requeridos desde F0: app_is_role(text), app_empresa_id(), app_centro_id()

CREATE POLICY f1_pilotos_select
ON public.pilotos
FOR SELECT
USING (
  app_is_role('admin') OR app_is_role('dev')
  OR (
    empresa_id = app_empresa_id()
    AND (
      app_is_role('oficina')
      OR (app_is_role('centro') AND (centro_id IS NULL OR centro_id = app_centro_id()))
    )
  )
);

CREATE POLICY f1_pilotos_insert
ON public.pilotos
FOR INSERT TO public
WITH CHECK (
  app_is_role('admin') OR (app_is_role('oficina') AND empresa_id = app_empresa_id())
);

CREATE POLICY f1_pilotos_update
ON public.pilotos
FOR UPDATE
USING (
  app_is_role('admin') OR (app_is_role('oficina') AND empresa_id = app_empresa_id())
)
WITH CHECK (
  app_is_role('admin') OR (app_is_role('oficina') AND empresa_id = app_empresa_id())
);

CREATE POLICY f1_pilotos_delete
ON public.pilotos
FOR DELETE
USING (app_is_role('admin'));

-- STEP: Grants (RLS gobierna filas)
GRANT SELECT ON public.pilotos TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.pilotos TO authenticated;

-- STEP: Prueba mínima rápida (opcional, comenta si usas automations en CI)
-- SELECT app_set_debug_claims(jsonb_build_object('role','admin'));
-- SELECT 1 WHERE EXISTS (SELECT 1 FROM public.pilotos);
-- SELECT app_clear_debug_claims();

COMMIT;
