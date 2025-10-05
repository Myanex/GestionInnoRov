BEGIN;
SET LOCAL search_path = public;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.movimientos'::regclass
      AND conname  = 'ck_movimientos_estado_valid'
  ) THEN
    EXECUTE 'ALTER TABLE public.movimientos DROP CONSTRAINT ck_movimientos_estado_valid';
  END IF;
END $$;

ALTER TABLE public.movimientos
  ADD CONSTRAINT ck_movimientos_estado_valid
  CHECK (
    estado IS NULL OR estado IN (
      'pendiente'::public.movimiento_estado,
      'en_transito'::public.movimiento_estado,
      'recibido'::public.movimiento_estado,
      'cancelado'::public.movimiento_estado
    )
  ) NOT VALID;

ALTER TABLE public.movimientos
  VALIDATE CONSTRAINT ck_movimientos_estado_valid;

COMMIT;
