BEGIN;
SET LOCAL search_path = public;

-- (idempotente) habilitar RLS por si acaso
ALTER TABLE public.equipos     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.componentes ENABLE ROW LEVEL SECURITY;

-- Política SELECT para equipos
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='equipos' AND policyname='eq_sel_auth'
  ) THEN
    EXECUTE 'CREATE POLICY eq_sel_auth ON public.equipos FOR SELECT TO authenticated USING (true)';
  END IF;
END$$;

-- Política SELECT para componentes
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='componentes' AND policyname='comp_sel_auth'
  ) THEN
    EXECUTE 'CREATE POLICY comp_sel_auth ON public.componentes FOR SELECT TO authenticated USING (true)';
  END IF;
END$$;

COMMIT;
