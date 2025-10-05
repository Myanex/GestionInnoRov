BEGIN;
SET LOCAL search_path = public;

-- columnas, NOT NULL, defaults y enums
SELECT a.attnum, a.attname, format_type(a.atttypid,a.atttypmod) AS type,
       a.attnotnull AS not_null,
       pg_get_expr(ad.adbin, ad.adrelid) AS default,
       t.typtype, t.typname
FROM pg_attribute a
JOIN pg_class c ON c.oid=a.attrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
JOIN pg_type t ON t.oid=a.atttypid
WHERE n.nspname='public' AND c.relname='prestamos'
  AND a.attnum>0 AND NOT a.attisdropped
ORDER BY a.attnum;

-- checks
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid='public.prestamos'::regclass AND contype='c';

-- índices
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='public' AND tablename='prestamos';

-- FKs
SELECT conname, confrelid::regclass AS references_table
FROM pg_constraint
WHERE conrelid='public.prestamos'::regclass AND contype='f';

ROLLBACK;
