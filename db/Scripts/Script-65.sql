BEGIN;
SET LOCAL search_path = public, app;

CREATE OR REPLACE FUNCTION app._audit_min(
  ev_action text, ev_entity text, ev_id uuid, ev_payload jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
  IF to_regclass('app.audit_event') IS NULL THEN
    RETURN; -- no existe la tabla de auditoría
  END IF;

  -- Intento 1: esquema con event_time
  BEGIN
    INSERT INTO app.audit_event(event_time, actor, action, entity, entity_id, payload)
    VALUES (now(), current_user, ev_action, ev_entity, ev_id, ev_payload);
    RETURN;
  EXCEPTION WHEN undefined_column THEN
    -- Intento 2: esquema con created_at
    BEGIN
      INSERT INTO app.audit_event(created_at, actor, action, entity, entity_id, payload)
      VALUES (now(), current_user, ev_action, ev_entity, ev_id, ev_payload);
      RETURN;
    EXCEPTION WHEN undefined_column THEN
      -- Intento 3: variante mínima (solo si existen esas columnas)
      BEGIN
        INSERT INTO app.audit_event(action, entity, entity_id, payload)
        VALUES (ev_action, ev_entity, ev_id, ev_payload);
        RETURN;
      EXCEPTION WHEN undefined_column THEN
        -- Ninguna calza: no-op
        RETURN;
      END;
    END;
  END;

EXCEPTION WHEN undefined_table THEN
  RETURN; -- no-op si la tabla desaparece entre medio
END $$;

COMMIT;
