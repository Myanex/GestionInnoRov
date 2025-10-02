
-- =====================================================================
-- Preflight F1.4 · Pilotos — UNIQUE por RUT normalizado (solo lectura)
-- Archivo sugerido: db/preflight/2025-10-02_00_f14_rut_norm_preflight.sql
-- Objetivo: detectar duplicados de RUT normalizado y presencia del índice único.
-- Normalización: lower(regexp_replace(rut, '[^0-9kK]', '', 'g'))
-- =====================================================================

SET search_path = public, app;

-- STEP 0 — Panorama de datos (pilotos con RUT no vacío)
WITH t AS (
  SELECT id,
         rut,
         lower(regexp_replace(rut, '[^0-9kK]', '', 'g')) AS rut_norm
  FROM public.pilotos
),
nz AS (
  SELECT * FROM t
  WHERE rut IS NOT NULL
    AND length(regexp_replace(rut, '[^0-9kK]', '', 'g')) > 0
)
SELECT 'totales' AS check,
       jsonb_build_object(
         'pilotos_total', (SELECT count(*) FROM public.pilotos),
         'con_rut_no_vacio', (SELECT count(*) FROM nz),
         'sin_rut_o_vacio', (SELECT count(*) FROM t) - (SELECT count(*) FROM nz)
       ) AS value,
       NULL::jsonb AS details;

-- STEP 1 — Duplicados por RUT normalizado
WITH t AS (
  SELECT id, rut, lower(regexp_replace(rut, '[^0-9kK]', '', 'g')) AS rut_norm
  FROM public.pilotos
),
nz AS (
  SELECT * FROM t
  WHERE rut IS NOT NULL
    AND length(regexp_replace(rut, '[^0-9kK]', '', 'g')) > 0
),
dups AS (
  SELECT rut_norm, count(*) AS n
  FROM nz
  GROUP BY rut_norm
  HAVING count(*) > 1
)
SELECT 'dup_rut_norm_count' AS check,
       jsonb_build_object('count', (SELECT coalesce(sum(n),0) FROM dups)) AS value,
       to_jsonb((SELECT array_agg(rut_norm) FROM dups)) AS details;

-- STEP 1.1 — Filas que caen en duplicado (si existen)
WITH t AS (
  SELECT id, rut, lower(regexp_replace(rut, '[^0-9kK]', '', 'g')) AS rut_norm
  FROM public.pilotos
),
nz AS (
  SELECT * FROM t
  WHERE rut IS NOT NULL
    AND length(regexp_replace(rut, '[^0-9kK]', '', 'g')) > 0
),
dups AS (
  SELECT rut_norm
  FROM nz
  GROUP BY rut_norm
  HAVING count(*) > 1
)
SELECT 'dup_rut_norm_rows' AS check,
       to_jsonb(nz.*) AS value,
       NULL::jsonb AS details
FROM nz
WHERE nz.rut_norm IN (SELECT rut_norm FROM dups)
ORDER BY nz.rut_norm, nz.id
LIMIT 200;

-- STEP 2 — ¿Existe índice único por RUT normalizado (por nombre)?
SELECT 'ux_name_exists' AS check,
       jsonb_build_object('exists',
         EXISTS (
           SELECT 1
           FROM pg_indexes
           WHERE schemaname='public' AND tablename='pilotos'
             AND indexname='ux_pilotos_rut_norm'
         )
       ) AS value,
       NULL::jsonb AS details;

-- STEP 2.1 — Índices únicos en pilotos (definición completa)
SELECT 'unique_indexes_on_pilotos' AS check,
       to_jsonb(jsonb_build_object(
         'indexname', i.indexname,
         'indexdef', pg_get_indexdef(ci.oid)
       )) AS value,
       NULL::jsonb AS details
FROM pg_indexes i
JOIN pg_class c  ON c.relname = i.tablename
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname='public'
JOIN pg_class ci ON ci.relname = i.indexname AND ci.relnamespace = n.oid
WHERE i.schemaname='public' AND i.tablename='pilotos'
  AND (SELECT indisunique FROM pg_index px WHERE px.indexrelid=ci.oid)
ORDER BY i.indexname;
