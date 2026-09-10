-- HTML reporting procedure for the MV space reclaimer.
-- Dependency: HTML_MAIL is an environment-specific mail helper and is NOT an Oracle built-in.
-- Replace addresses and SMTP host for your environment.

CREATE OR REPLACE PROCEDURE ADMINISTRATION.ADM_SEND_MV_COMPACT_REPORT
(
    P_RUN_ID      IN NUMBER   DEFAULT NULL,
    P_TO          IN VARCHAR2 DEFAULT 'dba@example.com',
    P_FROM_MAIL   IN VARCHAR2 DEFAULT 'oracle@example.com',
    P_SMTP_HOST   IN VARCHAR2 DEFAULT 'smtp.example.com'
)
AUTHID DEFINER
IS
    L_RUN_ID        NUMBER;
    L_RUN_STATUS    VARCHAR2(30);
    L_DBNAME        VARCHAR2(128);
    L_HOSTNAME      VARCHAR2(255);
    L_BODY          CLOB;
    L_HTML          CLOB;
    L_DETAIL_COUNT  PLS_INTEGER := 0;
    L_ERROR_MESSAGE VARCHAR2(4000);

    PROCEDURE APPEND_TEXT
    (
        P_CLOB IN OUT NOCOPY CLOB,
        P_TEXT IN VARCHAR2
    )
    IS
    BEGIN
        IF P_TEXT IS NOT NULL THEN
            DBMS_LOB.WRITEAPPEND(P_CLOB, LENGTH(P_TEXT), P_TEXT);
        END IF;
    END APPEND_TEXT;

    FUNCTION HTML_ESCAPE(P_TEXT IN VARCHAR2)
    RETURN VARCHAR2
    IS
        L_TEXT VARCHAR2(32767);
    BEGIN
        IF P_TEXT IS NULL THEN
            RETURN '-';
        END IF;

        L_TEXT := P_TEXT;
        L_TEXT := REPLACE(L_TEXT, '&', '&amp;');
        L_TEXT := REPLACE(L_TEXT, '<', '&lt;');
        L_TEXT := REPLACE(L_TEXT, '>', '&gt;');
        L_TEXT := REPLACE(L_TEXT, '"', '&quot;');
        L_TEXT := REPLACE(L_TEXT, '''', '&#39;');
        RETURN L_TEXT;
    END HTML_ESCAPE;

    FUNCTION HTML_MULTILINE(P_TEXT IN VARCHAR2)
    RETURN VARCHAR2
    IS
        L_TEXT VARCHAR2(32767);
    BEGIN
        IF P_TEXT IS NULL THEN
            RETURN '-';
        END IF;

        L_TEXT := HTML_ESCAPE(P_TEXT);
        L_TEXT := REPLACE(L_TEXT, CHR(13), '');
        L_TEXT := REPLACE(L_TEXT, CHR(10), '<br>');
        RETURN L_TEXT;
    END HTML_MULTILINE;

    FUNCTION FMT_NUM(P_VALUE IN NUMBER)
    RETURN VARCHAR2
    IS
    BEGIN
        IF P_VALUE IS NULL THEN
            RETURN '-';
        END IF;

        RETURN TO_CHAR(
            P_VALUE,
            'FM999G999G999G990D00',
            'NLS_NUMERIC_CHARACTERS='', '''
        );
    END FMT_NUM;

    FUNCTION FMT_INT(P_VALUE IN NUMBER)
    RETURN VARCHAR2
    IS
    BEGIN
        IF P_VALUE IS NULL THEN
            RETURN '-';
        END IF;

        RETURN TO_CHAR(
            P_VALUE,
            'FM999G999G999G990',
            'NLS_NUMERIC_CHARACTERS='', '''
        );
    END FMT_INT;

    FUNCTION FMT_DATE(P_VALUE IN DATE)
    RETURN VARCHAR2
    IS
    BEGIN
        IF P_VALUE IS NULL THEN
            RETURN '-';
        END IF;
        RETURN TO_CHAR(P_VALUE, 'DD/MM/YYYY HH24:MI:SS');
    END FMT_DATE;

    FUNCTION FMT_TS(P_VALUE IN TIMESTAMP)
    RETURN VARCHAR2
    IS
    BEGIN
        IF P_VALUE IS NULL THEN
            RETURN '-';
        END IF;
        RETURN TO_CHAR(P_VALUE, 'DD/MM/YYYY HH24:MI:SS,FF3');
    END FMT_TS;

    FUNCTION STATUS_STYLE(P_STATUS IN VARCHAR2)
    RETURN VARCHAR2
    IS
    BEGIN
        RETURN CASE
            WHEN UPPER(P_STATUS) IN
                 ('SUCCESS','ANALYSIS_COMPLETED','CONFIRMED','SUCCESS_STATS_WARNING')
            THEN 'background-color:#d4edda;color:#155724;font-weight:bold;text-align:center;'

            WHEN UPPER(P_STATUS) IN
                 ('STATS_ERROR','REFRESH_ERROR','UNEXPECTED_ERROR','ERROR','FAILED','COMPLETED_WITH_ERRORS')
            THEN 'background-color:#f8d7da;color:#721c24;font-weight:bold;text-align:center;'

            WHEN UPPER(P_STATUS) IN
                 ('REJECTED_AFTER_STATS','SKIPPED_NOT_ATOMIC','SKIPPED_REFRESH_CHANGED','COMPLETED_WITH_SKIPS')
            THEN 'background-color:#fff3cd;color:#856404;font-weight:bold;text-align:center;'

            WHEN UPPER(P_STATUS) = 'RUNNING'
            THEN 'background-color:#d1ecf1;color:#0c5460;font-weight:bold;text-align:center;'

            ELSE 'font-weight:bold;text-align:center;'
        END;
    END STATUS_STYLE;

