-- =====================================================================
-- F3 · PATCH MOVIMIENTOS — Fase A (solo columnas)  ✅
-- Archivo: db/migrations/2025-10-03_00a_f3_patch_movimientos_COLUMNS.sql
-- ---------------------------------------------------------------------
-- Propósito:
--   • Agregar las columnas requeridas por las RPC sin tocar constraints ni índices.
--   • Asegurar que el smoke y las RPC encuentren el esquema mínimo.
-- Idempotente.
-- =====================================================================

BEGIN;
SELECT pg_advisory_xact_lock(74123029);
SET LOCAL search_path = public, app;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = notice;

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

COMMIT;