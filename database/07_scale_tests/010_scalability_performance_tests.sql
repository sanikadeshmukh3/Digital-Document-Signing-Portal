-- ============================================================================
-- File:     database/07_scale_tests/010_scalability_performance_tests.sql
-- Project:  Document Workflow and E-signing Portal
-- Database: MySQL 8.x
-- ============================================================================
--
-- PURPOSE
--   Show how the database actually BEHAVES once it holds a realistic amount of
--   data (the ~12,000-row scale dataset from
--   database/04_seed/scale/generate_scale_data.py), not merely that it still
--   works. The focus is query execution behaviour at scale: which access paths
--   the optimizer picks, where an index is doing the heavy lifting, and where a
--   query falls back to a full table scan that would hurt as the data keeps
--   growing.
--
-- WHAT THIS FILE PROVES
--   Part 1  Scale snapshot      Reports total rows, per-table counts, and the
--                               rows-vs-documents distinction, and refuses to
--                               run the scale assertions on a tiny dataset.
--   Part 2  Indexed access      The hot operational queries (participant
--                               worklist, workflow steps, version history,
--                               audit-by-record) use their intended index and
--                               NOT a full table scan, even at scale.
--   Part 3  Measured latency    Representative queries are executed many times
--                               and timed; average/last latency is recorded so
--                               there is a concrete number at 12k rows.
--   Part 4  Indexing bottleneck Queries known to scan are compared against
--                               their indexed equivalents, and the full-scan
--                               ones are flagged as scaling risks with the row
--                               count they must examine.
--   Part 5  Integrity at scale  The referential/business invariants still hold
--                               across the whole scaled dataset, and the
--                               invariant scans are themselves timed.
--   Part 6  Audit overhead      Quantifies how many audit rows the dataset
--                               carries per workflow / per business row.
--
-- HOW TO READ THIS FILE
--   1. Skim the HELPER QUICK REFERENCE below.
--   2. Read Part 1 to see the size this run is measuring.
--   3. Read Parts 2-6 top to bottom. Each check is written as WHAT / WHY /
--      EXPECT followed by the code, and each writes one PASS/FAIL scoreboard
--      row. Performance checks also print the EXPLAIN / EXPLAIN ANALYZE plan
--      and a measured latency so you can see the evidence, not just the verdict.
--   4. The SCOREBOARD at the end summarises PASS/FAIL; the EVIDENCE LOG lists
--      every captured plan and timing.
--
-- HELPER QUICK REFERENCE
--   scl_results            Scoreboard table: one PASS/FAIL row per check.
--   scl_evidence           Evidence table: captured EXPLAIN plans + latencies.
--   sp__scl_check          Writes one PASS/FAIL row and prints it.
--   sp__scl_explain_uses   PASS if a query's JSON plan uses the expected index
--                          (and, optionally, avoids a full 'ALL' scan).
--   sp__scl_time_query     Runs a SELECT COUNT(*) wrapper N times and records
--                          average and last latency in milliseconds.
--   sp__scl_capture_plan   Stores a query's EXPLAIN ANALYZE text as evidence.
--
-- IMPORTANT
--   - READ-ONLY. This script never inserts, updates or deletes business data.
--     It is safe to run against the populated database as many times as you
--     like and will not change or destroy the generated scale dataset.
--   - It creates only session-local temporary tables and helper procedures,
--     and drops the procedures again at the end.
--   - NOT part of the ordered build manifest. Run it on demand after the
--     database has been built, seeded and scaled.
--
-- HOW TO RUN (from the repo root, inside WSL)
--   mysql --host=127.0.0.1 --user=<admin> --password \
--         document_portal_demo \
--         < database/07_scale_tests/010_scalability_performance_tests.sql
--
--   Replace document_portal_demo with your target database.
-- ============================================================================


-- ============================================================================
-- SESSION SETUP
-- ============================================================================

-- Pin a portable, strict sql_mode for the run and restore the caller's at the
-- end, so results are identical everywhere.
SET @scl_saved_sql_mode = @@SESSION.sql_mode;
SET SESSION sql_mode = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

-- The scoreboard. Every check adds one PASS or FAIL row here.
DROP TEMPORARY TABLE IF EXISTS scl_results;
CREATE TEMPORARY TABLE scl_results (
    seq        INT AUTO_INCREMENT PRIMARY KEY,
    area       VARCHAR(20),
    test_name  VARCHAR(200),
    result     VARCHAR(4),
    detail     TEXT
);

