-- =====================================================================
-- F3 · SMOKE (COMPLETO, SIN RESIDUOS) — Movimientos & Préstamos
-- Archivo sugerido: db/preflight/2025-10-03_99_f3_smoke.sql
-- ---------------------------------------------------------------------
-- Propósito
--   • Probar rutas felices y fallos esperados sin persistir nada.
--   • Adaptarse a datos existentes (elige equipo o componente disponible).
-- Cobertura
--   • Movimiento: crear → enviar → recibir (efectos de ubicación si columnas existen).
--   • Préstamo: crear activo → duplicado esperado → cerrar.
-- Notas
--   • SECURITY INVOKER: respeta RLS (ejecuta con un rol con permisos de negocio).
--   • Usa los advisory locks internos de las RPCs.
-- =====================================================================

BEGIN;
SET LOCAL search_path = public, app;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = notice;

-- STEP 0 — Presencia de RPCs
SELECT 'rpc_presence' AS check,
       jsonb_build_object(
         'rpc_mov_crear',      to_regprocedure('public.rpc_mov_crear(jsonb)') IS NOT NULL,
         'rpc_mov_enviar',     to_regprocedure('public.rpc_mov_enviar(uuid)') IS NOT NULL,
         'rpc_mov_recibir',    to_regprocedure('public.rpc_mov_recibir(uuid)') IS NOT NULL,
         'rpc_mov_cancelar',   to_regprocedure('public.rpc_mov_cancelar(uuid)') IS NOT NULL,
         'rpc_prestamo_crear', to_regprocedure('public.rpc_prestamo_crear(jsonb)') IS NOT NULL,
         'rpc_prestamo_cerrar',to_regprocedure('public.rpc_prestamo_cerrar(uuid)') IS NOT NULL
       ) AS value,
       NULL::jsonb AS details;

-- STEP 1 — Movimiento end-to-end
DO $$
DECLARE
  v_objeto_tipo text;
  v_objeto_id uuid;
  v_mov uuid;
BEGIN
  -- Elegir objeto disponible (equipo preferente; si no, componente)
  SELECT id INTO v_objeto_id FROM public.equipos LIMIT 1;
  IF FOUND THEN v_objeto_tipo := 'equipo'; END IF;

  IF v_objeto_id IS NULL THEN
    SELECT id INTO v_objeto_id FROM public.componentes LIMIT 1;
    IF FOUND THEN v_objeto_tipo := 'componente'; END IF;
  END IF;

  IF v_objeto_id IS NULL THEN
    RAISE NOTICE 'Smoke mov: sin objetos disponibles, se omite.';
  ELSE
    SELECT public.rpc_mov_crear(jsonb_build_object(
      'objeto_tipo', v_objeto_tipo,
      'objeto_id', v_objeto_id::text,
      'origen_tipo','centro',
      'origen_detalle','centro_demo',
      'destino_tipo','reparacion_externa',
      'destino_detalle','taller_oficial'
    )) INTO v_mov;

    PERFORM public.rpc_mov_enviar(v_mov);
    PERFORM public.rpc_mov_recibir(v_mov);
    RAISE NOTICE 'Smoke mov OK: %', v_mov;
  END IF;
END $$;

-- STEP 2 — Préstamo con duplicado esperado
DO $$
DECLARE
  v_cid uuid;
  v_p uuid;
  dup_ok boolean := false;
BEGIN
  SELECT id INTO v_cid FROM public.componentes LIMIT 1;
  IF NOT FOUND THEN
    RAISE NOTICE 'Smoke préstamo: sin componentes — omitido.';
    RETURN;
  END IF;

  SELECT public.rpc_prestamo_crear(jsonb_build_object('componente_id', v_cid::text)) INTO v_p;

  -- Segundo intento (debe fallar por índice único parcial o lógica)
  BEGIN
    PERFORM public.rpc_prestamo_crear(jsonb_build_object('componente_id', v_cid::text));
  EXCEPTION WHEN unique_violation OR integrity_constraint_violation OR sqlstate '23505' THEN
    dup_ok := true;
  END;

  IF NOT dup_ok THEN
    RAISE EXCEPTION 'Se esperaba rechazo de duplicado activo y no ocurrió';
  END IF;

  PERFORM public.rpc_prestamo_cerrar(v_p);
  RAISE NOTICE 'Smoke préstamo OK: %', v_p;
END $$;

ROLLBACK;
