-- 1) ¿Quedan inválidos?
SELECT count(*) AS invalidos
FROM public.pilotos
WHERE rut IS NOT NULL
  AND length(regexp_replace(rut,'[^0-9kK]','','g')) > 0
  AND NOT public.rut_is_valid(rut);

-- 2) ¿El CHECK quedó VALIDATED?
SELECT conname, convalidated
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname='public' AND t.relname='pilotos' AND c.conname='ck_pilotos_rut_valid';

-- 3) Bitácora persistente:
SELECT * FROM app.rut_fix_log_20251002 ORDER BY fixed_at DESC;
