-- =====================================================================
-- SMOKE PLANNER · public.movimientos
-- Objetivo: detectar el modelo vigente (LEGACY XOR vs OBJETO_TIPO/ID),
-- requisitos NOT NULL y dependencias, y generar un plan seguro.
-- NO inserta nada: imprime un "plan" (JSON) y un ejemplo de INSERT listo.
-- =====================================================================
DO $$
DECLARE
  v_has_equipo_id  boolean;
  v_has_componente_id boolean;
  v_has_objeto_tipo boolean;
  v_has_objeto_id  boolean;
  v_has_ck_xor     boolean := false;
  v_model          text;
  v_required       jsonb;
  v_labels_estado  jsonb;
  v_labels_tipo    jsonb;
  v_labels_lugar   jsonb;
  v_perf_sample    uuid;
  v_equipo_sample  uuid;
  v_comp_sample    uuid;
  v_can_insert     boolean := true;
  v_insert_sql     text;
BEGIN
  -- Detectar columnas
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='movimientos' AND column_name='equipo_id'),
         EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='movimientos' AND column_name='componente_id'),
         EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='movimientos' AND column_name='objeto_tipo'),
         EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='movimientos' AND column_name='objeto_id')
  INTO v_has_equipo_id, v_has_componente_id, v_has_objeto_tipo, v_has_objeto_id;

  -- Detectar CHECK XOR
  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.movimientos'::regclass AND contype='c'
      AND (conname ILIKE '%xor%' OR pg_get_constraintdef(oid) ILIKE '%equipo_id%' AND pg_get_constraintdef(oid) ILIKE '%componente_id%')
  ) INTO v_has_ck_xor;

  -- Modelo
  IF v_has_ck_xor AND v_has_equipo_id AND v_has_componente_id THEN
    v_model := 'legacy_xor';
  ELSIF v_has_objeto_tipo AND v_has_objeto_id THEN
    v_model := 'obj_pair';
  ELSE
    v_model := 'mixto/indeterminado';
  END IF;

  -- NOT NULL sin default
  SELECT jsonb_agg(attname ORDER BY attname) INTO v_required
  FROM (
    SELECT a.attname
    FROM pg_attribute a
    JOIN pg_class c ON c.oid=a.attrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
    WHERE n.nspname='public' AND c.relname='movimientos'
      AND a.attnum>0 AND NOT a.attisdropped
      AND a.attnotnull AND ad.adbin IS NULL AND a.attidentity=''
  ) s;

  -- Labels de enums (si existen)
  WITH et AS (
    SELECT a.attname, t.typname, t.typtype, t.oid AS typoid
    FROM pg_attribute a
    JOIN pg_class c ON c.oid=a.attrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    JOIN pg_type t ON t.oid=a.atttypid
    WHERE n.nspname='public' AND c.relname='movimientos' AND a.attname IN ('estado','tipo','origen_tipo','destino_tipo')
  )
  SELECT
    (SELECT jsonb_agg(enumlabel ORDER BY enumsortorder) FROM pg_enum e WHERE e.enumtypid=(SELECT typoid FROM et WHERE attname='estado')),
    (SELECT jsonb_agg(enumlabel ORDER BY enumsortorder) FROM pg_enum e WHERE e.enumtypid=(SELECT typoid FROM et WHERE attname='tipo'))
  INTO v_labels_estado, v_labels_tipo;

  SELECT jsonb_agg(enumlabel ORDER BY enumsortorder)
  INTO v_labels_lugar
  FROM pg_enum e
  WHERE e.enumtypid = (
    SELECT t.oid FROM pg_attribute a
    JOIN pg_class c ON c.oid=a.attrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    JOIN pg_type t ON t.oid=a.atttypid
    WHERE n.nspname='public' AND c.relname='movimientos' AND a.attname='origen_tipo'
    LIMIT 1
  );

  -- Dependencias mínimas
  SELECT id INTO v_perf_sample
  FROM public.perfiles
  WHERE rol::text IN ('oficina','admin')
  ORDER BY created_at LIMIT 1;

  SELECT id INTO v_equipo_sample FROM public.equipos LIMIT 1;
  SELECT id INTO v_comp_sample   FROM public.componentes LIMIT 1;

  IF v_perf_sample IS NULL THEN v_can_insert := false; END IF;
  IF v_equipo_sample IS NULL AND v_comp_sample IS NULL THEN v_can_insert := false; END IF;

  -- Preparar ejemplo de INSERT seguro
  IF v_model='legacy_xor' THEN
    IF v_equipo_sample IS NOT NULL THEN
      v_insert_sql := format($I$
        INSERT INTO public.movimientos(
          id, tipo, objeto, equipo_id,
          origen_tipo, origen_detalle,
          destino_tipo, destino_detalle,
          estado, created_at, created_by,
          responsable_origen_id, responsable_destino_id
        )
        VALUES (
          gen_random_uuid(), 'traslado', 'equipo', %L::uuid,
          'centro', 'centro_demo',
          'reparacion_externa', 'taller_oficial',
          'pendiente', now(), %L::uuid,
          %L::uuid, %L::uuid
        );
      $I$, v_equipo_sample::text, v_perf_sample::text, v_perf_sample::text, v_perf_sample::text);
    ELSIF v_comp_sample IS NOT NULL THEN
      v_insert_sql := format($I$
        INSERT INTO public.movimientos(
          id, tipo, objeto, componente_id,
          origen_tipo, origen_detalle,
          destino_tipo, destino_detalle,
          estado, created_at, created_by,
          responsable_origen_id, responsable_destino_id
        )
        VALUES (
          gen_random_uuid(), 'traslado', 'componente', %L::uuid,
          'centro', 'centro_demo',
          'reparacion_externa', 'taller_oficial',
          'pendiente', now(), %L::uuid,
          %L::uuid, %L::uuid
        );
      $I$, v_comp_sample::text, v_perf_sample::text, v_perf_sample::text, v_perf_sample::text);
    END IF;
  ELSIF v_model='obj_pair' THEN
    -- Variante objeto_tipo/objeto_id (por si el XOR no existe)
    IF v_equipo_sample IS NOT NULL THEN
      v_insert_sql := format($I$
        INSERT INTO public.movimientos(
          id, tipo, objeto_tipo, objeto_id,
          origen_tipo, origen_detalle,
          destino_tipo, destino_detalle,
          estado, created_at, created_by,
          responsable_origen_id, responsable_destino_id
        )
        VALUES (
          gen_random_uuid(), 'traslado', 'equipo', %L::uuid,
          'centro', 'centro_demo',
          'reparacion_externa', 'taller_oficial',
          'pendiente', now(), %L::uuid,
          %L::uuid, %L::uuid
        );
      $I$, v_equipo_sample::text, v_perf_sample::text, v_perf_sample::text, v_perf_sample::text);
    ELSIF v_comp_sample IS NOT NULL THEN
      v_insert_sql := format($I$
        INSERT INTO public.movimientos(
          id, tipo, objeto_tipo, objeto_id,
          origen_tipo, origen_detalle,
          destino_tipo, destino_detalle,
          estado, created_at, created_by,
          responsable_origen_id, responsable_destino_id
        )
        VALUES (
          gen_random_uuid(), 'traslado', 'componente', %L::uuid,
          'centro', 'centro_demo',
          'reparacion_externa', 'taller_oficial',
          'pendiente', now(), %L::uuid,
          %L::uuid, %L::uuid
        );
      $I$, v_comp_sample::text, v_perf_sample::text, v_perf_sample::text, v_perf_sample::text);
    END IF;
  END IF;

  RAISE NOTICE 'PLAN >> %',
    jsonb_build_object(
      'model', v_model,
      'can_insert_now', v_can_insert,
      'required_for_insert', coalesce(v_required,'[]'::jsonb),
      'enum_labels', jsonb_build_object(
         'estado', v_labels_estado,
         'tipo',   v_labels_tipo,
         'lugar',  v_labels_lugar
      ),
      'sample_ids', jsonb_build_object(
         'perfil', v_perf_sample,
         'equipo', v_equipo_sample,
         'componente', v_comp_sample
      ),
      'insert_example', v_insert_sql
    )::text;

END$$;