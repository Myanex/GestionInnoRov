-- Tipos reales de las 3 columnas
SELECT a.attname AS column, t.typname, t.typtype
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_attribute a ON a.attrelid=c.oid AND NOT a.attisdropped
JOIN pg_type t ON t.oid=a.atttypid
WHERE n.nspname='public'
  AND c.relname='movimientos'
  AND a.attname IN ('estado','origen_tipo','destino_tipo')
ORDER BY a.attname;

-- Si alguna es ENUM (typtype='e'), muestra sus etiquetas válidas
WITH cols AS (
  SELECT a.attname, t.oid AS typoid, t.typname, t.typtype
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_attribute a ON a.attrelid=c.oid AND NOT a.attisdropped
  JOIN pg_type t ON t.oid=a.atttypid
  WHERE n.nspname='public'
    AND c.relname='movimientos'
    AND a.attname IN ('estado','origen_tipo','destino_tipo')
)
SELECT c.attname AS column,
       c.typname,
       c.typtype,
       CASE WHEN c.typtype='e'
            THEN array_agg(e.enumlabel ORDER BY e.enumsortorder)
       END AS labels
FROM cols c
LEFT JOIN pg_enum e ON e.enumtypid=c.typoid
GROUP BY c.attname, c.typname, c.typtype
ORDER BY c.attname;
