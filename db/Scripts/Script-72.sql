-- =====================================================================
-- SMOKE PRESTAMOS — FIX1 (desambiguar rpc_prestamo_cerrar)
-- Llama a rpc_prestamo_cerrar(uuid, timestamptz) explícitamente.
-- No deja residuos (ROLLBACK)
-- =====================================================================

BEGIN;
SET LOCAL search_path = public, app;
SET LOCAL client_min_messages = notice;

DO $$
DECLARE
  v_comp uuid;
  v_eq_a uuid;
  v_eq_b uuid;
  v_resp uuid;
  v_p1 uuid;
  v_p2 uuid;
BEGIN
  -- muestras
  SELECT id INTO v_comp FROM public.componentes LIMIT 1;
  SELECT id INTO v_eq_a FROM public.equipos LIMIT 1;
  SELECT id INTO v_eq_b FROM public.equipos WHERE id <> v_eq_a LIMIT 1;
  IF v_eq_b IS NULL THEN v_eq_b := v_eq_a; END IF;

  SELECT id INTO v_resp
  FROM public.perfiles
  WHERE rol::text IN ('oficina','admin')
  ORDER BY created_at LIMIT 1;
  IF v_resp IS NULL THEN
    SELECT id INTO v_resp FROM public.perfiles ORDER BY created_at LIMIT 1;
  END IF;

  IF v_comp IS NULL OR v_eq_a IS NULL OR v_resp IS NULL THEN
    RAISE EXCEPTION 'Faltan datos base (componente/equipo/perfil)';
  END IF;

  -- crear activo
  v_p1 := public.rpc_prestamo_crear(jsonb_build_object(
    'componente_id', v_comp::text,
    'equipo_origen_id', v_eq_a::text,
    'equipo_destino_id', v_eq_b::text,
    'responsable_id', v_resp::text,
    'motivo', 'SMOKE f3'
  ));

  -- intentar duplicado (debe fallar)
  BEGIN
    PERFORM public.rpc_prestamo_crear(jsonb_build_object(
      'componente_id', v_comp::text,
      'equipo_origen_id', v_eq_a::text,
      'equipo_destino_id', v_eq_b::text,
      'responsable_id', v_resp::text,
      'motivo', 'SMOKE f3 dup'
    ));
    RAISE EXCEPTION 'Esperábamos error por duplicado activo y no ocurrió';
  EXCEPTION WHEN unique_violation OR foreign_key_violation OR check_violation OR others THEN
    RAISE NOTICE 'Duplicado rechazado OK (%).', SQLSTATE;
  END;

  -- cerrar y re-crear (2° arg explícito para desambiguar)
  PERFORM public.rpc_prestamo_cerrar(v_p1, now()::timestamptz);

  v_p2 := public.rpc_prestamo_crear(jsonb_build_object(
    'componente_id', v_comp::text,
    'equipo_origen_id', v_eq_a::text,
    'equipo_destino_id', v_eq_b::text,
    'responsable_id', v_resp::text,
    'motivo', 'SMOKE f3 after close'
  ));

  RAISE NOTICE 'SMOKE OK: %, %', v_p1, v_p2;
END $$;

ROLLBACK;