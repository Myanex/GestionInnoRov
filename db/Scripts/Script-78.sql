-- Ver
SELECT pid, application_name, state, now()-state_change AS idle_for
FROM pg_stat_activity
WHERE datname = current_database()
ORDER BY state, idle_for DESC;

-- Matar sesiones ociosas de DBeaver (excepto la actual)
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
  AND state IN ('idle','idle in transaction');