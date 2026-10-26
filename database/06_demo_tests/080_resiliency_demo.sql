-- ============================================================================
-- File:     database/06_demo_tests/080_resiliency_demo.sql
-- Project:  Document Workflow and E-signing Portal
-- Database: MySQL 8.x
-- ============================================================================
--
-- PURPOSE
--   Prove the system survives failures, mistakes and replays without ending
--   up in a broken or half-finished state.
--
-- WHAT THIS FILE PROVES
--   Part 2  Failed transactions   A multi-step "start workflow" that breaks
--                                 halfway is rolled back COMPLETELY, and a
--                                 corrected retry then works.
--   Part 3  Guards                Duplicate, out-of-sequence and wrong-version
--                                 actions are refused.
--   Part 4  Rejection             A rejection needs a reason; it is a valid
--                                 business outcome (not a crash); the fix is a
--                                 new version + new workflow, and the old
--                                 rejected history is kept.
--   Part 5  Cancellation          Cancelling cascades to every step and
--                                 assignment; later actions are refused.
--   Part 6  Expiration            The expiry batch job closes overdue
--                                 workflows; later actions are refused.
--   Part 7  Consistency sweep     After all of the above, global invariants
--                                 still hold.
--
-- HOW TO READ THIS FILE
--   1. Skim "THE CAST", "VARIABLE LEGEND" and "HELPER QUICK REFERENCE".
--   2. SKIP the HELPER PROCEDURES section on a first read (it is long; Part 2
--      and Part 4 helpers are explained step by step inside it).
--   3. Jump to "PART 1 - SETUP" and read straight down. Each test is
--      written as WHAT / WHY / EXPECT, followed by the code.
--
-- THE CAST (all created by the seed data)
--   Olivia Brooks  document OWNER
--   Marcus Reed    REVIEWER   (step 1)
--   Daniel Cho     APPROVER   (step 2)
--   Sofia Alvarez  SIGNER     (step 3)
--
-- THE DEMO WORKFLOW (every demo workflow in this file has the same shape)
--   Step 1: Marcus REVIEWS -> Step 2: Daniel APPROVES -> Step 3: Sofia SIGNS
--
-- THE FOUR WORKFLOWS BUILT IN PART 1 (one per scenario, so they do not interfere)
--   WF1  Guards         (Part 3)  runs the happy path while we poke at it
--   WF2  Rejection      (Part 4)  Daniel rejects, then it is corrected
--   WF3  Cancellation   (Part 5)  cancelled before anything happens
--   WF4  Expiration     (Part 6)  made overdue, then expired
--
-- VARIABLE LEGEND
--   @u_owner, @u_marcus, @u_daniel, @u_sofia    user ids (see cast)
--   For each workflow n = 1..4:
--     @dn  document id          @vn  version-1 id        @wn  workflow id
--     @rn  Marcus's REVIEW assignment id
--     @an  Daniel's APPROVAL assignment id
--     @sn  Sofia's SIGNATURE assignment id
--     (all assignment ids are WorkflowParticipantID values)
--   @ear_*   short-lived scratch values for a single check
--
-- HELPER QUICK REFERENCE
--   sp__ear_check                    Writes one PASS/FAIL row to the scoreboard.
--   sp__ear_snapshot                 Text "photo" of a workflow's state.
--   sp__ear_expect_reject            Statement must error AND leave state unchanged.
--   sp__ear_expect_ok                Statement must run without error.
--   sp__ear_make_doc                 Creates a fresh demo document + version 1.
--   sp__ear_initiate                 Starts the 3-step workflow.
--   sp__ear_new_workflow             Shortcut: make_doc + initiate.
--   sp__ear_test_initiation_rollback Part 2 engine: break a start halfway, prove
--                                    full rollback, then retry successfully.
--   sp__ear_test_correction          Part 4 engine: new version + new workflow
--                                    after a rejection; history preserved.
--   trg_Test_EAR_ForceFailure        TEMPORARY trigger that forces a failure
--                                    mid-transaction (Part 2 only).
--
-- IMPORTANT
--   - Self-contained and re-runnable: it creates its own demo data.
--   - Creates and drops ONE temporary trigger, trg_Test_EAR_ForceFailure.
--     If the script is interrupted, run this by hand to remove it:
--         DROP TRIGGER IF EXISTS trg_Test_EAR_ForceFailure;
--   - This file is NOT part of the normal build manifest.
-- ============================================================================


-- ============================================================================
-- SESSION SETUP
-- ============================================================================

-- Pin a portable, strict session sql_mode for this script and restore the
-- caller's mode at the very end, so the demo behaves identically everywhere.
-- In particular this clears IGNORE_SPACE. Under IGNORE_SPACE a built-in call
-- such as MD5(...) can be mis-resolved to a stored function and fail with
-- "FUNCTION <db>.MD5 does not exist".
SET @ear_saved_sql_mode = @@SESSION.sql_mode;
SET SESSION sql_mode = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

-- The scoreboard. Every check adds one PASS or FAIL row here.
DROP TEMPORARY TABLE IF EXISTS ear_results;
CREATE TEMPORARY TABLE ear_results (
    seq        INT AUTO_INCREMENT PRIMARY KEY,
    area       VARCHAR(20),
    test_name  VARCHAR(200),
    result     VARCHAR(4),
    detail     TEXT
);

-- Safety net: if an earlier run was stopped halfway, make sure the test-only
-- trigger is not still installed before we begin.
DROP TRIGGER IF EXISTS trg_Test_EAR_ForceFailure;


-- ============================================================================
-- HELPER PROCEDURES  (test plumbing only; safe to skip on first read)
-- They exist only for this demo and are dropped again at the end of the file.
-- ============================================================================
DELIMITER $$

-- ----------------------------------------------------------------------------
-- sp__ear_check
--   Records one scoreboard row and prints it on screen.
--   p_pass is the verdict: true -> PASS, false/NULL -> FAIL.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__ear_check $$
CREATE PROCEDURE sp__ear_check(IN p_area VARCHAR(20), IN p_name VARCHAR(200),
                               IN p_pass BOOLEAN, IN p_detail TEXT)
BEGIN
    INSERT INTO ear_results(area, test_name, result, detail)
    VALUES (p_area, p_name, IF(COALESCE(p_pass,0), 'PASS', 'FAIL'), p_detail);

    SELECT IF(COALESCE(p_pass,0), 'PASS', 'FAIL') AS Result,
           p_area   AS Area,
           p_name   AS Test,
           p_detail AS Detail;
END $$

