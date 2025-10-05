## 2025-10-01 15:xx America/Santiago

- Files: (preflight de inventario — solo lectura)
- Commit: n/a
- Resultado: OK
- Notas:
  - ANALYZE por tabla (DO $$ …) ejecutado sobre public/app.
  - Duplicados típicos (pilotos/empresas/centros/equipos/componentes): 0.
  - Asignaciones activas >1 por componente (equipo_componente): 0.
  - Orfandad en FKs (pilotos/perfiles/equipos/componentes/bitácora/movimientos/prestamos): 0.
  - Conexión directa 5432; `ssl = on`.
  - `v_comunicacion_zona` sin filas (observación informativa).
- Tag: preflight-inventario v1

## 2025-10-01 16:xx America/Santiago

- Files: (maintenance) backfill perfiles ← pilotos (rol='centro')
- Commit: n/a
- Resultado: OK
- Notas:
  - Pilotos sin perfil: 5 → 0 (insert idempotente con rol='centro').
  - Perfiles sin piloto: 2 (se mantienen; esperado para roles admin/dev/oficina).
  - Transacción con pg_advisory_xact_lock y SET LOCAL; cast dinámico al enum.
- Tag: f1.1-prep-backfill

## 2025-10-01 17:xx America/Santiago

- Files: (auditoría) perfiles sin piloto
- Commit: n/a
- Resultado: OK (observación)
- Notas:
  - 2 perfiles sin piloto:
    - oficina (id=00000000-0000-0000-0000-000000000010) — esperado.
    - centro (id=beb727ae-9a72-46e1-b5a1-1bd0875f3b09) — pendiente de datos mínimos.
  - No se hizo inserción en `pilotos` por faltar campos NOT NULL (nombre, apellido_paterno, rut, email).
- Tag: f1.1-prep-observaciones

## 2025-10-02 21:xx America/Santiago

- Files:
  - preflight: db/preflight/2025-10-02_00_f13_rls_trigger_preflight.sql
  - migración: db/migrations/2025-10-02_01_f13_rls_trigger.sql
  - smoke: db/preflight/2025-10-02_02_f13_rls_trigger_smoke.sql
- Commit: <sha> <!-- git rev-parse --short HEAD -->
- Resultado: OK
- Notas:
  - Función del trigger como SECURITY DEFINER + `SET search_path = pg_catalog, public`.
  - Trigger `tg_pilotos_sync_empresa_from_centro_biu` apuntando a `public.fn_pilotos_sync_empresa_from_centro()`.
  - Uso cualificado de `public.centros` confirmado.
  - Smoke: `empresa_match_after_trigger = true`; FK `pilotos(id)→perfiles(id)` continúa validada.
- Tag: f1.3

## 2025-10-02 22:xx America/Santiago

- Files:
  - preflight: db/preflight/2025-10-02_00_f14_rut_norm_preflight.sql
  - migración: db/migrations/2025-10-02_01_f14_rut_norm.sql
  - smoke: db/preflight/2025-10-02_02_f14_rut_norm_smoke.sql
- Commit: <sha> <!-- git rev-parse --short HEAD -->
- Resultado: OK
- Notas:
  - Índice UNIQUE por RUT normalizado creado: ux_pilotos_rut_norm
  - Normalización: lower(regexp_replace(rut, '[^0-9kK]', '', 'g')), filtrando NULL/vacíos
  - Smoke: rut_norm_unique_enforced = true
- Tag: f1.4

## 2025-10-01 15:xx America/Santiago

- Files: (preflight de inventario — solo lectura)
- Commit: n/a
- Resultado: OK
- Notas:
  - ANALYZE por tabla (DO $$ …) ejecutado sobre public/app.
  - Duplicados típicos (pilotos/empresas/centros/equipos/componentes): 0.
  - Asignaciones activas >1 por componente (equipo_componente): 0.
  - Orfandad en FKs (pilotos/perfiles/equipos/componentes/bitácora/movimientos/prestamos): 0.
  - Conexión directa 5432; `ssl = on`.
  - `v_comunicacion_zona` sin filas (observación informativa).
- Tag: preflight-inventario v1

## 2025-10-01 16:xx America/Santiago

- Files: (maintenance) backfill perfiles ← pilotos (rol='centro')
- Commit: n/a
- Resultado: OK
- Notas:
  - Pilotos sin perfil: 5 → 0 (insert idempotente con rol='centro').
  - Perfiles sin piloto: 2 (se mantienen; esperado para roles admin/dev/oficina).
  - Transacción con pg_advisory_xact_lock y SET LOCAL; cast dinámico al enum.
