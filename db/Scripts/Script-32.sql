-- =====================================================================
-- F3 · PATCH MOVIMIENTOS — Fase B (constraint + índice parcial)  ✅
-- Archivo: db/migrations/2025-10-03_00b_f3_patch_movimientos_CONSTRAINT_INDEX.sql
-- ---------------------------------------------------------------------
-- Propósito:
--   • Agregar CHECK de estado compatible con ENUM o TEXT.
--   • Crear índice parcial por "pendiente" sin usar funciones no-IMMUTABLE.
-- Idempotente y con VALIDATE "best effort".
-- =====================================================================

BEGIN;
SELECT pg_advisory_xact_lock(74123028);
SET LOCAL search_path = public, app;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = notice;

-- 1) CHECK compatible (compara estado::text).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ck_movimientos_estado_valid'
      AND conrelid = 'public.movimientos'::regclass
  ) THEN
    EXECUTE $DDL$
      ALTER TABLE public.movimientos
      ADD CONSTRAINT ck_movimientos_estado_valid
      CHECK (
        estado IS NULL OR estado::text IN ('pendiente','enviado','recibido','cancelado')
      ) NOT VALID
    $DDL$;

    -- Intentar validar; si hay datos legacy, dejar NOT VALID
    BEGIN
      EXECUTE 'ALTER TABLE public.movimientos VALIDATE CONSTRAINT ck_movimientos_estado_valid';
    EXCEPTION WHEN others THEN
      RAISE NOTICE 'VALIDATE de ck_movimientos_estado_valid pospuesto: %', SQLERRM;
    END;
  END IF;
END$$;

-- 2) Índice parcial "pendiente" sin funciones en el predicado:
--    Si estado es ENUM, usamos literal tipado 'pendiente'::<enum>.
--    Si es TEXT (u otro), usamos 'pendiente' simple.
DO $$
DECLARE
  v_typ      regtype;
  v_is_enum  boolean;
  v_schema   text;
  v_idxname  text := 'ix_mov_objeto_pendiente';
BEGIN
  -- ¿Tipo real de la columna estado?
  SELECT a.atttypid::regtype, t.typtype, n.nspname
    INTO v_typ, v_is_enum, v_schema
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'estado'
  JOIN pg_type t ON t.oid = a.atttypid
  WHERE n.nspname='public' AND c.relname='movimientos';

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='movimientos' AND indexname=v_idxname
  ) THEN
    IF v_is_enum THEN
      -- Enum: literal tipado evita funciones en predicado
      EXECUTE format(
        'CREATE INDEX %I ON public.movimientos(objeto_tipo, objeto_id) WHERE estado = %L::%s',
        v_idxname, 'pendiente', v_typ::text
      );
    ELSE
      -- Texto u otro: comparación simple
      EXECUTE format(
        'CREATE INDEX %I ON public.movimientos(objeto_tipo, objeto_id) WHERE estado = %L',
        v_idxname, 'pendiente'
      );
    END IF;
  END IF;
END$$;

COMMIT;