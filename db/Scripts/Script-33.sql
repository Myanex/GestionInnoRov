-- =====================================================================
-- F3 · RPC MOVIMIENTOS (COMPLETO · FIX1): crear / enviar / recibir / cancelar
-- Cambio: en rpc_mov_recibir se reemplazan $$...$$ (string) por '...'
-- para evitar conflicto con el cuerpo $$ de la función (error "near UPDATE").
-- Archivo: db/migrations/2025-10-03_01_f3_rpc_movimientos_FIX1.sql
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

CREATE OR REPLACE FUNCTION public.rpc_mov_crear(p jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_objeto_tipo     text := coalesce(p->>'objeto_tipo','');
  v_objeto_id       uuid := (p->>'objeto_id')::uuid;
  v_origen_tipo     text := p->>'origen_tipo';
  v_origen_detalle  text := p->>'origen_detalle';
  v_destino_tipo    text := p->>'destino_tipo';
  v_destino_detalle text := p->>'destino_detalle';
  v_id uuid := gen_random_uuid();
  v_lock_key bigint;
  v_exists int;
BEGIN
  IF v_objeto_id IS NULL OR v_objeto_tipo NOT IN ('equipo','componente') THEN
    RAISE EXCEPTION 'payload inválido: objeto_tipo debe ser equipo|componente y objeto_id uuid'
      USING ERRCODE = '22023';
  END IF;

  v_lock_key := hashtextextended(v_objeto_id::text, 0);
  PERFORM pg_advisory_xact_lock(v_lock_key);

  SELECT count(*) INTO v_exists
  FROM public.movimientos
  WHERE objeto_tipo = v_objeto_tipo
    AND objeto_id   = v_objeto_id
    AND estado IN ('pendiente');

  IF v_exists > 0 THEN
    RAISE EXCEPTION 'ya existe un movimiento pendiente para %:%', v_objeto_tipo, v_objeto_id
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.movimientos(
    id, objeto_tipo, objeto_id,
    origen_tipo, origen_detalle,
    destino_tipo, destino_detalle,
    estado, created_at, created_by
  )
  VALUES (
    v_id, v_objeto_tipo, v_objeto_id,
    v_origen_tipo, v_origen_detalle,
    v_destino_tipo, v_destino_detalle,
    'pendiente', now(), NULL
  );

  PERFORM app._audit_min('mov.crear','movimientos', v_id, p);
  RETURN v_id;
END$$;

CREATE OR REPLACE FUNCTION public.rpc_mov_enviar(p_mov_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  r RECORD;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_mov_id::text, 0));

  SELECT * INTO r FROM public.movimientos WHERE id = p_mov_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'movimiento no existe: %', p_mov_id USING ERRCODE='42P01';
  END IF;

  IF r.estado <> 'pendiente' THEN
    RAISE EXCEPTION 'solo movimientos en estado pendiente pueden enviarse' USING ERRCODE='23514';
  END IF;

  UPDATE public.movimientos
     SET estado='enviado', updated_at=now()
   WHERE id=p_mov_id;

  PERFORM app._audit_min('mov.enviar','movimientos', p_mov_id, NULL);
END$$;

CREATE OR REPLACE FUNCTION public.rpc_mov_recibir(p_mov_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  r RECORD;
  has_equipos_cols boolean;
  has_comp_cols boolean;
  sql_txt text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_mov_id::text, 0));

  SELECT * INTO r FROM public.movimientos WHERE id = p_mov_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'movimiento no existe: %', p_mov_id USING ERRCODE='42P01';
  END IF;

  IF r.estado <> 'enviado' THEN
    RAISE EXCEPTION 'solo movimientos en estado enviado pueden recibirse' USING ERRCODE='23514';
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

  IF r.objeto_tipo='equipo' AND has_equipos_cols THEN
    sql_txt := format(
      'UPDATE public.equipos SET ubicacion=%L, ubicacion_detalle=%L, updated_at=now() WHERE id=%L::uuid',
      r.destino_tipo, r.destino_detalle, r.objeto_id::text
    );
    EXECUTE sql_txt;
  ELSIF r.objeto_tipo='componente' AND has_comp_cols THEN
    sql_txt := format(
      'UPDATE public.componentes SET ubicacion=%L, ubicacion_detalle=%L, updated_at=now() WHERE id=%L::uuid',
      r.destino_tipo, r.destino_detalle, r.objeto_id::text
    );
    EXECUTE sql_txt;
  END IF;

  UPDATE public.movimientos
     SET estado='recibido', updated_at=now()
   WHERE id=p_mov_id;

  PERFORM app._audit_min('mov.recibir','movimientos', p_mov_id, NULL);
END$$;

CREATE OR REPLACE FUNCTION public.rpc_mov_cancelar(p_mov_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  r RECORD;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_mov_id::text, 0));

  SELECT * INTO r FROM public.movimientos WHERE id = p_mov_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'movimiento no existe: %', p_mov_id USING ERRCODE='42P01';
  END IF;

  IF r.estado NOT IN ('pendiente','enviado') THEN
    RAISE EXCEPTION 'solo movimientos pendiente o enviado pueden cancelarse' USING ERRCODE='23514';
  END IF;

  UPDATE public.movimientos
     SET estado='cancelado', updated_at=now()
   WHERE id=p_mov_id;

  PERFORM app._audit_min('mov.cancelar','movimientos', p_mov_id, NULL);
END$$;

COMMIT;