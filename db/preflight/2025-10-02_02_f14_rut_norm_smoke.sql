-- =====================================================================
-- Smoke F1.4 · Pilotos — UNIQUE por RUT normalizado (REVISADO)
-- Archivo sugerido: db/preflight/2025-10-02_02_f14_rut_norm_smoke.sql
-- Objetivo: evitar violación de FK creando perfiles efímeros para las filas de prueba.
-- Todo queda dentro de una transacción con ROLLBACK final.
-- =====================================================================

SET search_path = public, app;

-- STEP 0 — Guard: verificar que el índice único por RUT normalizado existe
SELECT 'ux_present' AS check,
       jsonb_build_object('exists', EXISTS (
         SELECT 1 FROM pg_indexes
         WHERE schemaname='public' AND tablename='pilotos' AND indexname='ux_pilotos_rut_norm'
       )) AS value,
       NULL::jsonb AS details;

-- STEP 1 — Prueba transaccional con perfiles efímeros
BEGIN;
SET LOCAL search_path = public, app;

-- Tabla temporal para resultado
CREATE TEMP TABLE IF NOT EXISTS _smoke_result_f14 (enforced boolean);

DO $$
DECLARE
  v_has_idx boolean;
  v_centro  uuid;
  v_emp     uuid;
  v_p1      uuid := gen_random_uuid();  -- perfil 1
  v_p2      uuid := gen_random_uuid();  -- perfil 2
  v_id1     uuid := v_p1;               -- piloto 1 -> mismo id que perfil 1
  v_id2     uuid := v_p2;               -- piloto 2 -> mismo id que perfil 2
  v_norm    text := lpad((floor(random()*90000000)+10000000)::int::text, 8, '0') || 'k';  -- ej: 12345678k
  v_rut1    text;
  v_rut2    text;
  v_enf     boolean := false;
BEGIN
  -- 1. Chequear que el índice exista; si no, abortar prueba
  SELECT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='pilotos' AND indexname='ux_pilotos_rut_norm'
  ) INTO v_has_idx;

  IF NOT v_has_idx THEN
    RAISE EXCEPTION 'Índice ux_pilotos_rut_norm no existe — corre la migración F1.4 antes del smoke.';
  END IF;

  -- 2. Tomar un centro/empresa válido (si no hay, dejar NULL y el trigger seteará empresa_id=NULL)
  SELECT id, empresa_id INTO v_centro, v_emp
  FROM public.centros
  LIMIT 1;

  -- 3. Crear dos perfiles efímeros (rol=centro) para satisfacer FK pilotos(id)→perfiles(id)
  INSERT INTO public.perfiles (id, rol, centro_id, empresa_id, nombre, email)
  VALUES
    (v_p1, 'centro', v_centro, v_emp, 'Smoke F14 Perfil 1', 'smoke_f14_perfil1@example.com'),
    (v_p2, 'centro', v_centro, v_emp, 'Smoke F14 Perfil 2', 'smoke_f14_perfil2@example.com');

  -- 4. Formatear dos RUT con misma normalización (rut1 con guión y K mayúscula; rut2 sin guión y k minúscula)
  v_rut1 := substr(v_norm,1,length(v_norm)-1) || '-' || upper(substr(v_norm,length(v_norm),1));
  v_rut2 := substr(v_norm,1,length(v_norm)-1) || lower(substr(v_norm,length(v_norm),1));

  -- 5. Insert 1 (debe pasar)
  INSERT INTO public.pilotos(id,nombre,apellido_paterno,rut,email,centro_id,empresa_id,activo)
  VALUES (v_id1,'Smoke','F14',v_rut1,'smoke_f14_p1@example.com',v_centro,v_emp,TRUE);

  -- 6. Insert 2 (misma normalización) — debe FALLAR por unique_violation
  BEGIN
    INSERT INTO public.pilotos(id,nombre,apellido_paterno,rut,email,centro_id,empresa_id,activo)
    VALUES (v_id2,'Smoke','F14',v_rut2,'smoke_f14_p2@example.com',v_centro,v_emp,TRUE);
    -- Si llegó aquí, no se aplicó la restricción (mal)
    v_enf := false;
  EXCEPTION WHEN unique_violation THEN
    v_enf := true;  -- OK: la restricción se aplicó
  END;

  INSERT INTO _smoke_result_f14(enforced) VALUES (v_enf);
END $$;

SELECT 'rut_norm_unique_enforced' AS check,
       to_jsonb((SELECT * FROM _smoke_result_f14 LIMIT 1)) AS value,
       NULL::jsonb AS details;

-- Revertir todo
ROLLBACK;

-- STEP 2 — Confirmar que el índice sigue presente y único
WITH idx AS (
  SELECT ci.oid, i.indexname, pg_get_indexdef(ci.oid) AS indexdef
  FROM pg_indexes i
  JOIN pg_class c  ON c.relname = i.tablename
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname='public'
  JOIN pg_class ci ON ci.relname = i.indexname AND ci.relnamespace = n.oid
  WHERE i.schemaname='public' AND i.tablename='pilotos'
)
SELECT 'ux_is_unique' AS check,
       jsonb_build_object('is_unique', EXISTS (
         SELECT 1
         FROM idx
         JOIN pg_index px ON px.indexrelid = idx.oid
         WHERE idx.indexname='ux_pilotos_rut_norm' AND px.indisunique
       )) AS value,
       NULL::jsonb AS details;
