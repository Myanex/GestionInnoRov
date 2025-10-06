BEGIN;
-- acceso mínimo al esquema y a la función
GRANT USAGE ON SCHEMA app TO authenticated;
GRANT EXECUTE ON FUNCTION app._audit_min(text, text, uuid, jsonb) TO authenticated;

-- si quieres que la auditoría realmente inserte en app.audit_event:
-- (de lo contrario, en el siguiente bloque te dejo una versión que hace no-op sin permisos)
GRANT INSERT ON app.audit_event TO authenticated;
COMMIT;
