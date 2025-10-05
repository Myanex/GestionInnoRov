BEGIN;
SET LOCAL search_path = public, app;
DROP INDEX IF EXISTS public.pilotos_rut_key;
COMMIT;
