-- Oracle Materialized View Space Reclaimer
-- Public/portfolio version: application schema names are anonymized.
-- Review all thresholds and privileges before use.
-- The procedure is intentionally conservative and targets valid,
-- non-partitioned, COMPLETE, REFRESH ON DEMAND materialized views.

CREATE OR REPLACE PROCEDURE ADMINISTRATION.ADM_COMPACT_MV_CANDIDATES
(
    P_OWNERS            IN  VARCHAR2 DEFAULT 'APP_SCHEMA_1,APP_SCHEMA_2',
    P_MIN_ALLOCATED_MB  IN  NUMBER   DEFAULT 100,
    P_MIN_RATIO_X       IN  NUMBER   DEFAULT 5,
    P_MIN_EXCESS_MB     IN  NUMBER   DEFAULT 100,
    P_EXECUTE_REFRESH   IN  VARCHAR2 DEFAULT 'N',
    P_STOP_ON_ERROR     IN  VARCHAR2 DEFAULT 'Y',
    P_RUN_ID            OUT NUMBER
)
AUTHID DEFINER
IS
    L_EXECUTE              VARCHAR2(1);
    L_STOP_ON_ERROR        VARCHAR2(1);
    L_OWNER_LIST           VARCHAR2(4000);

    L_TABLE_BYTES          NUMBER;
    L_INDEX_BYTES          NUMBER;
    L_ESTIMATED_BYTES      NUMBER;
    L_RATIO_X              NUMBER;
    L_EXCESS_BYTES         NUMBER;

    L_NUM_ROWS             NUMBER;
    L_AVG_ROW_LEN          NUMBER;
    L_LAST_ANALYZED        DATE;
    L_ALLOCATED_BLOCKS     NUMBER;
    L_EXTENTS              NUMBER;

    L_REFRESH_DATE_NOW     DATE;
    L_ATOMIC_NOW           VARCHAR2(1);
    L_REFRESH_ID_NOW       NUMBER;

    L_TABLE_BYTES_AFTER    NUMBER;
    L_INDEX_BYTES_AFTER    NUMBER;

    L_REFRESH_START        TIMESTAMP;
    L_REFRESH_END          TIMESTAMP;

    L_FULL_NAME            VARCHAR2(300);
    L_STATS_WARNING        VARCHAR2(4000);
    L_ERROR_CODE           NUMBER;
    L_ERROR_MESSAGE        VARCHAR2(4000);

    ------------------------------------------------------------------
    -- Sum the bytes allocated to indexes attached to the MV table.
    ------------------------------------------------------------------
    FUNCTION GET_INDEX_BYTES
    (
        P_OWNER      IN VARCHAR2,
        P_MVIEW_NAME IN VARCHAR2
    )
    RETURN NUMBER
    IS
        L_BYTES NUMBER;
    BEGIN
        SELECT NVL(SUM(S.BYTES), 0)
          INTO L_BYTES
          FROM DBA_INDEXES I
          JOIN DBA_SEGMENTS S
            ON S.OWNER        = I.OWNER
           AND S.SEGMENT_NAME = I.INDEX_NAME
           AND S.SEGMENT_TYPE = 'INDEX'
         WHERE I.TABLE_OWNER = P_OWNER
           AND I.TABLE_NAME  = P_MVIEW_NAME;

        RETURN L_BYTES;
    END GET_INDEX_BYTES;

    ------------------------------------------------------------------
    -- Return the ATOMIC_REFRESH value for the latest refresh attempt.
    -- The attempt is considered usable only if both the MV-level and
    -- run-level records are complete and the run reports no failures.
    ------------------------------------------------------------------
    PROCEDURE GET_LAST_ATOMIC_REFRESH
    (
        P_OWNER          IN  VARCHAR2,
        P_MVIEW_NAME     IN  VARCHAR2,
        P_ATOMIC_REFRESH OUT VARCHAR2,
        P_REFRESH_ID     OUT NUMBER
    )
    IS
        L_VALID VARCHAR2(1);
    BEGIN
        SELECT ATOMIC_REFRESH,
               REFRESH_ID,
               VALID_REFRESH
          INTO P_ATOMIC_REFRESH,
               P_REFRESH_ID,
               L_VALID
          FROM
          (
              SELECT R.ATOMIC_REFRESH,
                     S.REFRESH_ID,
                     CASE
                         WHEN S.END_TIME IS NOT NULL
                          AND R.END_TIME IS NOT NULL
                          AND NVL(R.NUMBER_OF_FAILURES, 0) = 0
                         THEN 'Y'
                         ELSE 'N'
                     END AS VALID_REFRESH
                FROM DBA_MVREF_STATS S
                JOIN DBA_MVREF_RUN_STATS R
                  ON R.REFRESH_ID = S.REFRESH_ID
               WHERE S.MV_OWNER = P_OWNER
                 AND S.MV_NAME  = P_MVIEW_NAME
               ORDER BY S.START_TIME DESC,
                        S.REFRESH_ID DESC
          )
         WHERE ROWNUM = 1;

        IF L_VALID <> 'Y' THEN
            P_ATOMIC_REFRESH := NULL;
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            P_ATOMIC_REFRESH := NULL;
            P_REFRESH_ID     := NULL;
    END GET_LAST_ATOMIC_REFRESH;

