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
