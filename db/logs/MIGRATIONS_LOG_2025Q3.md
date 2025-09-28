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
