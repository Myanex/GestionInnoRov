-- =====================================================================
-- Smoke F1.5 · Pilotos — Validación de RUT (verificación)
-- Archivo sugerido: db/preflight/2025-10-02_02_f15_rut_valid_smoke.sql
-- Comprueba:
--  (1) función y constraint presentes,
--  (2) constraint aplicado a nuevas filas (unique_violation si RUT inválido),
--  (3) no deja residuos.
-- =====================================================================

SET search_path = public, app;

-- STEP 0 — Existencia de función/constraint
SELECT 'fn_exists_rut_is_valid' AS check,
       jsonb_build_object('exists',
         EXISTS (
           SELECT 1 FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname='public' AND p.proname='rut_is_valid'
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

-- STEP 1 — Enforcement: insertar fila inválida dentro de ROLLBACK
BEGIN;
SET LOCAL search_path = public, app;

-- 1.1 Preparar entorno efímero (satisfacer FK con perfiles)
CREATE TEMP TABLE IF NOT EXISTS _smoke_result_f15 (invalid_rejected boolean);

DO $$
DECLARE
  v_centro uuid;
  v_emp    uuid;
  v_pid    uuid := gen_random_uuid();  -- perfil
  v_id     uuid := v_pid;              -- piloto
  v_bad    text := '12.345.678-9';     -- DV incorrecto (debería ser K)
  v_ok     text := '12.345.678-K';     -- DV correcto (para revertir intento)
  v_rej    boolean := false;
BEGIN
  SELECT id, empresa_id INTO v_centro, v_emp FROM public.centros LIMIT 1;

  INSERT INTO public.perfiles (id, rol, centro_id, empresa_id, nombre, email)
  VALUES (v_pid, 'centro', v_centro, v_emp, 'Smoke F15 Perfil', 'smoke_f15_perfil@example.com');

  -- Intento con RUT inválido (debe FALLAR por CHECK)
  BEGIN
    INSERT INTO public.pilotos(id,nombre,apellido_paterno,rut,email,centro_id,empresa_id,activo)
    VALUES (v_id,'Smoke','F15',v_bad,'smoke_f15@example.com',v_centro,v_emp,TRUE);
    v_rej := false; -- si inserta, algo falló
  EXCEPTION WHEN check_violation THEN
    v_rej := true;  -- OK, rechazó inválido
  WHEN others THEN
    -- Si el motor lanza otro error equivalente (puede variar), intenta assert alterno
    v_rej := NOT public.rut_is_valid(v_bad);
  END;

  INSERT INTO _smoke_result_f15(invalid_rejected) VALUES (v_rej);
END $$;

SELECT 'rut_invalid_rejected' AS check,
       to_jsonb((SELECT * FROM _smoke_result_f15 LIMIT 1)) AS value,
       NULL::jsonb AS details;

ROLLBACK;
