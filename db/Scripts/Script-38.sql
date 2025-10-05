-- =====================================================================
-- F3 · PATCH MOVIMIENTOS — Fase B (constraint + índice) · FIX-BOOL ✅
-- Archivo: db/migrations/2025-10-03_00b_f3_patch_movimientos_CONSTRAINT_INDEX_FIXBOOL.sql
-- ---------------------------------------------------------------------
-- Cambios:
--   • Corrige bug: no castear typtype 'e' a boolean (se compara explícito).
--   • Índice parcial enum-aware sin funciones en el predicado.
--   • CHECK con estado::text (compat enum/text), VALIDATE best-effort.
-- =====================================================================

BEGIN;
SELECT pg_advisory_xact_lock(74123028);
SET LOCAL search_path = public, app;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = notice;

-- 1) CHECK compatible
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

    BEGIN
      EXECUTE 'ALTER TABLE public.movimientos VALIDATE CONSTRAINT ck_movimientos_estado_valid';
    EXCEPTION WHEN others THEN
      RAISE NOTICE 'VALIDATE pospuesto: %', SQLERRM;
    END;
  END IF;
END$$;

-- 2) Índice parcial por "pendiente" (sin funciones en predicado)
DO $$
DECLARE
  v_typ      regtype;
  v_typtype  text;   -- 'e' si enum
  v_idxname  text := 'ix_mov_objeto_pendiente';
  v_has_pend boolean := true;
BEGIN
  SELECT a.atttypid::regtype, t.typtype
    INTO v_typ, v_typtype
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'estado'
  JOIN pg_type t ON t.oid = a.atttypid
  WHERE n.nspname='public' AND c.relname='movimientos';

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='movimientos' AND indexname=v_idxname
  ) THEN
    IF v_typtype = 'e' THEN
      -- Verificar que exista el label 'pendiente' en el enum
      SELECT EXISTS (
        SELECT 1 FROM pg_enum e WHERE e.enumtypid = v_typ::oid AND e.enumlabel = 'pendiente'
      ) INTO v_has_pend;

      IF v_has_pend THEN
        EXECUTE format(
          'CREATE INDEX %I ON public.movimientos(objeto_tipo, objeto_id) WHERE estado = %L::%s',
          v_idxname, 'pendiente', v_typ::text
        );
      ELSE
        RAISE NOTICE 'Enum % no contiene label pendiente; se omite índice parcial.', v_typ::text;
      END IF;
    ELSE
      EXECUTE format(
        'CREATE INDEX %I ON public.movimientos(objeto_tipo, objeto_id) WHERE estado = %L',
        v_idxname, 'pendiente'
      );
    END IF;
  END IF;
END$$;

COMMIT;