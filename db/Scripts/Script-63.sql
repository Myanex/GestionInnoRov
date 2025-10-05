BEGIN;
SET LOCAL search_path = public, app;
SET LOCAL client_min_messages = notice;

DO $$
DECLARE
  v_equipo uuid;
  v_comp   uuid;
  v_perfil uuid;
  v_mov    uuid;
BEGIN
  -- Muestras (usa cualquiera que exista)
  SELECT id INTO v_equipo FROM public.equipos LIMIT 1;
  SELECT id INTO v_comp   FROM public.componentes LIMIT 1;

  SELECT id INTO v_perfil
  FROM public.perfiles
  WHERE rol::text IN ('oficina','admin')
  ORDER BY created_at
  LIMIT 1;

  IF v_perfil IS NULL THEN
    SELECT id INTO v_perfil FROM public.perfiles ORDER BY created_at LIMIT 1;
  END IF;

  IF v_perfil IS NULL THEN
    RAISE EXCEPTION 'No hay perfiles para responsable_origen_id (requerido).';
  END IF;

  IF v_equipo IS NULL AND v_comp IS NULL THEN
    RAISE EXCEPTION 'No hay equipo/componente para probar movimientos.';
  END IF;

  -- INSERT legacy_xor con los obligatorios
  IF v_equipo IS NOT NULL THEN
    INSERT INTO public.movimientos(
      id, tipo, objeto, equipo_id,
      origen_tipo, origen_detalle,
      destino_tipo, destino_detalle,
      estado, created_at, created_by,
      responsable_origen_id, responsable_destino_id
    )
    VALUES (
      gen_random_uuid(), 'traslado', 'equipo', v_equipo,
      'centro', 'centro_demo',
      'reparacion_externa', 'taller_oficial',
      'pendiente', now(), v_perfil,
      v_perfil, v_perfil
    )
    RETURNING id INTO v_mov;
  ELSE
    INSERT INTO public.movimientos(
      id, tipo, objeto, componente_id,
      origen_tipo, origen_detalle,
      destino_tipo, destino_detalle,
      estado, created_at, created_by,
      responsable_origen_id, responsable_destino_id
    )
    VALUES (
      gen_random_uuid(), 'traslado', 'componente', v_comp,
      'centro', 'centro_demo',
      'reparacion_externa', 'taller_oficial',
      'pendiente', now(), v_perfil,
      v_perfil, v_perfil
    )
    RETURNING id INTO v_mov;
  END IF;

  -- Flujo: enviar → recibir
  PERFORM public.rpc_mov_enviar(v_mov);   -- debe pasar a en_transito
  PERFORM public.rpc_mov_recibir(v_mov);  -- debe pasar a recibido

  RAISE NOTICE 'SMOKE OK: %', v_mov;
END $$;

ROLLBACK;