- Tag: f1.1-prep-backfill

## 2025-10-01 17:xx America/Santiago

- Files: (auditoría) perfiles sin piloto
- Commit: n/a
- Resultado: OK (observación)
- Notas:
  - 2 perfiles sin piloto:
    - oficina (id=00000000-0000-0000-0000-000000000010) — esperado.
    - centro (id=beb727ae-9a72-46e1-b5a1-1bd0875f3b09) — pendiente de datos mínimos.
  - No se hizo inserción en `pilotos` por faltar campos NOT NULL (nombre, apellido_paterno, rut, email).
- Tag: f1.1-prep-observaciones

## 2025-10-02 19:xx America/Santiago

- Files:
  - preflight: db/preflight/2025-10-02_00_f12_pilotos_fk_reverse_preflight.sql
  - migración: db/migrations/2025-10-02_01_f12_pilotos_fk_reverse.sql
  - smoke: db/preflight/2025-10-02_02_f12_pilotos_fk_reverse_smoke.sql
- Commit: <sha> <!-- git rev-parse --short HEAD -->
- Resultado: OK
- Notas:
  - FK nueva `pilotos(id) → perfiles(id)` creada y VALIDADA (ON UPDATE CASCADE, ON DELETE RESTRICT).
  - FK antigua `perfiles(id) → pilotos(id)` eliminada.
  - Trigger `tg_pilotos_sync_empresa_from_centro_biu` operativo (smoke `empresa_match = true`).
  - `pilotos_sin_perfil = 0`; `perfiles_sin_piloto = 2` (roles no-piloto/centro sin datos).
- Tag: f1.2
-

## 2025-10-02 20:xx America/Santiago

- Files: (maintenance) alta de piloto desde perfil rol='centro'
- Commit: n/a
- Resultado: OK
- Notas:
  - Insert idempotente de public.pilotos (hereda empresa/centro desde perfiles).
  - Checks previos: perfil existe y es rol 'centro'; RUT no duplicado (normalizado).
  - Smoke: pilotos_sin_perfil=0; perfiles_sin_piloto=1 (queda el de oficina).
- Tag: f1.2.1

## 2025-10-02 20:xx America/Santiago

- Files: (maintenance) alta de piloto desde perfil rol='centro'
- Commit: n/a
- Resultado: OK
- Notas:
  - Insert idempotente en `public.pilotos` heredando `empresa_id/centro_id` desde `perfiles`.
  - Smoke: `pilotos_sin_perfil = 0`; `perfiles_sin_piloto = 1` (queda el de oficina).
- Tag: f1.2.1

# 2025-10-04 · F3 · Préstamos (RPCs + Smoke)

## Ambiente

- DB: Supabase Postgres
- Conexión: admin 5432 (directa, no pooler)
- Herramienta: DBeaver (Auto-commit ON, 1 conexión)

## Cambios aplicados

- CREATE OR REPLACE FUNCTION public.rpc_prestamo_crear(jsonb)
- CREATE OR REPLACE FUNCTION public.rpc_prestamo_cerrar(uuid, timestamptz DEFAULT now())
- DROP FUNCTION public.rpc_prestamo_cerrar(uuid) -- se elimina la sobrecarga ambigua
- CREATE OR REPLACE FUNCTION app.\_audit_min(...) -- auditoría tolerante (no bloquea)

## Preflight (OK)

- required_for_insert: ["equipo_origen_id","equipo_destino_id","componente_id","responsable_id","motivo"]
- unique_activo_por_componente: true
- prestamo_estado_labels: (detectadas por enum; incluye 'activo' + etiqueta(s) de cierre)
- rpc_presence: {"rpc_prestamo_crear": true, "rpc_prestamo_cerrar": true}

## Smoke (OK)

Duplicado rechazado OK (23505).
SMOKE OK: f604641f-0c32-446d-ba4d-3dcd65b7c0f6, c4534372-4b32-4346-87e4-ce5d54c0d40a

## Permisos

GRANT EXECUTE ON FUNCTION public.rpc_prestamo_crear(jsonb) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_prestamo_cerrar(uuid, timestamptz) TO anon, authenticated;

## Notas

- Se usa advisory lock por componente para evitar carreras en préstamos activos.
- El estado de cierre se elige dinámicamente según el enum disponible ('cerrado'/'devuelto'/otro != 'activo').
- Scripts ejecutados terminan en ROLLBACK durante smoke; sin residuos.
