-- File: db/preflight/2025-09-28_f0_smoketests.sql
-- F0 — Paso 3 (v2): Smoke tests por rol (robustos a NOT NULL extra).
-- No deja datos: todo en transacción con ROLLBACK.

BEGIN;
SELECT pg_advisory_xact_lock(420250928);

DO $$
BEGIN
  RAISE NOTICE '--- F0 Smoke Tests (v2): inicio ---';
END$$;

-- ================== Preparación (ADMIN/OFC) ==================
DO $prep$
DECLARE
  emp_id uuid;
  c1 uuid;
  c2 uuid;
  uid uuid := gen_random_uuid();

  have_me  boolean := (to_regclass('public.maestros_empresa') IS NOT NULL);
  have_mc  boolean := (to_regclass('public.maestros_centro')  IS NOT NULL);
  have_comp boolean := (to_regclass('public.componentes')    IS NOT NULL);
  have_eq   boolean := (to_regclass('public.equipos')        IS NOT NULL);
  have_mov  boolean := (to_regclass('public.movimientos')    IS NOT NULL);
  have_pres boolean := (to_regclass('public.prestamos')      IS NOT NULL);
  have_bit  boolean := (to_regclass('public.bitacora')       IS NOT NULL);

  -- ¿Permite INSERT mínimo? (sin campos extra NOT NULL sin default)
  comp_nn_extra int := 0;
  eq_nn_extra   int := 0;
  can_insert_comp boolean := false;
  can_insert_eq   boolean := false;
BEGIN
  IF NOT have_mc THEN
    RAISE NOTICE 'SKIP: maestros_centro no existe → smoke tests limitados.';
    RETURN;
  END IF;

  -- Perfil admin para preparar datos base
  PERFORM app.app_set_debug_claims(jsonb_build_object('role','admin','user_id',uid));

  -- Empresa/base
  IF have_me AND NOT EXISTS (SELECT 1 FROM public.maestros_empresa) THEN
    INSERT INTO public.maestros_empresa(id, nombre) VALUES (gen_random_uuid(), 'Smoke Empresa');
  END IF;

  IF have_me THEN
    SELECT id INTO emp_id FROM public.maestros_empresa LIMIT 1;
  ELSE
    SELECT empresa_id INTO emp_id FROM public.maestros_centro LIMIT 1;
  END IF;

  -- Centro A
  SELECT id INTO c1 FROM public.maestros_centro WHERE empresa_id = emp_id LIMIT 1;
  IF c1 IS NULL THEN
    INSERT INTO public.maestros_centro(id, empresa_id, zona_id, nombre)
    VALUES (gen_random_uuid(), emp_id, gen_random_uuid(), 'Smoke Centro A')
    RETURNING id INTO c1;
  END IF;

  -- Centro B (misma zona) para pruebas cross-centro
  SELECT id INTO c2 FROM public.maestros_centro
   WHERE empresa_id = emp_id AND id <> c1 LIMIT 1;
  IF c2 IS NULL THEN
    INSERT INTO public.maestros_centro(id, empresa_id, zona_id, nombre)
    VALUES (
      gen_random_uuid(),
      emp_id,
      (SELECT zona_id FROM public.maestros_centro WHERE id = c1),
      'Smoke Centro B'
    )
    RETURNING id INTO c2;
  END IF;

  -- Evaluar si componentes/equipos aceptan INSERT mínimo
  IF have_comp THEN
    SELECT count(*) INTO comp_nn_extra
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='componentes'
      AND is_nullable='NO' AND column_default IS NULL
      AND column_name NOT IN ('id','empresa_id','centro_id','created_at','updated_at');
    can_insert_comp := (comp_nn_extra = 0);
  END IF;

  IF have_eq THEN
    SELECT count(*) INTO eq_nn_extra
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='equipos'
      AND is_nullable='NO' AND column_default IS NULL
      AND column_name NOT IN ('id','empresa_id','centro_id','created_at','updated_at');
    can_insert_eq := (eq_nn_extra = 0);
  END IF;

  -- Cambiar a OFICINA para realizar inserts de prueba donde se pueda
  PERFORM app.app_set_debug_claims(jsonb_build_object('role','oficina','user_id',gen_random_uuid()));

  IF have_comp THEN
    IF can_insert_comp THEN
      INSERT INTO public.componentes(empresa_id, centro_id) VALUES (emp_id, c1);   -- centro A
      INSERT INTO public.componentes(empresa_id, centro_id) VALUES (emp_id, NULL); -- bodega
      RAISE NOTICE '[OFICINA] Insert componentes: OK (mínimo)';
    ELSE
      RAISE NOTICE '[OFICINA] SKIP insert componentes: hay % columnas NOT NULL sin default (p.ej. tipo).', comp_nn_extra;
    END IF;
  END IF;

  IF have_eq THEN
    IF can_insert_eq THEN
      INSERT INTO public.equipos(empresa_id, centro_id) VALUES (emp_id, c1);
      RAISE NOTICE '[OFICINA] Insert equipos: OK (mínimo)';
    ELSE
      RAISE NOTICE '[OFICINA] SKIP insert equipos: hay % columnas NOT NULL sin default.', eq_nn_extra;
    END IF;
  END IF;

  IF have_pres THEN
    BEGIN
      INSERT INTO public.prestamos(empresa_id, centro_id) VALUES (emp_id, c1);
      RAISE NOTICE '[OFICINA] Insert prestamos: OK';
    EXCEPTION WHEN others THEN
      RAISE NOTICE '[OFICINA] SKIP insert prestamos: esquema más estricto (%).', SQLERRM;
    END;
  END IF;

  IF have_bit THEN
    BEGIN
      INSERT INTO public.bitacora(empresa_id, centro_id) VALUES (emp_id, c1);
      RAISE NOTICE '[OFICINA] Insert bitacora: OK';
    EXCEPTION WHEN others THEN
      RAISE NOTICE '[OFICINA] SKIP insert bitacora: esquema más estricto (%).', SQLERRM;
    END;
  END IF;

  IF have_mov THEN
    BEGIN
      INSERT INTO public.movimientos(empresa_id, origen_centro_id, destino_centro_id, modo_transporte)
      VALUES (emp_id, c1, c2, 'auto');
      RAISE NOTICE '[OFICINA] Insert movimientos: OK';
    EXCEPTION WHEN others THEN
      RAISE NOTICE '[OFICINA] SKIP insert movimientos: esquema más estricto (%).', SQLERRM;
    END;
  END IF;

  RAISE NOTICE 'Prep OK: empresa=% centroA=% centroB=%', emp_id, c1, c2;
