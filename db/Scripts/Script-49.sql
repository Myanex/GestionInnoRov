-- =====================================================================
-- F3 · RPC MOVIMIENTOS (FIX6) — XOR legacy: (objeto + equipo_id/componente_id)
-- Evita poblar objeto_tipo/objeto_id para cumplir ck movimientos_objeto_xor_ck
-- Alineado con tus ENUMs y columnas NOT NULL (objeto, tipo, responsables, created_by)
-- Archivo: db/migrations/2025-10-04_01_f3_rpc_movimientos_FIX6.sql
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

-- Crear movimiento (usa XOR legacy: equipo_id o componente_id)
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
  v_objeto       public.movimientos.objeto%TYPE;
  v_tipo         public.movimientos.tipo%TYPE;
  v_origen_tipo  public.movimientos.origen_tipo%TYPE;
  v_destino_tipo public.movimientos.destino_tipo%TYPE;
  v_estado_pend  public.movimientos.estado%TYPE;

  -- IDs
  v_objeto_id       uuid := (p->>'objeto_id')::uuid;
  v_equipo_id       public.movimientos.equipo_id%TYPE;
  v_componente_id   public.movimientos.componente_id%TYPE;
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
  v_origen_tipo := v_origen_tipo_txt;
  v_destino_tipo := v_destino_tipo_txt;
  v_tipo        := coalesce(v_tipo_txt, 'traslado');
  v_estado_pend := 'pendiente';

  IF v_objeto = 'equipo' THEN
    v_equipo_id := v_objeto_id;
    v_componente_id := NULL;
  ELSE
    v_equipo_id := NULL;
    v_componente_id := v_objeto_id;
  END IF;

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

  -- Duplicado pendiente: buscar tanto legacy (equipo_id/componente_id) como posible forma nueva si existiera
  SELECT count(*) INTO v_exists
  FROM public.movimientos m
  WHERE m.estado = v_estado_pend
    AND (
          (m.objeto = v_objeto AND ((v_objeto='equipo' AND m.equipo_id = v_equipo_id) OR (v_objeto='componente' AND m.componente_id = v_componente_id)))
          OR
          (to_regclass('public.movimientos') IS NOT NULL AND m.objeto_tipo::text = v_objeto::text AND m.objeto_id = v_objeto_id)
        );

  IF v_exists > 0 THEN
    RAISE EXCEPTION 'ya existe un movimiento pendiente para %:%', v_objeto::text, v_objeto_id
      USING ERRCODE = '23505';
  END IF;

  -- INSERT usando SOLO el modelo legacy (cumple ck XOR)
  INSERT INTO public.movimientos(
    id, tipo, objeto,
    equipo_id, componente_id,
    origen_tipo, origen_detalle,
    destino_tipo, destino_detalle,
    estado, created_at, created_by,
    responsable_origen_id, responsable_destino_id
  )
  VALUES (
    v_id, v_tipo, v_objeto,
    v_equipo_id, v_componente_id,
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

-- Recibir (en_transito -> recibido) + actualización de ubicación si corresponde
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
  v_tipo_objeto text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_mov_id::text, 0));

  SELECT * INTO r FROM public.movimientos WHERE id = p_mov_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'movimiento no existe: %', p_mov_id USING ERRCODE='42P01';
  END IF;

  IF r.estado <> v_estado_env THEN
    RAISE EXCEPTION 'solo movimientos en estado en_transito pueden recibirse' USING ERRCODE='23514';
  END IF;

  -- Determinar si es equipo o componente a partir de columnas legacy/XOR
  v_tipo_objeto := COALESCE(r.objeto::text, r.objeto_tipo::text);

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

  IF v_tipo_objeto='equipo' AND has_equipos_cols THEN
    sql_txt := format(
      'UPDATE public.equipos SET ubicacion=%L, ubicacion_detalle=%L, updated_at=now() WHERE id=%L::uuid',
      r.destino_tipo::text, r.destino_detalle,
      COALESCE(r.equipo_id::text, r.objeto_id::text)
    );
    EXECUTE sql_txt;
  ELSIF v_tipo_objeto='componente' AND has_comp_cols THEN
    sql_txt := format(
      'UPDATE public.componentes SET ubicacion=%L, ubicacion_detalle=%L, updated_at=now() WHERE id=%L::uuid',
      r.destino_tipo::text, r.destino_detalle,
      COALESCE(r.componente_id::text, r.objeto_id::text)
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