BEGIN
    ------------------------------------------------------------------
    -- Validate and normalize parameters.
    ------------------------------------------------------------------
    L_EXECUTE :=
        CASE
            WHEN UPPER(SUBSTR(TRIM(P_EXECUTE_REFRESH), 1, 1)) = 'Y'
            THEN 'Y'
            ELSE 'N'
        END;

    L_STOP_ON_ERROR :=
        CASE
            WHEN UPPER(SUBSTR(TRIM(P_STOP_ON_ERROR), 1, 1)) = 'N'
            THEN 'N'
            ELSE 'Y'
        END;

    L_OWNER_LIST :=
        ',' || REPLACE(UPPER(P_OWNERS), ' ', '') || ',';

    IF P_MIN_ALLOCATED_MB <= 0
       OR P_MIN_RATIO_X <= 0
       OR P_MIN_EXCESS_MB < 0
    THEN
        RAISE_APPLICATION_ERROR(
            -20001,
            'Invalid threshold values.'
        );
    END IF;

    ------------------------------------------------------------------
    -- Create one audit campaign.
    ------------------------------------------------------------------
    SELECT ADM_MV_COMPACT_RUN_SEQ.NEXTVAL
      INTO P_RUN_ID
      FROM DUAL;

    INSERT INTO ADM_MV_COMPACT_RUN
    (
        RUN_ID,
        START_TIME,
        OWNERS_LIST,
        MIN_ALLOCATED_MB,
        MIN_RATIO_X,
        MIN_EXCESS_MB,
        EXECUTE_REFRESH,
        STATUS
    )
    VALUES
    (
        P_RUN_ID,
        SYSTIMESTAMP,
        P_OWNERS,
        P_MIN_ALLOCATED_MB,
        P_MIN_RATIO_X,
        P_MIN_EXCESS_MB,
        L_EXECUTE,
        'RUNNING'
    );

    COMMIT;

    ------------------------------------------------------------------
    -- STEP 1: pre-screen.
    -- Existing optimizer statistics are allowed here because this step
    -- only builds a candidate list. No maintenance is triggered yet.
    ------------------------------------------------------------------
    FOR R IN
    (
        WITH LAST_REFRESH AS
        (
            SELECT X.MV_OWNER,
                   X.MV_NAME,
                   X.REFRESH_ID,
                   X.ATOMIC_REFRESH
              FROM
              (
                  SELECT S.MV_OWNER,
                         S.MV_NAME,
                         S.REFRESH_ID,
                         RRS.ATOMIC_REFRESH,
                         S.END_TIME   AS MV_END_TIME,
                         RRS.END_TIME AS RUN_END_TIME,
                         RRS.NUMBER_OF_FAILURES,
                         ROW_NUMBER() OVER
                         (
                             PARTITION BY S.MV_OWNER, S.MV_NAME
                             ORDER BY S.START_TIME DESC,
                                      S.REFRESH_ID DESC
                         ) AS RN
                    FROM DBA_MVREF_STATS S
                    JOIN DBA_MVREF_RUN_STATS RRS
                      ON RRS.REFRESH_ID = S.REFRESH_ID
              ) X
             WHERE X.RN = 1
               AND X.MV_END_TIME IS NOT NULL
               AND X.RUN_END_TIME IS NOT NULL
               AND NVL(X.NUMBER_OF_FAILURES, 0) = 0
        )
        SELECT M.OWNER,
               M.MVIEW_NAME,
               M.LAST_REFRESH_DATE,
               LR.ATOMIC_REFRESH,
               LR.REFRESH_ID,
               T.NUM_ROWS,
               T.AVG_ROW_LEN,
               T.LAST_ANALYZED,
               S.BYTES,
               S.BLOCKS,
               S.EXTENTS
          FROM DBA_MVIEWS M
          JOIN DBA_TABLES T
            ON T.OWNER      = M.OWNER
           AND T.TABLE_NAME = M.MVIEW_NAME
          JOIN DBA_SEGMENTS S
            ON S.OWNER        = M.OWNER
           AND S.SEGMENT_NAME = M.MVIEW_NAME
           AND S.SEGMENT_TYPE = 'TABLE'
          JOIN LAST_REFRESH LR
            ON LR.MV_OWNER = M.OWNER
           AND LR.MV_NAME  = M.MVIEW_NAME
         WHERE INSTR(
                   L_OWNER_LIST,
                   ',' || M.OWNER || ','
               ) > 0
           AND T.PARTITIONED = 'NO'
           AND M.REFRESH_MODE = 'DEMAND'
           AND M.REFRESH_METHOD = 'COMPLETE'
           AND M.LAST_REFRESH_TYPE = 'COMPLETE'
           AND M.COMPILE_STATE = 'VALID'
           AND LR.ATOMIC_REFRESH = 'Y'
           AND NVL(T.NUM_ROWS, 0) > 0
           AND NVL(T.AVG_ROW_LEN, 0) > 0
           AND S.BYTES >= P_MIN_ALLOCATED_MB * 1024 * 1024
           AND S.BYTES
               / NULLIF(T.NUM_ROWS * T.AVG_ROW_LEN, 0)
               >= P_MIN_RATIO_X
           AND S.BYTES
               - (T.NUM_ROWS * T.AVG_ROW_LEN)
               >= P_MIN_EXCESS_MB * 1024 * 1024
         ORDER BY S.BYTES
    )
    LOOP
        L_INDEX_BYTES :=
            GET_INDEX_BYTES(R.OWNER, R.MVIEW_NAME);

        L_ESTIMATED_BYTES :=
            R.NUM_ROWS * R.AVG_ROW_LEN;

        L_RATIO_X :=
            R.BYTES / NULLIF(L_ESTIMATED_BYTES, 0);

        L_EXCESS_BYTES :=
            GREATEST(R.BYTES - L_ESTIMATED_BYTES, 0);

        INSERT INTO ADM_MV_COMPACT_DETAIL
        (
            RUN_ID,
            OWNER,
            MVIEW_NAME,
            STATUS,
            LAST_ATOMIC_REFRESH_BEFORE,
            REFRESH_ID_BEFORE,
            LAST_REFRESH_DATE_BEFORE,
            LAST_ANALYZED_BEFORE,
            NUM_ROWS_BEFORE,
            AVG_ROW_LEN_BEFORE,
            ALLOCATED_BLOCKS_BEFORE,
            EXTENTS_BEFORE,
            TABLE_MB_BEFORE,
            INDEX_MB_BEFORE,
            TOTAL_MB_BEFORE,
            ESTIMATED_DATA_MB_BEFORE,
            RATIO_X_BEFORE,
            EXCESS_MB_BEFORE
        )
        VALUES
        (
            P_RUN_ID,
            R.OWNER,
            R.MVIEW_NAME,
            'PRESELECTED',
            R.ATOMIC_REFRESH,
            R.REFRESH_ID,
            R.LAST_REFRESH_DATE,
            R.LAST_ANALYZED,
            R.NUM_ROWS,
            R.AVG_ROW_LEN,
            R.BLOCKS,
            R.EXTENTS,
            ROUND(R.BYTES / 1024 / 1024, 2),
            ROUND(L_INDEX_BYTES / 1024 / 1024, 2),
            ROUND((R.BYTES + L_INDEX_BYTES) / 1024 / 1024, 2),
            ROUND(L_ESTIMATED_BYTES / 1024 / 1024, 2),
            ROUND(L_RATIO_X, 2),
            ROUND(L_EXCESS_BYTES / 1024 / 1024, 2)
        );
    END LOOP;

    COMMIT;

    ------------------------------------------------------------------
    -- STEP 2: gather fresh statistics and make the real decision.
    ------------------------------------------------------------------
    FOR R IN
    (
        SELECT OWNER,
               MVIEW_NAME
          FROM ADM_MV_COMPACT_DETAIL
         WHERE RUN_ID = P_RUN_ID
           AND STATUS = 'PRESELECTED'
         ORDER BY TABLE_MB_BEFORE
    )
    LOOP
        BEGIN
            DBMS_STATS.GATHER_TABLE_STATS
            (
                OWNNAME          => R.OWNER,
                TABNAME          => R.MVIEW_NAME,
                ESTIMATE_PERCENT => DBMS_STATS.AUTO_SAMPLE_SIZE,
                METHOD_OPT       => 'FOR ALL COLUMNS SIZE 1',
                DEGREE           => 1,
                CASCADE          => FALSE,
                NO_INVALIDATE    => DBMS_STATS.AUTO_INVALIDATE
            );

            SELECT T.NUM_ROWS,
                   T.AVG_ROW_LEN,
                   T.LAST_ANALYZED,
                   S.BYTES,
                   S.BLOCKS,
                   S.EXTENTS
              INTO L_NUM_ROWS,
                   L_AVG_ROW_LEN,
                   L_LAST_ANALYZED,
                   L_TABLE_BYTES,
                   L_ALLOCATED_BLOCKS,
                   L_EXTENTS
              FROM DBA_TABLES T
              JOIN DBA_SEGMENTS S
                ON S.OWNER        = T.OWNER
               AND S.SEGMENT_NAME = T.TABLE_NAME
               AND S.SEGMENT_TYPE = 'TABLE'
             WHERE T.OWNER      = R.OWNER
               AND T.TABLE_NAME = R.MVIEW_NAME;

            L_INDEX_BYTES :=
                GET_INDEX_BYTES(R.OWNER, R.MVIEW_NAME);

            L_ESTIMATED_BYTES :=
                NVL(L_NUM_ROWS, 0) * NVL(L_AVG_ROW_LEN, 0);

            IF L_ESTIMATED_BYTES > 0 THEN
                L_RATIO_X :=
                    L_TABLE_BYTES / L_ESTIMATED_BYTES;

                L_EXCESS_BYTES :=
                    GREATEST(
                        L_TABLE_BYTES - L_ESTIMATED_BYTES,
                        0
                    );
            ELSE
                L_RATIO_X      := NULL;
                L_EXCESS_BYTES := 0;
            END IF;

            UPDATE ADM_MV_COMPACT_DETAIL
               SET LAST_ANALYZED_REFINED = L_LAST_ANALYZED,
                   NUM_ROWS_REFINED      = L_NUM_ROWS,
                   AVG_ROW_LEN_REFINED   = L_AVG_ROW_LEN,
                   TABLE_MB_REFINED      = ROUND(L_TABLE_BYTES / 1024 / 1024, 2),
                   INDEX_MB_REFINED      = ROUND(L_INDEX_BYTES / 1024 / 1024, 2),
                   TOTAL_MB_REFINED      = ROUND((L_TABLE_BYTES + L_INDEX_BYTES) / 1024 / 1024, 2),
                   ESTIMATED_DATA_MB_REFINED = ROUND(L_ESTIMATED_BYTES / 1024 / 1024, 2),
                   RATIO_X_REFINED       = ROUND(L_RATIO_X, 2),
                   EXCESS_MB_REFINED     = ROUND(L_EXCESS_BYTES / 1024 / 1024, 2),
                   STATUS =
                       CASE
                           WHEN L_TABLE_BYTES >= P_MIN_ALLOCATED_MB * 1024 * 1024
                            AND L_ESTIMATED_BYTES > 0
                            AND L_RATIO_X >= P_MIN_RATIO_X
                            AND L_EXCESS_BYTES >= P_MIN_EXCESS_MB * 1024 * 1024
                           THEN 'CONFIRMED'
                           ELSE 'REJECTED_AFTER_STATS'
                       END
             WHERE RUN_ID     = P_RUN_ID
               AND OWNER      = R.OWNER
               AND MVIEW_NAME = R.MVIEW_NAME;

            COMMIT;
        EXCEPTION
            WHEN OTHERS THEN
                L_ERROR_CODE := SQLCODE;
                L_ERROR_MESSAGE :=
                    SUBSTR(
                          DBMS_UTILITY.FORMAT_ERROR_STACK
                       || CHR(10)
                       || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                       1,
                       4000
                    );

                UPDATE ADM_MV_COMPACT_DETAIL
                   SET STATUS        = 'STATS_ERROR',
                       ERROR_CODE    = L_ERROR_CODE,
                       ERROR_MESSAGE = L_ERROR_MESSAGE
                 WHERE RUN_ID     = P_RUN_ID
                   AND OWNER      = R.OWNER
                   AND MVIEW_NAME = R.MVIEW_NAME;

                COMMIT;
        END;
    END LOOP;

    ------------------------------------------------------------------
    -- STEP 3: controlled non-atomic COMPLETE refresh.
    ------------------------------------------------------------------
    IF L_EXECUTE = 'Y' THEN
        FOR R IN
        (
            SELECT OWNER,
                   MVIEW_NAME,
                   LAST_REFRESH_DATE_BEFORE
              FROM ADM_MV_COMPACT_DETAIL
             WHERE RUN_ID = P_RUN_ID
               AND STATUS = 'CONFIRMED'
             ORDER BY TABLE_MB_REFINED
        )
        LOOP
            BEGIN
                SELECT LAST_REFRESH_DATE
                  INTO L_REFRESH_DATE_NOW
                  FROM DBA_MVIEWS
                 WHERE OWNER      = R.OWNER
                   AND MVIEW_NAME = R.MVIEW_NAME;

                GET_LAST_ATOMIC_REFRESH
                (
                    P_OWNER          => R.OWNER,
                    P_MVIEW_NAME     => R.MVIEW_NAME,
                    P_ATOMIC_REFRESH => L_ATOMIC_NOW,
                    P_REFRESH_ID     => L_REFRESH_ID_NOW
                );

                IF NVL(L_ATOMIC_NOW, 'N') <> 'Y' THEN
                    UPDATE ADM_MV_COMPACT_DETAIL
                       SET STATUS = 'SKIPPED_NOT_ATOMIC'
                     WHERE RUN_ID     = P_RUN_ID
                       AND OWNER      = R.OWNER
                       AND MVIEW_NAME = R.MVIEW_NAME;

                    COMMIT;
                    CONTINUE;
                END IF;

                IF    L_REFRESH_DATE_NOW <> R.LAST_REFRESH_DATE_BEFORE
                   OR (L_REFRESH_DATE_NOW IS NULL AND R.LAST_REFRESH_DATE_BEFORE IS NOT NULL)
                   OR (L_REFRESH_DATE_NOW IS NOT NULL AND R.LAST_REFRESH_DATE_BEFORE IS NULL)
                THEN
                    UPDATE ADM_MV_COMPACT_DETAIL
                       SET STATUS = 'SKIPPED_REFRESH_CHANGED'
                     WHERE RUN_ID     = P_RUN_ID
                       AND OWNER      = R.OWNER
                       AND MVIEW_NAME = R.MVIEW_NAME;

                    COMMIT;
                    CONTINUE;
                END IF;

                L_FULL_NAME :=
                       DBMS_ASSERT.SIMPLE_SQL_NAME(R.OWNER)
                    || '.'
                    || DBMS_ASSERT.SIMPLE_SQL_NAME(R.MVIEW_NAME);

                UPDATE ADM_MV_COMPACT_DETAIL
                   SET STATUS             = 'RUNNING',
                       REFRESH_START_TIME = SYSTIMESTAMP,
                       ERROR_CODE         = NULL,
                       ERROR_MESSAGE      = NULL
                 WHERE RUN_ID     = P_RUN_ID
                   AND OWNER      = R.OWNER
                   AND MVIEW_NAME = R.MVIEW_NAME;

                COMMIT;

                L_REFRESH_START := SYSTIMESTAMP;

                BEGIN
                    DBMS_MVIEW.REFRESH
                    (
                        LIST           => L_FULL_NAME,
                        METHOD         => 'C',
                        ATOMIC_REFRESH => FALSE,
                        OUT_OF_PLACE   => FALSE
                    );
                EXCEPTION
                    WHEN OTHERS THEN
                        L_ERROR_CODE := SQLCODE;
                        L_ERROR_MESSAGE :=
                            SUBSTR(
                                  DBMS_UTILITY.FORMAT_ERROR_STACK
                               || CHR(10)
                               || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                               1,
                               4000
                            );

                        L_REFRESH_END := SYSTIMESTAMP;

                        UPDATE ADM_MV_COMPACT_DETAIL
                           SET STATUS = 'REFRESH_ERROR',
                               REFRESH_END_TIME = L_REFRESH_END,
                               REFRESH_DURATION_SECONDS =
                                   ROUND(
                                       (
                                           CAST(L_REFRESH_END AS DATE)
                                           - CAST(L_REFRESH_START AS DATE)
                                       ) * 86400,
                                       2
                                   ),
                               ERROR_CODE    = L_ERROR_CODE,
                               ERROR_MESSAGE = L_ERROR_MESSAGE
                         WHERE RUN_ID     = P_RUN_ID
                           AND OWNER      = R.OWNER
                           AND MVIEW_NAME = R.MVIEW_NAME;

                        COMMIT;

                        IF L_STOP_ON_ERROR = 'Y' THEN
                            RAISE;
                        END IF;

                        CONTINUE;
                END;

                L_REFRESH_END   := SYSTIMESTAMP;
                L_STATS_WARNING := NULL;

                BEGIN
                    DBMS_STATS.GATHER_TABLE_STATS
                    (
                        OWNNAME          => R.OWNER,
                        TABNAME          => R.MVIEW_NAME,
                        ESTIMATE_PERCENT => DBMS_STATS.AUTO_SAMPLE_SIZE,
                        METHOD_OPT       => 'FOR ALL COLUMNS SIZE 1',
                        DEGREE           => 1,
                        CASCADE          => FALSE,
                        NO_INVALIDATE    => DBMS_STATS.AUTO_INVALIDATE
                    );
                EXCEPTION
                    WHEN OTHERS THEN
                        L_STATS_WARNING :=
                            SUBSTR(
                                'Refresh succeeded, but post-refresh statistics failed: '
                                || SQLERRM,
                                1,
                                4000
                            );
                END;

                SELECT T.NUM_ROWS,
                       T.AVG_ROW_LEN,
                       T.LAST_ANALYZED,
                       S.BYTES
                  INTO L_NUM_ROWS,
                       L_AVG_ROW_LEN,
                       L_LAST_ANALYZED,
                       L_TABLE_BYTES_AFTER
                  FROM DBA_TABLES T
                  JOIN DBA_SEGMENTS S
                    ON S.OWNER        = T.OWNER
                   AND S.SEGMENT_NAME = T.TABLE_NAME
                   AND S.SEGMENT_TYPE = 'TABLE'
                 WHERE T.OWNER      = R.OWNER
                   AND T.TABLE_NAME = R.MVIEW_NAME;

                L_INDEX_BYTES_AFTER :=
                    GET_INDEX_BYTES(R.OWNER, R.MVIEW_NAME);

                SELECT LAST_REFRESH_DATE
                  INTO L_REFRESH_DATE_NOW
                  FROM DBA_MVIEWS
                 WHERE OWNER      = R.OWNER
                   AND MVIEW_NAME = R.MVIEW_NAME;

                UPDATE ADM_MV_COMPACT_DETAIL D
                   SET D.STATUS =
                           CASE
                               WHEN L_STATS_WARNING IS NULL
                               THEN 'SUCCESS'
                               ELSE 'SUCCESS_STATS_WARNING'
                           END,
                       D.REFRESH_END_TIME = L_REFRESH_END,
                       D.REFRESH_DURATION_SECONDS =
                           ROUND(
                               (
                                   CAST(L_REFRESH_END AS DATE)
                                   - CAST(L_REFRESH_START AS DATE)
                               ) * 86400,
                               2
                           ),
                       D.LAST_REFRESH_DATE_AFTER = L_REFRESH_DATE_NOW,
                       D.LAST_ANALYZED_AFTER     = L_LAST_ANALYZED,
                       D.NUM_ROWS_AFTER          = L_NUM_ROWS,
                       D.AVG_ROW_LEN_AFTER       = L_AVG_ROW_LEN,
                       D.TABLE_MB_AFTER          = ROUND(L_TABLE_BYTES_AFTER / 1024 / 1024, 2),
                       D.INDEX_MB_AFTER          = ROUND(L_INDEX_BYTES_AFTER / 1024 / 1024, 2),
                       D.TOTAL_MB_AFTER          = ROUND((L_TABLE_BYTES_AFTER + L_INDEX_BYTES_AFTER) / 1024 / 1024, 2),
                       D.RECLAIMED_MB            =
                           ROUND(
                               (
                                   D.TOTAL_MB_REFINED * 1024 * 1024
                                   - L_TABLE_BYTES_AFTER
                                   - L_INDEX_BYTES_AFTER
                               ) / 1024 / 1024,
                               2
                           ),
                       D.ERROR_MESSAGE = L_STATS_WARNING
                 WHERE D.RUN_ID     = P_RUN_ID
                   AND D.OWNER      = R.OWNER
                   AND D.MVIEW_NAME = R.MVIEW_NAME;

                COMMIT;
            EXCEPTION
                WHEN OTHERS THEN
                    L_ERROR_CODE := SQLCODE;
                    L_ERROR_MESSAGE :=
                        SUBSTR(
                              DBMS_UTILITY.FORMAT_ERROR_STACK
                           || CHR(10)
                           || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                           1,
                           4000
                        );

                    UPDATE ADM_MV_COMPACT_DETAIL
                       SET STATUS =
                               CASE
                                   WHEN STATUS = 'REFRESH_ERROR'
                                   THEN STATUS
                                   ELSE 'UNEXPECTED_ERROR'
                               END,
                           ERROR_CODE = NVL(ERROR_CODE, L_ERROR_CODE),
                           ERROR_MESSAGE = NVL(ERROR_MESSAGE, L_ERROR_MESSAGE),
                           REFRESH_END_TIME = NVL(REFRESH_END_TIME, SYSTIMESTAMP)
                     WHERE RUN_ID     = P_RUN_ID
                       AND OWNER      = R.OWNER
                       AND MVIEW_NAME = R.MVIEW_NAME;

                    COMMIT;

                    IF L_STOP_ON_ERROR = 'Y' THEN
                        RAISE;
                    END IF;
            END;
        END LOOP;
    END IF;

    ------------------------------------------------------------------
    -- STEP 4: final campaign summary.
    ------------------------------------------------------------------
    UPDATE ADM_MV_COMPACT_RUN H
       SET H.END_TIME = SYSTIMESTAMP,
           H.NB_PRESELECTED =
           (
               SELECT COUNT(*)
                 FROM ADM_MV_COMPACT_DETAIL D
                WHERE D.RUN_ID = P_RUN_ID
           ),
           H.NB_CONFIRMED =
           (
               SELECT COUNT(*)
                 FROM ADM_MV_COMPACT_DETAIL D
                WHERE D.RUN_ID = P_RUN_ID
                  AND D.STATUS IN
                      (
                          'CONFIRMED',
                          'RUNNING',
                          'SUCCESS',
                          'SUCCESS_STATS_WARNING',
                          'REFRESH_ERROR',
                          'UNEXPECTED_ERROR',
                          'SKIPPED_NOT_ATOMIC',
                          'SKIPPED_REFRESH_CHANGED'
                      )
           ),
           H.NB_SUCCESS =
           (
               SELECT COUNT(*)
                 FROM ADM_MV_COMPACT_DETAIL D
                WHERE D.RUN_ID = P_RUN_ID
                  AND D.STATUS IN
                      (
                          'SUCCESS',
                          'SUCCESS_STATS_WARNING'
                      )
           ),
           H.NB_ERROR =
           (
               SELECT COUNT(*)
                 FROM ADM_MV_COMPACT_DETAIL D
                WHERE D.RUN_ID = P_RUN_ID
                  AND D.STATUS IN
                      (
                          'STATS_ERROR',
                          'REFRESH_ERROR',
                          'UNEXPECTED_ERROR'
                      )
           ),
           H.STATUS =
               CASE
                   WHEN EXISTS
                        (
                            SELECT 1
                              FROM ADM_MV_COMPACT_DETAIL D
                             WHERE D.RUN_ID = P_RUN_ID
                               AND D.STATUS IN
                                   (
                                       'STATS_ERROR',
                                       'REFRESH_ERROR',
                                       'UNEXPECTED_ERROR'
                                   )
                        )
                   THEN 'COMPLETED_WITH_ERRORS'

                   WHEN EXISTS
                        (
                            SELECT 1
                              FROM ADM_MV_COMPACT_DETAIL D
                             WHERE D.RUN_ID = P_RUN_ID
                               AND D.STATUS IN
                                   (
                                       'SKIPPED_NOT_ATOMIC',
                                       'SKIPPED_REFRESH_CHANGED'
                                   )
                        )
                   THEN 'COMPLETED_WITH_SKIPS'

                   WHEN L_EXECUTE = 'N'
                   THEN 'ANALYSIS_COMPLETED'

                   ELSE 'SUCCESS'
               END,
           H.ERROR_MESSAGE =
               CASE
                   WHEN EXISTS
                        (
                            SELECT 1
                              FROM ADM_MV_COMPACT_DETAIL D
                             WHERE D.RUN_ID = P_RUN_ID
                               AND D.STATUS IN
                                   (
                                       'STATS_ERROR',
                                       'REFRESH_ERROR',
                                       'UNEXPECTED_ERROR'
                                   )
                        )
                   THEN 'See ADM_MV_COMPACT_DETAIL for error details.'
                   ELSE NULL
               END
     WHERE H.RUN_ID = P_RUN_ID;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        DECLARE
            L_GLOBAL_ERROR_CODE    NUMBER := SQLCODE;
            L_GLOBAL_ERROR_MESSAGE VARCHAR2(4000);
        BEGIN
            L_GLOBAL_ERROR_MESSAGE :=
                SUBSTR(
                      DBMS_UTILITY.FORMAT_ERROR_STACK
                   || CHR(10)
                   || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                   1,
                   4000
                );

            IF P_RUN_ID IS NOT NULL THEN
                UPDATE ADM_MV_COMPACT_RUN
                   SET END_TIME = SYSTIMESTAMP,
                       STATUS   = 'ERROR',
                       NB_ERROR =
                       (
                           SELECT COUNT(*)
                             FROM ADM_MV_COMPACT_DETAIL D
                            WHERE D.RUN_ID = P_RUN_ID
                              AND D.STATUS IN
                                  (
                                      'STATS_ERROR',
                                      'REFRESH_ERROR',
                                      'UNEXPECTED_ERROR'
                                  )
                       ),
                       ERROR_MESSAGE =
                           'ORA' || ABS(L_GLOBAL_ERROR_CODE)
                           || CHR(10)
                           || L_GLOBAL_ERROR_MESSAGE
                 WHERE RUN_ID = P_RUN_ID;

                COMMIT;
            END IF;

            RAISE;
        END;
END ADM_COMPACT_MV_CANDIDATES;
/
