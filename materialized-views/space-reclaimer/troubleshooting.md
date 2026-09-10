# Troubleshooting and implementation lessons

This file documents the main issues encountered while turning the initial manual test into a reusable PL/SQL framework.

## 1. `SHRINK SPACE` produced almost no gain

The initial instinct was to use Oracle segment shrink. It is a supported feature and can adjust the high-water mark and release space in suitable cases. In the pilot, however, only a few blocks were releasable at the end of the segment while most free space remained within the allocated segment. The shrink therefore did not materially reduce allocation.

The successful alternative for this workload was a COMPLETE non-atomic refresh:

```sql
DBMS_MVIEW.REFRESH(
    list           => '<OWNER>.<MVIEW_NAME>',
    method         => 'C',
    atomic_refresh => FALSE,
    out_of_place   => FALSE
);
```

The engineering lesson was to measure before and after rather than assume that a generic space-reclamation command will solve every HWM/allocation pattern.

## 2. Stored procedure compiled with ORA-00942 despite DBA role

The procedure uses `AUTHID DEFINER` and static SQL against DBA dictionary views. Role-based privileges are not enough for this pattern; the procedure owner needed direct object grants on the dictionary views it references.

Examples:

```sql
GRANT SELECT ON SYS.DBA_INDEXES         TO ADMINISTRATION;
GRANT SELECT ON SYS.DBA_SEGMENTS        TO ADMINISTRATION;
GRANT SELECT ON SYS.DBA_TABLES          TO ADMINISTRATION;
GRANT SELECT ON SYS.DBA_MVIEWS          TO ADMINISTRATION;
GRANT SELECT ON SYS.DBA_MVREF_STATS     TO ADMINISTRATION;
GRANT SELECT ON SYS.DBA_MVREF_RUN_STATS TO ADMINISTRATION;
```

The secondary PL/SQL errors on the cursor record were cascading errors caused by the failed static SQL parse, not independent bugs in expressions such as `R.BYTES`.

## 3. `DBMS_STATS.GATHER_TABLE_STATS` returned ORA-20000 for other schemas

Executing the package itself was not sufficient for cross-schema statistics collection. The framework owner also required the appropriate system privilege:

```sql
GRANT ANALYZE ANY TO ADMINISTRATION;
```

This was first validated with a direct `DBMS_STATS.GATHER_TABLE_STATS` call on a test MV before relaunching the full procedure.

## 4. `GRANT EXECUTE ON SYS.DBMS_MVIEW` returned ORA-04042

On the tested environment, `DBMS_MVIEW` resolved through a synonym and `SYS.DBMS_MVIEW` was not the physical package name. The object/synonym mapping was checked explicitly:

```sql
SELECT owner, synonym_name, table_owner, table_name
FROM dba_synonyms
WHERE synonym_name IN ('DBMS_MVIEW','DBMS_SNAPSHOT');

SELECT owner, object_name, object_type, status
FROM dba_objects
WHERE object_name IN ('DBMS_MVIEW','DBMS_SNAPSHOT');
```

The lesson is not to assume the physical package name when granting EXECUTE: verify the target in the current Oracle release/environment.

## 5. Why the latest refresh attempt is ranked before filtering failures

The refresh-history CTE ranks **all** attempts first, then accepts only the newest attempt if it completed and reported no failures. Filtering failed attempts first could accidentally make an older successful refresh appear to be the latest state.

## 6. Why automatic execution is limited to `REFRESH ON DEMAND`

This is a safety boundary, not a claim that `ON COMMIT` or `ON STATEMENT` MVs cannot become oversized. Their refresh lifecycle is more directly tied to application transactions, so this project reports the design choice explicitly instead of forcing a COMPLETE non-atomic refresh on them automatically.
