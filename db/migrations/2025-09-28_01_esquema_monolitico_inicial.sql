-- =============================================================================
-- Sistema de Gestión ROV — Esquema monolítico (v1.0-enums · 2025-09-19)
-- Compatibilidad: Supabase/Postgres (sin superuser). Usa gen_random_uuid().
-- =============================================================================

BEGIN;
-- STEP: lock global para evitar colisiones de despliegue
SELECT pg_advisory_xact_lock(74123001);

-- =============================================================================
-- STEP: Drops (idempotencia) - tablas primero, luego tipos/funciones
-- =============================================================================
-- Tablas (orden inverso de dependencias)
DROP TABLE IF EXISTS piloto_situaciones        CASCADE;
DROP TABLE IF EXISTS pilotos                   CASCADE;
DROP TABLE IF EXISTS bitacora_items            CASCADE;
DROP TABLE IF EXISTS bitacora                  CASCADE;
DROP TABLE IF EXISTS movimientos               CASCADE;
DROP TABLE IF EXISTS prestamos                 CASCADE;
DROP TABLE IF EXISTS equipo_componente         CASCADE;
DROP TABLE IF EXISTS equipos                   CASCADE;
DROP TABLE IF EXISTS componentes               CASCADE;
DROP TABLE IF EXISTS perfiles                  CASCADE;
DROP TABLE IF EXISTS config_centro             CASCADE;
DROP TABLE IF EXISTS centros                   CASCADE;
DROP TABLE IF EXISTS zonas                     CASCADE;
DROP TABLE IF EXISTS empresas                  CASCADE;

-- Funciones
DROP FUNCTION IF EXISTS fn_touch_updated_at()  CASCADE;

-- Tipos
DROP TYPE IF EXISTS rol_usuario                        CASCADE;
DROP TYPE IF EXISTS estado_activo_inactivo             CASCADE;
DROP TYPE IF EXISTS componente_tipo                    CASCADE;
DROP TYPE IF EXISTS operatividad                       CASCADE;
DROP TYPE IF EXISTS componente_condicion               CASCADE;
DROP TYPE IF EXISTS componente_ubicacion               CASCADE;
DROP TYPE IF EXISTS equipo_estado                      CASCADE;
DROP TYPE IF EXISTS equipo_condicion                   CASCADE;
DROP TYPE IF EXISTS equipo_rol                         CASCADE;
DROP TYPE IF EXISTS equipo_ubicacion                   CASCADE;
DROP TYPE IF EXISTS rol_componente_en_equipo           CASCADE;
DROP TYPE IF EXISTS prestamo_estado                    CASCADE;
DROP TYPE IF EXISTS movimiento_tipo                    CASCADE;
DROP TYPE IF EXISTS movimiento_estado                  CASCADE;
DROP TYPE IF EXISTS objeto_movimiento                  CASCADE;
DROP TYPE IF EXISTS jornada                            CASCADE;
DROP TYPE IF EXISTS estado_puerto                      CASCADE;
DROP TYPE IF EXISTS actividad_bitacora                 CASCADE;
DROP TYPE IF EXISTS equipo_usado                       CASCADE;
DROP TYPE IF EXISTS piloto_estado                      CASCADE;
DROP TYPE IF EXISTS piloto_situacion                   CASCADE;
DROP TYPE IF EXISTS lugar_operacion                    CASCADE;

-- =============================================================================
-- STEP: Función utilitaria - touch updated_at
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- =============================================================================
-- STEP: ENUMS
-- =============================================================================
-- Seguridad
CREATE TYPE rol_usuario AS ENUM ('dev','admin','oficina','centro');

-- Organización / estados
CREATE TYPE estado_activo_inactivo AS ENUM ('activo','inactivo');

-- Inventario / Componentes
CREATE TYPE componente_tipo      AS ENUM ('rov','controlador','umbilical','sensor','grabber');
CREATE TYPE operatividad         AS ENUM ('operativo','no_operativo','restringido');
CREATE TYPE componente_condicion AS ENUM ('normal','falla_menor','falla_mayor','en_reparacion','enredado','baja');
CREATE TYPE componente_ubicacion AS ENUM ('bodega','centro','asignado_a_equipo','en_transito','reparacion_externa');

-- Inventario / Equipos
CREATE TYPE equipo_estado    AS ENUM ('vigente','no_vigente');
CREATE TYPE equipo_condicion AS ENUM ('normal','falta_componente','en_reparacion','enredado','baja');
CREATE TYPE equipo_rol       AS ENUM ('principal','backup');
CREATE TYPE equipo_ubicacion AS ENUM ('bodega','centro','en_transito','reparacion_externa');

