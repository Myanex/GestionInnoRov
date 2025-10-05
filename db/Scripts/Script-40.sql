-- Tipo y si es enum
SELECT a.attname AS column, t.typname, t.typtype
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_attribute a ON a.attrelid=c.oid AND NOT a.attisdropped
JOIN pg_type t ON t.oid=a.atttypid
WHERE n.nspname='public'
  AND c.relname='movimientos'
  AND a.attname IN ('tipo')
ORDER BY a.attname;

-- Si es ENUM (typtype='e'), ver etiquetas válidas
WITH col AS (
  SELECT a.atttypid::regtype AS regtype, t.oid AS typoid, t.typtype
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname='tipo'
  JOIN pg_type t ON t.oid=a.atttypid
  WHERE n.nspname='public' AND c.relname='movimientos'
)
SELECT array_agg(e.enumlabel ORDER BY e.enumsortorder) AS labels
FROM col
LEFT JOIN pg_enum e ON e.enumtypid = col.typoid;