END
$prep$;

-- ================== Tests por rol ==================

-- ---- ANON ----
DO $anon$
DECLARE
  have_comp boolean := (to_regclass('public.componentes') IS NOT NULL);
  have_bit  boolean := (to_regclass('public.bitacora')    IS NOT NULL);
  cnt int;
BEGIN
  PERFORM app.app_set_debug_claims(jsonb_build_object('role','anon','user_id',gen_random_uuid()));
  IF have_comp THEN
    SELECT count(*) INTO cnt FROM public.componentes;
    RAISE NOTICE '[ANON] SELECT componentes → % filas (esperado: 0 por RLS)', cnt;
  END IF;

  IF have_bit THEN
    BEGIN
      INSERT INTO public.bitacora(empresa_id, centro_id) VALUES (gen_random_uuid(), gen_random_uuid());
      RAISE EXCEPTION 'ERROR: ANON pudo insertar en bitacora (no esperado)';
    EXCEPTION WHEN others THEN
      RAISE NOTICE '[ANON] INSERT bitacora → DENEGADO (ok)';
    END;
  END IF;
END
$anon$;

-- ---- CENTRO ----
DO $centro$
DECLARE
  emp_id uuid;
  c1 uuid;
  c2 uuid;
  have_comp boolean := (to_regclass('public.componentes') IS NOT NULL);
  have_mov  boolean := (to_regclass('public.movimientos') IS NOT NULL);
  have_pres boolean := (to_regclass('public.prestamos')   IS NOT NULL);
  have_bit  boolean := (to_regclass('public.bitacora')    IS NOT NULL);
  cnt int;
  any_uuid uuid;