-- ----------------------------------------------------------------------------
-- sp__ear_snapshot
--   Builds one line of text describing a workflow's current state:
--     WORKFLOW=<status> | STEPS=<seq:status,...> | ASSIGNMENTS=<id:status,...>
--     | DECISIONS=<count> | SIGNATURES=<count>
--   Two identical snapshots mean "nothing changed".
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__ear_snapshot $$
CREATE PROCEDURE sp__ear_snapshot(IN p_wf BIGINT UNSIGNED, OUT p_snap TEXT)
BEGIN
    SELECT CONCAT_WS(' | ',

        -- Overall workflow status
        CONCAT('WORKFLOW=', COALESCE((
            SELECT rd.Code
            FROM Workflow w
            JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID
            WHERE w.WorkflowID = p_wf), '?')),

        -- Each step's status, in sequence order
        CONCAT('STEPS=', COALESCE((
            SELECT GROUP_CONCAT(CONCAT(ws.SequenceNumber, ':', rd.Code)
                                ORDER BY ws.SequenceNumber SEPARATOR ',')
            FROM WorkflowStep ws
            JOIN ReferenceData rd ON rd.ReferenceDataID = ws.StepStatusID
            WHERE ws.WorkflowID = p_wf), '-')),

        -- Each person's assignment status
        CONCAT('ASSIGNMENTS=', COALESCE((
            SELECT GROUP_CONCAT(CONCAT(wp.WorkflowParticipantID, ':', rd.Code)
                                ORDER BY wp.WorkflowParticipantID SEPARATOR ',')
            FROM WorkflowParticipant wp
            JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
            JOIN ReferenceData rd ON rd.ReferenceDataID = wp.AssignmentStatusID
            WHERE ws.WorkflowID = p_wf), '-')),

        -- How many approval decisions exist
        CONCAT('DECISIONS=', (
            SELECT COUNT(*)
            FROM ApprovalDecision ad
            JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = ad.WorkflowParticipantID
            JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
            WHERE ws.WorkflowID = p_wf)),

        -- How many signatures exist
        CONCAT('SIGNATURES=', (
            SELECT COUNT(*)
            FROM Signature s
            JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = s.WorkflowParticipantID
            JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
            WHERE ws.WorkflowID = p_wf))

    ) INTO p_snap;
END $$

-- ----------------------------------------------------------------------------
-- sp__ear_expect_reject      (NEGATIVE test)
--   Runs p_stmt, which we EXPECT to be blocked.
--   PASS only if BOTH are true:
--     1. the statement raised an error, and
--     2. the workflow snapshot is identical before and after.
--   The detail text also reports how many audit rows were added (for
--   information only; it is not part of the pass/fail decision).
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__ear_expect_reject $$
CREATE PROCEDURE sp__ear_expect_reject(IN p_area VARCHAR(20), IN p_name VARCHAR(200),
                                       IN p_stmt TEXT, IN p_wf BIGINT UNSIGNED)
BEGIN
    DECLARE v_rejected     BOOLEAN DEFAULT FALSE;   -- did the statement error?
    DECLARE v_msg          TEXT    DEFAULT NULL;    -- the error message, if any
    DECLARE v_before       TEXT;                    -- snapshot before
    DECLARE v_after        TEXT;                    -- snapshot after
    DECLARE v_audit_before INT DEFAULT 0;
    DECLARE v_audit_after  INT DEFAULT 0;

    -- Step 1: photograph the state before.
    CALL sp__ear_snapshot(p_wf, v_before);
    SELECT COUNT(*) INTO v_audit_before FROM AuditLog;

    -- Step 2: run the statement; if it errors, remember that instead of crashing.
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_rejected = TRUE;
        END;

        SET @ear_stmt = p_stmt;
        PREPARE ear_s FROM @ear_stmt;
        EXECUTE ear_s;
        DEALLOCATE PREPARE ear_s;
    END;

    -- Step 3: photograph the state after.
    CALL sp__ear_snapshot(p_wf, v_after);
    SELECT COUNT(*) INTO v_audit_after FROM AuditLog;

    -- Step 4: PASS = it errored AND nothing moved.
    CALL sp__ear_check(p_area, p_name,
        v_rejected AND v_before = v_after,
        CONCAT('Error raised: ', COALESCE(v_msg, '(NONE - action was NOT rejected)'),
               ' || State unchanged: ', IF(v_before = v_after, 'yes', 'NO'),
               ' || State: ', v_after,
               ' || Audit rows added: ', v_audit_after - v_audit_before));
END $$

-- ----------------------------------------------------------------------------
-- sp__ear_expect_ok          (POSITIVE test)
--   Runs p_stmt, which we EXPECT to work. PASS only if it raised no error.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__ear_expect_ok $$
CREATE PROCEDURE sp__ear_expect_ok(IN p_area VARCHAR(20), IN p_name VARCHAR(200), IN p_stmt TEXT)
BEGIN
    DECLARE v_failed BOOLEAN DEFAULT FALSE;
    DECLARE v_msg    TEXT    DEFAULT NULL;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_failed = TRUE;
        END;

        SET @ear_stmt = p_stmt;
        PREPARE ear_s FROM @ear_stmt;
        EXECUTE ear_s;
        DEALLOCATE PREPARE ear_s;
    END;

    CALL sp__ear_check(p_area, p_name, NOT v_failed,
                       COALESCE(v_msg, 'Executed without error'));
END $$

-- ----------------------------------------------------------------------------
-- sp__ear_make_doc
--   Creates a brand-new DRAFT/INTERNAL document owned by Olivia, plus its
--   version 1 (via the real sp_create_document_version).
--   OUT o_doc = new DocumentID, OUT o_ver = new DocumentVersionID.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__ear_make_doc $$
CREATE PROCEDURE sp__ear_make_doc(IN p_title VARCHAR(200),
                                  OUT o_doc BIGINT UNSIGNED, OUT o_ver BIGINT UNSIGNED)
BEGIN
    DECLARE v_owner  BIGINT UNSIGNED;
    DECLARE v_status BIGINT UNSIGNED;
    DECLARE v_class  BIGINT UNSIGNED;

    -- Look up the owner and the DRAFT / INTERNAL reference values.
    SELECT UserID INTO v_owner FROM `User` WHERE Email = 'olivia.brooks@initech.example' LIMIT 1;
    SELECT ReferenceDataID INTO v_status FROM ReferenceData
        WHERE DomainName = 'DOCUMENT_STATUS' AND Code = 'DRAFT' LIMIT 1;
    SELECT ReferenceDataID INTO v_class FROM ReferenceData
        WHERE DomainName = 'DOCUMENT_CLASSIFICATION' AND Code = 'INTERNAL' LIMIT 1;

    -- Create the document.
    INSERT INTO Document (Title, BusinessDescription, OwnerUserID, ClassificationID, LifecycleStatusID)
    VALUES (p_title, 'Isolated document for the resiliency demo.', v_owner, v_class, v_status);
    SET o_doc = LAST_INSERT_ID();

    -- Create its version 1 through the real procedure.
    CALL sp_create_document_version(v_owner, o_doc, 1, 'EAR demo version 1');

    SELECT DocumentVersionID INTO o_ver FROM DocumentVersion
        WHERE DocumentID = o_doc AND VersionNumber = 1 LIMIT 1;
