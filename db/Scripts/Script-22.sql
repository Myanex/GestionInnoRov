-- =====================================================================
-- FIX F1.5 — Asignación automática de RUTs válidos y únicos (V2, staging persistente)
-- Archivo sugerido: db/scripts/2025-10-02_fix_f15_rut_autogen_v2.sql
-- Cambios vs V1:
--   • Usa tabla de staging persistente app.assignments_rut_f15_persist (no TEMP)
--   • Al inicio hace TRUNCATE de la staging (idempotente)
--   • El reporte final lee desde la staging persistente
--   • Mantiene bitácora en app.rut_fix_log_20251002
-- =====================================================================

BEGIN;
SET LOCAL search_path = public, app;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL idle_in_transaction_session_timeout = '180s';
SET LOCAL client_min_messages = notice;

-- Guard 0 — función y unique index necesarios
DO $$
BEGIN
  IF to_regprocedure('public.rut_is_valid(text)') IS NULL THEN
    RAISE EXCEPTION 'Falta la función public.rut_is_valid(text). Corre la migración F1.5 antes de este fix.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='pilotos' AND indexname='ux_pilotos_rut_norm'
  ) THEN
    RAISE EXCEPTION 'Falta el índice UNIQUE ux_pilotos_rut_norm. Corre F1.4 antes de este fix.';
  END IF;
END$$;

-- Bitácora (idempotente)
CREATE SCHEMA IF NOT EXISTS app;

CREATE TABLE IF NOT EXISTS app.rut_fix_log_20251002 (
  piloto_id uuid PRIMARY KEY,
  rut_old   text NOT NULL,
  rut_new   text NOT NULL,
  fixed_by  text NOT NULL,
  fixed_at  timestamptz NOT NULL DEFAULT now()
);

-- Staging persistente (idempotente)
CREATE TABLE IF NOT EXISTS app.assignments_rut_f15_persist (
  piloto_id uuid PRIMARY KEY,
  rut_old   text,
  rut_new   text,
  generated_at timestamptz NOT NULL DEFAULT now()
);

TRUNCATE TABLE app.assignments_rut_f15_persist;

-- Generación y asignación (sin colisiones por normalizado)
DO $$
DECLARE
  r RECORD;
  base text;
  dv   text;
  rutc text;
  norm text;
  s    int;
  m    int;
  i    int;
  calc int;
BEGIN
  FOR r IN
    SELECT p.id, p.rut
    FROM public.pilotos p
    WHERE p.rut IS NOT NULL
      AND length(regexp_replace(p.rut,'[^0-9kK]','','g')) > 0
      AND NOT public.rut_is_valid(p.rut)
  LOOP
    <<retry>>
    -- Generar base aleatoria de 8 dígitos
    base := lpad(((floor(random()*90000000)+10000000)::int)::text, 8, '0');

    -- DV por módulo 11
    s := 0; m := 2;
    FOR i IN REVERSE 1..length(base) LOOP
      s := s + (substr(base,i,1))::int * m;
      m := m + 1;
      IF m > 7 THEN m := 2; END IF;
    END LOOP;
    calc := 11 - (s % 11);
    IF calc = 11 THEN
      dv := '0';
    ELSIF calc = 10 THEN
      dv := 'K';
    ELSE
      dv := calc::text;
    END IF;

    rutc := base || '-' || dv;
    norm := lower(regexp_replace(rutc,'[^0-9kK]','','g'));

    -- Colisión con datos actuales (excluyendo el propio id) o con asignaciones previas
    IF EXISTS (
      SELECT 1 FROM public.pilotos p
      WHERE lower(regexp_replace(p.rut,'[^0-9kK]','','g')) = norm
        AND p.id <> r.id
    ) OR EXISTS (
      SELECT 1 FROM app.assignments_rut_f15_persist a
      WHERE lower(regexp_replace(a.rut_new,'[^0-9kK]','','g')) = norm
    ) THEN
      -- Colisión improbable, reintentar
      GOTO retry;
    END IF;

    INSERT INTO app.assignments_rut_f15_persist(piloto_id, rut_old, rut_new)
    VALUES (r.id, r.rut, rutc)
    ON CONFLICT (piloto_id) DO UPDATE
      SET rut_old = EXCLUDED.rut_old,
          rut_new = EXCLUDED.rut_new,
          generated_at = now();
  END LOOP;
END$$;

-- Actualizar en bloque
UPDATE public.pilotos p
SET rut = a.rut_new
FROM app.assignments_rut_f15_persist a
WHERE a.piloto_id = p.id;

-- Registrar bitácora
INSERT INTO app.rut_fix_log_20251002 (piloto_id, rut_old, rut_new, fixed_by, fixed_at)
SELECT a.piloto_id, a.rut_old, a.rut_new, current_user, now()
FROM app.assignments_rut_f15_persist a
ON CONFLICT (piloto_id) DO UPDATE
SET rut_old = EXCLUDED.rut_old,
    rut_new = EXCLUDED.rut_new,
    fixed_by = EXCLUDED.fixed_by,
    fixed_at = EXCLUDED.fixed_at;

-- Validar constraint si ya no quedan inválidos
DO $$
DECLARE v_invalids int;
BEGIN
  SELECT count(*) INTO v_invalids
  FROM public.pilotos
  WHERE rut IS NOT NULL
    AND length(regexp_replace(rut,'[^0-9kK]','','g')) > 0
    AND NOT public.rut_is_valid(rut);

  IF v_invalids = 0 THEN
    EXECUTE 'ALTER TABLE public.pilotos VALIDATE CONSTRAINT ck_pilotos_rut_valid';
    RAISE NOTICE 'Constraint ck_pilotos_rut_valid VALIDATED.';
  ELSE
    RAISE EXCEPTION 'Persisten % RUT inválidos; revisar app.assignments_rut_f15_persist y repetir fix.', v_invalids;
  END IF;
END$$;

COMMIT;

-- Reporte (persistente)
SELECT 'rut_f15_assignments' AS check,
       to_jsonb(a.*) AS value,
       NULL::jsonb AS details
FROM app.assignments_rut_f15_persist a
ORDER BY a.piloto_id;