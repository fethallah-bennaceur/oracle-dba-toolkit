-- Run as SYS or another account allowed to grant these privileges.
-- This script assumes the framework owner already exists.
-- Replace ADMINISTRATION if you use another owner.

GRANT SELECT ON SYS.DBA_INDEXES         TO ADMINISTRATION;
GRANT SELECT ON SYS.DBA_SEGMENTS        TO ADMINISTRATION;
GRANT SELECT ON SYS.DBA_TABLES          TO ADMINISTRATION;
GRANT SELECT ON SYS.DBA_MVIEWS          TO ADMINISTRATION;
GRANT SELECT ON SYS.DBA_MVREF_STATS     TO ADMINISTRATION;
GRANT SELECT ON SYS.DBA_MVREF_RUN_STATS TO ADMINISTRATION;

GRANT EXECUTE ON SYS.DBMS_STATS   TO ADMINISTRATION;
GRANT EXECUTE ON SYS.DBMS_ASSERT  TO ADMINISTRATION;
GRANT EXECUTE ON SYS.DBMS_UTILITY TO ADMINISTRATION;

-- Required when statistics are gathered for objects owned by another schema.
GRANT ANALYZE ANY TO ADMINISTRATION;

-- Required when refreshing a materialized view owned by another schema.
GRANT ALTER ANY MATERIALIZED VIEW TO ADMINISTRATION;

-- DBMS_MVIEW may resolve through a PUBLIC synonym to the physical package
-- SYS.DBMS_SNAPSHOT, depending on the Oracle release/environment. Verify first:
SELECT owner, synonym_name, table_owner, table_name
FROM dba_synonyms
WHERE synonym_name IN ('DBMS_MVIEW','DBMS_SNAPSHOT');

SELECT owner, object_name, object_type, status
FROM dba_objects
WHERE object_name IN ('DBMS_MVIEW','DBMS_SNAPSHOT');

-- Grant EXECUTE on the physical package only if a direct grant is required.
-- Example seen on some environments:
-- GRANT EXECUTE ON SYS.DBMS_SNAPSHOT TO ADMINISTRATION;

-- Optional / environment-specific mail helper used by 04_adm_send_mv_compact_report.sql:
-- GRANT EXECUTE ON <MAIL_OWNER>.HTML_MAIL TO ADMINISTRATION;