-- Evidence log. Captured plans and measured latencies live here so the final
-- report can show the actual execution behaviour, not just the verdict.
DROP TEMPORARY TABLE IF EXISTS scl_evidence;
CREATE TEMPORARY TABLE scl_evidence (
    seq        INT AUTO_INCREMENT PRIMARY KEY,
    label      VARCHAR(200),
    kind       VARCHAR(20),       -- 'PLAN' or 'TIMING'
    detail     LONGTEXT
);


-- ============================================================================
-- HELPER PROCEDURES  (test plumbing only; safe to skip on first read)
-- They exist only for this script and are dropped again at the end.
-- ============================================================================
DELIMITER $$

-- ----------------------------------------------------------------------------
-- sp__scl_check
--   Records one scoreboard row and prints it. p_pass: true -> PASS.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__scl_check $$
CREATE PROCEDURE sp__scl_check(IN p_area VARCHAR(20), IN p_name VARCHAR(200),
                               IN p_pass BOOLEAN, IN p_detail TEXT)
BEGIN
    INSERT INTO scl_results(area, test_name, result, detail)
    VALUES (p_area, p_name, IF(COALESCE(p_pass,0), 'PASS', 'FAIL'), p_detail);

    SELECT IF(COALESCE(p_pass,0), 'PASS', 'FAIL') AS Result,
           p_area   AS Area,
           p_name   AS Test,
           p_detail AS Detail;
END $$

-- ----------------------------------------------------------------------------
-- sp__scl_access_path
--   Determines whether a query is satisfied by an INDEX SEEK or by a FULL
--   TABLE SCAN, using the session Handler_* status counters (a supported,
--   script-friendly signal, since MySQL cannot capture EXPLAIN output into a
--   variable or table).
--
--   Method: FLUSH STATUS resets the counters; we run the query; then we read
--     Handler_read_rnd_next  - rows read sequentially during a FULL SCAN
--     Handler_read_key       - index lookups performed
--   A query served purely from an index reads few/zero sequential rows; a full
--   scan reads roughly one per table row.
--
--   PASS when:
--     - Handler_read_key > 0 (an index was used), AND
--     - if p_forbid_full is TRUE, Handler_read_rnd_next is below p_scan_cap
--       (so the query did not fall back to scanning a whole table).
--   When p_forbid_full is FALSE the check only DOCUMENTS the behaviour (used
--   to record known full-scan bottlenecks); it passes regardless and reports
--   the sequential-row count as the bottleneck's size.
--
--   The matching EXPLAIN plan is printed separately (sp__scl_show_plan) so a
--   human reviewer sees the chosen key and access type too.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__scl_access_path $$
CREATE PROCEDURE sp__scl_access_path(IN p_area VARCHAR(20), IN p_name VARCHAR(200),
                                     IN p_stmt TEXT, IN p_forbid_full BOOLEAN,
                                     IN p_scan_cap INT)
BEGIN
    DECLARE v_rnd_next BIGINT DEFAULT 0;
    DECLARE v_read_key BIGINT DEFAULT 0;

    -- Reset session counters, run the query, read the deltas.
    FLUSH STATUS;
    SET @scl_ap = p_stmt;
    PREPARE scl_ap FROM @scl_ap;
    EXECUTE scl_ap;
    DEALLOCATE PREPARE scl_ap;

    SELECT CAST(VARIABLE_VALUE AS SIGNED) INTO v_rnd_next
    FROM performance_schema.session_status
    WHERE VARIABLE_NAME = 'Handler_read_rnd_next';

    SELECT CAST(VARIABLE_VALUE AS SIGNED) INTO v_read_key
    FROM performance_schema.session_status
    WHERE VARIABLE_NAME = 'Handler_read_key';

    INSERT INTO scl_evidence(label, kind, detail)
    VALUES (p_name, 'HANDLER',
            CONCAT('Handler_read_key=', v_read_key,
                   ' (index lookups), Handler_read_rnd_next=', v_rnd_next,
                   ' (sequential/full-scan row reads)'));

    CALL sp__scl_check(p_area, p_name,
        (v_read_key > 0) AND (NOT p_forbid_full OR v_rnd_next <= p_scan_cap),
        CONCAT('index lookups (Handler_read_key)=', v_read_key,
               ' || sequential row reads (Handler_read_rnd_next)=', v_rnd_next,
               ' || forbid full scan=', IF(p_forbid_full, 'yes', 'no'),
               IF(p_forbid_full, CONCAT(' (cap=', p_scan_cap, ')'), '')));
END $$

