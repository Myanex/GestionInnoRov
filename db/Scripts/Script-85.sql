CREATE INDEX IF NOT EXISTS ix_audit_entity_time 
ON app.audit_event (entity, entity_id, event_time DESC);
