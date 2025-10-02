
-- =====================================================================
-- Migración F1.4 · Pilotos — UNIQUE por RUT normalizado (idempotente)
-- Archivo sugerido: db/migrations/2025-10-02_01_f14_rut_norm.sql
-- Regla: un RUT (normalizado) no puede repetirse entre pilotos con RUT no vacío.
-- Normalización: lower(regexp_replace(rut, '[^0-9kK]', '', 'g'))
-- Implementación: índice único por expresión con filtro WHERE rut no vacío.
-- =====================================================================

BEGIN;
SELECT pg_advisory_xact_lock(74123001);

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL idle_in_transaction_session_timeout = '120s';
SET LOCAL client_min_messages = notice;
SET LOCAL search_path = public, app;

-- STEP 0 — Guardrail: abortar si hay duplicados actuales
DO $$
DECLARE v_dups int;
BEGIN
  SELECT COALESCE(sum(n),0) INTO v_dups
  FROM (
    SELECT count(*) AS n
    FROM (
      SELECT lower(regexp_replace(rut, '[^0-9kK]', '', 'g')) AS rut_norm
      FROM public.pilotos
      WHERE rut IS NOT NULL
        AND length(regexp_replace(rut, '[^0-9kK]', '', 'g')) > 0
      GROUP BY 1
      HAVING count(*) > 1
    ) t
  ) s;

  IF v_dups > 0 THEN
    RAISE EXCEPTION 'No se puede crear UNIQUE(rut_norm): hay % filas duplicadas (ver preflight).', v_dups
      USING HINT = 'Normaliza/depura RUTs duplicados antes de correr esta migración.';
  ELSE
    RAISE NOTICE 'Sin duplicados de rut_norm — OK para crear índice único.';
  END IF;
END $$;

-- STEP 1 — Crear índice único (idempotente)
-- Nota: filtra casos con RUT vacío para permitir múltiples NULL/'' (sin normalizar).
CREATE UNIQUE INDEX IF NOT EXISTS ux_pilotos_rut_norm
ON public.pilotos ((lower(regexp_replace(rut, '[^0-9kK]', '', 'g'))))
WHERE rut IS NOT NULL AND length(regexp_replace(rut, '[^0-9kK]', '', 'g')) > 0;

COMMENT ON INDEX public.ux_pilotos_rut_norm IS
  'Unicidad por RUT normalizado en pilotos: lower(regexp_replace(rut, ''[^0-9kK]'', '''', ''g'')), filtrando NULL/vacíos.';

COMMIT;