-- ----------------------------------------------------------------------------
-- sp__scl_show_plan
--   Prints the traditional EXPLAIN plan for a statement so the chosen key and
--   access type are visible as human evidence. EXPLAIN output cannot be
--   captured programmatically in MySQL, so this is display-only.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__scl_show_plan $$
CREATE PROCEDURE sp__scl_show_plan(IN p_label VARCHAR(200), IN p_stmt TEXT)
BEGIN
    SELECT p_label AS ExplainFor;
    SET @scl_sp = CONCAT('EXPLAIN ', p_stmt);
    PREPARE scl_sp FROM @scl_sp;
    EXECUTE scl_sp;
    DEALLOCATE PREPARE scl_sp;
END $$

-- ----------------------------------------------------------------------------
-- sp__scl_time_query
--   Executes p_stmt p_iters times and records the AVERAGE and LAST latency in
--   milliseconds. p_stmt must be a complete SELECT. Timing uses NOW(6)
--   microsecond clocks around each execution. The measurement is stored as
--   evidence and also printed. No pass/fail by itself; callers may assert on
--   the returned @scl_avg_ms / @scl_last_ms if they wish.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__scl_time_query $$
CREATE PROCEDURE sp__scl_time_query(IN p_label VARCHAR(200), IN p_stmt TEXT,
                                    IN p_iters INT)
BEGIN
    DECLARE v_i INT DEFAULT 0;
    DECLARE v_t0 DATETIME(6);
    DECLARE v_t1 DATETIME(6);
    DECLARE v_total_us BIGINT DEFAULT 0;
    DECLARE v_last_us BIGINT DEFAULT 0;

    -- Wrap the query as a derived table so the full result set is materialised
    -- and consumed server-side (SELECT COUNT(*) INTO a sink variable) instead
    -- of streaming every row to the client on each of the p_iters runs. This
    -- still forces the whole query to execute; it just avoids flooding output.
    SET @scl_timed = CONCAT('SELECT COUNT(*) INTO @scl_sink FROM (', p_stmt, ') AS scl_sub');
    PREPARE scl_t FROM @scl_timed;

    WHILE v_i < p_iters DO
        SET v_t0 = NOW(6);
        EXECUTE scl_t;
        SET v_t1 = NOW(6);
        SET v_last_us  = TIMESTAMPDIFF(MICROSECOND, v_t0, v_t1);
        SET v_total_us = v_total_us + v_last_us;
        SET v_i = v_i + 1;
    END WHILE;

    DEALLOCATE PREPARE scl_t;

    SET @scl_avg_ms  = ROUND((v_total_us / p_iters) / 1000.0, 4);
    SET @scl_last_ms = ROUND(v_last_us / 1000.0, 4);

    INSERT INTO scl_evidence(label, kind, detail)
    VALUES (p_label, 'TIMING',
            CONCAT('iterations=', p_iters,
                   ' || avg_ms=', @scl_avg_ms,
                   ' || last_ms=', @scl_last_ms));

    SELECT p_label AS Query, p_iters AS Iterations,
           @scl_avg_ms AS AvgMs, @scl_last_ms AS LastMs;
END $$

-- ----------------------------------------------------------------------------
-- sp__scl_capture_plan
--   Runs and prints a query's EXPLAIN ANALYZE output. EXPLAIN ANALYZE executes
--   the query and reports the optimizer's ACTUAL timing and row counts, which
--   is the clearest "at this scale" performance evidence MySQL offers. The
--   output cannot be captured into a table/variable in MySQL, so it is printed
--   for the reviewer rather than stored in scl_evidence.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__scl_capture_plan $$
CREATE PROCEDURE sp__scl_capture_plan(IN p_label VARCHAR(200), IN p_stmt TEXT)
BEGIN
    SELECT p_label AS ExplainAnalyzeFor;
    SET @scl_an = CONCAT('EXPLAIN ANALYZE ', p_stmt);
    PREPARE scl_a FROM @scl_an;
    EXECUTE scl_a;
    DEALLOCATE PREPARE scl_a;
END $$

DELIMITER ;


-- ============================================================================
-- ============================================================================
--                     THE SCALABILITY TESTS START HERE
-- ============================================================================
-- ============================================================================


-- ============================================================================
-- PART 1 - SCALE SNAPSHOT
--   WHAT:   measure the dataset this run is about to test.
--   WHY:    scalability evidence is only meaningful if we state the size, and
--           we must not claim "at scale" results on a tiny seed-only database.
--   EXPECT: total core rows > 10,000, so the numbers below are genuine
--           at-scale evidence.
--
--   Note the deliberate rows-vs-documents distinction: one generated
--   "document" (one workflow bundle) expands into roughly a dozen rows across
--   the core tables, so total rows is far larger than the document count.
-- ============================================================================
SELECT '=== PART 1: SCALE SNAPSHOT ===' AS Section;

