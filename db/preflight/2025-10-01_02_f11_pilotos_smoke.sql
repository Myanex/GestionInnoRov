-- =====================================================================
-- Smoke F1.1 · Pilotos (Identidad 1:1 + Hardening)
-- Archivo: db/preflight/2025-10-01_02_f11_pilotos_smoke.sql
-- Modo: SOLO LECTURA + prueba temporal con ROLLBACK
-- =====================================================================

SET LOCAL search_path = public, app;

-- STEP: Repetir checks clave 1:1
WITH
p AS (SELECT id FROM public.pilotos),
f AS (SELECT id FROM public.perfiles),
p_sin_f AS (SELECT p.id FROM p LEFT JOIN f ON f.id = p.id WHERE f.id IS NULL),
f_sin_p AS (SELECT f.id FROM f LEFT JOIN p ON p.id = f.id WHERE p.id IS NULL)
SELECT 'pilotos_sin_perfil' AS check,
       jsonb_build_object('count', (SELECT count(*) FROM p_sin_f)) AS value,
       to_jsonb((SELECT array_agg(id) FROM p_sin_f)) AS details
UNION ALL
SELECT 'perfiles_sin_piloto',
       jsonb_build_object('count', (SELECT count(*) FROM f_sin_p)) AS value,
       to_jsonb((SELECT array_agg(id) FROM f_sin_p)) AS details
;

-- STEP: Verificar existencia/validación de la FK
SELECT 'fk_perfiles_id_pilotos_exists' AS check,
       jsonb_build_object('exists', EXISTS (
         SELECT 1 FROM pg_constraint con
         JOIN pg_class c ON c.oid = con.conrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname='public' AND c.relname='perfiles'
           AND con.contype='f' AND con.conname='fk_perfiles_id_pilotos'
       ),
       'validated', EXISTS (
         SELECT 1 FROM pg_constraint con
         JOIN pg_class c ON c.oid = con.conrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname='public' AND c.relname='perfiles'
           AND con.contype='f' AND con.conname='fk_perfiles_id_pilotos'
           AND con.convalidated
       )) AS value,
       NULL::jsonb AS details
;

-- STEP: Prueba del trigger con ROLLBACK (sin UPDATE ... LIMIT)
BEGIN;
SET LOCAL search_path = public, app;

-- Elegir muestras determinísticas (si no hay, no falla)
WITH p AS (
  SELECT id FROM public.pilotos ORDER BY id ASC LIMIT 1
),
c AS (
  SELECT id, empresa_id FROM public.centros ORDER BY id ASC LIMIT 1
)
UPDATE public.pilotos t
   SET centro_id = c.id
  FROM p, c
 WHERE t.id = p.id;

-- Assert: empresa_id del piloto = empresa_id del centro
WITH c AS (SELECT id, empresa_id FROM public.centros ORDER BY id ASC LIMIT 1),
t AS (SELECT * FROM public.pilotos ORDER BY id ASC LIMIT 1)
SELECT 'empresa_match_after_trigger' AS check,
       jsonb_build_object('match', (SELECT (t.empresa_id = c.empresa_id) FROM t, c)) AS value,
       NULL::jsonb AS details
;

ROLLBACK;

-- STEP: Verificación de duplicados post-migración (debería ser igual al preflight)
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
