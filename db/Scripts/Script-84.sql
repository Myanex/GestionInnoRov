GRANT USAGE ON SCHEMA app TO authenticated;
GRANT EXECUTE ON FUNCTION app._audit_min(text,text,uuid,jsonb) TO authenticated;
GRANT INSERT  ON app.audit_event TO authenticated;  -- para registrar eventos
