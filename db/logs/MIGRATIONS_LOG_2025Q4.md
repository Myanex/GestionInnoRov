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