END $$

-- ----------------------------------------------------------------------------
-- sp__ear_initiate
--   Starts the 3-step workflow on a document version using the real
--   sp_initiate_workflow:
--       step 1 REVIEW    -> Marcus (Reviewer)   due in  7 days
--       step 2 APPROVAL  -> Daniel (Approver)   due in 14 days
--       step 3 SIGNATURE -> Sofia  (Signer)     due in 21 days
--   OUT parameters return the workflow id and the three assignment ids.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__ear_initiate $$
CREATE PROCEDURE sp__ear_initiate(IN p_doc BIGINT UNSIGNED, IN p_ver BIGINT UNSIGNED,
    OUT o_wf BIGINT UNSIGNED, OUT o_review BIGINT UNSIGNED,
    OUT o_approval BIGINT UNSIGNED, OUT o_sign BIGINT UNSIGNED)
BEGIN
    DECLARE v_owner, v_marcus, v_daniel, v_sofia BIGINT UNSIGNED;
    DECLARE v_rev_role, v_app_role, v_sig_role   BIGINT UNSIGNED;
    DECLARE v_steps JSON;

    -- Look up the people and the roles.
    SELECT OwnerUserID INTO v_owner FROM Document WHERE DocumentID = p_doc;
    SELECT UserID INTO v_marcus FROM `User` WHERE Email = 'marcus.reed@initech.example' LIMIT 1;
    SELECT UserID INTO v_daniel FROM `User` WHERE Email = 'daniel.cho@initech.example' LIMIT 1;
    SELECT UserID INTO v_sofia  FROM `User` WHERE Email = 'sofia.alvarez@initech.example' LIMIT 1;
    SELECT RoleID INTO v_rev_role FROM Role WHERE RoleName = 'Reviewer' LIMIT 1;
    SELECT RoleID INTO v_app_role FROM Role WHERE RoleName = 'Approver' LIMIT 1;
    SELECT RoleID INTO v_sig_role FROM Role WHERE RoleName = 'Signer' LIMIT 1;

    -- Describe the three steps as a JSON array.
    SET v_steps = JSON_ARRAY(

        JSON_OBJECT('sequence_number', 1, 'step_type', 'REVIEW',
            'due_date', DATE_FORMAT(DATE_ADD(NOW(), INTERVAL 7 DAY), '%Y-%m-%d %H:%i:%s'),
            'participants', JSON_ARRAY(JSON_OBJECT('user_id', v_marcus, 'role_id', v_rev_role,
                                                   'action', 'REVIEW', 'required', 1))),

        JSON_OBJECT('sequence_number', 2, 'step_type', 'APPROVAL',
            'due_date', DATE_FORMAT(DATE_ADD(NOW(), INTERVAL 14 DAY), '%Y-%m-%d %H:%i:%s'),
            'participants', JSON_ARRAY(JSON_OBJECT('user_id', v_daniel, 'role_id', v_app_role,
                                                   'action', 'APPROVAL', 'required', 1))),

        JSON_OBJECT('sequence_number', 3, 'step_type', 'SIGNATURE',
            'due_date', DATE_FORMAT(DATE_ADD(NOW(), INTERVAL 21 DAY), '%Y-%m-%d %H:%i:%s'),
            'participants', JSON_ARRAY(JSON_OBJECT('user_id', v_sofia, 'role_id', v_sig_role,
                                                   'action', 'SIGNATURE', 'required', 1))));

    -- Start the workflow through the real procedure.
    CALL sp_initiate_workflow(v_owner, p_doc, p_ver, 'FULL_REVIEW_APPROVAL_SIGNATURE',
                              DATE_ADD(NOW(), INTERVAL 30 DAY), v_steps);

    -- Report back the new workflow id and the three assignment ids.
    SELECT MAX(WorkflowID) INTO o_wf FROM Workflow WHERE DocumentVersionID = p_ver;

    SELECT wp.WorkflowParticipantID INTO o_review FROM WorkflowParticipant wp
        JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
        WHERE ws.WorkflowID = o_wf AND ws.SequenceNumber = 1 LIMIT 1;
    SELECT wp.WorkflowParticipantID INTO o_approval FROM WorkflowParticipant wp
        JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
        WHERE ws.WorkflowID = o_wf AND ws.SequenceNumber = 2 LIMIT 1;
    SELECT wp.WorkflowParticipantID INTO o_sign FROM WorkflowParticipant wp
        JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
        WHERE ws.WorkflowID = o_wf AND ws.SequenceNumber = 3 LIMIT 1;
END $$

-- ----------------------------------------------------------------------------
-- sp__ear_new_workflow
--   One-shot shortcut: make_doc, then initiate.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__ear_new_workflow $$
CREATE PROCEDURE sp__ear_new_workflow(IN p_title VARCHAR(200),
    OUT o_doc BIGINT UNSIGNED, OUT o_ver BIGINT UNSIGNED, OUT o_wf BIGINT UNSIGNED,
    OUT o_review BIGINT UNSIGNED, OUT o_approval BIGINT UNSIGNED, OUT o_sign BIGINT UNSIGNED)
BEGIN
    CALL sp__ear_make_doc(p_title, o_doc, o_ver);
    CALL sp__ear_initiate(o_doc, o_ver, o_wf, o_review, o_approval, o_sign);
END $$

