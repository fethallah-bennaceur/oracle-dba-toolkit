-- Example Scheduler job.
-- It runs the compacting procedure and then sends the report for the exact RUN_ID.
-- No wrapper procedure is required: the job uses a PL/SQL block.

BEGIN
    DBMS_SCHEDULER.CREATE_JOB
    (
        JOB_NAME        => 'ADMINISTRATION.ADM_MV_COMPACT_REPORT_JOB',
        JOB_TYPE        => 'PLSQL_BLOCK',
        JOB_ACTION      => q'[
            DECLARE
                L_RUN_ID NUMBER;
            BEGIN
                ADMINISTRATION.ADM_COMPACT_MV_CANDIDATES
                (
                    P_OWNERS            => 'APP_SCHEMA_1,APP_SCHEMA_2',
                    P_MIN_ALLOCATED_MB  => 100,
                    P_MIN_RATIO_X       => 5,
                    P_MIN_EXCESS_MB     => 100,
                    P_EXECUTE_REFRESH   => 'Y',
                    P_STOP_ON_ERROR     => 'Y',
                    P_RUN_ID            => L_RUN_ID
                );

                ADMINISTRATION.ADM_SEND_MV_COMPACT_REPORT
                (
                    P_RUN_ID => L_RUN_ID
                );
            END;
        ]',
        START_DATE      => SYSTIMESTAMP,
        REPEAT_INTERVAL => 'FREQ=WEEKLY;BYDAY=SUN;BYHOUR=3;BYMINUTE=0;BYSECOND=0',
        ENABLED         => FALSE,
        AUTO_DROP       => FALSE,
        COMMENTS        => 'Detect and reclaim excessive MV allocation, then send an HTML report'
    );
END;
/

-- Test synchronously before enabling the recurring schedule.
BEGIN
    DBMS_SCHEDULER.RUN_JOB
    (
        JOB_NAME            => 'ADMINISTRATION.ADM_MV_COMPACT_REPORT_JOB',
        USE_CURRENT_SESSION => TRUE
    );
END;
/

-- Enable only after validation in your environment.
BEGIN
    DBMS_SCHEDULER.ENABLE('ADMINISTRATION.ADM_MV_COMPACT_REPORT_JOB');
END;
/

SELECT owner, job_name, enabled, state, repeat_interval,
       last_start_date, next_run_date, run_count, failure_count
FROM dba_scheduler_jobs
WHERE owner = 'ADMINISTRATION'
  AND job_name = 'ADM_MV_COMPACT_REPORT_JOB';
