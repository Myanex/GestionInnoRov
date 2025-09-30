-- STEP: Preflight F1.1 Pilotos (identidad 1:1 + hardening)
-- Archivo: db/preflight/2025-09-30_f1_1_preflight.sql
-- Modo: SOLO lectura / chequeos, sin cambios

BEGIN;
SELECT pg_advisory_xact_lock(2025093001);

-- 1) Pilotos sin perfil homólogo
SELECT pl.id AS piloto_id
FROM public.pilotos pl
LEFT JOIN public.perfiles p ON p.id = pl.id
WHERE p.id IS NULL;

-- 2) Duplicados potenciales de email (case-insensitive)
SELECT LOWER(TRIM(email)) AS email_norm, COUNT(*) AS total
FROM public.pilotos
GROUP BY 1
HAVING COUNT(*) > 1;

-- 3) Duplicados potenciales de rut (case-insensitive)
SELECT LOWER(TRIM(rut)) AS rut_norm, COUNT(*) AS total
FROM public.pilotos
GROUP BY 1
HAVING COUNT(*) > 1;

-- 4) Verificación de índices / constraints que tocaremos
-- Unique por codigo
SELECT conname, conrelid::regclass AS table_name, conkey, condeferrable, convalidated
FROM pg_constraint
WHERE conrelid = 'public.pilotos'::regclass
  AND contype = 'u';

-- Índices existentes
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'pilotos';

COMMIT;
