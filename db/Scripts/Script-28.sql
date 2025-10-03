-- =====================================================================
-- F3 · PATCH DE ESQUEMA — Alinear tabla public.movimientos al contrato de RPC
-- Archivo sugerido: db/migrations/2025-10-03_00a_f3_patch_movimientos.sql
-- ---------------------------------------------------------------------
-- Qué hace:
--   • Agrega columnas requeridas por las RPC (si no existen).
--   • Crea un CHECK seguro para estado (permite NULL en filas antiguas).
--   • Índice parcial para detectar/evitar dobles "pendientes" por objeto.
-- Idempotente: usa IF NOT EXISTS / chequeos en catálogos.
-- =====================================================================

BEGIN;
SELECT pg_advisory_xact_lock(74123029);
SET LOCAL search_path = public, app;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = notice;

-- 1) Columnas requeridas por contrato
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

-- 2) CHECK de estado (NULL permitido para filas legacy)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ck_movimientos_estado_valid'
      AND conrelid = 'public.movimientos'::regclass
  ) THEN
    ALTER TABLE public.movimientos
      ADD CONSTRAINT ck_movimientos_estado_valid
      CHECK (estado IS NULL OR estado IN ('pendiente','enviado','recibido','cancelado')) NOT VALID;
    ALTER TABLE public.movimientos VALIDATE CONSTRAINT ck_movimientos_estado_valid;
  END IF;
END$$;

-- 3) Índice parcial para consultas/validación de "pendiente" por objeto
CREATE INDEX IF NOT EXISTS ix_mov_objeto_pendiente
ON public.movimientos(objeto_tipo, objeto_id)
WHERE estado = 'pendiente';

COMMIT;

-- Verificación rápida (opcional)
-- SELECT column_name FROM information_schema.columns
--  WHERE table_schema='public' AND table_name='movimientos'
--    AND column_name IN ('objeto_tipo','objeto_id','origen_tipo','origen_detalle','destino_tipo','destino_detalle','estado','created_at','updated_at','created_by')
--  ORDER BY column_name;