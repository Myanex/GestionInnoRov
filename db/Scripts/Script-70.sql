-- =====================================================================
-- PREFLIGHT PRESTAMOS — Validaciones antes del smoke
-- Archivo: 2025-10-04_f3_preflight_prestamos.sql
-- Solo lectura (termina en ROLLBACK)
-- =====================================================================
BEGIN;
SET LOCAL search_path = public, app;
SET LOCAL client_min_messages = notice;

-- 0) Objetos base
SELECT 'obj_exists:public.prestamos' AS check,
       jsonb_build_object('exists', to_regclass('public.prestamos') IS NOT NULL) AS value, '' AS details;

-- 1) Columnas requeridas para INSERT (NOT NULL sin DEFAULT y no identity)
WITH req AS (
  SELECT a.attname AS col
  FROM pg_attribute a
  JOIN pg_class c ON c.oid=a.attrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
  WHERE n.nspname='public' AND c.relname='prestamos'
    AND a.attnum>0 AND NOT a.attisdropped
    AND a.attnotnull AND ad.adbin IS NULL AND a.attidentity=''
)
SELECT 'required_for_insert' AS check,
       jsonb_agg(col ORDER BY col) AS value, '' AS details
FROM req;

-- 2) Índice único parcial para activo por componente (al menos 1)
SELECT 'unique_activo_por_componente' AS check,
       jsonb_build_object('exists',
         EXISTS (
           SELECT 1 FROM pg_indexes
           WHERE schemaname='public' AND tablename='prestamos'
             AND indexdef ILIKE '% UNIQUE INDEX %'
             AND indexdef ILIKE '% (componente_id) %'
             AND indexdef ILIKE '%estado = ''activo''%'
         )
       ) AS value, '' AS details;

-- 3) Enum labels para estado
SELECT 'prestamo_estado_labels' AS check,
       jsonb_agg(enumlabel ORDER BY enumsortorder) AS value, '' AS details
FROM pg_enum e
JOIN pg_type t ON t.oid=e.enumtypid
WHERE t.typname='prestamo_estado';

-- 4) RPC presence
SELECT 'rpc_presence' AS check,
       jsonb_build_object(
         'rpc_prestamo_crear', (SELECT to_regprocedure('public.rpc_prestamo_crear(jsonb)') IS NOT NULL),
         'rpc_prestamo_cerrar', (SELECT to_regprocedure('public.rpc_prestamo_cerrar(uuid, timestamptz)') IS NOT NULL)
       ) AS value, '' AS details;

ROLLBACK;