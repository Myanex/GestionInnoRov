SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE usename = current_user
  AND state IN ('idle','idle in transaction','idle in transaction (aborted)')
  AND now() - state_change > interval '10 minutes';