BEGIN
  SELECT mc.empresa_id, mc.id INTO emp_id, c1 FROM public.maestros_centro mc LIMIT 1;
  SELECT id INTO c2 FROM public.maestros_centro WHERE empresa_id = emp_id AND id <> c1 LIMIT 1;

  PERFORM app.app_set_debug_claims(jsonb_build_object(
    'role','centro','empresa_id',emp_id,'centro_id',c1,'user_id',gen_random_uuid()
  ));

  IF have_comp THEN
    SELECT count(*) INTO cnt FROM public.componentes WHERE centro_id = c1;
    RAISE NOTICE '[CENTRO] SELECT componentes (su centro) → % filas (>=0 esperado)', cnt;

    SELECT count(*) INTO cnt FROM public.componentes WHERE centro_id IS NULL;
    RAISE NOTICE '[CENTRO] SELECT componentes bodega → % filas (esperado: 0)', cnt;

    -- Intento UPDATE (debe fallar siempre)
    SELECT id INTO any_uuid FROM public.componentes WHERE centro_id = c1 LIMIT 1;
    IF any_uuid IS NOT NULL THEN
      BEGIN
        UPDATE public.componentes SET updated_at = now() WHERE id = any_uuid;
        RAISE EXCEPTION 'ERROR: CENTRO pudo UPDATE componentes (no esperado)';
      EXCEPTION WHEN others THEN
        RAISE NOTICE '[CENTRO] UPDATE componentes → DENEGADO (ok)';
      END;
    ELSE
      RAISE NOTICE '[CENTRO] UPDATE componentes → SKIP (sin filas de prueba)';
    END IF;
  END IF;

  IF have_bit THEN
    BEGIN
      INSERT INTO public.bitacora(empresa_id, centro_id) VALUES (emp_id, c1);
      RAISE NOTICE '[CENTRO] INSERT bitacora propio centro → OK';
    EXCEPTION WHEN others THEN
      RAISE NOTICE '[CENTRO] INSERT bitacora propio centro → ESQUEMA ESTRICTO (%), se considera ok si RLS luego aplica.', SQLERRM;
    END;

    IF c2 IS NOT NULL THEN
      BEGIN
        INSERT INTO public.bitacora(empresa_id, centro_id) VALUES (emp_id, c2);
        RAISE EXCEPTION 'ERROR: CENTRO pudo INSERT bitacora de otro centro (no esperado)';
      EXCEPTION WHEN others THEN
        RAISE NOTICE '[CENTRO] INSERT bitacora otro centro → DENEGADO (ok)';
      END;
    END IF;
  END IF;

  IF have_pres THEN
    BEGIN
      INSERT INTO public.prestamos(empresa_id, centro_id) VALUES (emp_id, c1);
      RAISE NOTICE '[CENTRO] INSERT prestamos intracentro → OK';
    EXCEPTION WHEN others THEN
      RAISE NOTICE '[CENTRO] INSERT prestamos intracentro → ESQUEMA ESTRICTO (%).', SQLERRM;
    END;
  END IF;

  IF have_mov THEN
    SELECT count(*) INTO cnt
    FROM public.movimientos
    WHERE origen_centro_id = c1 OR destino_centro_id = c1;
    RAISE NOTICE '[CENTRO] SELECT movimientos donde participa → % filas (>=0 esperado)', cnt;
  END IF;
END
$centro$;

-- ---- OFICINA ----
DO $oficina$
DECLARE
  have_comp boolean := (to_regclass('public.componentes') IS NOT NULL);
  have_bit  boolean := (to_regclass('public.bitacora')    IS NOT NULL);
  cnt int;
  any_uuid uuid;
BEGIN
  PERFORM app.app_set_debug_claims(jsonb_build_object('role','oficina','user_id',gen_random_uuid()));

  IF have_comp THEN
    SELECT count(*) INTO cnt FROM public.componentes WHERE centro_id IS NULL;
    RAISE NOTICE '[OFICINA] SELECT componentes bodega (global) → % filas (>=0 esperado; 0 si se omitió insert)', cnt;

    SELECT id INTO any_uuid FROM public.componentes LIMIT 1;
    IF any_uuid IS NOT NULL THEN
      UPDATE public.componentes SET updated_at = now() WHERE id = any_uuid;
      RAISE NOTICE '[OFICINA] UPDATE componentes → OK (RLS RW global)';
    ELSE
      RAISE NOTICE '[OFICINA] UPDATE componentes → SKIP (sin filas de prueba)';
    END IF;
  END IF;

  IF have_bit THEN
    SELECT id INTO any_uuid FROM public.bitacora LIMIT 1;
    IF any_uuid IS NOT NULL THEN
      DELETE FROM public.bitacora WHERE id = any_uuid;
      RAISE NOTICE '[OFICINA] DELETE bitacora → OK';
    ELSE
      RAISE NOTICE '[OFICINA] DELETE bitacora → SKIP (sin filas de prueba)';
    END IF;
  END IF;
END
$oficina$;

-- ---- ADMIN ----
DO $admin$
DECLARE
  cnt int;
BEGIN
  PERFORM app.app_set_debug_claims(jsonb_build_object('role','admin','user_id',gen_random_uuid()));
  IF to_regclass('public.componentes') IS NOT NULL THEN
    SELECT count(*) INTO cnt FROM public.componentes;
    RAISE NOTICE '[ADMIN] SELECT componentes → % filas (>=0 esperado)', cnt;
  END IF;
END
$admin$;

-- Limpieza debug + rollback
SELECT app.app_clear_debug_claims();

DO $$
BEGIN
  RAISE NOTICE '--- F0 Smoke Tests (v2): fin (se revertirá la transacción) ---';
END$$;

ROLLBACK;
