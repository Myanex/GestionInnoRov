
-- =====================================================================
-- Smoke F1.4 · Pilotos — UNIQUE por RUT normalizado (verificación)
-- Archivo sugerido: db/preflight/2025-10-02_02_f14_rut_norm_smoke.sql
-- Comprueba: (1) sin duplicados, (2) índice único presente, (3) enforcement real.
-- =====================================================================

SET search_path = public, app;

-- STEP 0 — Sin duplicados actuales
WITH nz AS (
  SELECT lower(regexp_replace(rut, '[^0-9kK]', '', 'g')) AS rut_norm
  FROM public.pilotos
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
       jsonb_build_object('count', COALESCE((SELECT sum(n) FROM dups),0)) AS value,
       to_jsonb((SELECT array_agg(rut_norm) FROM dups)) AS details;

-- STEP 1 — Índice único presente y único
WITH idx AS (
  SELECT ci.oid, i.indexname, pg_get_indexdef(ci.oid) AS indexdef
  FROM pg_indexes i
  JOIN pg_class c  ON c.relname = i.tablename
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname='public'
  JOIN pg_class ci ON ci.relname = i.indexname AND ci.relnamespace = n.oid
  WHERE i.schemaname='public' AND i.tablename='pilotos'
)
SELECT 'ux_present' AS check,
       jsonb_build_object('exists', EXISTS(SELECT 1 FROM idx WHERE indexname='ux_pilotos_rut_norm')) AS value,
       NULL::jsonb AS details
UNION ALL
SELECT 'ux_is_unique',
       jsonb_build_object('is_unique', EXISTS (
         SELECT 1
         FROM idx
         JOIN pg_index px ON px.indexrelid = idx.oid
         WHERE idx.indexname='ux_pilotos_rut_norm' AND px.indisunique
       )),
       NULL
;

-- STEP 2 — Enforcement real (prueba transaccional con SAVEPOINT y ROLLBACK)
-- Crea 2 pilotos con el mismo RUT normalizado dentro de la transacción y verifica unique_violation.
BEGIN;
SET LOCAL search_path = public, app;

-- Preparar valores: tomar un centro/empresa válidos
WITH ce AS (SELECT id AS centro_id, empresa_id FROM public.centros LIMIT 1)
SELECT * FROM ce;  -- devuelve 1 fila informativa

-- Tabla temporal para devolver el resultado de enforcement
CREATE TEMP TABLE IF NOT EXISTS _smoke_result (enforced boolean);

DO $$
DECLARE
  v_centro uuid;
  v_emp    uuid;
  v_id1    uuid := gen_random_uuid();
  v_id2    uuid := gen_random_uuid();
  v_norm   text := lpad((floor(random()*90000000)+10000000)::int::text, 8, '0') || 'k';  -- como '12345678k'
  v_rut1   text;
  v_rut2   text;
  v_enf    boolean := false;
BEGIN
  SELECT centro_id, empresa_id INTO v_centro, v_emp FROM (SELECT id AS centro_id, empresa_id FROM public.centros LIMIT 1) s;

  -- Formatear dos representaciones diferentes con mismo normalizado
  v_rut1 := substr(v_norm,1,length(v_norm)-1) || '-' || upper(substr(v_norm,length(v_norm),1));
  v_rut2 := substr(v_norm,1,length(v_norm)-1) || lower(substr(v_norm,length(v_norm),1));  -- sin guión

  -- Inserción 1
  BEGIN
    INSERT INTO public.pilotos(id,nombre,apellido_paterno,rut,email,centro_id,empresa_id,activo)
    VALUES (v_id1,'Smoke','Test',v_rut1,'smoke_f14_1@example.com',v_centro,v_emp,TRUE);
  EXCEPTION WHEN unique_violation THEN
    -- Raro: colisionó con datos reales; regenerar v_norm y reintentar una vez
    v_norm := lpad((floor(random()*90000000)+10000000)::int::text, 8, '0') || 'k';
    v_rut1 := substr(v_norm,1,length(v_norm)-1) || '-' || upper(substr(v_norm,length(v_norm),1));
    INSERT INTO public.pilotos(id,nombre,apellido_paterno,rut,email,centro_id,empresa_id,activo)
    VALUES (v_id1,'Smoke','Test',v_rut1,'smoke_f14_1b@example.com',v_centro,v_emp,TRUE);
  END;

  -- Inserción 2 (misma normalización) — debe fallar
  BEGIN
    v_rut2 := substr(v_norm,1,length(v_norm)-1) || '-' || lower(substr(v_norm,length(v_norm),1));
    INSERT INTO public.pilotos(id,nombre,apellido_paterno,rut,email,centro_id,empresa_id,activo)
    VALUES (v_id2,'Smoke','Test',v_rut2,'smoke_f14_2@example.com',v_centro,v_emp,TRUE);
    -- Si llegó aquí, no se aplicó la restricción (mal)
    v_enf := false;
  EXCEPTION WHEN unique_violation THEN
    v_enf := true;  -- OK: la restricción se aplicó
  END;

  INSERT INTO _smoke_result(enforced) VALUES (v_enf);
END $$;

SELECT 'rut_norm_unique_enforced' AS check,
       to_jsonb((SELECT * FROM _smoke_result LIMIT 1)) AS value,
       NULL::jsonb AS details;

-- No persistir datos de prueba
ROLLBACK;