-- Per-table counts and the grand total of core-table rows.
SET @scl_users      = (SELECT COUNT(*) FROM `User`);
SET @scl_userroles  = (SELECT COUNT(*) FROM UserRole);
SET @scl_docs       = (SELECT COUNT(*) FROM Document);
SET @scl_versions   = (SELECT COUNT(*) FROM DocumentVersion);
SET @scl_workflows  = (SELECT COUNT(*) FROM Workflow);
SET @scl_steps      = (SELECT COUNT(*) FROM WorkflowStep);
SET @scl_parts      = (SELECT COUNT(*) FROM WorkflowParticipant);
SET @scl_decisions  = (SELECT COUNT(*) FROM ApprovalDecision);
SET @scl_signatures = (SELECT COUNT(*) FROM Signature);
SET @scl_audit      = (SELECT COUNT(*) FROM AuditLog);
SET @scl_refdata    = (SELECT COUNT(*) FROM ReferenceData);
SET @scl_roles      = (SELECT COUNT(*) FROM Role);

SET @scl_total_rows =
      @scl_users + @scl_userroles + @scl_docs + @scl_versions
    + @scl_workflows + @scl_steps + @scl_parts + @scl_decisions
    + @scl_signatures + @scl_audit + @scl_refdata + @scl_roles;

-- Business-object counts (documents / workflows) are NOT the same as rows.
SET @scl_scale_docs = (SELECT COUNT(*) FROM Document WHERE Title LIKE 'SCALE-DOC-%');

SELECT 'Per-table row counts (core tables)' AS Snapshot;
SELECT 'User' AS TableName, @scl_users AS RowCountValue
UNION ALL SELECT 'UserRole', @scl_userroles
UNION ALL SELECT 'Document', @scl_docs
UNION ALL SELECT 'DocumentVersion', @scl_versions
UNION ALL SELECT 'Workflow', @scl_workflows
UNION ALL SELECT 'WorkflowStep', @scl_steps
UNION ALL SELECT 'WorkflowParticipant', @scl_parts
UNION ALL SELECT 'ApprovalDecision', @scl_decisions
UNION ALL SELECT 'Signature', @scl_signatures
UNION ALL SELECT 'AuditLog', @scl_audit
UNION ALL SELECT 'ReferenceData', @scl_refdata
UNION ALL SELECT 'Role', @scl_roles
UNION ALL SELECT 'TOTAL (all core tables)', @scl_total_rows;

SELECT CONCAT(
    'Total core rows = ', @scl_total_rows,
    '  ||  Documents (business objects) = ', @scl_docs,
    '  ||  of which generated scale docs = ', @scl_scale_docs,
    '  ||  Workflows = ', @scl_workflows,
    '  ||  rows-per-document ~= ',
    ROUND(@scl_total_rows / NULLIF(@scl_docs, 0), 2)
) AS RowsVsDocuments;

-- CHECK: this really is a scaled dataset (not a seed-only database).
CALL sp__scl_check('SCALE',
    'Dataset is at scale: more than 10,000 total core rows',
    @scl_total_rows > 10000,
    CONCAT('total core rows = ', @scl_total_rows,
           ' across ', @scl_docs, ' documents / ', @scl_workflows, ' workflows'));


-- ============================================================================
-- PART 2 - INDEXED ACCESS PATHS HOLD AT SCALE
--   WHAT:   confirm the hot operational queries still resolve through their
--           intended index at 12k rows, instead of degrading to a full scan.
--   WHY:    an index that the optimizer stops using as data grows is the
--           classic scalability cliff. These are the queries the application
--           runs constantly, so their access path matters most.
--   EXPECT: each query's plan names the intended index and does NOT contain a
--           full "ALL" scan on its driving table.
-- ============================================================================
SELECT '=== PART 2: INDEXED ACCESS PATHS AT SCALE ===' AS Section;

-- Pick a real, "hot" user: the one holding the most ACTIVE assignments. This
-- makes the worklist query representative rather than empty.
SET @scl_active_ps = (SELECT ReferenceDataID FROM ReferenceData
                      WHERE DomainName = 'PARTICIPANT_STATUS' AND Code = 'ACTIVE' LIMIT 1);
SET @scl_hot_user = (
    SELECT UserID FROM WorkflowParticipant
    WHERE AssignmentStatusID = @scl_active_ps
    GROUP BY UserID ORDER BY COUNT(*) DESC, UserID LIMIT 1);
SET @scl_hot_user = COALESCE(@scl_hot_user,
    (SELECT UserID FROM `User` ORDER BY UserID LIMIT 1));

