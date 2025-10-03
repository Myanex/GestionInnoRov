BEGIN;
SELECT pg_advisory_xact_lock(74123001);

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL idle_in_transaction_session_timeout = '120s';
SET LOCAL client_min_messages = notice;
SET LOCAL search_path = public, app;

DO $$
DECLARE
  v_id       uuid := 'beb727ae-9a72-46e1-b5a1-1bd0875f3b09'::uuid;  -- perfil rol=centro sin piloto
  -- 🔁 Completar con datos reales:
  v_nombre   text := 'Juan';
  v_ap_pat   text := 'Soto';
  v_ap_mat   text := NULL;                -- opcional: 'APELLIDO_MATERNO'
  v_rut      text := '12.123.111-1';
  v_email    text := 'jsoto@demo.cl';
  v_alias    text := NULL;                -- opcional
  v_telefono text := NULL;                -- opcional
  v_turno    text := NULL;                -- opcional

  v_emp      uuid;
  v_centro   uuid;
  v_rol_txt  text;
  v_dup_rut  boolean;
BEGIN
  -- 0) Ya existe piloto con ese id => salir sin error
  IF EXISTS (SELECT 1 FROM public.pilotos WHERE id = v_id) THEN
    RAISE NOTICE 'pilotos(%) ya existe — nada que hacer', v_id;
    RETURN;
  END IF;

  -- 1) Perfil debe existir y ser rol 'centro'
  SELECT empresa_id, centro_id, (rol::text)
    INTO v_emp, v_centro, v_rol_txt
  FROM public.perfiles
  WHERE id = v_id;

  IF v_rol_txt IS NULL THEN
    RAISE EXCEPTION 'Perfil % no existe en public.perfiles', v_id;
  ELSIF v_rol_txt <> 'centro' THEN
    RAISE EXCEPTION 'Perfil % tiene rol=%, se esperaba rol=''centro''', v_id, v_rol_txt;
  END IF;

  -- 2) Validaciones mínimas de datos obligatorios
  IF coalesce(trim(v_nombre), '') = '' THEN
    RAISE EXCEPTION 'v_nombre obligatorio';
  END IF;
  IF coalesce(trim(v_ap_pat), '') = '' THEN
    RAISE EXCEPTION 'v_ap_pat obligatorio';
  END IF;
  IF coalesce(trim(v_rut), '') = '' THEN
    RAISE EXCEPTION 'v_rut obligatorio';
  END IF;
  IF coalesce(trim(v_email), '') = '' THEN
    RAISE EXCEPTION 'v_email obligatorio';
  END IF;

  -- 3) Chequeo anti-duplicado de RUT (normalizado)
  SELECT EXISTS (
    SELECT 1
      FROM public.pilotos
     WHERE lower(regexp_replace(rut, '[^0-9kK]', '', 'g'))
         = lower(regexp_replace(v_rut,'[^0-9kK]', '', 'g'))
  ) INTO v_dup_rut;

  IF v_dup_rut THEN
    RAISE EXCEPTION 'RUT ya existe en pilotos (normalizado): %', v_rut
      USING HINT = 'Verifica homónimos o corrige el RUT antes de insertar';
  END IF;

  -- 4) Insert idempotente (empresa_id y centro_id heredados del perfil)
  INSERT INTO public.pilotos
    ( id,  nombre,  apellido_paterno,  apellido_materno,
      rut, email,   empresa_id,        centro_id,
      alias, telefono, turno, activo )
  VALUES
    ( v_id, v_nombre, v_ap_pat, v_ap_mat,
      v_rut, v_email, v_emp,     v_centro,
      v_alias, v_telefono, v_turno, TRUE )
  ON CONFLICT (id) DO NOTHING;

  RAISE NOTICE 'Piloto % insertado OK', v_id;
END $$;

COMMIT;
