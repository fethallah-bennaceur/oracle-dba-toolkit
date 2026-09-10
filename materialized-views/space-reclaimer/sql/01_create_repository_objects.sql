-- Repository objects for run-level and MV-level audit history.
-- Run this as the schema that will own the maintenance framework (for example ADMINISTRATION).

CREATE SEQUENCE ADM_MV_COMPACT_RUN_SEQ
    START WITH 1
    INCREMENT BY 1
    CACHE 20;

CREATE TABLE ADM_MV_COMPACT_RUN
(
    RUN_ID                  NUMBER         NOT NULL,
    START_TIME              TIMESTAMP      DEFAULT SYSTIMESTAMP,
    END_TIME                TIMESTAMP,
    OWNERS_LIST             VARCHAR2(1000),
    MIN_ALLOCATED_MB        NUMBER,
    MIN_RATIO_X             NUMBER,
    MIN_EXCESS_MB           NUMBER,
    EXECUTE_REFRESH         VARCHAR2(1),
    STATUS                  VARCHAR2(30),
    NB_PRESELECTED          NUMBER,
    NB_CONFIRMED            NUMBER,
    NB_SUCCESS              NUMBER,
    NB_ERROR                NUMBER,
    ERROR_MESSAGE           VARCHAR2(4000),

    CONSTRAINT PK_ADM_MV_COMPACT_RUN
        PRIMARY KEY (RUN_ID)
);

CREATE TABLE ADM_MV_COMPACT_DETAIL
(
    RUN_ID                       NUMBER          NOT NULL,
    OWNER                        VARCHAR2(128)   NOT NULL,
    MVIEW_NAME                   VARCHAR2(128)   NOT NULL,

    STATUS                       VARCHAR2(40),
    DETECTED_AT                  TIMESTAMP       DEFAULT SYSTIMESTAMP,

    LAST_ATOMIC_REFRESH_BEFORE   VARCHAR2(1),
    REFRESH_ID_BEFORE            NUMBER,
    LAST_REFRESH_DATE_BEFORE     DATE,
    LAST_REFRESH_DATE_AFTER      DATE,

    LAST_ANALYZED_BEFORE         DATE,
    LAST_ANALYZED_REFINED        DATE,
    LAST_ANALYZED_AFTER          DATE,

    NUM_ROWS_BEFORE              NUMBER,
    NUM_ROWS_REFINED             NUMBER,
    NUM_ROWS_AFTER               NUMBER,

    AVG_ROW_LEN_BEFORE           NUMBER,
    AVG_ROW_LEN_REFINED          NUMBER,
    AVG_ROW_LEN_AFTER            NUMBER,

    ALLOCATED_BLOCKS_BEFORE      NUMBER,
    EXTENTS_BEFORE               NUMBER,

    TABLE_MB_BEFORE              NUMBER,
    INDEX_MB_BEFORE              NUMBER,
    TOTAL_MB_BEFORE              NUMBER,

    ESTIMATED_DATA_MB_BEFORE     NUMBER,
    RATIO_X_BEFORE               NUMBER,
    EXCESS_MB_BEFORE             NUMBER,

    TABLE_MB_REFINED             NUMBER,
    INDEX_MB_REFINED             NUMBER,
    TOTAL_MB_REFINED             NUMBER,

    ESTIMATED_DATA_MB_REFINED    NUMBER,
    RATIO_X_REFINED              NUMBER,
    EXCESS_MB_REFINED            NUMBER,

    REFRESH_START_TIME           TIMESTAMP,
    REFRESH_END_TIME             TIMESTAMP,
    REFRESH_DURATION_SECONDS     NUMBER,

    TABLE_MB_AFTER               NUMBER,
    INDEX_MB_AFTER               NUMBER,
    TOTAL_MB_AFTER               NUMBER,
    RECLAIMED_MB                 NUMBER,

    ERROR_CODE                   NUMBER,
    ERROR_MESSAGE                VARCHAR2(4000),

    CONSTRAINT PK_ADM_MV_COMPACT_DETAIL
        PRIMARY KEY (RUN_ID, OWNER, MVIEW_NAME),

    CONSTRAINT FK_ADM_MV_COMPACT_DETAIL
        FOREIGN KEY (RUN_ID)
        REFERENCES ADM_MV_COMPACT_RUN (RUN_ID)
);
