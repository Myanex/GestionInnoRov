BEGIN;
-- (5.1) Evitar índice duplicado en préstamos
-- Si tienes dos parciales para "estado='activo'", deja 1 solo:
DROP INDEX IF EXISTS public.prestamos_activo_por_componente_uk;

-- (5.2) Búsquedas típicas en movimientos
CREATE INDEX IF NOT EXISTS idx_mov_estado_created_at ON public.movimientos (estado, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_mov_objeto             ON public.movimientos (objeto_tipo, objeto_id);
CREATE INDEX IF NOT EXISTS idx_mov_responsables       ON public.movimientos (responsable_origen_id, responsable_destino_id);
COMMIT;

-- Chequeo
SELECT indexname,indexdef FROM pg_indexes 
WHERE schemaname='public' AND tablename IN ('movimientos','prestamos')
ORDER BY tablename,indexname;
