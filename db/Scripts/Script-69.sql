-- =====================================================================
-- F3 · RPC PRESTAMOS — Alineado a tu esquema (legacy) y enums
-- Archivo: 2025-10-04_02_f3_rpc_prestamos_FIX.sql
-- ---------------------------------------------------------------------
-- Requisitos de tabla public.prestamos (según tu dump):
--  NOT NULL: id (default gen_random_uuid()), estado (default 'activo'),
--            equipo_origen_id, equipo_destino_id, componente_id,
--            responsable_id, motivo, fecha_prestamo (default now()),
--            created_at (default now()), updated_at (default now()).
--  FKs: componente_id -> public.componentes(id)
--       equipo_origen_id, equipo_destino_id -> public.equipos(id)
--       responsable_id -> public.perfiles(id)
--  Unique parcial: (componente_id) WHERE estado='activo'
--
-- Notas:
--  * Usa advisory locks para evitar carreras al crear préstamos de un mismo componente.
--  * Estado de cierre se resuelve dinámicamente: 'cerrado' si existe en el enum,
--    si no, 'devuelto'; si ninguna, toma la primera etiqueta != 'activo'.
--  * Auditoría mínima es "best-effort": no rompe si la tabla/campos no calzan.
-- =====================================================================

BEGIN;
SELECT pg_advisory_xact_lock(74123031);
SET LOCAL search_path = public, app;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = notice;

-- Auditoría mínima tolerante
CREATE OR REPLACE FUNCTION app._audit_min(
  ev_action text, ev_entity text, ev_id uuid, ev_payload jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
  IF to_regclass('app.audit_event') IS NULL THEN
    RETURN;
  END IF;

  BEGIN
    INSERT INTO app.audit_event(event_time, actor, action, entity, entity_id, payload)
    VALUES (now(), current_user, ev_action, ev_entity, ev_id, ev_payload);
    RETURN;
  EXCEPTION WHEN undefined_column THEN
    BEGIN
      INSERT INTO app.audit_event(created_at, actor, action, entity, entity_id, payload)
      VALUES (now(), current_user, ev_action, ev_entity, ev_id, ev_payload);
      RETURN;
    EXCEPTION WHEN undefined_column THEN
      BEGIN
        INSERT INTO app.audit_event(action, entity, entity_id, payload)
        VALUES (ev_action, ev_entity, ev_id, ev_payload);
        RETURN;
      EXCEPTION WHEN undefined_column THEN
        RETURN;
      END;
    END;
  END;
EXCEPTION WHEN undefined_table THEN
  RETURN;
END $$;

-- Crear préstamo (estado='activo')
CREATE OR REPLACE FUNCTION public.rpc_prestamo_crear(p jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_id uuid := gen_random_uuid();

  -- payload
  v_componente_id uuid := (p->>'componente_id')::uuid;
  v_equipo_origen uuid := (p->>'equipo_origen_id')::uuid;
  v_equipo_destino uuid := (p->>'equipo_destino_id')::uuid;
  v_responsable uuid := (p->>'responsable_id')::uuid;
  v_motivo text := nullif(p->>'motivo','');
  v_empresa_id uuid := NULLIF(p->>'empresa_id','')::uuid;
  v_centro_id uuid := NULLIF(p->>'centro_id','')::uuid;
  v_fecha_prestamo timestamptz := COALESCE((p->>'fecha_prestamo')::timestamptz, now());

  v_estado_act  public.prestamos.estado%TYPE := 'activo';
  v_lock_key bigint;
  v_exists int;
BEGIN
  IF v_componente_id IS NULL OR v_equipo_origen IS NULL OR v_equipo_destino IS NULL
     OR v_responsable IS NULL OR v_motivo IS NULL THEN
    RAISE EXCEPTION 'Faltan campos requeridos: componente_id, equipo_origen_id, equipo_destino_id, responsable_id, motivo'
      USING ERRCODE='22023';
  END IF;

  -- Lock por componente para evitar duplicidad
  v_lock_key := hashtextextended(coalesce(v_componente_id::text,'x'), 0);
  PERFORM pg_advisory_xact_lock(v_lock_key);

  SELECT count(*) INTO v_exists
  FROM public.prestamos
  WHERE componente_id = v_componente_id
    AND estado = v_estado_act;

  IF v_exists > 0 THEN
    RAISE EXCEPTION 'Ya existe préstamo ACTIVO para componente %', v_componente_id
      USING ERRCODE='23505';
  END IF;

  INSERT INTO public.prestamos(
    id, estado,
    equipo_origen_id, equipo_destino_id, componente_id,
    responsable_id, motivo, fecha_prestamo,
    empresa_id, centro_id
  )
  VALUES (
    v_id, v_estado_act,
    v_equipo_origen, v_equipo_destino, v_componente_id,
    v_responsable, v_motivo, v_fecha_prestamo,
    v_empresa_id, v_centro_id
  );

  PERFORM app._audit_min('prestamo.crear','prestamos', v_id, p);
  RETURN v_id;
END $$;

-- Cerrar préstamo (estado != 'activo')
CREATE OR REPLACE FUNCTION public.rpc_prestamo_cerrar(p_prestamo_id uuid, p_fecha_devuelto timestamptz DEFAULT now())
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  r RECORD;
  v_estado_act  public.prestamos.estado%TYPE := 'activo';
  v_estado_fin_txt text;
  v_estado_fin  public.prestamos.estado%TYPE;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_prestamo_id::text, 0));

  SELECT * INTO r FROM public.prestamos WHERE id = p_prestamo_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'préstamo no existe: %', p_prestamo_id USING ERRCODE='42P01';
  END IF;

  IF r.estado = v_estado_act THEN
    -- elegir label de cierre preferida
    SELECT COALESCE(
      (SELECT 'cerrado' WHERE EXISTS (
         SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
         WHERE t.typname='prestamo_estado' AND e.enumlabel='cerrado')),
      (SELECT 'devuelto' WHERE EXISTS (
         SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
         WHERE t.typname='prestamo_estado' AND e.enumlabel='devuelto')),
      (SELECT e.enumlabel
       FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
       WHERE t.typname='prestamo_estado' AND e.enumlabel <> 'activo'
       ORDER BY e.enumsortorder
       LIMIT 1)
    ) INTO v_estado_fin_txt;

    IF v_estado_fin_txt IS NULL THEN
      RAISE EXCEPTION 'Enum prestamo_estado no tiene label de cierre distinta de ''activo''';
    END IF;

    v_estado_fin := v_estado_fin_txt;

    UPDATE public.prestamos
       SET estado = v_estado_fin,
           fecha_devuelto = COALESCE(p_fecha_devuelto, now()),
           updated_at = now()
     WHERE id = p_prestamo_id;
  END IF;

  PERFORM app._audit_min('prestamo.cerrar','prestamos', p_prestamo_id, NULL);
END $$;

COMMIT;