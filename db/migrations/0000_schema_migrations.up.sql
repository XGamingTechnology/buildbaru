-- 0000 migration bookkeeping. Idempotent; never rolled back.
CREATE TABLE IF NOT EXISTS schema_migrations (
  version     INT UNSIGNED NOT NULL PRIMARY KEY,
  name        VARCHAR(128) NOT NULL,
  applied_at  DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB;
