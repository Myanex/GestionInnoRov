-- =====================================================================
-- F3 · RPC PRÉSTAMOS (COMPLETO): crear / cerrar + índice único parcial
-- Archivo sugerido: db/migrations/2025-10-03_02_f3_rpc_prestamos.sql
-- ---------------------------------------------------------------------
-- Contrato (rpc_prestamo_crear):
--   {
--     "componente_id": "<uuid>",
--     "responsable_id": "<uuid|null>"  (opcional)
--   }
-- Regla de negocio
--   • A lo sumo UN préstamo 'activo' por componente_id (enforced por índice único parcial).
-- Seguridad
--   • SECURITY INVOKER (respeta RLS).
-- Concurrencia
--   • pg_advisory_xact_lock por componente_id.
-- Blindaje anti-carrera
--   • unique index parcial: uix_prestamos_activo_componente.
-- Idempotencia
--   • CREATE OR REPLACE FUNCTION + CREATE UNIQUE INDEX IF NOT EXISTS.
-- =====================================================================

BEGIN;
-- Lock de despliegue
SELECT pg_advisory_xact_lock(74123031);
SET LOCAL search_path = public, app;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SET LOCAL client_min_messages = notice;

-- Índice único parcial (anti-carrera): un 'activo' por componente
CREATE UNIQUE INDEX IF NOT EXISTS uix_prestamos_activo_componente
ON public.prestamos(componente_id)
WHERE estado = 'activo';

-- Auditoría mínima (reutiliza si ya existe)
DO $$
BEGIN
  IF to_regprocedure('app._audit_min(text,text,uuid,jsonb)') IS NULL THEN
    CREATE OR REPLACE FUNCTION app._audit_min(ev_action text, ev_entity text, ev_id uuid, ev_payload jsonb)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY INVOKER
    AS $F$
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
    END
    $F$;
  END IF;
END$$;

-- RPC: crear préstamo (estado = activo)
CREATE OR REPLACE FUNCTION public.rpc_prestamo_crear(p jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
  v_componente_id uuid := (p->>'componente_id')::uuid;
  v_responsable_id uuid := NULLIF(p->>'responsable_id','')::uuid;
  v_lock_key bigint;
  v_exists int;
BEGIN
  IF v_componente_id IS NULL THEN
    RAISE EXCEPTION 'payload inválido: componente_id requerido' USING ERRCODE='22023';
  END IF;

  v_lock_key := hashtextextended(v_componente_id::text, 0);
  PERFORM pg_advisory_xact_lock(v_lock_key);

  SELECT count(*) INTO v_exists
  FROM public.prestamos
  WHERE componente_id = v_componente_id
    AND estado = 'activo';

  IF v_exists > 0 THEN
    RAISE EXCEPTION 'ya existe un préstamo activo para componente %', v_componente_id USING ERRCODE='23505';
  END IF;

  INSERT INTO public.prestamos(id, componente_id, responsable_id, estado, created_at, created_by)
  VALUES (v_id, v_componente_id, v_responsable_id, 'activo', now(), NULL);

  PERFORM app._audit_min('prestamo.crear','prestamos', v_id, p);
  RETURN v_id;
END$$;

-- RPC: cerrar préstamo (activo → cerrado)
CREATE OR REPLACE FUNCTION public.rpc_prestamo_cerrar(p_prestamo_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  r RECORD;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_prestamo_id::text, 0));

  SELECT * INTO r FROM public.prestamos WHERE id = p_prestamo_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'préstamo no existe: %', p_prestamo_id USING ERRCODE='42P01';
  END IF;

  IF r.estado <> 'activo' THEN
    RAISE EXCEPTION 'solo préstamos activos pueden cerrarse' USING ERRCODE='23514';
  END IF;

  UPDATE public.prestamos
     SET estado='cerrado', updated_at=now()
   WHERE id=p_prestamo_id;

  PERFORM app._audit_min('prestamo.cerrar','prestamos', p_prestamo_id, NULL);
END$$;

COMMIT;
