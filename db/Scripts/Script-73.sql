-- Lista versiones de rpc_prestamo_cerrar para ver sobrecargas
SELECT n.nspname, p.proname, pg_get_function_identity_arguments AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_prestamo_cerrar'
ORDER BY 1,2,3;