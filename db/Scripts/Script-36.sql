-- columnas mínimas (deberían existir ya por Fase A)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema='public' AND table_name='movimientos'
  AND column_name IN ('objeto_tipo','objeto_id','origen_tipo','origen_detalle',
                      'destino_tipo','destino_detalle','estado','created_at',
                      'updated_at','created_by');

-- RPCs de movimientos presentes
SELECT
  to_regprocedure('public.rpc_mov_crear(jsonb)')   IS NOT NULL AS mov_crear,
  to_regprocedure('public.rpc_mov_enviar(uuid)')   IS NOT NULL AS mov_enviar,
  to_regprocedure('public.rpc_mov_recibir(uuid)')  IS NOT NULL AS mov_recibir,
  to_regprocedure('public.rpc_mov_cancelar(uuid)') IS NOT NULL AS mov_cancelar;

-- Índice parcial por pendiente
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='public' AND tablename='movimientos'
  AND indexname='ix_mov_objeto_pendiente';
