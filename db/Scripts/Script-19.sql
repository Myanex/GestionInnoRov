-- ¿El CHECK está validado?
SELECT conname, convalidated
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname='public' AND t.relname='pilotos' AND c.conname='ck_pilotos_rut_valid';

-- Listado de inválidos (con normalizado)
SELECT id, nombre, rut,
       lower(regexp_replace(rut,'[^0-9kK]','','g')) AS rut_norm
FROM public.pilotos
WHERE rut IS NOT NULL
  AND length(regexp_replace(rut,'[^0-9kK]','','g')) > 0
  AND NOT public.rut_is_valid(rut)
ORDER BY 2,1;
