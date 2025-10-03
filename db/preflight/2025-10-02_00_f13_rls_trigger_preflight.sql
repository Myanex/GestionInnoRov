-- =====================================================================
-- Preflight F1.3 · Pilotos (Hardening RLS + Trigger robusto) — REVISADO
-- Archivo sugerido: db/preflight/2025-10-02_00_f13_rls_trigger_preflight.sql
-- Cambio menor: usar SET search_path (no LOCAL) para evitar dependencia de transacción.
-- =====================================================================

SET search_path = public, app;

-- STEP: 0. Existencia de objetos base
SELECT 'obj_exists:public.pilotos' AS check, to_jsonb(t.*) AS value, NULL::jsonb AS details
FROM (SELECT to_regclass('public.pilotos') IS NOT NULL AS exists) t
UNION ALL
SELECT 'obj_exists:public.perfiles', to_jsonb(t.*), NULL
FROM (SELECT to_regclass('public.perfiles') IS NOT NULL AS exists) t
UNION ALL
SELECT 'obj_exists:public.centros', to_jsonb(t.*), NULL
FROM (SELECT to_regclass('public.centros') IS NOT NULL AS exists) t
;

-- STEP: 1. Estado 1:1 Pilotos ↔ Perfiles (contexto)
WITH p AS (SELECT id FROM public.pilotos),
     f AS (SELECT id FROM public.perfiles),
     p_sin_f AS (SELECT p.id FROM p LEFT JOIN f ON f.id = p.id WHERE f.id IS NULL),
     f_sin_p AS (SELECT f.id FROM f LEFT JOIN p ON p.id = f.id WHERE p.id IS NULL)
SELECT 'pilotos_sin_perfil' AS check,
       jsonb_build_object('count',(SELECT count(*) FROM p_sin_f)) AS value,
       to_jsonb((SELECT array_agg(id) FROM p_sin_f)) AS details
UNION ALL
SELECT 'perfiles_sin_piloto',
       jsonb_build_object('count',(SELECT count(*) FROM f_sin_p)) AS value,
       to_jsonb((SELECT array_agg(id) FROM f_sin_p)) AS details
;

-- STEP: 2. Trigger en pilotos y su función
WITH trg AS (
  SELECT t.tgname,
         t.tgfoid::regprocedure AS fn_signature,
         p.oid AS fn_oid,
         p.proname AS fn_name
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE n.nspname = 'public'
    AND c.relname = 'pilotos'
    AND t.tgname = 'tg_pilotos_sync_empresa_from_centro_biu'
)
SELECT 'trigger_fn_binding' AS check,
       to_jsonb(trg) AS value,
       NULL::jsonb AS details
FROM trg
UNION ALL
SELECT 'trigger_exists',
       jsonb_build_object('exists', EXISTS(SELECT 1 FROM trg)),
       NULL
;

-- STEP: 3. Propiedades de la función del trigger
WITH f AS (
  SELECT p.oid,
         p.proname,
         p.prosecdef AS is_security_definer,
         pg_get_userbyid(p.proowner) AS owner,
         l.lanname AS language,
         p.proconfig AS proconfig,
         pg_get_functiondef(p.oid) AS fn_ddl
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_proc p ON p.oid = t.tgfoid
  JOIN pg_language l ON l.oid = p.prolang
  WHERE n.nspname = 'public'
    AND c.relname = 'pilotos'
    AND t.tgname = 'tg_pilotos_sync_empresa_from_centro_biu'
)
SELECT 'trigger_fn_properties' AS check,
       to_jsonb(f.*) AS value,
       NULL::jsonb AS details
FROM f
UNION ALL
SELECT 'fn_uses_public_centros_qualified' AS check,
       jsonb_build_object(
         'qualified', COALESCE((SELECT position('public.centros' IN f.fn_ddl) > 0 FROM f), false)
       ) AS value,
       NULL::jsonb AS details
;

-- STEP: 4. RLS policies vigentes en public.centros (solo informar)
SELECT 'rls_policies_public_centros' AS check,
       jsonb_build_object('count', count(*)) AS value,
       to_jsonb(array_agg(jsonb_build_object(
         'policyname', policyname,
         'cmd', cmd,
         'roles', roles,
         'qual', qual,
         'with_check', with_check
       ))) AS details
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'centros'
;