-- ----------------------------------------------------------------------------
-- sp__ear_test_initiation_rollback      (the engine behind Part 2)
--
--   Proves: if starting a workflow breaks PARTWAY, the database undoes
--   EVERYTHING, and a corrected retry on the same document then succeeds.
--
--   p_mode chooses HOW the start is made to break:
--     'FK'      step 2 refers to a role id that does not exist, so a foreign
--               key refuses it (a "natural" failure).
--     'TRIGGER' step 2 is perfectly valid, but its due date is the magic value
--               2099-12-31 23:59:59, which the temporary trigger
--               trg_Test_EAR_ForceFailure rejects (a "forced" failure).
--
--   Flow (two scoreboard checks per call):
--     A. Create a fresh document.
--     B. Count rows in every affected table ("before").
--     C. Call sp_initiate_workflow with 2 steps, the second of which is bad.
--        Step 1 is inserted first; the failure on step 2 happens mid-way.
--     D. Count rows again ("after").
--     E. CHECK: it failed, and every "before" equals its "after"
--        (no partial workflow, steps, assignments, audit rows, or version lock).
--     F. Retry on the SAME document with good input (sp__ear_initiate).
--     G. CHECK: the retry worked and produced 1 workflow, 3 steps, 3 assignments.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__ear_test_initiation_rollback $$
CREATE PROCEDURE sp__ear_test_initiation_rollback(IN p_mode VARCHAR(10))
BEGIN
    -- People, roles, document ids
    DECLARE v_doc, v_ver, v_owner, v_marcus, v_daniel, v_rev_role, v_app_role, v_role2 BIGINT UNSIGNED;
    -- Ids returned by the retry
    DECLARE v_w, v_r, v_a, v_s BIGINT UNSIGNED;
    -- Due date used for step 2 (normal, or the trigger's magic value)
    DECLARE v_due2 VARCHAR(30);
    -- Outcome flags and messages
    DECLARE v_failed       BOOLEAN DEFAULT FALSE;
    DECLARE v_retry_failed BOOLEAN DEFAULT FALSE;
    DECLARE v_msg          TEXT DEFAULT NULL;
    DECLARE v_retry_msg    TEXT DEFAULT NULL;
    -- Row counts: _b = before the failed attempt, _a = after it
    --   wf = workflows, st = steps, pt = assignments, au = audit rows
    DECLARE v_wf_b, v_wf_a, v_st_b, v_st_a, v_pt_b, v_pt_a, v_au_b, v_au_a INT DEFAULT 0;
    -- Row counts after the successful retry (f = final)
    DECLARE v_wf_f, v_st_f, v_pt_f INT DEFAULT 0;
    -- Version status and lock time, before (_b) and after (_a)
    DECLARE v_vs_b, v_vs_a VARCHAR(50);
    DECLARE v_lk_b, v_lk_a VARCHAR(40);

    -- A. Fresh document, so earlier tests cannot interfere.
    CALL sp__ear_make_doc(CONCAT('EAR Demo - Rollback Agreement ', p_mode), v_doc, v_ver);

    SELECT OwnerUserID INTO v_owner FROM Document WHERE DocumentID = v_doc;
    SELECT UserID INTO v_marcus FROM `User` WHERE Email = 'marcus.reed@initech.example' LIMIT 1;
    SELECT UserID INTO v_daniel FROM `User` WHERE Email = 'daniel.cho@initech.example' LIMIT 1;
    SELECT RoleID INTO v_rev_role FROM Role WHERE RoleName = 'Reviewer' LIMIT 1;
    SELECT RoleID INTO v_app_role FROM Role WHERE RoleName = 'Approver' LIMIT 1;

    -- Decide how step 2 will be bad:
    --   FK mode:      role id 999999999 (does not exist), normal due date
    --   TRIGGER mode: real Approver role, but the trigger's magic due date
    SET v_role2 = IF(p_mode = 'FK', 999999999, v_app_role);
    SET v_due2  = IF(p_mode = 'FK',
                     DATE_FORMAT(DATE_ADD(NOW(), INTERVAL 14 DAY), '%Y-%m-%d %H:%i:%s'),
                     '2099-12-31 23:59:59');

    -- B. Count everything BEFORE the failed attempt.
    SELECT COUNT(*) INTO v_wf_b FROM Workflow WHERE DocumentID = v_doc;

    SELECT COUNT(*) INTO v_st_b
    FROM WorkflowStep ws
    JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
    WHERE w.DocumentID = v_doc;

    SELECT COUNT(*) INTO v_pt_b
    FROM WorkflowParticipant wp
    JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
    WHERE w.DocumentID = v_doc;

    SELECT COUNT(*) INTO v_au_b FROM AuditLog;

    SELECT rd.Code, COALESCE(CAST(dv.LockedDateTime AS CHAR), 'NULL') INTO v_vs_b, v_lk_b
    FROM DocumentVersion dv
    JOIN ReferenceData rd ON rd.ReferenceDataID = dv.CurrentVersionStatusID
    WHERE dv.DocumentVersionID = v_ver;

    -- C. The doomed attempt: a 2-step workflow whose step 2 is bad.
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_failed = TRUE;
        END;

        CALL sp_initiate_workflow(v_owner, v_doc, v_ver, 'FULL_REVIEW_APPROVAL_SIGNATURE',
            DATE_ADD(NOW(), INTERVAL 30 DAY),
            JSON_ARRAY(

                -- Step 1: perfectly good
                JSON_OBJECT('sequence_number', 1, 'step_type', 'REVIEW',
                    'due_date', DATE_FORMAT(DATE_ADD(NOW(), INTERVAL 7 DAY), '%Y-%m-%d %H:%i:%s'),
                    'participants', JSON_ARRAY(JSON_OBJECT('user_id', v_marcus,
                        'role_id', v_rev_role, 'action', 'REVIEW', 'required', 1))),

                -- Step 2: bad (unknown role, or trigger-rejected due date)
                JSON_OBJECT('sequence_number', 2, 'step_type', 'APPROVAL',
                    'due_date', v_due2,
                    'participants', JSON_ARRAY(JSON_OBJECT('user_id', v_daniel,
                        'role_id', v_role2, 'action', 'APPROVAL', 'required', 1)))));
    END;

    -- D. Count everything AFTER the failed attempt.
    SELECT COUNT(*) INTO v_wf_a FROM Workflow WHERE DocumentID = v_doc;

    SELECT COUNT(*) INTO v_st_a
    FROM WorkflowStep ws
    JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
    WHERE w.DocumentID = v_doc;

    SELECT COUNT(*) INTO v_pt_a
    FROM WorkflowParticipant wp
    JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
    WHERE w.DocumentID = v_doc;

    SELECT COUNT(*) INTO v_au_a FROM AuditLog;

    SELECT rd.Code, COALESCE(CAST(dv.LockedDateTime AS CHAR), 'NULL') INTO v_vs_a, v_lk_a
    FROM DocumentVersion dv
    JOIN ReferenceData rd ON rd.ReferenceDataID = dv.CurrentVersionStatusID
    WHERE dv.DocumentVersionID = v_ver;

    -- E. CHECK: it failed AND nothing at all changed.
    CALL sp__ear_check('RESILIENCY',
        CONCAT('[', p_mode, '] Failed multi-step initiation leaves no partial workflow, steps, assignments, audit rows or version lock'),
        v_failed AND v_wf_b = v_wf_a AND v_st_b = v_st_a AND v_pt_b = v_pt_a
            AND v_au_b = v_au_a AND v_vs_b = v_vs_a AND v_lk_b = v_lk_a,
        CONCAT('Error: ', COALESCE(v_msg, '(none - failure was NOT raised)'),
               ' || workflows ', v_wf_b, '->', v_wf_a, ', steps ', v_st_b, '->', v_st_a,
               ', assignments ', v_pt_b, '->', v_pt_a, ', audit ', v_au_b, '->', v_au_a,
               ', version ', v_vs_b, '->', v_vs_a, ', locked ', v_lk_b, '->', v_lk_a));

    -- F. RETRY with corrected input on the SAME document and version.
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_retry_msg = MESSAGE_TEXT;
            SET v_retry_failed = TRUE;
        END;

        CALL sp__ear_initiate(v_doc, v_ver, v_w, v_r, v_a, v_s);
    END;

    SELECT COUNT(*) INTO v_wf_f FROM Workflow WHERE DocumentID = v_doc;

    SELECT COUNT(*) INTO v_st_f
    FROM WorkflowStep ws
    JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
    WHERE w.DocumentID = v_doc;

    SELECT COUNT(*) INTO v_pt_f
    FROM WorkflowParticipant wp
    JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
    WHERE w.DocumentID = v_doc;

    -- G. CHECK: retry succeeded and built a complete workflow (1 / 3 / 3).
    CALL sp__ear_check('RESILIENCY',
        CONCAT('[', p_mode, '] Retry with corrected input succeeds after the rolled-back attempt'),
        NOT v_retry_failed AND v_wf_f = 1 AND v_st_f = 3 AND v_pt_f = 3,
        CONCAT('Retry error: ', COALESCE(v_retry_msg, '(none)'),
               ' || workflows=', v_wf_f, ', steps=', v_st_f, ', assignments=', v_pt_f));
END $$

-- ----------------------------------------------------------------------------
-- sp__ear_test_correction               (the engine behind Part 4)
--
--   Proves: after a REJECTION, the fix is a brand-new version plus a
--   brand-new workflow, while the old rejected record is kept as history.
--
--   p_doc     the document whose workflow was rejected
--   p_old_wf  that rejected workflow
--
--   Flow (one scoreboard check):
--     1. Owner creates version 2 of the document.
--     2. A new workflow is started on version 2.
--     3. CHECK: no error; the document now has 2 workflows; the old workflow
--        is STILL 'REJECTED'; version 1 is STILL 'LOCKED'.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__ear_test_correction $$
CREATE PROCEDURE sp__ear_test_correction(IN p_doc BIGINT UNSIGNED, IN p_old_wf BIGINT UNSIGNED)
BEGIN
    DECLARE v_owner, v_v2, v_w, v_r, v_a, v_s BIGINT UNSIGNED;
    DECLARE v_failed BOOLEAN DEFAULT FALSE;
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE v_old_status VARCHAR(50);     -- status of the old workflow afterwards
    DECLARE v_v1_status  VARCHAR(50);     -- status of version 1 afterwards
    DECLARE v_wf_count   INT DEFAULT 0;   -- workflows on the document afterwards

    SELECT OwnerUserID INTO v_owner FROM Document WHERE DocumentID = p_doc;

    -- Steps 1 + 2: create version 2, then start a fresh workflow on it.
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_failed = TRUE;
        END;

        CALL sp_create_document_version(v_owner, p_doc, 2, 'Corrected after rejection');

        SELECT DocumentVersionID INTO v_v2
        FROM DocumentVersion
        WHERE DocumentID = p_doc AND VersionNumber = 2
        LIMIT 1;

        CALL sp__ear_initiate(p_doc, v_v2, v_w, v_r, v_a, v_s);
    END;

    -- Gather the facts for the check.
    SELECT rd.Code INTO v_old_status
    FROM Workflow w
    JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID
    WHERE w.WorkflowID = p_old_wf;

    SELECT rd.Code INTO v_v1_status
    FROM DocumentVersion dv
    JOIN ReferenceData rd ON rd.ReferenceDataID = dv.CurrentVersionStatusID
    WHERE dv.DocumentID = p_doc AND dv.VersionNumber = 1;

    SELECT COUNT(*) INTO v_wf_count FROM Workflow WHERE DocumentID = p_doc;

    -- Step 3: the check.
    CALL sp__ear_check('RESILIENCY',
        'Correction after rejection: new version v2 + new workflow; rejected history preserved',
        NOT v_failed AND v_wf_count = 2 AND v_old_status = 'REJECTED' AND v_v1_status = 'LOCKED',
        CONCAT('Error: ', COALESCE(v_msg, '(none)'),
               ' || workflows on document=', v_wf_count,
               ' || original workflow still ', COALESCE(v_old_status, '?'),
               ' || v1 still ', COALESCE(v_v1_status, '?')));
END $$

-- ----------------------------------------------------------------------------
-- trg_Test_EAR_ForceFailure      (TEMPORARY, test-only failure injector)
--   Fires before every insert into WorkflowParticipant. If the new row's
--   due date is the magic value 2099-12-31 23:59:59, it raises an error.
--   This lets Part 2 crash a transaction in the MIDDLE (step 1 already
--   inserted, step 2 fails) to prove the database cleans up after itself.
--   It is dropped again right after Part 2 and again at the end of the file.
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_Test_EAR_ForceFailure
BEFORE INSERT ON WorkflowParticipant
FOR EACH ROW
BEGIN
    IF NEW.DueDateTime = '2099-12-31 23:59:59' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Forced TEST failure during second participant insert.';
    END IF;
END $$

DELIMITER ;


-- ============================================================================
-- ============================================================================
--                         THE DEMO STARTS HERE
-- ============================================================================
-- ============================================================================


-- ============================================================================
-- PART 1 - SETUP
--   Look up the cast and build four separate workflows, one per scenario.
-- ============================================================================
SELECT '=== RESILIENCY DEMO - PART 1: SETUP ===' AS Section;

-- The cast, found by email address.
SET @u_owner  = (SELECT UserID FROM `User` WHERE Email = 'olivia.brooks@initech.example' LIMIT 1);
SET @u_marcus = (SELECT UserID FROM `User` WHERE Email = 'marcus.reed@initech.example' LIMIT 1);
SET @u_daniel = (SELECT UserID FROM `User` WHERE Email = 'daniel.cho@initech.example' LIMIT 1);
SET @u_sofia  = (SELECT UserID FROM `User` WHERE Email = 'sofia.alvarez@initech.example' LIMIT 1);

-- Four independent workflows. Each call outputs, in order:
--   document, version, workflow, review assignment, approval assignment, signature assignment
--   WF1: guards (Part 3)     WF2: rejection + correction (Part 4)
--   WF3: cancellation (Part 5)   WF4: expiration (Part 6)
CALL sp__ear_new_workflow('EAR Demo - Guards Agreement',       @d1, @v1, @w1, @r1, @a1, @s1);
CALL sp__ear_new_workflow('EAR Demo - Rejection Agreement',    @d2, @v2, @w2, @r2, @a2, @s2);
CALL sp__ear_new_workflow('EAR Demo - Cancellation Agreement', @d3, @v3, @w3, @r3, @a3, @s3);
CALL sp__ear_new_workflow('EAR Demo - Expiration Agreement',   @d4, @v4, @w4, @r4, @a4, @s4);


-- ============================================================================
-- PART 2 - FAILED MULTI-STEP TRANSACTION + RETRY
--   Claim: a start that breaks halfway leaves NO trace, and a corrected retry
--   works. The work is done by sp__ear_test_initiation_rollback (explained in
--   the helper section). Each call below adds 2 checks to the scoreboard.
--   CHECKS 1-4
-- ============================================================================
SELECT '=== PART 2: CONTROLLED FAILURE OF A MULTI-STEP TRANSACTION ===' AS Section;

-- 2.1  CHECKS 1-2:  a "natural" failure.
--      Step 2 names a role that does not exist -> a foreign key refuses it.
SELECT '2.1 Natural failure: step 2 references a non-existent role' AS Section;
CALL sp__ear_test_initiation_rollback('FK');

-- 2.2  CHECKS 3-4:  a "forced" failure.
--      Step 1 inserts fine, then the temporary trigger blows up on step 2.
SELECT '2.2 Forced mid-transaction failure: step 1 inserted, trigger fails step 2 insert' AS Section;
CALL sp__ear_test_initiation_rollback('TRIGGER');

-- Remove the test-only trigger immediately; nothing below needs it.
DROP TRIGGER IF EXISTS trg_Test_EAR_ForceFailure;


-- ============================================================================
-- PART 3 - GUARDS (out-of-sequence, duplicate, wrong version)
--   Workflow: WF1.  We walk the happy path one step at a time, and after
--   each step try to repeat or skip ahead. The repeat/skip must be refused.
--
--   Timeline:
--     early approval (refused) -> early signature (refused)
--     -> review OK -> review again (refused)
--     -> approval OK -> approval again (refused)
--     -> signature on WRONG version (refused) -> signature OK
--     -> signature again (refused) -> workflow is cleanly COMPLETED
--   CHECKS 5-14
-- ============================================================================
SELECT '=== PART 3: GUARDS ON WF1 ===' AS Section;

-- ----- Out of sequence: nothing is ACTIVE except the review ----------------

-- CHECK 5:  Daniel tries to approve before the review is done.
--   Runs: CALL sp_record_approval_decision(<Daniel's approval>, <Daniel>,
--                  'APPROVED', 'too early', NULL)
CALL sp__ear_expect_reject('RESILIENCY',
    'Out-of-sequence: approval before the review step is complete is rejected',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_daniel, ',''APPROVED'',''too early'',NULL)'),
    @w1);

