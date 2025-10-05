-- Debe seguir existiendo SOLO el unique por RUT normalizado:
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='public' AND tablename='pilotos'
ORDER BY indexname;
