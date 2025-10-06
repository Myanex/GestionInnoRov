## 2025-10-06 23:xx America/Santiago

- Scope: F4 · Etapa A — Skeleton + Auth + Placeholders
- Resultado: OK
- Pruebas:
  - / → /dashboard (redirect)
  - /dashboard sin sesión → /login
  - Login OK → /dashboard (persistencia verificada)
  - Rutas protegidas funcionan con sesión
- Notas:
  - Se limpió encabezado de archivos (.txt) que rompía TSX.
  - Alias @/\* verificado en tsconfig.
