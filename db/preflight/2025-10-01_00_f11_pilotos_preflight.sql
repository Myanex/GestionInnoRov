-- =====================================================================
-- Preflight F1.1 · Pilotos (Identidad 1:1 + Hardening)
-- Archivo: db/preflight/2025-10-01_00_f11_pilotos_preflight.sql
-- Modo: SOLO LECTURA (no DDL/DML)
-- Objetivo: Detectar estado actual antes de migrar.
-- =====================================================================

-- STEP: Ajustar contexto seguro de ejecución
SET LOCAL search_path = public, app;

-- STEP: 0. Existencia de objetos clave
SELECT 'obj_exists:public.pilotos' AS check, to_jsonb(t.*) AS value, NULL::jsonb AS details
FROM (SELECT to_regclass('public.pilotos') IS NOT NULL AS exists) t
UNION ALL
SELECT 'obj_exists:public.perfiles', to_jsonb(t.*), NULL
FROM (SELECT to_regclass('public.perfiles') IS NOT NULL AS exists) t
UNION ALL
SELECT 'obj_exists:public.centros', to_jsonb(t.*), NULL
FROM (SELECT to_regclass('public.centros') IS NOT NULL AS exists) t
UNION ALL
SELECT 'obj_exists:public.empresas', to_jsonb(t.*), NULL
FROM (SELECT to_regclass('public.empresas') IS NOT NULL AS exists) t
UNION ALL
SELECT 'obj_exists:public.v_comunicacion_zona', to_jsonb(t.*), NULL
FROM (SELECT to_regclass('public.v_comunicacion_zona') IS NOT NULL AS exists) t
;

-- STEP: 1. 1:1 Pilotos↔Perfiles (mismo id)
WITH
p AS (SELECT id FROM public.pilotos),
f AS (SELECT id FROM public.perfiles),
p_sin_f AS (
  SELECT p.id FROM p
  LEFT JOIN f ON f.id = p.id
  WHERE f.id IS NULL
),
f_sin_p AS (
  SELECT f.id FROM f
  LEFT JOIN p ON p.id = f.id
  WHERE p.id IS NULL
)
SELECT 'pilotos_sin_perfil' AS check,
       jsonb_build_object('count', (SELECT count(*) FROM p_sin_f)) AS value,
       to_jsonb((SELECT array_agg(id) FROM p_sin_f)) AS details
UNION ALL
SELECT 'perfiles_sin_piloto',
       jsonb_build_object('count', (SELECT count(*) FROM f_sin_p)) AS value,
       to_jsonb((SELECT array_agg(id) FROM f_sin_p)) AS details
;

-- STEP: 2. Consistencia empresa_id materializada desde centro_id
-- Regla: si p.centro_id no es NULL, entonces p.empresa_id debe == centros.empresa_id
WITH viol AS (
  SELECT p.id, p.centro_id, p.empresa_id AS empresa_piloto, c.empresa_id AS empresa_centro
  FROM public.pilotos p
  JOIN public.centros c ON c.id = p.centro_id
  WHERE p.centro_id IS NOT NULL
    AND p.empresa_id IS DISTINCT FROM c.empresa_id
)
SELECT 'consistencia_empresa_vs_centro' AS check,
       jsonb_build_object('violaciones', (SELECT count(*) FROM viol)) AS value,
       to_jsonb((SELECT array_agg(viol) FROM viol)) AS details
;

-- STEP: 3. Duplicados en pilotos por rut normalizado y por código
WITH norm AS (
  SELECT
    id,
    lower(trim(codigo)) AS codigo_norm,
    lower(regexp_replace(coalesce(rut,''),'[^0-9kK]','','g')) AS rut_norm
  FROM public.pilotos
),
dup_rut AS (
  SELECT rut_norm, count(*) AS n, array_agg(id) AS ids
  FROM norm
  WHERE rut_norm <> '' AND rut_norm IS NOT NULL
  GROUP BY rut_norm HAVING count(*) > 1
),
dup_codigo AS (
  SELECT codigo_norm, count(*) AS n, array_agg(id) AS ids
  FROM norm
  WHERE codigo_norm <> '' AND codigo_norm IS NOT NULL
  GROUP BY codigo_norm HAVING count(*) > 1
)
SELECT 'dup_rut_norm' AS check,
       jsonb_build_object('count', (SELECT count(*) FROM dup_rut)) AS value,
       to_jsonb((SELECT array_agg(dup_rut) FROM dup_rut)) AS details
UNION ALL
SELECT 'dup_codigo_norm',
       jsonb_build_object('count', (SELECT count(*) FROM dup_codigo)) AS value,
       to_jsonb((SELECT array_agg(dup_codigo) FROM dup_codigo)) AS details
;

-- STEP: 4. Constraints NOT VALID pendientes (tabla pilotos y perfiles)
WITH cte AS (
  SELECT n.nspname, c.relname, con.conname, NOT con.convalidated AS not_valid
  FROM pg_constraint con
  JOIN pg_class c ON c.oid = con.conrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN ('pilotos','perfiles')
)
SELECT 'constraints_not_valid' AS check,
       jsonb_build_object('count', (SELECT count(*) FROM cte WHERE not_valid)) AS value,
       to_jsonb((SELECT array_agg(cte) FROM cte WHERE not_valid)) AS details
;

-- STEP: 5. RLS en public.pilotos (esperado: true)
SELECT 'rls_pilotos_enabled' AS check,
       to_jsonb(t.*) AS value,
       NULL::jsonb AS details
FROM (
  SELECT relrowsecurity AS enabled
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname='public' AND c.relname='pilotos'
) t
;

-- STEP: 6. Presencia de FK perfiles(id) -> pilotos(id) (informativo)
SELECT 'fk_perfiles_id_pilotos_exists' AS check,
       jsonb_build_object('exists', EXISTS (
         SELECT 1
         FROM pg_constraint con
         JOIN pg_class c ON c.oid = con.conrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname='public'
           AND c.relname='perfiles'
           AND con.contype='f'
           AND con.conname='fk_perfiles_id_pilotos'
       )) AS value,
       NULL::jsonb AS details
;