-- Equipo-Componente
CREATE TYPE rol_componente_en_equipo AS ENUM ('rov','controlador','umbilical','sensor','grabber');

-- Préstamos
CREATE TYPE prestamo_estado AS ENUM ('activo','devuelto','definitivo');

-- Movimientos
CREATE TYPE movimiento_tipo   AS ENUM ('ingreso','traslado','devolucion','baja');
CREATE TYPE movimiento_estado AS ENUM ('pendiente','en_transito','recibido','cancelado');
CREATE TYPE objeto_movimiento AS ENUM ('equipo','componente');
-- Lugares operativos (movimientos)
CREATE TYPE lugar_operacion   AS ENUM ('centro','bodega','oficina','reparacion_externa');

-- Bitácora
CREATE TYPE jornada         AS ENUM ('am','pm');
CREATE TYPE estado_puerto   AS ENUM ('abierto','restringido','cerrado');
CREATE TYPE actividad_bitacora AS ENUM (
  'extraccion_mortalidad','inspeccion_redes_loberas','inspeccion_redes_peceras',
  'inspeccion','otro','condicion_puerto_cerrado'
);
CREATE TYPE equipo_usado     AS ENUM ('principal','backup');

-- Pilotos
CREATE TYPE piloto_estado    AS ENUM ('con_centro','sin_centro');
CREATE TYPE piloto_situacion AS ENUM ('en_turno','descanso','licencia','vacaciones','sin_centro','en_spot');

