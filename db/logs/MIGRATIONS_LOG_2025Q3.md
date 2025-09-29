## 2025-09-28 12:00 America/Santiago
- Files: `2025-09-28_01_esquema_monolitico_inicial.sql`
- Commit: `pending`
- Resultado: OK
- Notas:
  - Esquema base completo (tipos, tablas, índices, triggers updated_at).
  - FK compuesta centros(zona_id, empresa_id) → zonas(id, empresa_id).
  - Índices parciales en equipo_componente y piloto_situaciones.
  - Seed_test mínimo (empresa/zona/centro/perfiles/piloto).
  - Sin RLS/RPC aún; TODOs de triggers de negocio documentados en comentarios.
- Tag: `schema-v1.0`
Recordatorios clave
- Consolidar en chats de fase: RLS, RPCs y triggers de negocio antes de exponer en producción.

## 2025-09-28 18:10 America/Santiago
- Files: `db/migrations/2025-09-28_00_rls_base.sql`
- Commit: `feat(db): F0 RLS base (helpers, enum, RLS, policies, triggers)`
- Resultado: OK
- Notas:
  - Esquema `app` + helpers: `app_current_perfil()`, `app_is_role()`, `app_set_debug_claims()` / `app_clear_debug_claims()`, `app_empresa_id()`, `app_centro_id()`.
  - Enum `modo_transporte_enum`.
  - Utilidad `app._ensure_column()` y normalización de columnas mínimas (id/empresa_id/centro_id/timestamps); campos extra en `movimientos` (origen/destino/responsables/modo_transporte).
  - `ENABLE RLS` en: `maestros_empresa`, `maestros_centro`, `componentes`, `equipos`, `equipo_componente`, `movimientos`, `prestamos`, `bitacora`.
  - Policies por rol (prefijo `f0_`):  
    - `admin/dev`: ALL.  
    - `oficina` (InnoROV): RW global.  
    - `centro`: lectura estricta por centro; RW en `bitacora`; CRUD intracentro en `prestamos`; sin bodega.
  - Triggers: `tr_prestamos_enforce_perfil_biu` (normalize empresa/centro para rol centro), `tr_audit_prestamos_cud` y `tr_audit_bitacora_cud`.
- Prueba mínima ejecutada: ver smoke tests Paso 3.
- Tag: `F0-RLS-base`
Recordatorios clave
- Alinear claims JWT (`role`, `empresa_id`, `centro_id`).
- Mantener prefijo `f0_` para identificar policies de esta fase.

## 2025-09-28 18:35 America/Santiago
- Files: `db/migrations/2025-09-28_01_view_comunicacion.sql`
- Commit: `feat(db): vista comunicación por zona (SECURITY DEFINER)`
- Resultado: OK
- Notas:
  - Función `app.v_comunicacion_zona()` (SECURITY DEFINER, STABLE, `search_path = public, pg_temp`) con filtro interno por rol/empresa/zona.
  - Soporta ausencia de `public.pilotos` sin fallar.
  - Vista `public.v_comunicacion_zona` como envoltorio (frontend).
  - No modifica datos.
- Prueba mínima ejecutada: ver smoke tests Paso 3 (SELECT según rol).
- Tag: `F0-RLS-base`
Recordatorios clave
- Si se requiere, restringir `EXECUTE` de la función a `authenticated`/`anon`.

## 2025-09-28 18:55 America/Santiago
- Files: `db/migrations/2025-09-28_00a_bootstrap_maestros.sql`
- Commit: `feat(db): bootstrap catálogos maestros (empresa/centro)`
- Resultado: OK
- Notas:
  - Creadas tablas `maestros_empresa` y `maestros_centro` (con `zona_id`) + índices.
  - `ENABLE RLS` y policies alineadas con F0:  
    - `admin/dev`: ALL, `oficina`: ALL, `centro`: SELECT solo su centro (otros centros de la zona se exponen por la vista).
  - Sin seeds (solo estructura).
- Prueba mínima ejecutada: re-ejecución smoke tests (Paso 3) sin errores.
- Tag: `F0-RLS-base`
Recordatorios clave
- `maestros_centro` es prerequisito para la vista de comunicación y para filtros por zona.

## 2025-09-29 20:00 America/Santiago
- Files:
  - `db/migrations/2025-09-29_02_f1_pilotos_hardening.sql`
  - `db/migrations/2025-09-29_03_f1_rebuild_vista_y_smoke.sql`
  - `db/preflight/2025-09-29_f1_smoketest_vista.sql`
- Commit: `<sha>`
- Resultado: OK
- Notas:
  - Hardening `public.pilotos`: DEFAULT `id=gen_random_uuid()`, trigger `updated_at`, secuencia `pilotos_codigo_seq`, FKs coherentes (`empresa_id`/`centro_id`), RLS `f1_*` repuestas.
  - Rebuild `v_comunicacion_zona` con resumen por empresa/centro (basada en `pilotos`), RLS heredado.
  - Seed forzado: +3 pilotos válidos (`nombre`, `apellido_paterno`, `rut`, `email`, enum `con_centro/sin_centro`), total visibles=6.
  - Preflight smoke devuelve totales >0 para admin/dev/oficina/centro.
- Tag: `f1-pilotos`
Recordatorios clave
- Si `Catalogos.txt` fija más estados/situaciones, migrar enum en F2.
- Frontend puede consumir `v_comunicacion_zona.pilotos_json` directo.

## 2025-09-29 12:30 America/Santiago
- Files: `db/seeds/2025-09-29_00_seed_demo_empresas_centros.sql`
- Commit: `seed(db): demo empresas+centros (idempotente, zonas/slug-safe)`
- Resultado: OK
- Notas: crea 1 empresa y 2 centros en la misma zona si faltan (maneja FK a zonas y slug NOT NULL).

## 2025-09-29 13:15 America/Santiago
- Files: `db/migrations/2025-09-29_04_fix_view_comunicacion_resiliente.sql`
- Commit: `fix(db): v_comunicacion_zona tolera pilotos sin nombre/activo y sin empresa_id`
- Resultado: OK

## 2025-09-29 13:40 America/Santiago
- Files: `db/migrations/2025-09-29_05_fix_debug_claims_visibility.sql`
- Commit: `fix(db): debug claims a nivel de sesión (visibles para SECURITY DEFINER)`
- Resultado: OK

## 2025-09-29 13:50 America/Santiago
- Files: `db/migrations/2025-09-29_06_debug_run_as.sql`
- Commit: `feat(db): wrapper app.v_comunicacion_zona_as(claims)`
- Resultado: OK