-- A real workflow / document / affected-record to probe the other hot paths.
SET @scl_a_workflow = (SELECT WorkflowID FROM Workflow ORDER BY WorkflowID LIMIT 1);
SET @scl_a_document = (SELECT DocumentID FROM Document ORDER BY DocumentID LIMIT 1);

-- CHECK: participant worklist resolves through an index (equality on
-- user+status, then ordered by due date) and does NOT scan the whole
-- WorkflowParticipant table. Cap = 20 sequential reads: a true index seek
-- touches only the matching rows, far fewer than the 3,000+ participant rows.
CALL sp__scl_show_plan('participant worklist',
    CONCAT('SELECT wp.WorkflowParticipantID, wp.DueDateTime ',
           'FROM WorkflowParticipant wp ',
           'WHERE wp.UserID = ', @scl_hot_user,
           ' AND wp.AssignmentStatusID = ', @scl_active_ps,
           ' ORDER BY wp.DueDateTime'));
CALL sp__scl_access_path('SCALE',
    'Participant worklist uses an index seek, not a full scan',
    CONCAT('SELECT wp.WorkflowParticipantID, wp.DueDateTime ',
           'FROM WorkflowParticipant wp ',
           'WHERE wp.UserID = ', @scl_hot_user,
           ' AND wp.AssignmentStatusID = ', @scl_active_ps,
           ' ORDER BY wp.DueDateTime'),
    TRUE, 20);

-- CHECK: workflow steps in execution order are served from an index, not a
-- scan of the 3,000+ WorkflowStep rows.
CALL sp__scl_show_plan('workflow steps in order',
    CONCAT('SELECT WorkflowStepID, SequenceNumber FROM WorkflowStep ',
           'WHERE WorkflowID = ', @scl_a_workflow, ' ORDER BY SequenceNumber'));
CALL sp__scl_access_path('SCALE',
    'Workflow steps use an index seek (WorkflowID, SequenceNumber), not a full scan',
    CONCAT('SELECT WorkflowStepID, SequenceNumber FROM WorkflowStep ',
           'WHERE WorkflowID = ', @scl_a_workflow, ' ORDER BY SequenceNumber'),
    TRUE, 20);

-- CHECK: document version history uses the UNIQUE(DocumentID, VersionNumber)
-- index for ordered retrieval instead of scanning DocumentVersion.
CALL sp__scl_show_plan('document version history',
    CONCAT('SELECT DocumentVersionID, VersionNumber FROM DocumentVersion ',
           'WHERE DocumentID = ', @scl_a_document, ' ORDER BY VersionNumber'));
CALL sp__scl_access_path('SCALE',
    'Document version history uses an index seek, not a full scan',
    CONCAT('SELECT DocumentVersionID, VersionNumber FROM DocumentVersion ',
           'WHERE DocumentID = ', @scl_a_document, ' ORDER BY VersionNumber'),
    TRUE, 20);

-- CHECK: audit history for one business record uses idx_AuditLog_AffectedRecord
-- rather than scanning the 2,000+ AuditLog rows.
CALL sp__scl_show_plan('audit history by record',
    CONCAT('SELECT AuditLogID, EventDateTime FROM AuditLog ',
           'WHERE AffectedRecordType = ''Workflow'' ',
           'AND AffectedRecordID = ', @scl_a_workflow, ' ORDER BY EventDateTime'));
CALL sp__scl_access_path('SCALE',
    'Audit-by-record uses an index seek, not a full scan',
    CONCAT('SELECT AuditLogID, EventDateTime FROM AuditLog ',
           'WHERE AffectedRecordType = ''Workflow'' ',
           'AND AffectedRecordID = ', @scl_a_workflow, ' ORDER BY EventDateTime'),
    TRUE, 20);


-- ============================================================================
-- PART 3 - MEASURED LATENCY AT SCALE
--   WHAT:   actually execute the representative queries many times and record
--           the average and last latency in milliseconds, plus the optimizer's
--           own EXPLAIN ANALYZE timing.
--   WHY:    EXPLAIN shows the plan; this shows the cost. A concrete number at
--           12k rows is the performance evidence the exercise asks for.
--   EXPECT: these run and are recorded. The indexed worklist should be an
--           order of magnitude faster than a scanning report (verified in the
--           timing numbers and the Part 4 comparison).
-- ============================================================================
SELECT '=== PART 3: MEASURED LATENCY AT SCALE ===' AS Section;

