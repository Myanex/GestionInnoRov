-- =========================================================
-- PREFLIGHT F0 — Diagnóstico antes de aplicar RLS base
-- No cambia nada: puro SELECT/inspección.
-- =========================================================

-- STEP 0 (FIX): contexto esperado sin castear a regclass
WITH expected AS (
  SELECT unnest(ARRAY[
    'public.maestros_empresa',
    'public.maestros_centro',
    'public.componentes',
    'public.equipos',
    'public.equipo_componente',
    'public.movimientos',
    'public.prestamos',
    'public.bitacora'
  ])::text AS table_name
)
SELECT
  'expected_tables' AS section,
  e.table_name,
  to_regclass(e.table_name) IS NOT NULL AS exists
FROM expected e
ORDER BY e.table_name;

-- STEP 1: ¿Qué tablas existen realmente?
SELECT 'existing_tables' AS section, table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- STEP 2: ¿Cuáles de las esperadas faltan?
WITH expected AS (
  SELECT unnest(ARRAY[
    'public.maestros_empresa',
    'public.maestros_centro',
    'public.componentes',
    'public.equipos',
    'public.equipo_componente',
    'public.movimientos',
    'public.prestamos',
    'public.bitacora'
  ])::text AS t
)
SELECT 'missing_tables' AS section, t AS table_name
FROM expected e
WHERE to_regclass(e.t) IS NULL
ORDER BY t;

-- STEP 3: Estado de RLS por tabla (si existen)
SELECT 'rls_status' AS section,
       n.nspname AS schema,
       c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname IN ('maestros_empresa','maestros_centro','componentes','equipos','equipo_componente','movimientos','prestamos','bitacora')
ORDER BY c.relname;

-- STEP 4: Policies existentes por tabla (nombre y comando)
SELECT 'policies' AS section,
       schemaname AS schema,
       tablename  AS table_name,
       polname    AS policy_name,
       cmd        AS applies_to -- ALL/SELECT/INSERT/UPDATE/DELETE
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('maestros_empresa','maestros_centro','componentes','equipos','equipo_componente','movimientos','prestamos','bitacora')
ORDER BY tablename, policy_name;

-- STEP 5: Columnas clave presentes por tabla (empresa_id, centro_id, timestamps)
SELECT 'columns' AS section,
       table_name,
       column_name,
       data_type,
       is_nullable,
       column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('maestros_empresa','maestros_centro','componentes','equipos','equipo_componente','movimientos','prestamos','bitacora')
  AND column_name IN ('id','empresa_id','centro_id','created_at','updated_at','origen_centro_id','destino_centro_id','responsable_envio_id','responsable_recepcion_id','modo_transporte','zona_id','nombre')
ORDER BY table_name, column_name;

-- STEP 6: ¿Faltan columnas obligatorias por tabla? (resumen)
WITH req AS (
  SELECT 'maestros_empresa'::text AS t, 'id'::text AS c UNION ALL
  SELECT 'maestros_centro','id' UNION ALL
  SELECT 'maestros_centro','empresa_id' UNION ALL
  SELECT 'maestros_centro','zona_id' UNION ALL
  SELECT 'componentes','id' UNION ALL
  SELECT 'componentes','empresa_id' UNION ALL
  SELECT 'componentes','centro_id' UNION ALL
  SELECT 'componentes','created_at' UNION ALL
  SELECT 'equipos','id' UNION ALL
  SELECT 'equipos','empresa_id' UNION ALL
  SELECT 'equipos','centro_id' UNION ALL
  SELECT 'equipos','created_at' UNION ALL
  SELECT 'equipo_componente','id' UNION ALL
  SELECT 'equipo_componente','empresa_id' UNION ALL
  SELECT 'movimientos','id' UNION ALL
  SELECT 'movimientos','empresa_id' UNION ALL
  SELECT 'movimientos','origen_centro_id' UNION ALL
  SELECT 'movimientos','destino_centro_id' UNION ALL
  SELECT 'movimientos','responsable_envio_id' UNION ALL
  SELECT 'movimientos','responsable_recepcion_id' UNION ALL
  SELECT 'movimientos','modo_transporte' UNION ALL
  SELECT 'prestamos','id' UNION ALL
  SELECT 'prestamos','empresa_id' UNION ALL
  SELECT 'prestamos','centro_id' UNION ALL
  SELECT 'bitacora','id' UNION ALL
  SELECT 'bitacora','empresa_id' UNION ALL
  SELECT 'bitacora','centro_id'
),
have AS (
  SELECT table_name AS t, column_name AS c
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name IN ('maestros_empresa','maestros_centro','componentes','equipos','equipo_componente','movimientos','prestamos','bitacora')
),
missing AS (
  SELECT r.t AS table_name, r.c AS missing_column
  FROM req r
  LEFT JOIN have h ON h.t = r.t AND h.c = r.c
  WHERE h.c IS NULL
)
SELECT 'missing_columns' AS section, *
FROM missing
ORDER BY table_name, missing_column;

-- STEP 7: Tipos ENUM requeridos (modo_transporte_enum)
SELECT 'enum_exists' AS section, t.typname AS enum_name, array_agg(e.enumlabel ORDER BY e.enumsortorder) AS labels
FROM pg_type t
JOIN pg_enum e ON e.enumtypid = t.oid
WHERE t.typname IN ('modo_transporte_enum')
GROUP BY t.typname
UNION ALL
SELECT 'enum_exists' AS section, 'modo_transporte_enum' AS enum_name, NULL::text[] AS labels
WHERE NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'modo_transporte_enum');

-- STEP 8: Foreign keys útiles (vista general rápida)
SELECT 'foreign_keys' AS section,
       tc.table_name,
       kcu.column_name,
       ccu.table_name AS foreign_table,
       ccu.column_name AS foreign_column,
       tc.constraint_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
  AND tc.table_name IN ('componentes','equipos','equipo_componente','movimientos','prestamos','bitacora','maestros_centro')
ORDER BY tc.table_name, kcu.column_name;

-- STEP 9: Triggers presentes en prestamos/bitacora (por si ya tienes algo)
SELECT 'triggers' AS section,
       event_object_table AS table_name,
       trigger_name,
       action_timing,
       event_manipulation,
       action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table IN ('prestamos','bitacora')
ORDER BY event_object_table, trigger_name;

-- STEP 10: Vistas relacionadas (por si existe una previa de comunicación)
SELECT 'views' AS section, table_name AS view_name
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name IN ('v_comunicacion_zona')
ORDER BY table_name;