BEGIN
    L_DBNAME   := SYS_CONTEXT('USERENV', 'DB_NAME');
    L_HOSTNAME := SYS_CONTEXT('USERENV', 'SERVER_HOST');

    IF P_RUN_ID IS NULL THEN
        SELECT MAX(RUN_ID)
          INTO L_RUN_ID
          FROM ADMINISTRATION.ADM_MV_COMPACT_RUN;
    ELSE
        L_RUN_ID := P_RUN_ID;
    END IF;

    IF L_RUN_ID IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001, 'No execution found in ADM_MV_COMPACT_RUN.');
    END IF;

    DBMS_LOB.CREATETEMPORARY(L_BODY, TRUE, DBMS_LOB.CALL);
    DBMS_LOB.CREATETEMPORARY(L_HTML, TRUE, DBMS_LOB.CALL);

    APPEND_TEXT(
        L_BODY,
        '<h2>Oracle Materialized View Space Reclaimer</h2>'
        || '<table class="meta">'
        || '<tr><td><strong>Database</strong></td><td>' || HTML_ESCAPE(UPPER(L_DBNAME)) || '</td></tr>'
        || '<tr><td><strong>Server</strong></td><td>' || HTML_ESCAPE(UPPER(L_HOSTNAME)) || '</td></tr>'
        || '<tr><td><strong>RUN_ID</strong></td><td>' || L_RUN_ID || '</td></tr>'
        || '<tr><td><strong>Report time</strong></td><td>' || TO_CHAR(SYSDATE,'DD/MM/YYYY HH24:MI:SS') || '</td></tr>'
        || '</table>'
    );

    ------------------------------------------------------------------
    -- Campaign summary.
    ------------------------------------------------------------------
    APPEND_TEXT(
        L_BODY,
        '<h3>1. Campaign summary</h3>'
        || '<div class="scroll"><table class="report-table">'
        || '<thead><tr>'
        || '<th>RUN_ID</th><th>Start</th><th>End</th><th>Schemas</th>'
        || '<th>Min table MB</th><th>Min ratio</th><th>Min excess MB</th>'
        || '<th>Execute</th><th>Status</th><th>Preselected</th>'
        || '<th>Confirmed</th><th>Success</th><th>Errors</th><th>Message</th>'
        || '</tr></thead><tbody>'
    );

    FOR R IN
    (
        SELECT RUN_ID,
               START_TIME,
               END_TIME,
               OWNERS_LIST,
               MIN_ALLOCATED_MB,
               MIN_RATIO_X,
               MIN_EXCESS_MB,
               EXECUTE_REFRESH,
               STATUS,
               NB_PRESELECTED,
               NB_CONFIRMED,
               NB_SUCCESS,
               NB_ERROR,
               ERROR_MESSAGE
          FROM ADMINISTRATION.ADM_MV_COMPACT_RUN
         WHERE RUN_ID = L_RUN_ID
    )
    LOOP
        L_RUN_STATUS := R.STATUS;

        APPEND_TEXT(
            L_BODY,
            '<tr>'
            || '<td class="num">' || FMT_INT(R.RUN_ID) || '</td>'
            || '<td>' || FMT_TS(R.START_TIME) || '</td>'
            || '<td>' || FMT_TS(R.END_TIME) || '</td>'
            || '<td>' || HTML_ESCAPE(R.OWNERS_LIST) || '</td>'
            || '<td class="num">' || FMT_NUM(R.MIN_ALLOCATED_MB) || '</td>'
            || '<td class="num">' || FMT_NUM(R.MIN_RATIO_X) || '</td>'
            || '<td class="num">' || FMT_NUM(R.MIN_EXCESS_MB) || '</td>'
            || '<td class="center">' || HTML_ESCAPE(R.EXECUTE_REFRESH) || '</td>'
            || '<td style="' || STATUS_STYLE(R.STATUS) || '">' || HTML_ESCAPE(R.STATUS) || '</td>'
            || '<td class="num">' || FMT_INT(R.NB_PRESELECTED) || '</td>'
            || '<td class="num">' || FMT_INT(R.NB_CONFIRMED) || '</td>'
            || '<td class="num">' || FMT_INT(R.NB_SUCCESS) || '</td>'
            || '<td class="num">' || FMT_INT(R.NB_ERROR) || '</td>'
            || '<td class="message">' || HTML_MULTILINE(R.ERROR_MESSAGE) || '</td>'
            || '</tr>'
        );
    END LOOP;

    IF L_RUN_STATUS IS NULL THEN
        RAISE_APPLICATION_ERROR(-20002, 'RUN_ID ' || L_RUN_ID || ' does not exist.');
    END IF;

    APPEND_TEXT(L_BODY, '</tbody></table></div>');

    ------------------------------------------------------------------
    -- Detail including measured before/after allocation.
    ------------------------------------------------------------------
    APPEND_TEXT(
        L_BODY,
        '<h3>2. Materialized view detail</h3>'
        || '<div class="scroll"><table class="report-table">'
        || '<thead><tr>'
        || '<th>Owner</th><th>Materialized view</th><th>Status</th><th>Atomic before</th>'
        || '<th>Last refresh before</th><th>Stats before</th><th>Stats refined</th>'
        || '<th>Rows refined</th><th>Table before MB</th><th>Table refined MB</th>'
        || '<th>Index refined MB</th><th>Total refined MB</th><th>Estimated data MB</th>'
        || '<th>Ratio</th><th>Estimated excess MB</th>'
        || '<th>Table after MB</th><th>Index after MB</th><th>Total after MB</th>'
        || '<th>Reclaimed MB</th><th>Refresh sec</th><th>Error code</th><th>Error message</th>'
        || '</tr></thead><tbody>'
    );

    FOR R IN
    (
        SELECT OWNER,
               MVIEW_NAME,
               STATUS,
               LAST_ATOMIC_REFRESH_BEFORE,
               LAST_REFRESH_DATE_BEFORE,
               LAST_ANALYZED_BEFORE,
               LAST_ANALYZED_REFINED,
               NUM_ROWS_REFINED,
               TABLE_MB_BEFORE,
               TABLE_MB_REFINED,
               INDEX_MB_REFINED,
               TOTAL_MB_REFINED,
               ESTIMATED_DATA_MB_REFINED,
               RATIO_X_REFINED,
               EXCESS_MB_REFINED,
               TABLE_MB_AFTER,
               INDEX_MB_AFTER,
               TOTAL_MB_AFTER,
               RECLAIMED_MB,
               REFRESH_DURATION_SECONDS,
               ERROR_CODE,
               ERROR_MESSAGE
          FROM ADMINISTRATION.ADM_MV_COMPACT_DETAIL
         WHERE RUN_ID = L_RUN_ID
         ORDER BY RECLAIMED_MB DESC NULLS LAST,
                  TABLE_MB_REFINED DESC NULLS LAST
    )
    LOOP
        L_DETAIL_COUNT := L_DETAIL_COUNT + 1;

        APPEND_TEXT(
            L_BODY,
            '<tr>'
            || '<td>' || HTML_ESCAPE(R.OWNER) || '</td>'
            || '<td>' || HTML_ESCAPE(R.MVIEW_NAME) || '</td>'
            || '<td style="' || STATUS_STYLE(R.STATUS) || '">' || HTML_ESCAPE(R.STATUS) || '</td>'
            || '<td class="center">' || HTML_ESCAPE(R.LAST_ATOMIC_REFRESH_BEFORE) || '</td>'
            || '<td>' || FMT_DATE(R.LAST_REFRESH_DATE_BEFORE) || '</td>'
            || '<td>' || FMT_DATE(R.LAST_ANALYZED_BEFORE) || '</td>'
            || '<td>' || FMT_DATE(R.LAST_ANALYZED_REFINED) || '</td>'
            || '<td class="num">' || FMT_INT(R.NUM_ROWS_REFINED) || '</td>'
            || '<td class="num">' || FMT_NUM(R.TABLE_MB_BEFORE) || '</td>'
            || '<td class="num">' || FMT_NUM(R.TABLE_MB_REFINED) || '</td>'
            || '<td class="num">' || FMT_NUM(R.INDEX_MB_REFINED) || '</td>'
            || '<td class="num">' || FMT_NUM(R.TOTAL_MB_REFINED) || '</td>'
            || '<td class="num">' || FMT_NUM(R.ESTIMATED_DATA_MB_REFINED) || '</td>'
            || '<td class="num">' || FMT_NUM(R.RATIO_X_REFINED) || '</td>'
            || '<td class="num">' || FMT_NUM(R.EXCESS_MB_REFINED) || '</td>'
            || '<td class="num">' || FMT_NUM(R.TABLE_MB_AFTER) || '</td>'
            || '<td class="num">' || FMT_NUM(R.INDEX_MB_AFTER) || '</td>'
            || '<td class="num">' || FMT_NUM(R.TOTAL_MB_AFTER) || '</td>'
            || '<td class="num"><strong>' || FMT_NUM(R.RECLAIMED_MB) || '</strong></td>'
            || '<td class="num">' || FMT_NUM(R.REFRESH_DURATION_SECONDS) || '</td>'
            || '<td class="num">' || FMT_INT(R.ERROR_CODE) || '</td>'
            || '<td class="message">' || HTML_MULTILINE(R.ERROR_MESSAGE) || '</td>'
            || '</tr>'
        );
    END LOOP;

    IF L_DETAIL_COUNT = 0 THEN
        APPEND_TEXT(
            L_BODY,
            '<tr><td colspan="22" class="center">No materialized view matched this campaign.</td></tr>'
        );
    END IF;

    APPEND_TEXT(L_BODY, '</tbody></table></div>');

    ------------------------------------------------------------------
    -- Build HTML document.
    ------------------------------------------------------------------
    APPEND_TEXT(
        L_HTML,
        '<!DOCTYPE html><html><head>'
        || '<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">'
        || '<title>Oracle MV Space Reclaimer</title>'
        || '<style>'
        || 'body{font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#212529;}'
        || 'h2,h3{color:#1f4e78;}'
        || '.meta td{padding:3px 10px 3px 0;}'
        || '.scroll{overflow-x:auto;}'
        || '.report-table{border-collapse:collapse;width:100%;font-size:12px;}'
        || '.report-table th{background-color:#1f4e78;color:white;border:1px solid #808080;padding:6px;white-space:nowrap;}'
        || '.report-table td{border:1px solid #b0b0b0;padding:5px;vertical-align:top;}'
        || '.report-table tbody tr:nth-child(even){background-color:#f2f2f2;}'
        || '.num{text-align:right;font-weight:bold;white-space:nowrap;}'
        || '.center{text-align:center;}'
        || '.message{font-family:Consolas,monospace;font-size:11px;min-width:220px;}'
        || '.footer{margin-top:30px;padding-top:10px;border-top:1px solid #ccc;color:#555;}'
        || '</style></head><body>'
    );

    DBMS_LOB.APPEND(L_HTML, L_BODY);

    APPEND_TEXT(
        L_HTML,
        '<div class="footer">Generated by Oracle Materialized View Space Reclaimer</div>'
        || '</body></html>'
    );

    ------------------------------------------------------------------
    -- Environment-specific mail helper.
    ------------------------------------------------------------------
    HTML_MAIL
    (
        P_TO        => P_TO,
        FROMNAME    => 'MV_COMPACT.' || UPPER(L_HOSTNAME),
        FROMMAIL    => P_FROM_MAIL,
        P_SUBJECT   => 'Oracle MV Space Reclaimer - RUN_ID '
                       || L_RUN_ID || ' - ' || UPPER(L_DBNAME)
                       || ' - ' || NVL(L_RUN_STATUS, 'UNKNOWN'),
        P_TEXT_MSG  => NULL,
        P_HTML_MSG  => L_HTML,
        P_SMTP_HOST => P_SMTP_HOST
    );

    IF DBMS_LOB.ISTEMPORARY(L_BODY) = 1 THEN
        DBMS_LOB.FREETEMPORARY(L_BODY);
    END IF;

    IF DBMS_LOB.ISTEMPORARY(L_HTML) = 1 THEN
        DBMS_LOB.FREETEMPORARY(L_HTML);
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        L_ERROR_MESSAGE :=
            SUBSTR(
                  DBMS_UTILITY.FORMAT_ERROR_STACK
               || CHR(10)
               || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
               1,
               1900
            );

        IF L_BODY IS NOT NULL AND DBMS_LOB.ISTEMPORARY(L_BODY) = 1 THEN
            DBMS_LOB.FREETEMPORARY(L_BODY);
        END IF;

        IF L_HTML IS NOT NULL AND DBMS_LOB.ISTEMPORARY(L_HTML) = 1 THEN
            DBMS_LOB.FREETEMPORARY(L_HTML);
        END IF;

        RAISE_APPLICATION_ERROR(
            -20001,
            'Error while generating MV compact report: ' || L_ERROR_MESSAGE
        );
END ADM_SEND_MV_COMPACT_REPORT;
/
