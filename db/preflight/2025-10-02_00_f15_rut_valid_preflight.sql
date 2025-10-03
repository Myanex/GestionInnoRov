-- =====================================================================
-- Preflight F1.5 · Pilotos — Validación de RUT (solo lectura)
-- Archivo sugerido: db/preflight/2025-10-02_00_f15_rut_valid_preflight.sql
-- Objetivo: verificar presencia de función/constraint y (si existe la función) estimar inválidos.
-- Nota: si la función aún no existe, este preflight NO intenta calcular válidos/ inválidos.
-- =====================================================================

SET search_path = public, app;

-- STEP 0 — Existencia de la función y del constraint
SELECT 'fn_exists_rut_is_valid' AS check,
       jsonb_build_object('exists',
         EXISTS (
           SELECT 1 FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname = 'rut_is_valid'
                 AND pg_get_function_identity_arguments(p.oid) = 'text'
         )
       ) AS value,
       NULL::jsonb AS details
UNION ALL
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
       NULL::jsonb AS details
;

-- STEP 1 — (Opcional) Conteo de RUT inválidos si ya existe la función
WITH fn AS (
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='rut_is_valid'
          AND pg_get_function_identity_arguments(p.oid) = 'text'
  ) AS exists
)
SELECT 'rut_invalidos_si_fn_existe' AS check,
       CASE WHEN (SELECT exists FROM fn) THEN
         jsonb_build_object('count',
           (SELECT count(*) FROM public.pilotos
             WHERE rut IS NOT NULL
               AND length(regexp_replace(rut,'[^0-9kK]','','g')) > 0
               AND NOT public.rut_is_valid(rut)
           )
         )
       ELSE
         jsonb_build_object('skipped','rut_is_valid() aún no existe')
       END AS value,
       NULL::jsonb AS details
;
