-- =====================================================================
-- F3 · PRE-FLIGHT (SOLO LECTURA, COMPLETO) — Movimientos & Préstamos
-- Archivo sugerido: db/preflight/2025-10-03_00_f3_preflight.sql
-- ---------------------------------------------------------------------
-- Propósito
--   • Confirmar que el esquema satisface los prerrequisitos para F3.
--   • Detectar a priori columnas/índices faltantes que afectarían las RPC.
--   • Verificar idempotencia: presencia/ausencia de funciones objetivo.
--
-- Lineamientos
--   • BEGIN…ROLLBACK (no deja huella).
--   • Salidas “check / value / details” en JSONB para lectura rápida.
--   • Timeouts y locks acotados.
--
-- Catálogo alineado (conceptos clave)
--   • “reparacion_externa” es un TIPO DE UBICACIÓN/DESTINO (no un “tipo de movimiento”).
--   • Payload modelo: objeto (equipo|componente), origen/destino (tipo + detalle).
--   • Efectos de ubicación: opcionales, solo si columnas existen.
--
-- Orden recomendado de ejecución global
--   1) Este preflight
--   2) 2025-10-03_01_f3_rpc_movimientos.sql
--   3) 2025-10-03_02_f3_rpc_prestamos.sql
--   4) 2025-10-03_99_f3_smoke.sql
-- =====================================================================

BEGIN;

SET LOCAL search_path = public, app;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = notice;

-- STEP 0 — Objetos base requeridos
SELECT 'obj_exists' AS check,
       jsonb_build_object(
         'movimientos', (to_regclass('public.movimientos') IS NOT NULL),
         'prestamos',   (to_regclass('public.prestamos')   IS NOT NULL),
         'equipos',     (to_regclass('public.equipos')     IS NOT NULL),
         'componentes', (to_regclass('public.componentes') IS NOT NULL),
         'audit_event', (to_regclass('app.audit_event')    IS NOT NULL)
       ) AS value,
       NULL::jsonb AS details;

-- STEP 1 — Columnas usadas por efectos de ubicación/condición (mov_recibir)
WITH cols AS (
  SELECT table_schema, table_name, column_name
  FROM information_schema.columns
  WHERE (table_schema, table_name) IN (('public','equipos'), ('public','componentes'))
)
SELECT 'ubicacion_columns' AS check,
       jsonb_build_object(
         'equipos.ubicacion',            EXISTS(SELECT 1 FROM cols WHERE table_name='equipos' AND column_name='ubicacion'),
         'equipos.ubicacion_detalle',    EXISTS(SELECT 1 FROM cols WHERE table_name='equipos' AND column_name='ubicacion_detalle'),
         'componentes.ubicacion',        EXISTS(SELECT 1 FROM cols WHERE table_name='componentes' AND column_name='ubicacion'),
         'componentes.ubicacion_detalle',EXISTS(SELECT 1 FROM cols WHERE table_name='componentes' AND column_name='ubicacion_detalle'),
         'componentes.condicion',        EXISTS(SELECT 1 FROM cols WHERE table_name='componentes' AND column_name='condicion')
       ) AS value,
       NULL::jsonb AS details;

-- STEP 2 — Índice único parcial recomendado (anti-carrera) en préstamos
SELECT 'uix_prestamos_activo_componente' AS check,
       jsonb_build_object('exists',
         EXISTS (
           SELECT 1
           FROM pg_indexes
           WHERE schemaname='public'
             AND tablename='prestamos'
             AND indexname='uix_prestamos_activo_componente'
         )
       ) AS value,
       NULL::jsonb AS details;

-- STEP 3 — Presencia de RPCs (para despliegue idempotente)
SELECT 'rpc_presence' AS check,
       jsonb_build_object(
         'rpc_mov_crear',      to_regprocedure('public.rpc_mov_crear(jsonb)') IS NOT NULL,
         'rpc_mov_enviar',     to_regprocedure('public.rpc_mov_enviar(uuid)') IS NOT NULL,
         'rpc_mov_recibir',    to_regprocedure('public.rpc_mov_recibir(uuid)') IS NOT NULL,
         'rpc_mov_cancelar',   to_regprocedure('public.rpc_mov_cancelar(uuid)') IS NOT NULL,
         'rpc_prestamo_crear', to_regprocedure('public.rpc_prestamo_crear(jsonb)') IS NOT NULL,
         'rpc_prestamo_cerrar',to_regprocedure('public.rpc_prestamo_cerrar(uuid)') IS NOT NULL
       ) AS value,
       NULL::jsonb AS details;

ROLLBACK;
