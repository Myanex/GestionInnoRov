-- =====================================================================
-- DISCOVERY · public.movimientos
-- Objetivo: listar TODO lo relevante para construir un smoke que no falle.
-- Seguro de ejecutar: SOLO lectura (ROLLBACK al final).
-- =====================================================================
BEGIN;
SET LOCAL search_path = public, app;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';

-- 0) Conteo
SELECT 'row_count' AS section, jsonb_build_object('count', count(*)) AS info, NULL::text AS note
FROM public.movimientos;

-- 1) Columnas, tipos, NOT NULL, default, identity, enums
WITH cols AS (
  SELECT
    a.attnum,
    a.attname AS column_name,
    pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
    a.attnotnull AS not_null,
    pg_get_expr(ad.adbin, ad.adrelid) AS column_default,
    a.attidentity <> '' AS is_identity,
    t.oid AS typoid, t.typname, t.typtype
  FROM pg_attribute a
  JOIN pg_class c ON c.oid=a.attrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_type t ON t.oid=a.atttypid
  LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
  WHERE n.nspname='public' AND c.relname='movimientos' AND a.attnum>0 AND NOT a.attisdropped
)
SELECT 'columns' AS section,
       jsonb_agg(jsonb_build_object(
         'ord', attnum,
         'name', column_name,
         'type', data_type,
         'not_null', not_null,
         'default', column_default,
         'identity', is_identity,
         'enum', (typtype='e'),
         'labels', CASE WHEN typtype='e'
                        THEN (SELECT jsonb_agg(enumlabel ORDER BY enumsortorder)
                              FROM pg_enum e WHERE e.enumtypid=typoid)
                   END
       ) ORDER BY attnum) AS info,
       'Listado de columnas' AS note
FROM cols;

-- 2) Columnas requeridas para INSERT (NOT NULL sin DEFAULT y no identity)
WITH req AS (
  SELECT a.attname AS column_name
  FROM pg_attribute a
  JOIN pg_class c ON c.oid=a.attrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
  WHERE n.nspname='public' AND c.relname='movimientos'
    AND a.attnum>0 AND NOT a.attisdropped
    AND a.attnotnull
    AND ad.adbin IS NULL
    AND a.attidentity = ''
)
SELECT 'required_for_insert' AS section,
       jsonb_agg(column_name ORDER BY column_name) AS info,
       'Debes proveer estas columnas al insertar (o tener triggers que las llenen)' AS note
FROM req;

-- 3) CHECK constraints
SELECT 'checks' AS section,
       jsonb_agg(jsonb_build_object('name', conname, 'def', pg_get_constraintdef(oid))) AS info,
       'Restricciones CHECK' AS note
FROM pg_constraint
WHERE conrelid='public.movimientos'::regclass AND contype='c';

-- 4) FKs
WITH fk AS (
  SELECT
    con.oid, con.conname, conconfrelid::regclass AS references_table,
    con.confupdtype, con.confdeltype, con.convalidated,
    a.attname AS col, af.attname AS ref_col, k.ord
  FROM pg_constraint con
  JOIN unnest(con.conkey) WITH ORDINALITY AS k(attnum,ord) ON true
  JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=k.attnum
  JOIN unnest(con.confkey) WITH ORDINALITY AS fk(attnum,ord2) ON fk.ord2=k.ord
  JOIN pg_attribute af ON af.attrelid=con.confrelid AND af.attnum=fk.attnum
  WHERE con.conrelid='public.movimientos'::regclass AND con.contype='f'
)
SELECT 'foreign_keys' AS section,
       jsonb_agg(
         jsonb_build_object(
           'name', conname,
           'ref_table', references_table::text,
           'on_update', confupdtype,
           'on_delete', confdeltype,
           'validated', convalidated,
           'cols', (SELECT jsonb_agg(col ORDER BY ord) FROM fk f2 WHERE f2.oid=fk.oid),
           'ref_cols', (SELECT jsonb_agg(ref_col ORDER BY ord) FROM fk f2 WHERE f2.oid=fk.oid)
         )
       ) AS info,
       'Llaves foráneas' AS note
FROM fk;

-- 5) Índices (incl. unique)
SELECT 'indexes' AS section,
       jsonb_agg(jsonb_build_object('name', indexname, 'def', indexdef)) AS info,
       'Índices' AS note
FROM pg_indexes
WHERE schemaname='public' AND tablename='movimientos';

-- 6) Triggers
SELECT 'triggers' AS section,
       jsonb_agg(jsonb_build_object('name', tgname, 'enabled', tgenabled, 'def', pg_get_triggerdef(oid))) AS info,
       'Triggers' AS note
FROM pg_trigger
WHERE tgrelid='public.movimientos'::regclass AND NOT tgisinternal;

-- 7) RLS
SELECT 'rls' AS section,
       jsonb_build_object('enabled', c.relrowsecurity, 'force', c.relforcerowsecurity) AS info,
       'Row Level Security' AS note
FROM pg_class c
WHERE c.oid='public.movimientos'::regclass;

SELECT 'policies' AS section,
       jsonb_agg(jsonb_build_object('name', polname, 'cmd', polcmd, 'qual', pg_get_expr(polqual, polrelid), 'check', pg_get_expr(polwithcheck, polrelid), 'roles', polroles::regrole[])) AS info,
       'RLS Policies' AS note
FROM pg_policy
WHERE polrelid='public.movimientos'::regclass;

ROLLBACK;