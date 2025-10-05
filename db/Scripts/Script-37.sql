SELECT e.enumlabel
FROM pg_type t JOIN pg_enum e ON e.enumtypid=t.oid
WHERE t.typname = (SELECT a.atttypid::regtype::text
                   FROM pg_class c
                   JOIN pg_namespace n ON n.oid=c.relnamespace
                   JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname='estado'
                   WHERE n.nspname='public' AND c.relname='movimientos')::regtype
ORDER BY e.enumsortorder;