-- CHECK 6:  Sofia tries to sign before approval is done.
--   Runs: CALL sp_record_signature(<Sofia's signature>, <Sofia>, <v1>,
--                  'SIGNED', 'TYPED_NAME', 'too early')
CALL sp__ear_expect_reject('RESILIENCY',
    'Out-of-sequence: signature before approval is complete is rejected',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_sofia, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''too early'')'),
    @w1);

-- ----- Review step ----------------------------------------------------------

-- CHECK 7:  Marcus completes his review normally.
CALL sp__ear_expect_ok('RESILIENCY', 'Review completed normally',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r1, ',', @u_marcus, ')'));

-- CHECK 8:  the exact same review call again (a replay) must be refused.
CALL sp__ear_expect_reject('RESILIENCY',
    'Duplicate review completion (replay) is rejected',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r1, ',', @u_marcus, ')'),
    @w1);

-- ----- Approval step --------------------------------------------------------

-- CHECK 9:  Daniel approves normally.
CALL sp__ear_expect_ok('RESILIENCY', 'Approval recorded normally',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_daniel, ',''APPROVED'',''guards demo'',NULL)'));

-- CHECK 10:  approving a second time (double-click / replay) must be refused.
--   (sp__ear_expect_reject also proves the decision count did not change.)
CALL sp__ear_expect_reject('RESILIENCY',
    'Duplicate approval (double-click / replay) is rejected; still exactly 1 decision',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_daniel, ',''APPROVED'',''replay'',NULL)'),
    @w1);

