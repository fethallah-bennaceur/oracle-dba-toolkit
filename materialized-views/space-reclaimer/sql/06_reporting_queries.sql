-- Latest campaign summary
SELECT run_id,
       start_time,
       end_time,
       owners_list,
       min_allocated_mb,
       min_ratio_x,
       min_excess_mb,
       execute_refresh,
       status,
       nb_preselected,
       nb_confirmed,
       nb_success,
       nb_error,
       error_message
FROM administration.adm_mv_compact_run
WHERE run_id =
(
    SELECT MAX(run_id)
    FROM administration.adm_mv_compact_run
);

-- Candidate / decision detail
SELECT owner,
       mview_name,
       status,
       last_atomic_refresh_before,
       last_refresh_date_before,
       last_analyzed_before,
       last_analyzed_refined,
       num_rows_before,
       num_rows_refined,
       table_mb_before,
       table_mb_refined,
       index_mb_refined,
       total_mb_refined,
       estimated_data_mb_refined,
       ratio_x_refined,
       excess_mb_refined,
       error_code,
       error_message
FROM administration.adm_mv_compact_detail
WHERE run_id =
(
    SELECT MAX(run_id)
    FROM administration.adm_mv_compact_run
)
ORDER BY
    CASE status
        WHEN 'STATS_ERROR' THEN 1
        WHEN 'REFRESH_ERROR' THEN 1
        WHEN 'UNEXPECTED_ERROR' THEN 1
        WHEN 'CONFIRMED' THEN 2
        WHEN 'SUCCESS' THEN 2
        WHEN 'SUCCESS_STATS_WARNING' THEN 2
        WHEN 'REJECTED_AFTER_STATS' THEN 3
        ELSE 4
    END,
    table_mb_refined;

-- Real before/after reclaimed space for one run
SELECT owner,
       mview_name,
       status,
       table_mb_refined,
       index_mb_refined,
       total_mb_refined,
       table_mb_after,
       index_mb_after,
       total_mb_after,
       reclaimed_mb,
       refresh_duration_seconds
FROM administration.adm_mv_compact_detail
WHERE run_id = :run_id
ORDER BY reclaimed_mb DESC NULLS LAST;
