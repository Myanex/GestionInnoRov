-- =====================================================================
-- Preflight F1.5 (LITE) · Pilotos — Validación de RUT (solo existencia)
-- Archivo sugerido: db/preflight/2025-10-02_00_f15_rut_valid_preflight_LITE.sql
-- Evita cualquier referencia directa a public.rut_is_valid(text) si aún no existe.
-- Úsalo ANTES de correr la migración.
-- =====================================================================

SET search_path = public, app;

-- STEP 0 — ¿Existe la función public.rut_is_valid(text)?
SELECT 'fn_exists_rut_is_valid' AS check,
       jsonb_build_object('exists', (to_regprocedure('public.rut_is_valid(text)') IS NOT NULL)) AS value,
       NULL::jsonb AS details;

-- STEP 1 — ¿Existe el constraint ck_pilotos_rut_valid en public.pilotos?
SELECT 'ck_exists_pilotos_rut_valid' AS check,
       jsonb_build_object('exists',
         EXISTS (
           SELECT 1
           FROM pg_constraint c
           JOIN pg_class t ON t.oid = c.conrelid
           JOIN pg_namespace n ON n.oid = t.relnamespace
           WHERE n.nspname='public' AND t.relname='pilotos'
             AND c.contype='c' AND c.conname='ck_pilotos_rut_valid'
         )
       ) AS value,
       NULL::jsonb AS details;

-- NOTA:
-- Este preflight no intenta calcular "RUT inválidos" para evitar el error de resolución
-- cuando la función todavía no existe. Tras la migración, puedes ejecutar:
--   SELECT count(*) AS invalidos
--   FROM public.pilotos
--   WHERE rut IS NOT NULL
--     AND length(regexp_replace(rut,'[^0-9kK]','','g')) > 0
--     AND NOT public.rut_is_valid(rut);