-- ----- Signature step -------------------------------------------------------

-- CHECK 11:  Sofia tries to sign, but names version 2 (@v2, which belongs to
--            a DIFFERENT document) instead of this workflow's version 1.
CALL sp__ear_expect_reject('RESILIENCY',
    'Signature bound to the WRONG document version is rejected',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_sofia, ',', @v2, ',''SIGNED'',''TYPED_NAME'',''wrong-version'')'),
    @w1);

-- CHECK 12:  Sofia signs the correct version. Must succeed.
CALL sp__ear_expect_ok('RESILIENCY', 'Signature recorded normally against the correct version',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_sofia, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''EAR-RES-SIG-1'')'));

-- CHECK 13:  signing again on the already-signed assignment must be refused.
CALL sp__ear_expect_reject('RESILIENCY',
    'Duplicate signature on an already-signed assignment is rejected',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_sofia, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''replay'')'),
    @w1);

-- CHECK 14:  after all those bad attempts, WF1 should be cleanly COMPLETED.
SET @ear_t = (
    SELECT rd.Code
    FROM Workflow w
    JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID
    WHERE w.WorkflowID = @w1);

CALL sp__ear_check('RESILIENCY', 'After replays and bad attempts, WF1 is still cleanly COMPLETED',
    @ear_t = 'COMPLETED',
    CONCAT('Workflow status = ', COALESCE(@ear_t, '?')));


-- ============================================================================
-- PART 4 - BUSINESS REJECTION AND CORRECTION
--   Workflow: WF2.  A rejection is a normal business outcome, not an error.
--
--   Timeline:
--     review OK -> reject WITHOUT reason (refused)
--     -> reject WITH reason (accepted; workflow becomes REJECTED)
--     -> signing a rejected workflow (refused)
--     -> correction: new version v2 + new workflow, old history preserved
--   CHECKS 15-20
-- ============================================================================
SELECT '=== PART 4: REJECTION (BUSINESS OUTCOME) AND CORRECTION ===' AS Section;

-- CHECK 15:  Marcus completes the review so Daniel's step becomes ACTIVE.
CALL sp__ear_expect_ok('RESILIENCY', 'WF2: Marcus completes review',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r2, ',', @u_marcus, ')'));

-- CHECK 16:  Daniel tries to REJECT but gives no reason (last argument NULL).
--   Runs: CALL sp_record_approval_decision(<Daniel's approval>, <Daniel>,
--                  'REJECTED', 'no reason given', NULL)
CALL sp__ear_expect_reject('RESILIENCY',
    'WF2: rejection WITHOUT a reason is refused; nothing changes',
    CONCAT('CALL sp_record_approval_decision(', @a2, ',', @u_daniel, ',''REJECTED'',''no reason given'',NULL)'),
    @w2);

