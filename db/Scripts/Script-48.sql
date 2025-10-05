-- =====================================================================
-- F3 · RPC MOVIMIENTOS (FIX5)
-- Pobla columnas legacy NOT NULL: objeto, responsable_origen_id (y destino opcional)
-- Alineado a tus ENUMs:
--   movimiento_estado = {pendiente, en_transito, recibido, cancelado}
--   movimiento_tipo   = {ingreso, traslado, devolucion, baja}
--   lugar_operacion   = {centro, bodega, oficina, reparacion_externa}
-- ---------------------------------------------------------------------
-- Requisitos cubiertos:
--   • objeto (legacy) -> 'equipo'|'componente'
--   • tipo -> 'traslado' por defecto (si no viene)
--   • responsable_origen_id -> del payload o fallback a un perfil existente
--   • responsable_destino_id -> del payload o igual a responsable_origen_id (fallback)
--   • created_by -> usa responsable_origen_id
-- =====================================================================

BEGIN;
SELECT pg_advisory_xact_lock(74123030);
SET LOCAL search_path = public, app;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = notice;

CREATE OR REPLACE FUNCTION app._audit_min(ev_action text, ev_entity text, ev_id uuid, ev_payload jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
  IF to_regclass('app.audit_event') IS NOT NULL THEN
    INSERT INTO app.audit_event(event_time, actor, action, entity, entity_id, payload)
    SELECT now(), current_user, ev_action, ev_entity, ev_id, ev_payload
    WHERE EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema='app' AND table_name='audit_event'
        AND column_name IN ('event_time','actor','action','entity','entity_id','payload')
    );
  END IF;
EXCEPTION WHEN undefined_table THEN
  NULL;
END$$;

-- Crear movimiento
CREATE OR REPLACE FUNCTION public.rpc_mov_crear(p jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  -- Payload crudo
  v_objeto_tipo_txt     text := coalesce(p->>'objeto_tipo','');
  v_origen_tipo_txt     text := p->>'origen_tipo';
  v_destino_tipo_txt    text := p->>'destino_tipo';
  v_tipo_txt            text := nullif(p->>'tipo','');
  v_resp_origen_txt     text := nullif(p->>'responsable_origen_id','');
  v_resp_destino_txt    text := nullif(p->>'responsable_destino_id','');

  -- Tipados (enum/text-safe)
  v_objeto      public.movimientos.objeto%TYPE;
  v_tipo        public.movimientos.tipo%TYPE;
  v_objeto_tipo public.movimientos.objeto_tipo%TYPE;
  v_origen_tipo public.movimientos.origen_tipo%TYPE;
  v_destino_tipo public.movimientos.destino_tipo%TYPE;
  v_estado_pend public.movimientos.estado%TYPE;

  -- IDs
  v_objeto_id       uuid := (p->>'objeto_id')::uuid;
  v_resp_origen_id  public.movimientos.responsable_origen_id%TYPE;
  v_resp_destino_id public.movimientos.responsable_destino_id%TYPE;

  -- Otros
  v_origen_detalle  text := p->>'origen_detalle';
  v_destino_detalle text := p->>'destino_detalle';
  v_id uuid := gen_random_uuid();
  v_lock_key bigint;
  v_exists int;
BEGIN
  IF v_objeto_id IS NULL OR v_objeto_tipo_txt NOT IN ('equipo','componente') THEN
    RAISE EXCEPTION 'payload inválido: objeto_tipo (equipo|componente) y objeto_id uuid son requeridos'
      USING ERRCODE = '22023';
  END IF;

  -- Mapear a tipos de columna
  v_objeto      := v_objeto_tipo_txt;   -- legacy NOT NULL
  v_objeto_tipo := v_objeto_tipo_txt;
  v_origen_tipo := v_origen_tipo_txt;
  v_destino_tipo := v_destino_tipo_txt;
  v_tipo        := coalesce(v_tipo_txt, 'traslado');
  v_estado_pend := 'pendiente';

  -- Resolver responsables (payload → perfil oficina/admin → cualquier perfil)
  v_resp_origen_id := NULLIF(v_resp_origen_txt,'')::uuid;
  v_resp_destino_id := NULLIF(v_resp_destino_txt,'')::uuid;

  IF v_resp_origen_id IS NULL THEN
    SELECT id
      INTO v_resp_origen_id
    FROM public.perfiles
    WHERE rol::text IN ('oficina','admin')
    ORDER BY created_at
    LIMIT 1;
  END IF;

  IF v_resp_origen_id IS NULL THEN
    SELECT id INTO v_resp_origen_id
    FROM public.perfiles
    ORDER BY created_at
    LIMIT 1;
  END IF;

  IF v_resp_origen_id IS NULL THEN
    RAISE EXCEPTION 'No se pudo resolver responsable_origen_id; pásalo en el payload'
      USING ERRCODE='23502';
  END IF;

  IF v_resp_destino_id IS NULL THEN
    v_resp_destino_id := v_resp_origen_id;
  END IF;

  -- Lock por OBJETO
  v_lock_key := hashtextextended(v_objeto_id::text, 0);
  PERFORM pg_advisory_xact_lock(v_lock_key);

  -- Duplicado pendiente
  SELECT count(*) INTO v_exists
  FROM public.movimientos
  WHERE objeto_tipo = v_objeto_tipo
    AND objeto_id   = v_objeto_id
    AND estado      = v_estado_pend;

  IF v_exists > 0 THEN
    RAISE EXCEPTION 'ya existe un movimiento pendiente para %:%', v_objeto_tipo_txt, v_objeto_id
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.movimientos(
    id, tipo, objeto,
    objeto_tipo, objeto_id,
    origen_tipo, origen_detalle,
    destino_tipo, destino_detalle,
    estado, created_at, created_by,
    responsable_origen_id, responsable_destino_id
  )
  VALUES (
    v_id, v_tipo, v_objeto,
    v_objeto_tipo, v_objeto_id,
    v_origen_tipo, v_origen_detalle,
    v_destino_tipo, v_destino_detalle,
    v_estado_pend, now(), v_resp_origen_id,
    v_resp_origen_id, v_resp_destino_id
  );

  PERFORM app._audit_min('mov.crear','movimientos', v_id, p);
  RETURN v_id;
END$$;

-- Enviar (pendiente -> en_transito)
CREATE OR REPLACE FUNCTION public.rpc_mov_enviar(p_mov_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  r RECORD;
  v_estado_pend public.movimientos.estado%TYPE := 'pendiente';
  v_estado_env  public.movimientos.estado%TYPE := 'en_transito';
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_mov_id::text, 0));

  SELECT * INTO r FROM public.movimientos WHERE id = p_mov_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'movimiento no existe: %', p_mov_id USING ERRCODE='42P01';
  END IF;

  IF r.estado <> v_estado_pend THEN
    RAISE EXCEPTION 'solo movimientos en estado pendiente pueden enviarse' USING ERRCODE='23514';
  END IF;

  UPDATE public.movimientos
     SET estado=v_estado_env, updated_at=now()
   WHERE id=p_mov_id;

  PERFORM app._audit_min('mov.enviar','movimientos', p_mov_id, NULL);
