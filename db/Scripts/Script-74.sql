-- 1) Listar sobrecargas de rpc_prestamo_cerrar (ahora sí)
SELECT n.nspname, p.proname,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_prestamo_cerrar'
ORDER BY 1,2,3;

-- 2) Borrar la versión de 1 argumento si existe
DO $$
BEGIN
  IF to_regprocedure('public.rpc_prestamo_cerrar(uuid)') IS NOT NULL THEN
    EXECUTE 'DROP FUNCTION public.rpc_prestamo_cerrar(uuid)';
  END IF;
END$$;

-- 3) Verifica que queda solo la de (uuid, timestamptz)
SELECT n.nspname, p.proname,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_prestamo_cerrar'
ORDER BY 1,2,3;
