SELECT
  to_regprocedure('public.rpc_mov_crear(jsonb)')    IS NOT NULL AS mov_crear,
  to_regprocedure('public.rpc_mov_enviar(uuid)')    IS NOT NULL AS mov_enviar,
  to_regprocedure('public.rpc_mov_recibir(uuid)')   IS NOT NULL AS mov_recibir,
  to_regprocedure('public.rpc_mov_cancelar(uuid)')  IS NOT NULL AS mov_cancelar;
