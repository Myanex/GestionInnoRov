BEGIN;
SET LOCAL search_path = public, app;
SET LOCAL client_min_messages = notice;

-- 2.A) GRANTS en RPCs
GRANT EXECUTE ON FUNCTION public.rpc_mov_crear(jsonb)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_mov_enviar(uuid)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_mov_recibir(uuid)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_mov_cancelar(uuid)      TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_prestamo_crear(jsonb)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_prestamo_cerrar(uuid, timestamptz) TO authenticated;

-- 2.B) RLS ON
ALTER TABLE public.movimientos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prestamos  ENABLE ROW LEVEL SECURITY;

-- 2.C) Políticas mínimas (idempotentes) — MOVIMIENTOS
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='movimientos' AND policyname='mov_sel_auth'
  ) THEN
    EXECUTE 'CREATE POLICY mov_sel_auth ON public.movimientos FOR SELECT TO authenticated USING (true)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='movimientos' AND policyname='mov_ins_auth'
  ) THEN
    EXECUTE 'CREATE POLICY mov_ins_auth ON public.movimientos FOR INSERT TO authenticated WITH CHECK (true)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='movimientos' AND policyname='mov_upd_auth'
  ) THEN
    EXECUTE 'CREATE POLICY mov_upd_auth ON public.movimientos FOR UPDATE TO authenticated USING (true) WITH CHECK (true)';
  END IF;
END $$;

-- 2.C) Políticas mínimas (idempotentes) — PRESTAMOS
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='prestamos' AND policyname='pre_sel_auth'
  ) THEN
    EXECUTE 'CREATE POLICY pre_sel_auth ON public.prestamos FOR SELECT TO authenticated USING (true)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='prestamos' AND policyname='pre_ins_auth'
  ) THEN
    EXECUTE 'CREATE POLICY pre_ins_auth ON public.prestamos FOR INSERT TO authenticated WITH CHECK (true)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='prestamos' AND policyname='pre_upd_auth'
  ) THEN
    EXECUTE 'CREATE POLICY pre_upd_auth ON public.prestamos FOR UPDATE TO authenticated USING (true) WITH CHECK (true)';
  END IF;
END $$;

COMMIT;

-- Verificación rápida
SELECT 'movimientos' AS tbl, relrowsecurity AS rls_enabled
FROM pg_class WHERE oid='public.movimientos'::regclass
UNION ALL
SELECT 'prestamos', relrowsecurity
FROM pg_class WHERE oid='public.prestamos'::regclass;

SELECT schemaname, tablename, policyname, roles, cmd
FROM pg_policies
WHERE schemaname='public' AND tablename IN ('movimientos','prestamos')
ORDER BY tablename, policyname;
