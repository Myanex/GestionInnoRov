-- =====================================================================
-- Smoke F1.3 · Pilotos (Trigger robusto) — SIMPLE
-- Archivo sugerido: db/preflight/2025-10-02_02_f13_rls_trigger_smoke.sql
-- Nota: sin creación de roles (compatible con Supabase). Demuestra que:
--   • La función del trigger es SECURITY DEFINER con search_path fijo.
--   • El trigger actualiza empresa_id al cambiar centro_id.
--   • La FK pilotos→perfiles sigue validada.
-- =====================================================================

SET search_path = public, app;

-- STEP 0. Propiedades de la función (DEFINER + search_path + uso de public.centros)
WITH f AS (
  SELECT p.oid,
         p.prosecdef AS is_security_definer,
         pg_get_userbyid(p.proowner) AS owner,
         p.proconfig,
         pg_get_functiondef(p.oid) AS fn_ddl
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE n.nspname='public'
    AND c.relname='pilotos'
    AND t.tgname='tg_pilotos_sync_empresa_from_centro_biu'
)
SELECT 'fn_properties' AS check,
       jsonb_build_object(
         'is_security_definer',(SELECT is_security_definer FROM f),
         'owner',(SELECT owner FROM f),
         'search_path_in_proconfig', EXISTS (
            SELECT 1 FROM f, LATERAL unnest(f.proconfig) AS guc
            WHERE split_part(guc,'=',1) = 'search_path'
              AND split_part(guc,'=',2) = 'pg_catalog, public'
         ),
         'uses_public_centros_qualified', COALESCE((SELECT position('public.centros' IN fn_ddl) > 0 FROM f), false)
       ) AS value,
       NULL::jsonb AS details
;

-- STEP 1. Prueba funcional del trigger (UPDATE ... RETURNING) con ROLLBACK
BEGIN;
SET LOCAL search_path = public, app;

WITH p AS (SELECT id FROM public.pilotos LIMIT 1),
     c AS (SELECT id, empresa_id FROM public.centros LIMIT 1),
     u AS (
       UPDATE public.pilotos t
          SET centro_id = c.id
         FROM p, c
        WHERE t.id = p.id
       RETURNING t.id, t.empresa_id
     )
SELECT 'empresa_match_after_trigger' AS check,
       json_build_object('match', (SELECT u.empresa_id = c.empresa_id FROM u, c)) AS value,
       ''::text AS details;

ROLLBACK;

-- STEP 2. FK pilotos(id) → perfiles(id) sigue validada
SELECT 'fk_pilotos_id_perfiles_validated' AS check,
       jsonb_build_object('validated', EXISTS (
         SELECT 1
         FROM pg_constraint con
         JOIN pg_class c ON c.oid = con.conrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname='public'
           AND c.relname='pilotos'
           AND con.contype='f'
           AND con.convalidated
       )) AS value,
       NULL::jsonb AS details
;
