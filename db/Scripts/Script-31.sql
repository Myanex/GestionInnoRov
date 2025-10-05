SELECT column_name
FROM information_schema.columns
WHERE table_schema='public' AND table_name='movimientos'
  AND column_name IN ('objeto_tipo','objeto_id','origen_tipo','origen_detalle',
                      'destino_tipo','destino_detalle','estado','created_at',
                      'updated_at','created_by')
ORDER BY column_name;