END$$;

-- Recibir (en_transito -> recibido)
CREATE OR REPLACE FUNCTION public.rpc_mov_recibir(p_mov_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  r RECORD;
  v_estado_env public.movimientos.estado%TYPE := 'en_transito';
  v_estado_rec public.movimientos.estado%TYPE := 'recibido';
  has_equipos_cols boolean;
  has_comp_cols boolean;
  sql_txt text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_mov_id::text, 0));

  SELECT * INTO r FROM public.movimientos WHERE id = p_mov_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'movimiento no existe: %', p_mov_id USING ERRCODE='42P01';
  END IF;

  IF r.estado <> v_estado_env THEN
    RAISE EXCEPTION 'solo movimientos en estado en_transito pueden recibirse' USING ERRCODE='23514';
  END IF;

  has_equipos_cols := (to_regclass('public.equipos') IS NOT NULL) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='equipos'
      AND column_name IN ('ubicacion','ubicacion_detalle')
    GROUP BY table_name HAVING count(*)=2
  );

  has_comp_cols := (to_regclass('public.componentes') IS NOT NULL) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='componentes'
      AND column_name IN ('ubicacion','ubicacion_detalle')
    GROUP BY table_name HAVING count(*)=2
  );

  IF r.objeto_tipo::text='equipo' AND has_equipos_cols THEN
    sql_txt := format(
      'UPDATE public.equipos SET ubicacion=%L, ubicacion_detalle=%L, updated_at=now() WHERE id=%L::uuid',
      r.destino_tipo::text, r.destino_detalle, r.objeto_id::text
    );
    EXECUTE sql_txt;
  ELSIF r.objeto_tipo::text='componente' AND has_comp_cols THEN
    sql_txt := format(
      'UPDATE public.componentes SET ubicacion=%L, ubicacion_detalle=%L, updated_at=now() WHERE id=%L::uuid',
      r.destino_tipo::text, r.destino_detalle, r.objeto_id::text
    );
    EXECUTE sql_txt;
  END IF;

  UPDATE public.movimientos
     SET estado=v_estado_rec, updated_at=now()
   WHERE id=p_mov_id;

  PERFORM app._audit_min('mov.recibir','movimientos', p_mov_id, NULL);
END$$;

-- Cancelar (pendiente|en_transito -> cancelado)
CREATE OR REPLACE FUNCTION public.rpc_mov_cancelar(p_mov_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  r RECORD;
  v_estado_pend public.movimientos.estado%TYPE := 'pendiente';
  v_estado_env  public.movimientos.estado%TYPE := 'en_transito';
  v_estado_can  public.movimientos.estado%TYPE := 'cancelado';
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_mov_id::text, 0));

  SELECT * INTO r FROM public.movimientos WHERE id = p_mov_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'movimiento no existe: %', p_mov_id USING ERRCODE='42P01';
  END IF;

  IF r.estado NOT IN (v_estado_pend, v_estado_env) THEN
    RAISE EXCEPTION 'solo movimientos pendiente o en_transito pueden cancelarse' USING ERRCODE='23514';
  END IF;

  UPDATE public.movimientos
     SET estado=v_estado_can, updated_at=now()
   WHERE id=p_mov_id;

  PERFORM app._audit_min('mov.cancelar','movimientos', p_mov_id, NULL);
END$$;

COMMIT;