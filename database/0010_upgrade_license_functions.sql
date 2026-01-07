-- Upgrade from old PL/Perl license functions to pg_pagecamel_license C extension
-- This script safely migrates all dependencies, particularly getposdate() defaults
--
-- Usage: psql -f upgrade_license_functions.sql
--
-- IMPORTANT: This script must be run as a superuser or database owner

BEGIN;

-- Step 1: Create temporary table to store column defaults using getposdate()
CREATE TEMPORARY TABLE _saved_getposdate_defaults (
    table_schema TEXT NOT NULL,
    table_name TEXT NOT NULL,
    column_name TEXT NOT NULL,
    column_default TEXT NOT NULL
);

-- Step 2: Find and save all columns with getposdate() as default
INSERT INTO _saved_getposdate_defaults (table_schema, table_name, column_name, column_default)
SELECT
    n.nspname AS table_schema,
    c.relname AS table_name,
    a.attname AS column_name,
    pg_get_expr(d.adbin, d.adrelid) AS column_default
FROM pg_attrdef d
JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
JOIN pg_class c ON c.oid = d.adrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE pg_get_expr(d.adbin, d.adrelid) LIKE '%getposdate()%';

-- Report what we found
DO $$
DECLARE
    cnt INTEGER;
BEGIN
    SELECT count(*) INTO cnt FROM _saved_getposdate_defaults;
    RAISE NOTICE 'Found % columns with getposdate() defaults', cnt;
END$$;

-- Step 3: Remove the defaults from all affected columns
DO $$
DECLARE
    rec RECORD;
    sql TEXT;
BEGIN
    FOR rec IN SELECT * FROM _saved_getposdate_defaults LOOP
        sql := format('ALTER TABLE %I.%I ALTER COLUMN %I DROP DEFAULT',
                      rec.table_schema, rec.table_name, rec.column_name);
        RAISE NOTICE 'Removing default: %.%.%', rec.table_schema, rec.table_name, rec.column_name;
        EXECUTE sql;
    END LOOP;
END$$;

-- Step 4: Drop trigger first (depends on the function)
DROP TRIGGER IF EXISTS create_session_trigger ON sessions;

-- Step 5: Drop old functions (now possible since defaults are removed)
DROP FUNCTION IF EXISTS createsessiontrigger();
DROP FUNCTION IF EXISTS advanceposdate();
DROP FUNCTION IF EXISTS setposdate(DATE);
DROP FUNCTION IF EXISTS getposdate();
DROP FUNCTION IF EXISTS getlicense();

-- Step 5b: Drop old licensecounttype (so extension can create new one with additional columns)
DROP TYPE IF EXISTS licensecounttype;

DO $$ BEGIN RAISE NOTICE 'Old PL/Perl functions and types dropped successfully'; END $$;

-- Step 6: Create the new C extension
CREATE EXTENSION pg_pagecamel_license;

DO $$ BEGIN RAISE NOTICE 'pg_pagecamel_license extension created successfully'; END $$;

-- Step 7: Restore all the defaults using the new getposdate() function
DO $$
DECLARE
    rec RECORD;
    sql TEXT;
BEGIN
    FOR rec IN SELECT * FROM _saved_getposdate_defaults LOOP
        sql := format('ALTER TABLE %I.%I ALTER COLUMN %I SET DEFAULT %s',
                      rec.table_schema, rec.table_name, rec.column_name, rec.column_default);
        RAISE NOTICE 'Restoring default: %.%.% = %', rec.table_schema, rec.table_name, rec.column_name, rec.column_default;
        EXECUTE sql;
    END LOOP;
END$$;

-- Step 8: Recreate the session trigger
CREATE TRIGGER create_session_trigger
    BEFORE INSERT ON sessions
    FOR EACH ROW EXECUTE FUNCTION createsessiontrigger();

DO $$ BEGIN RAISE NOTICE 'Session trigger recreated'; END $$;

-- Step 9: Verify the migration
DO $$
DECLARE
    cnt INTEGER;
    license_result RECORD;
BEGIN
    -- Check that all defaults were restored
    SELECT count(*) INTO cnt
    FROM _saved_getposdate_defaults s
    WHERE NOT EXISTS (
        SELECT 1
        FROM information_schema.columns c
        WHERE c.table_schema = s.table_schema
          AND c.table_name = s.table_name
          AND c.column_name = s.column_name
          AND c.column_default IS NOT NULL
    );

    IF cnt > 0 THEN
        RAISE EXCEPTION 'Migration failed: % defaults were not restored', cnt;
    END IF;

    -- Test getlicense() function
    SELECT * INTO license_result FROM getlicense();
    RAISE NOTICE 'getlicense() test: normal=%, admin=%, ebody=%',
                 license_result.normal, license_result.admin, license_result.ebody;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Migration completed successfully!';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
END$$;

-- Cleanup temporary table (will be auto-dropped at end of transaction anyway)
DROP TABLE _saved_getposdate_defaults;

COMMIT;