-- =============================================================================
-- STEP: Organización
-- =============================================================================
CREATE TABLE empresas (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre        text NOT NULL UNIQUE,
  slug          text NOT NULL UNIQUE,
  display_name  text,
  estado        estado_activo_inactivo NOT NULL DEFAULT 'activo',
  is_demo       boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER empresas_touch_updated_at
BEFORE UPDATE ON empresas
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE zonas (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre      text NOT NULL,
  slug        text NOT NULL,
  empresa_id  uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  is_demo     boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT zonas_empresa_nombre_uk UNIQUE (empresa_id, nombre),
  CONSTRAINT zonas_empresa_slug_uk   UNIQUE (empresa_id, slug)
);
-- Para FK compuesta centros(zona_id, empresa_id) → zonas(id, empresa_id)
ALTER TABLE zonas
  ADD CONSTRAINT zonas_id_empresa_uk UNIQUE (id, empresa_id);

CREATE TRIGGER zonas_touch_updated_at
BEFORE UPDATE ON zonas
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE centros (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre      text NOT NULL UNIQUE,             -- globalmente único
  slug        text NOT NULL UNIQUE,
  empresa_id  uuid NOT NULL REFERENCES empresas(id) ON DELETE RESTRICT,
  zona_id     uuid NOT NULL REFERENCES zonas(id)    ON DELETE RESTRICT,
  estado      estado_activo_inactivo NOT NULL DEFAULT 'activo',
  is_demo     boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  -- Coherencia: la zona debe pertenecer a la misma empresa del centro
  CONSTRAINT centros_zona_empresa_fk
    FOREIGN KEY (zona_id, empresa_id) REFERENCES zonas(id, empresa_id)
);
CREATE TRIGGER centros_touch_updated_at
BEFORE UPDATE ON centros
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- =============================================================================
-- STEP: Seguridad / Perfiles
-- =============================================================================
-- Nota: perfiles.id = auth.users.id (1:1 con el usuario autenticado)
CREATE TABLE perfiles (
  id          uuid PRIMARY KEY, -- = auth.users.id
  rol         rol_usuario NOT NULL,
  empresa_id  uuid REFERENCES empresas(id),
  centro_id   uuid REFERENCES centros(id),
  nombre      text,
  email       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
  -- RLS/masking para PII se define en fases.
);
CREATE UNIQUE INDEX IF NOT EXISTS perfiles_email_uk
  ON perfiles (email)
  WHERE email IS NOT NULL;

CREATE TRIGGER perfiles_touch_updated_at
BEFORE UPDATE ON perfiles
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- =============================================================================
-- STEP: Inventario - Componentes
-- =============================================================================
CREATE TABLE componentes (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       uuid NOT NULL REFERENCES empresas(id),
  zona_id          uuid REFERENCES zonas(id),
  centro_id        uuid REFERENCES centros(id),
  tipo             componente_tipo NOT NULL,
  codigo           text NOT NULL UNIQUE,
  estado           estado_activo_inactivo NOT NULL DEFAULT 'activo',
  fecha_activo     timestamptz,
  fecha_inactivo   timestamptz,
  motivo_inactivo  text,
  serie            text NOT NULL UNIQUE,
  operatividad     operatividad NOT NULL DEFAULT 'operativo',
  condicion        componente_condicion NOT NULL DEFAULT 'normal',
  ubicacion        componente_ubicacion, -- NULL permitido si condicion='baja'
  ubicacion_detalle text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT componentes_baja_ubicacion_ck
    CHECK (NOT (condicion = 'baja' AND ubicacion IS DISTINCT FROM NULL))
);
CREATE TRIGGER componentes_touch_updated_at
BEFORE UPDATE ON componentes
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- =============================================================================
-- STEP: Inventario - Equipos
-- =============================================================================
CREATE TABLE equipos (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       uuid NOT NULL REFERENCES empresas(id),
  zona_id          uuid REFERENCES zonas(id),
  centro_id        uuid REFERENCES centros(id),
  codigo           text NOT NULL UNIQUE,
  estado           equipo_estado NOT NULL DEFAULT 'vigente',
  fecha_activo     timestamptz,
  fecha_inactivo   timestamptz,
  motivo_inactivo  text,
  operatividad     operatividad NOT NULL DEFAULT 'operativo',
  condicion        equipo_condicion NOT NULL DEFAULT 'normal',
  rol              equipo_rol,              -- principal/backup/null
  ubicacion        equipo_ubicacion,        -- NULL permitido si condicion='baja'
  ubicacion_detalle text,
  -- Denormalizado opcional para rapidez de consultas; mantenido por trigger
  rov_componente_id uuid REFERENCES componentes(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT equipos_baja_ubicacion_ck
    CHECK (NOT (condicion = 'baja' AND ubicacion IS DISTINCT FROM NULL))
);
CREATE TRIGGER equipos_touch_updated_at
BEFORE UPDATE ON equipos
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- =============================================================================
-- STEP: Inventario - Equipo_Componente (histórico)
-- =============================================================================
CREATE TABLE equipo_componente (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  equipo_id            uuid NOT NULL REFERENCES equipos(id) ON DELETE CASCADE,
  componente_id        uuid NOT NULL REFERENCES componentes(id) ON DELETE RESTRICT,
  rol_componente       rol_componente_en_equipo NOT NULL,
  fecha_asignacion     timestamptz NOT NULL DEFAULT now(),
  fecha_desasignacion  timestamptz
);
-- 1) Un componente no puede estar en dos equipos a la vez (vigente):
CREATE UNIQUE INDEX equipo_comp_componente_vigente_uk
  ON equipo_componente (componente_id)
  WHERE fecha_desasignacion IS NULL;

-- 2) Por equipo, exactamente un ROV vigente:
CREATE UNIQUE INDEX equipo_comp_rov_vigente_por_equipo_uk
  ON equipo_componente (equipo_id)
  WHERE fecha_desasignacion IS NULL AND rol_componente = 'rov';

-- 3) Por equipo, máximo uno vigente para 'controlador' y 'umbilical':
CREATE UNIQUE INDEX equipo_comp_unico_roles_basicos_uk
  ON equipo_componente (equipo_id, rol_componente)
  WHERE fecha_desasignacion IS NULL AND rol_componente IN ('controlador','umbilical');

-- Sensores y grabbers: múltiples vigentes permitidos (sin unique por rol).

-- TODO: Trigger (fase posterior):
-- - Mantener equipos.rov_componente_id y validar invariante de ROV único.
-- - Si el ROV cambia a condicion='baja' -> disolver equipo (no_vigente + cerrar asignaciones).

