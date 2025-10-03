BEGIN;
SET LOCAL search_path = public, app;

-- Elimina el constraint UNIQUE (esto también remueve su índice "propietario")
ALTER TABLE public.pilotos DROP CONSTRAINT IF EXISTS pilotos_rut_key;

COMMIT;
