-- =====================================================================
-- F3 · PATCH DE ESQUEMA (FIX2) — Compat con ENUM movimiento_estado
-- Archivo: db/migrations/2025-10-03_00a_f3_patch_movimientos_FIX2.sql
-- ---------------------------------------------------------------------
-- Cambios vs FIX1:
--   • El CHECK compara estado::text para no castear literales al ENUM.
--   • El índice parcial usa estado::text='pendiente' (compat enum/text).
--   • La VALIDACIÓN del CHECK es "best effort": si falla, se deja NOT VALID.
-- =====================================================================

BEGIN;
SELECT pg_advisory_xact_lock(74123029);
SET LOCAL search_path = public, app;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = notice;

-- 1) Columnas exigidas por contrato (no tocan tipos existentes)
ALTER TABLE public.movimientos
  ADD COLUMN IF NOT EXISTS objeto_tipo       text,
  ADD COLUMN IF NOT EXISTS objeto_id         uuid,
  ADD COLUMN IF NOT EXISTS origen_tipo       text,
  ADD COLUMN IF NOT EXISTS origen_detalle    text,
  ADD COLUMN IF NOT EXISTS destino_tipo      text,
  ADD COLUMN IF NOT EXISTS destino_detalle   text,
  ADD COLUMN IF NOT EXISTS estado            text,
  ADD COLUMN IF NOT EXISTS created_at        timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at        timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS created_by        uuid;

-- 2) CHECK de estado compatible con ENUM/text (no forzamos labels exactos)
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
        estado IS NULL
        OR estado::text IN ('pendiente','enviado','recibido','cancelado')
      ) NOT VALID
    $DDL$;

    -- Intentar VALIDATE; si falla por datos legacy, dejar NOT VALID y continuar
    BEGIN
      EXECUTE 'ALTER TABLE public.movimientos VALIDATE CONSTRAINT ck_movimientos_estado_valid';
    EXCEPTION WHEN others THEN
      RAISE NOTICE 'VALIDATE de ck_movimientos_estado_valid pospuesto: %', SQLERRM;
    END;
  END IF;
END$$;

-- 3) Índice parcial para "pendiente" (compat enum/text)
CREATE INDEX IF NOT EXISTS ix_mov_objeto_pendiente
ON public.movimientos(objeto_tipo, objeto_id)
WHERE estado::text = 'pendiente';

COMMIT;

-- (Opcional) Inspección de labels si el tipo es enum:
-- SELECT e.enumlabel
-- FROM pg_type t JOIN pg_enum e ON e.enumtypid=t.oid
-- WHERE t.typname='movimiento_estado'
-- ORDER BY e.enumsortorder;