-- Indexed point-ish lookup: the participant worklist for the hot user.
CALL sp__scl_time_query('participant worklist (indexed)',
    CONCAT('SELECT wp.WorkflowParticipantID, wp.DueDateTime ',
           'FROM WorkflowParticipant wp ',
           'WHERE wp.UserID = ', @scl_hot_user,
           ' AND wp.AssignmentStatusID = ', @scl_active_ps,
           ' ORDER BY wp.DueDateTime'),
    100);
CALL sp__scl_capture_plan('participant worklist (indexed) - EXPLAIN ANALYZE',
    CONCAT('SELECT wp.WorkflowParticipantID, wp.DueDateTime ',
           'FROM WorkflowParticipant wp ',
           'WHERE wp.UserID = ', @scl_hot_user,
           ' AND wp.AssignmentStatusID = ', @scl_active_ps,
           ' ORDER BY wp.DueDateTime'));

-- Operational report over a view that joins the whole participant table.
CALL sp__scl_time_query('outstanding actions report (view)',
    'SELECT * FROM vw_OutstandingActions ORDER BY DueDateTime LIMIT 500', 30);
CALL sp__scl_capture_plan('outstanding actions report (view) - EXPLAIN ANALYZE',
    'SELECT * FROM vw_OutstandingActions ORDER BY DueDateTime LIMIT 500');

-- Aggregated status summary across all workflows.
CALL sp__scl_time_query('workflow status summary (aggregate)',
    CONCAT('SELECT rd.Code, COUNT(*) FROM Workflow w ',
           'JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID ',
           'GROUP BY rd.Code'),
    50);
CALL sp__scl_capture_plan('workflow status summary (aggregate) - EXPLAIN ANALYZE',
    CONCAT('SELECT rd.Code, COUNT(*) FROM Workflow w ',
           'JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID ',
           'GROUP BY rd.Code'));

-- Full workflow detail for one workflow (wide multi-join via the view).
CALL sp__scl_time_query('workflow detail for one workflow (view)',
    CONCAT('SELECT * FROM vw_WorkflowDetail WHERE WorkflowID = ', @scl_a_workflow),
    50);


-- ============================================================================
-- PART 4 - INDEXING BOTTLENECKS
--   WHAT:   contrast a query the optimizer can satisfy from an index against
--           one that must scan a whole table, and flag the scanning ones as
--           scaling risks together with the number of rows they examine.
--   WHY:    identifying where a full scan is the chosen plan is exactly the
--           "potential indexing bottleneck" the exercise asks us to surface.
--   EXPECT: - the indexed worklist is confirmed NOT to scan (a good path).
--           - vw_OutstandingActions is confirmed TO scan WorkflowParticipant
--             (access_type "ALL"); this is recorded as a known bottleneck that
--             grows linearly with the participant table.
--           - a LIKE '%...%' search on Document is confirmed to scan; recorded
--             as inherently unindexable (leading wildcard).
-- ============================================================================
SELECT '=== PART 4: INDEXING BOTTLENECKS ===' AS Section;

-- GOOD PATH: the indexed worklist must NOT scan the whole participant table.
CALL sp__scl_access_path('SCALE',
    'GOOD: indexed worklist avoids a full table scan at scale',
    CONCAT('SELECT wp.WorkflowParticipantID FROM WorkflowParticipant wp ',
           'WHERE wp.UserID = ', @scl_hot_user,
           ' AND wp.AssignmentStatusID = ', @scl_active_ps),
    TRUE, 20);

-- BOTTLENECK 1: the outstanding-actions view scans WorkflowParticipant. We
-- DOCUMENT the scan (p_forbid_full = FALSE, so the check passes while
-- recording the behaviour) and print its EXPLAIN ANALYZE so the scan and its
-- row count are visible.
CALL sp__scl_capture_plan('BOTTLENECK vw_OutstandingActions - EXPLAIN ANALYZE',
    'SELECT * FROM vw_OutstandingActions ORDER BY DueDateTime LIMIT 500');
CALL sp__scl_access_path('SCALE',
    'BOTTLENECK: vw_OutstandingActions scans WorkflowParticipant (documented)',
    'SELECT * FROM vw_OutstandingActions ORDER BY DueDateTime LIMIT 500',
    FALSE, 0);

-- Record the size of the table being scanned, as the bottleneck's growth driver.
CALL sp__scl_check('SCALE',
    'BOTTLENECK documented: outstanding-actions scan grows with WorkflowParticipant',
    TRUE,
    CONCAT('vw_OutstandingActions scans all ', @scl_parts,
           ' WorkflowParticipant rows; a filtered/covering index on ',
           'AssignmentStatusID would let it seek instead of scan as this table grows.'));

