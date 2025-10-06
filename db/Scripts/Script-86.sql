BEGIN;
SET LOCAL search_path = app, public;

-- 1) Agregar columna estándar si no existe
ALTER TABLE app.audit_event
  ADD COLUMN IF NOT EXISTS event_time timestamptz;

-- 2) Backfill (si había created_at y event_time está nula)
UPDATE app.audit_event
SET event_time = COALESCE(event_time, created_at, now())
WHERE event_time IS NULL;

-- 3) NOT NULL + DEFAULT para nuevas filas
ALTER TABLE app.audit_event
  ALTER COLUMN event_time SET DEFAULT now(),
  ALTER COLUMN event_time SET NOT NULL;

-- 4) Índice sugerido
CREATE INDEX IF NOT EXISTS ix_audit_entity_time
  ON app.audit_event (entity, entity_id, event_time DESC);

COMMIT;

-- Verificación
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='app' AND tablename='audit_event';
