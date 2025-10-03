-- =====================================================================
-- Migración F1.5 · Pilotos — Validación de RUT (función + CHECK)
-- Archivo sugerido: db/migrations/2025-10-02_01_f15_rut_valid.sql
-- Implementa:
--   • public.rut_is_valid(text) — IMMUTABLE/STRICT (módulo 11)
--   • CHECK ck_pilotos_rut_valid (NOT VALID) + intento de VALIDATE si no hay inválidos
-- =====================================================================

BEGIN;
SELECT pg_advisory_xact_lock(74123002);

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL idle_in_transaction_session_timeout = '120s';
SET LOCAL client_min_messages = notice;
SET LOCAL search_path = public, app;

-- STEP 1 — Función rut_is_valid(text) (idempotente)
CREATE OR REPLACE FUNCTION public.rut_is_valid(rut_in text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $$
DECLARE
  rnorm text;
  base  text;
  dv_in text;
  s     int := 0;
  m     int := 2;
  i     int;
  ch    text;
  calc  int;
  dv_calc text;
BEGIN
  -- Normalizar: solo dígitos y 'k' en minúscula
  IF rut_in IS NULL THEN
    RETURN NULL; -- STRICT evita null, pero por claridad
  END IF;

  rnorm := lower(regexp_replace(rut_in, '[^0-9kK]', '', 'g'));
  IF length(rnorm) < 2 THEN
    RETURN FALSE;
  END IF;

  dv_in := right(rnorm, 1);
  base  := left(rnorm, length(rnorm) - 1);

  -- Recorrer base de derecha a izquierda aplicando factores 2..7
  s := 0; m := 2;
  FOR i IN REVERSE 1..length(base) LOOP
    ch := substr(base, i, 1);
    s := s + (ch::int) * m;
    m := m + 1;
    IF m > 7 THEN
      m := 2;
    END IF;
  END LOOP;

  calc := 11 - (s % 11);
  IF calc = 11 THEN
    dv_calc := '0';
  ELSIF calc = 10 THEN
    dv_calc := 'k';
  ELSE
    dv_calc := calc::text;
  END IF;

  RETURN dv_calc = dv_in;
END;
$$;

COMMENT ON FUNCTION public.rut_is_valid(text) IS
  'Valida un RUT chileno (módulo 11). Insensible a puntos/guiones, acepta K/k. IMMUTABLE+STRICT.';

-- STEP 2 — CHECK en pilotos (NOT VALID) + intento de VALIDATE si no hay inválidos
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname='public' AND t.relname='pilotos'
      AND c.contype='c' AND c.conname='ck_pilotos_rut_valid'
  ) THEN
    EXECUTE $SQL$
      ALTER TABLE public.pilotos
      ADD CONSTRAINT ck_pilotos_rut_valid
      CHECK (
        rut IS NULL
        OR length(regexp_replace(rut, '[^0-9kK]', '', 'g')) = 0
        OR public.rut_is_valid(rut)
      ) NOT VALID
    $SQL$;
    RAISE NOTICE 'Constraint ck_pilotos_rut_valid creado (NOT VALID).';
  ELSE
    RAISE NOTICE 'Constraint ck_pilotos_rut_valid ya existía — omitido.';
  END IF;
END $$;

-- STEP 2.1 — Intentar VALIDATE si no hay RUT inválidos
DO $$
DECLARE v_invalids int;
BEGIN
  SELECT count(*) INTO v_invalids
  FROM public.pilotos
  WHERE rut IS NOT NULL
    AND length(regexp_replace(rut,'[^0-9kK]','','g')) > 0
    AND NOT public.rut_is_valid(rut);

  IF v_invalids = 0 THEN
    BEGIN
      EXECUTE 'ALTER TABLE public.pilotos VALIDATE CONSTRAINT ck_pilotos_rut_valid';
      RAISE NOTICE 'Constraint ck_pilotos_rut_valid VALIDATED (0 inválidos).';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'VALIDATE falló (se mantiene NOT VALID): %', SQLERRM;
    END;
  ELSE
    RAISE NOTICE 'Se detectaron % RUT inválidos — constraint permanece NOT VALID.', v_invalids;
  END IF;
END $$;

COMMIT;