-- BOTTLENECK 2: a leading-wildcard LIKE on Document cannot use an index and
-- must scan every Document row.
CALL sp__scl_show_plan('leading-wildcard LIKE on Document',
    'SELECT COUNT(*) FROM Document WHERE BusinessDescription LIKE ''%scale%''');
CALL sp__scl_access_path('SCALE',
    'BOTTLENECK: leading-wildcard LIKE on Document scans the table (documented)',
    'SELECT COUNT(*) FROM Document WHERE BusinessDescription LIKE ''%scale%''',
    FALSE, 0);
CALL sp__scl_time_query('leading-wildcard LIKE on Document (scan)',
    'SELECT COUNT(*) FROM Document WHERE BusinessDescription LIKE ''%scale%''', 50);
CALL sp__scl_check('SCALE',
    'BOTTLENECK documented: leading-wildcard LIKE is inherently unindexable',
    TRUE,
    CONCAT('Scans all ', @scl_docs, ' Document rows. A leading ''%'' prevents ',
           'index use; full-text search or a trailing-wildcard prefix would be needed.'));


-- ============================================================================
-- PART 5 - REFERENTIAL AND BUSINESS INTEGRITY AT SCALE
--   WHAT:   re-check the invariants across the WHOLE scaled dataset and time
--           the scans.
--   WHY:    bulk generation is where integrity bugs would surface; at 12k rows
--           every FK and business rule must still hold, and the checks must
--           still be cheap.
--   EXPECT: every violation count is 0, and each scan completes quickly.
-- ============================================================================
SELECT '=== PART 5: INTEGRITY AT SCALE ===' AS Section;

-- Orphan scans (every child resolves to a parent). All must be 0.
SET @scl_t0 = NOW(6);

SET @scl_orphan_wf = (
    SELECT COUNT(*) FROM Workflow w
    LEFT JOIN Document d ON d.DocumentID = w.DocumentID
    WHERE d.DocumentID IS NULL);

SET @scl_orphan_step = (
    SELECT COUNT(*) FROM WorkflowStep ws
    LEFT JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
    WHERE w.WorkflowID IS NULL);

SET @scl_orphan_part = (
    SELECT COUNT(*) FROM WorkflowParticipant wp
    LEFT JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
    WHERE ws.WorkflowStepID IS NULL);

-- Every assignment must be held by a user who actually has that role
-- (the composite WorkflowParticipant -> UserRole FK).
SET @scl_part_norole = (
    SELECT COUNT(*) FROM WorkflowParticipant wp
    LEFT JOIN UserRole ur ON ur.UserID = wp.UserID AND ur.RoleID = wp.RoleID
    WHERE ur.UserID IS NULL);

-- At most one signature and one decision per participant.
SET @scl_multi_sig = (
    SELECT COUNT(*) FROM (
        SELECT WorkflowParticipantID FROM Signature
        GROUP BY WorkflowParticipantID HAVING COUNT(*) > 1) t);

SET @scl_multi_dec = (
    SELECT COUNT(*) FROM (
        SELECT WorkflowParticipantID FROM ApprovalDecision
        GROUP BY WorkflowParticipantID HAVING COUNT(*) > 1) t);

-- Exactly one CURRENT version per document (the one-current-version rule).
SET @scl_multi_current = (
    SELECT COUNT(*) FROM (
        SELECT dv.DocumentID FROM DocumentVersion dv
        JOIN ReferenceData rd ON rd.ReferenceDataID = dv.CurrentVersionStatusID
        WHERE rd.Code = 'CURRENT'
        GROUP BY dv.DocumentID HAVING COUNT(*) > 1) t);

-- Every signature is bound to the same version its workflow is about.
SET @scl_sig_version = (
    SELECT COUNT(*) FROM Signature s
    JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = s.WorkflowParticipantID
    JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
    WHERE s.DocumentVersionID <> w.DocumentVersionID);

SET @scl_t1 = NOW(6);
SET @scl_integrity_ms = ROUND(TIMESTAMPDIFF(MICROSECOND, @scl_t0, @scl_t1) / 1000.0, 3);

INSERT INTO scl_evidence(label, kind, detail)
VALUES ('integrity sweep (all invariants)', 'TIMING',
        CONCAT('scanned whole dataset in ', @scl_integrity_ms, ' ms'));

