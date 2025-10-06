GRANT EXECUTE ON FUNCTION public.rpc_prestamo_crear(jsonb) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_prestamo_cerrar(uuid, timestamptz) TO anon, authenticated;
