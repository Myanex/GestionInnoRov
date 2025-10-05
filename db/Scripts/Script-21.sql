SELECT count(*) AS invalidos
FROM public.pilotos
WHERE rut IS NOT NULL
  AND length(regexp_replace(rut,'[^0-9kK]','','g')) > 0
  AND NOT public.rut_is_valid(rut);
