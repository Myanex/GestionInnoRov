
-- =====================================================================
-- FIX F1.5 — Asignación automática de RUTs válidos y únicos (por normalizado)
-- Archivo sugerido: db/scripts/2025-10-02_fix_f15_rut_autogen.sql
-- Qué hace:
--   1) Verifica que existan: función rut_is_valid(text) y el índice UNIQUE por rut_norm.
--   2) Genera para cada piloto con RUT inválido un nuevo RUT:
--      - base aleatoria de 8 dígitos (10.000.000–99.999.999)
--      - DV correcto (módulo 11; 'K' en mayúscula cuando aplique)
--      - Formato final: ########-DV
--      - Sin colisiones con ux_pilotos_rut_norm ni entre sí
--   3) Actualiza public.pilotos y deja bitácora en app.rut_fix_log_20251002
--   4) Si ya no quedan inválidos, valida ck_pilotos_rut_valid
-- Todo corre en una sola transacción; si algo falla, se revierte.
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

-- Asignaciones temporales
CREATE TEMP TABLE _assignments_rut_f15 (
  piloto_id uuid PRIMARY KEY,
  rut_old   text,
  rut_new   text
);

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
      SELECT 1 FROM _assignments_rut_f15 a
      WHERE lower(regexp_replace(a.rut_new,'[^0-9kK]','','g')) = norm
    ) THEN
      -- Colisión improbable, reintentar
      GOTO retry;
    END IF;

    INSERT INTO _assignments_rut_f15(piloto_id, rut_old, rut_new)
    VALUES (r.id, r.rut, rutc);
  END LOOP;
END$$;

-- Actualizar en bloque
UPDATE public.pilotos p
SET rut = a.rut_new
FROM _assignments_rut_f15 a
WHERE a.piloto_id = p.id;

-- Registrar bitácora
INSERT INTO app.rut_fix_log_20251002 (piloto_id, rut_old, rut_new, fixed_by, fixed_at)
SELECT a.piloto_id, a.rut_old, a.rut_new, current_user, now()
FROM _assignments_rut_f15 a
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
    RAISE EXCEPTION 'Persisten % RUT inválidos; revisar app.rut_fix_log_20251002/_assignments_rut_f15 y repetir fix.', v_invalids;
  END IF;
END$$;

COMMIT;

-- Reporte de asignaciones realizadas
SELECT 'rut_f15_assignments' AS check,
       to_jsonb(a.*) AS value,
       NULL::jsonb AS details
FROM _assignments_rut_f15 a
ORDER BY a.piloto_id;