-- =============================================================================
-- STEP: Préstamos intra-centro
-- =============================================================================
CREATE TABLE prestamos (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  estado               prestamo_estado NOT NULL DEFAULT 'activo',
  equipo_origen_id     uuid NOT NULL REFERENCES equipos(id),
  equipo_destino_id    uuid NOT NULL REFERENCES equipos(id),
  componente_id        uuid NOT NULL REFERENCES componentes(id),
  responsable_id       uuid NOT NULL REFERENCES perfiles(id),
  motivo               text NOT NULL,
  fecha_prestamo       timestamptz NOT NULL DEFAULT now(),
  fecha_devuelto       timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER prestamos_touch_updated_at
BEFORE UPDATE ON prestamos
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- Un préstamo activo por componente a la vez
CREATE UNIQUE INDEX prestamos_activo_por_componente_uk
  ON prestamos (componente_id)
  WHERE estado = 'activo';

-- TODO (fase posterior): trigger que
-- - valide que ambos equipos pertenecen al mismo centro (intra-centro).
-- - valide que el componente está vigente en equipo_origen y no prestado.
-- - al pasar a 'definitivo': reasignar titularidad (cerrar/abrir en equipo_componente).
-- - al 'devuelto': revertir si corresponde.

-- =============================================================================
-- STEP: Movimientos
-- =============================================================================
CREATE TABLE movimientos (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo                     movimiento_tipo NOT NULL,
  estado                   movimiento_estado NOT NULL DEFAULT 'pendiente',
  objeto                   objeto_movimiento NOT NULL,
  equipo_id                uuid REFERENCES equipos(id),
  componente_id            uuid REFERENCES componentes(id),
  origen_tipo              lugar_operacion NOT NULL,
  origen_detalle           text NOT NULL,
  destino_tipo             lugar_operacion NOT NULL,
  destino_detalle          text NOT NULL,
  responsable_origen_id    uuid NOT NULL REFERENCES perfiles(id),
  responsable_destino_id   uuid REFERENCES perfiles(id),
  nota                     text,
  fecha_creado             timestamptz NOT NULL DEFAULT now(),
  fecha_envio              timestamptz,
  fecha_recepcion          timestamptz,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT movimientos_objeto_xor_ck CHECK (
    (objeto = 'equipo' AND equipo_id IS NOT NULL AND componente_id IS NULL)
    OR
    (objeto = 'componente' AND componente_id IS NOT NULL AND equipo_id IS NULL)
  )
);
CREATE TRIGGER movimientos_touch_updated_at
BEFORE UPDATE ON movimientos
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- TODO (fase posterior): trigger/funciones workflow
-- - Flujo estados: pendiente→en_transito→recibido; cancelado desde pendiente.
-- - 'reparacion_externa': recibido solo por 'oficina'.
-- - Recepción equipo: actualizar ubicaciones del equipo y sus componentes vigentes.
-- - Recepción componente: actualizar ubicación directa.
-- - 'baja': exigir nota y marcar inactividad (fecha/motivo).
-- - Traslado: origen != destino.

-- =============================================================================
-- STEP: Bitácora
-- =============================================================================
CREATE TABLE bitacora (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fecha          date NOT NULL,
  jornada        jornada,
  empresa_id     uuid NOT NULL REFERENCES empresas(id),
  zona_id        uuid REFERENCES zonas(id),
  centro_id      uuid NOT NULL REFERENCES centros(id),
  piloto_id      uuid NOT NULL REFERENCES perfiles(id), -- rol centro
  estado_puerto  estado_puerto,
  equipo_usado   equipo_usado DEFAULT 'principal',
  comentarios    text,
  motivo_atraso  text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER bitacora_touch_updated_at
BEFORE UPDATE ON bitacora
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE bitacora_items (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bitacora_id    uuid NOT NULL REFERENCES bitacora(id) ON DELETE CASCADE,
  actividad      actividad_bitacora NOT NULL,
  detalle        text,
  equipo_usado   equipo_usado DEFAULT 'principal',
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER bitacora_items_touch_updated_at
BEFORE UPDATE ON bitacora_items
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- TODO (fase posterior): trigger que si actividad='condicion_puerto_cerrado' entonces
-- bitacora.estado_puerto debe ser 'cerrado'. Ventanas de edición se validan vía RPC/trigger usando config_centro.

-- =============================================================================
-- STEP: Pilotos (PII) y situaciones
-- =============================================================================
-- 1:1 con perfiles.id (aplica típicamente cuando rol='centro')
CREATE TABLE pilotos (
  id                   uuid PRIMARY KEY, -- = perfiles.id
  nombre               text NOT NULL,
  apellido_paterno     text NOT NULL,
  apellido_materno     text,
  rut                  text NOT NULL UNIQUE,
  email                text NOT NULL UNIQUE,
  centro_id            uuid REFERENCES centros(id),
  estado               piloto_estado,
  situacion            piloto_situacion,
  fecha_contratacion   date,
  fecha_desvinculacion date,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER pilotos_touch_updated_at
BEFORE UPDATE ON pilotos
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE piloto_situaciones (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  piloto_id      uuid NOT NULL REFERENCES pilotos(id) ON DELETE CASCADE,
  situacion      piloto_situacion NOT NULL,
  fecha_inicio   timestamptz NOT NULL,
  fecha_fin      timestamptz,
  motivo         text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER piloto_situaciones_touch_updated_at
BEFORE UPDATE ON piloto_situaciones
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- Cero o una situación vigente por piloto
CREATE UNIQUE INDEX piloto_situacion_vigente_uk
  ON piloto_situaciones (piloto_id)
  WHERE fecha_fin IS NULL;

-- =============================================================================
-- STEP: Configuración de centros (ventanas bitácora)
-- =============================================================================
CREATE TABLE config_centro (
  centro_id             uuid PRIMARY KEY REFERENCES centros(id) ON DELETE CASCADE,
  hora_corte            time NOT NULL DEFAULT '23:59',
  ventana_edicion_horas int  NOT NULL DEFAULT 24,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER config_centro_touch_updated_at
BEFORE UPDATE ON config_centro
FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

-- =============================================================================
-- STEP: Vistas (opcionales) - se definirán en su fase si aplica
-- =============================================================================
-- -- Ejemplo:
-- -- CREATE VIEW vw_componentes_vigentes_por_equipo AS
-- -- SELECT ...

-- =============================================================================
-- STEP: Prueba mínima (seed_test reducido e idempotente)
-- =============================================================================
-- Empresa/Zona/Centro demo
INSERT INTO empresas (id, nombre, slug, display_name, is_demo)
VALUES ('00000000-0000-0000-0000-000000000001','Empresa Demo','empresa-demo','Empresa Demo S.A.', true)
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO zonas (id, nombre, slug, empresa_id, is_demo)
SELECT '00000000-0000-0000-0000-000000000002','Zona Norte','zona-norte', e.id, true
FROM empresas e WHERE e.nombre='Empresa Demo'
ON CONFLICT (empresa_id, nombre) DO NOTHING;

INSERT INTO centros (id, nombre, slug, empresa_id, zona_id, is_demo)
SELECT
  '00000000-0000-0000-0000-000000000003',
  'Centro Demo','centro-demo', z.empresa_id, z.id, true
FROM zonas z
JOIN empresas e ON e.id = z.empresa_id
WHERE z.nombre='Zona Norte' AND e.nombre='Empresa Demo'
ON CONFLICT (nombre) DO NOTHING;

-- Perfil oficina demo
INSERT INTO perfiles (id, rol, empresa_id, nombre, email)
SELECT '00000000-0000-0000-0000-000000000010','oficina', e.id, 'Oficina Demo','oficina.demo@example.com'
FROM empresas e WHERE e.nombre='Empresa Demo'
ON CONFLICT (id) DO NOTHING;

-- Piloto demo (rol centro) - solo ficha PII, asumiendo que auth.users existe aparte
INSERT INTO perfiles (id, rol, empresa_id, centro_id, nombre, email)
SELECT '00000000-0000-0000-0000-000000000011','centro', e.id, c.id, 'Piloto Demo','piloto.demo@example.com'
FROM empresas e
JOIN centros c ON c.empresa_id = e.id
WHERE e.nombre='Empresa Demo' AND c.nombre='Centro Demo'
ON CONFLICT (id) DO NOTHING;

INSERT INTO pilotos (id, nombre, apellido_paterno, rut, email, centro_id, estado, situacion)
SELECT
  '00000000-0000-0000-0000-000000000011','Piloto','Demo','11.111.111-1','piloto.demo@example.com', c.id,
  'con_centro','en_turno'
FROM centros c WHERE c.nombre='Centro Demo'
ON CONFLICT (id) DO NOTHING;

-- Conteos de integridad básica
-- 1) Empresa/Zona/Centro
SELECT
  (SELECT COUNT(*) FROM empresas)   AS empresas_cnt,
  (SELECT COUNT(*) FROM zonas)      AS zonas_cnt,
  (SELECT COUNT(*) FROM centros)    AS centros_cnt;

-- 2) Perfiles/Pilotos coherentes
SELECT
  (SELECT COUNT(*) FROM perfiles WHERE rol='oficina') AS perfiles_oficina_cnt,
  (SELECT COUNT(*) FROM perfiles WHERE rol='centro')  AS perfiles_centro_cnt,
  (SELECT COUNT(*) FROM pilotos)                      AS pilotos_cnt;

COMMIT;

-- =============================================================================
-- FIN DEL ESQUEMA MONOLÍTICO
-- =============================================================================
