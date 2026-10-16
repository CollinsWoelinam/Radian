DROP TABLE IF EXISTS job_events;
DROP INDEX IF EXISTS uq_jobs_active_vehicle;
DROP INDEX IF EXISTS uq_jobs_number;
ALTER TABLE jobs
    DROP COLUMN IF EXISTS updated_at,
    DROP COLUMN IF EXISTS last_dispatch_at,
    DROP COLUMN IF EXISTS declined_vehicle_ids,
    DROP COLUMN IF EXISTS offer_expires_at,
    DROP COLUMN IF EXISTS offered_at,
    DROP COLUMN IF EXISTS offered_vehicle_id,
    DROP COLUMN IF EXISTS created_by,
    DROP COLUMN IF EXISTS number;
DROP TABLE IF EXISTS dispatchers;
-- Postgres can't drop an enum value; 'OFFERED' stays on job_status.
