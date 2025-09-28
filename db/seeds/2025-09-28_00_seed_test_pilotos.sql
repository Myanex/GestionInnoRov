-- F1 — seed_test pilotos (compat text/enum para columna estado)
-- Inserta 3 pilotos de prueba asociados a la empresa/centro de sesión, evitando duplicados por (empresa_id, nombre).

BEGIN;
SELECT pg_advisory_xact_lock(10003); -- F1 seed lock

-- STEP: (Opcional) asegurar unique por idempotencia del anti-join
CREATE UNIQUE INDEX IF NOT EXISTS pilotos_unq_empresa_nombre ON public.pilotos (empresa_id, nombre);

DO $$
DECLARE
  v_is_enum boolean := false;
  v_inserted integer := 0;
BEGIN
  -- Detectar si public.pilotos.estado es enum 'piloto_estado'
  SELECT (c.data_type = 'USER-DEFINED' AND c.udt_schema = 'public' AND c.udt_name = 'piloto_estado')
  INTO  v_is_enum
  FROM information_schema.columns c
  WHERE c.table_schema='public' AND c.table_name='pilotos' AND c.column_name='estado';

  IF v_is_enum THEN
    -- Inserción con CAST a enum
    EXECUTE $SQL$
      WITH base AS (
        SELECT public.app_empresa_id() AS empresa_id, public.app_centro_id() AS centro_id
      ),
      src AS (
        SELECT 
          b.empresa_id, 
          b.centro_id,
          x.nombre, x.alias, x.estado, x.telefono, x.email, x.turno, x.notas
        FROM base b
        CROSS JOIN (VALUES
          ('Juan Pérez',   'JP',   'activo',    '9-1111-1111', 'juan.perez@example.com',   '14x14', 'seed_test'),
          ('María Soto',    NULL,  'activo',    '9-2222-2222', 'maria.soto@example.com',   '15x15', 'seed_test'),
          ('Carlos Díaz',  'Carl', 'inactivo',  '9-3333-3333', 'carlos.diaz@example.com',  NULL,    'seed_test')
        ) AS x(nombre, alias, estado, telefono, email, turno, notas)
      ),
      ins AS (
        INSERT INTO public.pilotos (empresa_id, centro_id, nombre, alias, estado, telefono, email, turno, notas)
        SELECT s.empresa_id, s.centro_id, s.nombre, s.alias, s.estado::public.piloto_estado, s.telefono, s.email, s.turno, s.notas
        FROM src s
        WHERE s.empresa_id IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM public.pilotos p
            WHERE p.empresa_id = s.empresa_id
              AND p.nombre = s.nombre
          )
        RETURNING 1
      )
      SELECT count(*) FROM ins
    $SQL$
    INTO v_inserted;
  ELSE
    -- Inserción sin cast (columna estado es TEXT)
    EXECUTE $SQL$
      WITH base AS (
        SELECT public.app_empresa_id() AS empresa_id, public.app_centro_id() AS centro_id
      ),
      src AS (
        SELECT 
          b.empresa_id, 
          b.centro_id,
          x.nombre, x.alias, x.estado, x.telefono, x.email, x.turno, x.notas
        FROM base b
        CROSS JOIN (VALUES
          ('Juan Pérez',   'JP',   'activo',    '9-1111-1111', 'juan.perez@example.com',   '14x14', 'seed_test'),
          ('María Soto',    NULL,  'activo',    '9-2222-2222', 'maria.soto@example.com',   '15x15', 'seed_test'),
          ('Carlos Díaz',  'Carl', 'inactivo',  '9-3333-3333', 'carlos.diaz@example.com',  NULL,    'seed_test')
        ) AS x(nombre, alias, estado, telefono, email, turno, notas)
      ),
      ins AS (
        INSERT INTO public.pilotos (empresa_id, centro_id, nombre, alias, estado, telefono, email, turno, notas)
        SELECT s.empresa_id, s.centro_id, s.nombre, s.alias, s.estado, s.telefono, s.email, s.turno, s.notas
        FROM src s
        WHERE s.empresa_id IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM public.pilotos p
            WHERE p.empresa_id = s.empresa_id
              AND p.nombre = s.nombre
          )
        RETURNING 1
      )
      SELECT count(*) FROM ins
    $SQL$
    INTO v_inserted;
  END IF;

  RAISE NOTICE 'seed_test_pilotos: % filas insertadas', v_inserted;
END
$$ LANGUAGE plpgsql;

COMMIT;