-- CHECK 17:  Daniel rejects again, this time with a reason (last argument).
--   Runs: CALL sp_record_approval_decision(<Daniel's approval>, <Daniel>,
--                  'REJECTED', 'EAR demo rejection', 'Terms unacceptable')
CALL sp__ear_expect_ok('RESILIENCY',
    'WF2: rejection WITH a reason is accepted as a valid business outcome (not a crash)',
    CONCAT('CALL sp_record_approval_decision(', @a2, ',', @u_daniel, ',''REJECTED'',''EAR demo rejection'',''Terms unacceptable'')'));

-- CHECK 18:  confirm the outcome in the data.
--   EXPECT: workflow REJECTED, exactly 1 decision, and the stored reason.
SET @ear_t = (
    SELECT CONCAT(wr.Code,
                  ' / decisions=', (SELECT COUNT(*) FROM ApprovalDecision
                                    WHERE WorkflowParticipantID = @a2),
                  ' / reason=',    COALESCE(ad.RejectionReason, '(none)'))
    FROM Workflow w
    JOIN ReferenceData wr ON wr.ReferenceDataID = w.WorkflowStatusID
    LEFT JOIN ApprovalDecision ad ON ad.WorkflowParticipantID = @a2
    WHERE w.WorkflowID = @w2);

CALL sp__ear_check('RESILIENCY', 'WF2 ends REJECTED with the reason stored',
    @ear_t = 'REJECTED / decisions=1 / reason=Terms unacceptable',
    @ear_t);

-- CHECK 19:  Sofia tries to sign a workflow that was already rejected.
CALL sp__ear_expect_reject('RESILIENCY', 'Signing a REJECTED workflow is refused',
    CONCAT('CALL sp_record_signature(', @s2, ',', @u_sofia, ',', @v2, ',''SIGNED'',''TYPED_NAME'',''after rejection'')'),
    @w2);

-- CHECK 20:  the correction (new v2 + new workflow; old history kept).
--   See sp__ear_test_correction in the helper section.
CALL sp__ear_test_correction(@d2, @w2);


-- ============================================================================
-- PART 5 - CANCELLATION
--   Workflow: WF3.  We update ONLY the Workflow row; a trigger must cascade
--   the CANCELLED status down to every step and assignment.
--   CHECKS 21-23
-- ============================================================================
SELECT '=== PART 5: CANCELLATION (trigger cascade; later actions refused) ===' AS Section;

-- CHECK 21:  cancel the workflow with a plain UPDATE of the Workflow row.
--   Runs: UPDATE Workflow
--         SET WorkflowStatusID = <CANCELLED>, CancellationDateTime = NOW(),
--             CancellationReason = 'EAR demo: cancelled'
--         WHERE WorkflowID = <WF3>
CALL sp__ear_expect_ok('RESILIENCY', 'WF3: cancel workflow (only the Workflow row is updated)',
    CONCAT(
        'UPDATE Workflow SET WorkflowStatusID=(SELECT ReferenceDataID FROM ReferenceData ',
        'WHERE DomainName=''WORKFLOW_STATUS'' AND Code=''CANCELLED''), ',
        'CancellationDateTime=NOW(), CancellationReason=''EAR demo: cancelled'' WHERE WorkflowID=', @w3));

-- CHECK 22:  the trigger should have cancelled everything underneath.
--   EXPECT: 0 assignments and 0 steps that are NOT CANCELLED.
SET @ear_out = (
        SELECT COUNT(*)
        FROM WorkflowParticipant wp
        JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
        JOIN ReferenceData rd ON rd.ReferenceDataID = wp.AssignmentStatusID
        WHERE ws.WorkflowID = @w3 AND rd.Code <> 'CANCELLED')
    + (
        SELECT COUNT(*)
        FROM WorkflowStep ws
        JOIN ReferenceData rd ON rd.ReferenceDataID = ws.StepStatusID
        WHERE ws.WorkflowID = @w3 AND rd.Code <> 'CANCELLED');

CALL sp__ear_check('RESILIENCY', 'Trigger cascaded CANCELLED to every step and assignment of WF3',
    @ear_out = 0,
    CONCAT('Steps/assignments not CANCELLED: ', @ear_out));

-- CHECK 23:  Marcus tries to do his review on the cancelled workflow.
CALL sp__ear_expect_reject('RESILIENCY', 'Review on a CANCELLED workflow is refused',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r3, ',', @u_marcus, ')'),
    @w3);


-- ============================================================================
-- PART 6 - EXPIRATION
--   Workflow: WF4.  We back-date it so it is overdue, run the real expiry
--   batch procedure, and verify it was closed out and audited.
--   CHECKS 24-27
-- ============================================================================
SELECT '=== PART 6: EXPIRATION (batch procedure; later actions refused) ===' AS Section;

-- CHECK 24:  TEST SETUP ONLY. Pretend WF4 started 2 days ago and expired
--            yesterday, so the expiry job will pick it up.
CALL sp__ear_expect_ok('RESILIENCY', 'WF4: make workflow overdue (test setup only)',
    CONCAT(
        'UPDATE Workflow SET StartDateTime=DATE_SUB(NOW(), INTERVAL 2 DAY), ',
        'ExpirationDateTime=DATE_SUB(NOW(), INTERVAL 1 DAY) WHERE WorkflowID=', @w4));

-- CHECK 25:  run the real expiry batch. NULL means "all overdue workflows",
--            so it may also expire other overdue seeded workflows.
CALL sp__ear_expect_ok('RESILIENCY',
    'sp_expire_workflows runs (batch; may also expire other overdue seeded workflows)',
    'CALL sp_expire_workflows(NULL)');

-- CHECK 26
--   WHAT:   inspect WF4 after the batch.
--   EXPECT: - status is EXPIRED
--           - no step or assignment is still PENDING or ACTIVE
--           - at least one WORKFLOW_EXPIRED audit row exists for WF4
SET @ear_ex = (
    SELECT rd.Code
    FROM Workflow w
    JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID
    WHERE w.WorkflowID = @w4);

SET @ear_out = (
        SELECT COUNT(*)
        FROM WorkflowParticipant wp
        JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
        JOIN ReferenceData rd ON rd.ReferenceDataID = wp.AssignmentStatusID
        WHERE ws.WorkflowID = @w4 AND rd.Code IN ('PENDING', 'ACTIVE'))
    + (
        SELECT COUNT(*)
        FROM WorkflowStep ws
        JOIN ReferenceData rd ON rd.ReferenceDataID = ws.StepStatusID
        WHERE ws.WorkflowID = @w4 AND rd.Code IN ('PENDING', 'ACTIVE'));

SET @ear_exa = (
    SELECT COUNT(*)
    FROM AuditLog
    WHERE EventType = 'WORKFLOW_EXPIRED'
      AND AffectedRecordType = 'Workflow'
      AND AffectedRecordID = @w4);

