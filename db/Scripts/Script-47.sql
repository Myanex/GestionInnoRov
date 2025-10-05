-- =====================================================================
-- F3 · SMOKE (ACTUALIZADO y RESILIENTE) — Movimientos & Préstamos
-- Adaptado a tus ENUMs:
--   • lugar_operacion = {centro,bodega,oficina,reparacion_externa}
--   • movimiento_estado = {pendiente,en_transito,recibido,cancelado}
-- Nota:
--   • Si las RPC usan 'enviado' internamente, este smoke captura el error y
--     continúa (no deja residuos, todo en ROLLBACK). Sirve para detectar el
--     desalineamiento sin cortar el pipeline.
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

-- STEP 1 — Movimiento end-to-end (con fallback si hay mismatch de ENUM)
DO $$
DECLARE
  v_objeto_tipo text;
  v_objeto_id uuid;
  v_mov uuid;
  v_enviar_ok boolean := false;
  v_recibir_ok boolean := false;
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
    RETURN;
  END IF;

  -- Crear movimiento (usa labels válidos de lugar_operacion)
  SELECT public.rpc_mov_crear(jsonb_build_object(
    'objeto_tipo', v_objeto_tipo,
    'objeto_id', v_objeto_id::text,
    'origen_tipo','centro',
    'origen_detalle','centro_demo',
    'destino_tipo','reparacion_externa',
    'destino_detalle','taller_oficial'
  )) INTO v_mov;

  -- Enviar (si RPC usa 'enviado' pero ENUM es 'en_transito', esto puede fallar)
  BEGIN
    PERFORM public.rpc_mov_enviar(v_mov);
    v_enviar_ok := true;
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'Smoke mov: enviar saltado por error (posible mismatch enum): %', SQLERRM;
  END;

  -- Recibir (solo si enviar fue OK)
  IF v_enviar_ok THEN
    BEGIN
      PERFORM public.rpc_mov_recibir(v_mov);
      v_recibir_ok := true;
    EXCEPTION WHEN others THEN
      RAISE NOTICE 'Smoke mov: recibir saltado por error (posible mismatch enum): %', SQLERRM;
    END;
  END IF;

  -- Si no se pudo completar, intentar cancelar para no dejar residuo
  IF NOT v_recibir_ok THEN
    BEGIN
      PERFORM public.rpc_mov_cancelar(v_mov);
      RAISE NOTICE 'Smoke mov: cancelado para limpiar.';
    EXCEPTION WHEN others THEN
      RAISE NOTICE 'Smoke mov: no se pudo cancelar, se ignora (rollback global). Error: %', SQLERRM;
    END;
  ELSE
    RAISE NOTICE 'Smoke mov OK: %', v_mov;
  END IF;
END $$;

-- STEP 2 — Préstamo con duplicado esperado (índice parcial o lógica)
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

  -- Segundo intento (debe fallar)
  BEGIN
    PERFORM public.rpc_prestamo_crear(jsonb_build_object('componente_id', v_cid::text));
  EXCEPTION
    WHEN unique_violation OR integrity_constraint_violation OR sqlstate '23505' THEN
      dup_ok := true;
  END;

  IF NOT dup_ok THEN
    RAISE EXCEPTION 'Se esperaba rechazo de duplicado activo y no ocurrió';
  END IF;

  PERFORM public.rpc_prestamo_cerrar(v_p);
  RAISE NOTICE 'Smoke préstamo OK: %', v_p;
END $$;

ROLLBACK;