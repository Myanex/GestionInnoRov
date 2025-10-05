-- Ver sesiones
SELECT pid, application_name, state, now()-state_change AS idle_for
FROM pg_stat_activity
WHERE datname = current_database()
ORDER BY state, idle_for DESC;

-- Terminar sesiones ociosas de DBeaver
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE application_name ILIKE 'DBeaver%' AND state IN ('idle','idle in transaction');