CALL sp__ear_check('RESILIENCY', 'WF4 is EXPIRED, no outstanding work remains, expiry is audited',
    @ear_ex = 'EXPIRED' AND @ear_out = 0 AND @ear_exa >= 1,
    CONCAT('Status: ', COALESCE(@ear_ex, '?'),
           ' || outstanding: ', @ear_out,
           ' || expiry audit rows: ', @ear_exa));

-- CHECK 27:  Marcus tries to do his review on the expired workflow.
CALL sp__ear_expect_reject('RESILIENCY', 'Review on an EXPIRED workflow is refused',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r4, ',', @u_marcus, ')'),
    @w4);


-- ============================================================================
-- PART 7 - FINAL CONSISTENCY SWEEP
--   After every failure, replay, rejection, cancellation and expiration above,
--   scan the WHOLE database (not just our demo rows) for impossible states.
--   CHECK 28
--
--   Each query counts violations of one rule. All six must be 0.
-- ============================================================================
SELECT '=== PART 7: DATABASE IS STILL CONSISTENT AFTER EVERYTHING ABOVE ===' AS Section;

-- Rule 1: a COMPLETED workflow must not still have open (PENDING/ACTIVE) assignments.
SET @ear_i1 = (
    SELECT COUNT(DISTINCT w.WorkflowID)
    FROM Workflow w
    JOIN ReferenceData wr ON wr.ReferenceDataID = w.WorkflowStatusID
    JOIN WorkflowStep st ON st.WorkflowID = w.WorkflowID
    JOIN WorkflowParticipant wp ON wp.WorkflowStepID = st.WorkflowStepID
    JOIN ReferenceData ps ON ps.ReferenceDataID = wp.AssignmentStatusID
    WHERE wr.Code = 'COMPLETED'
      AND ps.Code IN ('PENDING', 'ACTIVE'));

-- Rule 2: a signature must be bound to the same version its workflow is about.
SET @ear_i2 = (
    SELECT COUNT(*)
    FROM Signature s
    JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = s.WorkflowParticipantID
    JOIN WorkflowStep st ON st.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w ON w.WorkflowID = st.WorkflowID
    WHERE s.DocumentVersionID <> w.DocumentVersionID);

-- Rule 3: every assignment must be held by a person who actually has that role.
SET @ear_i3 = (
    SELECT COUNT(*)
    FROM WorkflowParticipant wp
    LEFT JOIN UserRole ur ON ur.UserID = wp.UserID AND ur.RoleID = wp.RoleID
    WHERE ur.UserID IS NULL);

-- Rule 4: every REJECTED decision must carry a non-blank reason.
SET @ear_i4 = (
    SELECT COUNT(*)
    FROM ApprovalDecision ad
    JOIN ReferenceData dv ON dv.ReferenceDataID = ad.DecisionValueID
    WHERE dv.Code = 'REJECTED'
      AND (ad.RejectionReason IS NULL OR TRIM(ad.RejectionReason) = ''));

-- Rule 5: every CANCELLED workflow must carry a non-blank reason.
SET @ear_i5 = (
    SELECT COUNT(*)
    FROM Workflow w
    JOIN ReferenceData wr ON wr.ReferenceDataID = w.WorkflowStatusID
    WHERE wr.Code = 'CANCELLED'
      AND (w.CancellationReason IS NULL OR TRIM(w.CancellationReason) = ''));

-- Rule 6: no workflow may exist without steps (that would be a half-made start).
SET @ear_i6 = (
    SELECT COUNT(*)
    FROM Workflow w
    LEFT JOIN WorkflowStep st ON st.WorkflowID = w.WorkflowID
    WHERE st.WorkflowStepID IS NULL);

CALL sp__ear_check('RESILIENCY', 'Global invariants hold after all tests (see detail)',
    @ear_i1 = 0 AND @ear_i2 = 0 AND @ear_i3 = 0 AND @ear_i4 = 0 AND @ear_i5 = 0 AND @ear_i6 = 0,
    CONCAT('completed-with-open-work=', @ear_i1,
           ', signature/version mismatches=', @ear_i2,
           ', assignment/role mismatches=', @ear_i3,
           ', rejections without reason=', @ear_i4,
           ', cancellations without reason=', @ear_i5,
           ', workflows with no steps (partial inits)=', @ear_i6));

-- Tip: re-run 05_validation/020_data_validation.sql now; it must still PASS
-- with all demo data included.

-- ----------------------------------------------------------------------------
-- MANUAL CONCURRENCY / ISOLATION DEMO (needs two terminals; not automated)
--   Session A:  START TRANSACTION;
--               CALL sp_record_approval_decision(<participant>, <user>, 'APPROVED', 'A', NULL);
--               -- do NOT commit yet
--   Session B:  CALL sp_record_approval_decision(<same participant>, <same user>, 'APPROVED', 'B', NULL);
--               -- blocks on the row lock (or errors) until A finishes
--   Session A:  COMMIT;
--   Session B:  now fails as a duplicate; verify exactly ONE ApprovalDecision row exists.
-- ----------------------------------------------------------------------------


-- ============================================================================
-- SCOREBOARD
--   If every row shows Failed = 0, every resiliency rule held.
-- ============================================================================
SELECT '=== RESILIENCY SCOREBOARD ===' AS Section;
SELECT COALESCE(area, 'ALL') AS Area,
       SUM(result = 'PASS')  AS Passed,
       SUM(result = 'FAIL')  AS Failed,
       COUNT(*)              AS Total
FROM ear_results
GROUP BY area WITH ROLLUP;

SELECT '=== FAILURES (should be empty) ===' AS Section;
SELECT seq, test_name, detail
FROM ear_results
WHERE result = 'FAIL'
ORDER BY seq;

SELECT '=== FULL RESULT LOG ===' AS Section;
SELECT seq, result, test_name
FROM ear_results
ORDER BY seq;


-- ============================================================================
-- CLEAN UP
--   Remove the test trigger and helper procedures; restore the caller's
--   sql_mode.
-- ============================================================================
DROP TRIGGER IF EXISTS trg_Test_EAR_ForceFailure;

DROP PROCEDURE IF EXISTS sp__ear_test_correction;
DROP PROCEDURE IF EXISTS sp__ear_test_initiation_rollback;
DROP PROCEDURE IF EXISTS sp__ear_new_workflow;
DROP PROCEDURE IF EXISTS sp__ear_initiate;
DROP PROCEDURE IF EXISTS sp__ear_make_doc;
DROP PROCEDURE IF EXISTS sp__ear_expect_ok;
DROP PROCEDURE IF EXISTS sp__ear_expect_reject;
DROP PROCEDURE IF EXISTS sp__ear_snapshot;
DROP PROCEDURE IF EXISTS sp__ear_check;

SET SESSION sql_mode = @ear_saved_sql_mode;