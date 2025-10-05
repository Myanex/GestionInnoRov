-- =====================================================================
-- F3 · RPC MOVIMIENTOS (FIX4) — agrega `objeto` (NOT NULL legacy) y respeta tus ENUMs
-- Archivo: db/migrations/2025-10-04_01_f3_rpc_movimientos_FIX4.sql
-- ---------------------------------------------------------------------
-- Contexto:
--   La tabla public.movimientos exige la columna `objeto` NOT NULL (modelo legacy),
--   además de nuestras columnas nuevas `objeto_tipo` y `objeto_id`.
--   Este FIX inserta ambas (`objeto` y `objeto_tipo`) con el mismo valor ('equipo'|'componente').
--
-- Mantiene:
--   • Estados: pendiente -> en_transito -> recibido (cancelado)
--   • lugar_operacion: {centro,bodega,oficina,reparacion_externa}
--   • tipo: usa 'traslado' por defecto si no llega en payload
--   • %TYPE para compatibilidad con ENUM/TEXT
-- =====================================================================

BEGIN;
SELECT pg_advisory_xact_lock(74123030);
SET LOCAL search_path = public, app;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = notice;

-- Auditoría mínima (resiliente)
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

-- Crear movimiento (estado = pendiente, tipo = traslado por defecto)
CREATE OR REPLACE FUNCTION public.rpc_mov_crear(p jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  -- Raw payload
  v_objeto_tipo_txt     text := coalesce(p->>'objeto_tipo','');
  v_origen_tipo_txt     text := p->>'origen_tipo';
  v_destino_tipo_txt    text := p->>'destino_tipo';
  v_tipo_txt            text := nullif(p->>'tipo','');

  -- Tipados según columnas (enum/text-safe)
  v_objeto      public.movimientos.objeto%TYPE;
  v_tipo        public.movimientos.tipo%TYPE;
  v_objeto_tipo public.movimientos.objeto_tipo%TYPE;
  v_origen_tipo public.movimientos.origen_tipo%TYPE;
  v_destino_tipo public.movimientos.destino_tipo%TYPE;
  v_estado_pend public.movimientos.estado%TYPE;

  v_objeto_id       uuid := (p->>'objeto_id')::uuid;
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

  -- Asignación a tipos de columna (ENUM o TEXT)
  v_objeto      := v_objeto_tipo_txt;   -- << llena columna legacy NOT NULL
  v_objeto_tipo := v_objeto_tipo_txt;   -- << columna nueva
  v_origen_tipo := v_origen_tipo_txt;
  v_destino_tipo := v_destino_tipo_txt;
  v_tipo        := coalesce(v_tipo_txt, 'traslado');  -- default compatible con movimiento_tipo
  v_estado_pend := 'pendiente';

  -- Lock por OBJETO
  v_lock_key := hashtextextended(v_objeto_id::text, 0);
  PERFORM pg_advisory_xact_lock(v_lock_key);

  -- No permitir doble "pendiente" por objeto (usamos objeto_tipo/objeto_id)
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
    id, tipo, objeto,                -- << agrega `objeto` legacy
    objeto_tipo, objeto_id,
    origen_tipo, origen_detalle,
    destino_tipo, destino_detalle,
    estado, created_at, created_by
  )
  VALUES (
    v_id, v_tipo, v_objeto,
    v_objeto_tipo, v_objeto_id,
    v_origen_tipo, v_origen_detalle,
    v_destino_tipo, v_destino_detalle,
    v_estado_pend, now(), NULL
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
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_mov_id::text, 0));

  SELECT * INTO r FROM public.movimientos WHERE id = p_mov_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'movimiento no existe: %', p_mov_id USING ERRCODE='42P01';
  END IF;

  IF r.estado <> v_estado_env THEN
    RAISE EXCEPTION 'solo movimientos en estado en_transito pueden recibirse' USING ERRCODE='23514';
  END IF;

  -- ¿Existen columnas de ubicación?
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