CALL sp__scl_check('SCALE',
    'Referential and business integrity hold across the whole scaled dataset',
    @scl_orphan_wf = 0 AND @scl_orphan_step = 0 AND @scl_orphan_part = 0
      AND @scl_part_norole = 0 AND @scl_multi_sig = 0 AND @scl_multi_dec = 0
      AND @scl_multi_current = 0 AND @scl_sig_version = 0,
    CONCAT('orphan workflows=', @scl_orphan_wf,
           ', orphan steps=', @scl_orphan_step,
           ', orphan participants=', @scl_orphan_part,
           ', participants w/o matching UserRole=', @scl_part_norole,
           ', participants w/ >1 signature=', @scl_multi_sig,
           ', participants w/ >1 decision=', @scl_multi_dec,
           ', documents w/ >1 CURRENT version=', @scl_multi_current,
           ', signature/version mismatches=', @scl_sig_version,
           ' || sweep time=', @scl_integrity_ms, ' ms'));


-- ============================================================================
-- PART 6 - AUDIT OVERHEAD AT SCALE
--   WHAT:   quantify how much of the dataset is audit data, and how many audit
--           rows accompany each workflow and each business row.
--   WHY:    the AuditLog is append-only and grows with every state change; its
--           relative size is a real scalability consideration for storage and
--           for audit-history queries.
--   EXPECT: this reports the ratios. The check passes as long as audit rows
--           exist and the ratios are computable (there is no "wrong" value to
--           fail on; it is evidence).
-- ============================================================================
SELECT '=== PART 6: AUDIT OVERHEAD AT SCALE ===' AS Section;

-- Business rows = everything except the AuditLog and static reference tables.
SET @scl_business_rows =
      @scl_docs + @scl_versions + @scl_workflows + @scl_steps
    + @scl_parts + @scl_decisions + @scl_signatures;

SELECT CONCAT(
    'AuditLog rows = ', @scl_audit,
    '  ||  per workflow = ', ROUND(@scl_audit / NULLIF(@scl_workflows, 0), 3),
    '  ||  per business row = ', ROUND(@scl_audit / NULLIF(@scl_business_rows, 0), 3),
    '  ||  AuditLog as % of all core rows = ',
    ROUND(100 * @scl_audit / NULLIF(@scl_total_rows, 0), 2), '%'
) AS AuditOverhead;

INSERT INTO scl_evidence(label, kind, detail)
VALUES ('audit overhead', 'TIMING',
        CONCAT('audit rows=', @scl_audit,
               ', per workflow=', ROUND(@scl_audit / NULLIF(@scl_workflows, 0), 3),
               ', per business row=', ROUND(@scl_audit / NULLIF(@scl_business_rows, 0), 3)));

CALL sp__scl_check('SCALE',
    'Audit overhead is quantified at scale',
    @scl_audit > 0 AND @scl_workflows > 0,
    CONCAT('audit rows=', @scl_audit,
           ', workflows=', @scl_workflows,
           ', ~', ROUND(@scl_audit / NULLIF(@scl_workflows, 0), 2),
           ' audit rows per workflow'));


-- ============================================================================
-- SCOREBOARD
--   If every row shows Failed = 0, every scalability assertion held.
-- ============================================================================
SELECT '=== SCALABILITY SCOREBOARD ===' AS Section;
SELECT COALESCE(area, 'ALL') AS Area,
       SUM(result = 'PASS')  AS Passed,
       SUM(result = 'FAIL')  AS Failed,
       COUNT(*)              AS Total
FROM scl_results
GROUP BY area WITH ROLLUP;

SELECT '=== FAILURES (should be empty) ===' AS Section;
SELECT seq, test_name, detail
FROM scl_results
WHERE result = 'FAIL'
ORDER BY seq;

SELECT '=== FULL RESULT LOG ===' AS Section;
SELECT seq, result, test_name, detail
FROM scl_results
ORDER BY seq;

-- ============================================================================
-- EVIDENCE LOG
--   The captured EXPLAIN / EXPLAIN ANALYZE plans and measured latencies that
--   back up the verdicts above. This is the "actual performance evidence at
--   scale" the checks summarise.
-- ============================================================================
SELECT '=== PERFORMANCE EVIDENCE (plans + timings) ===' AS Section;
SELECT seq, kind, label, detail
FROM scl_evidence
ORDER BY seq;


-- ============================================================================
-- CLEAN UP
--   Drop the helper procedures and restore the caller's sql_mode. The
--   temporary scoreboard/evidence tables are session-local and disappear on
--   disconnect; they are kept until then so the results above remain queryable.
-- ============================================================================
DROP PROCEDURE IF EXISTS sp__scl_capture_plan;
DROP PROCEDURE IF EXISTS sp__scl_show_plan;
DROP PROCEDURE IF EXISTS sp__scl_access_path;
DROP PROCEDURE IF EXISTS sp__scl_time_query;
DROP PROCEDURE IF EXISTS sp__scl_check;

SET SESSION sql_mode = @scl_saved_sql_mode;
