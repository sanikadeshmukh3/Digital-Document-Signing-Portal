-- ============================================================================
-- File:     database/06_demo_tests/060_entitlement_demo.sql
-- Project:  Document Workflow and E-signing Portal
-- Database: MySQL 8.x
-- ============================================================================
--
-- PURPOSE
--   Prove that the portal only lets people do what they are authorized to do.
--   Security is enforced at several layers in the database itself, not just by
--   hiding buttons in the user interface.
--
-- THE LAYERS THIS FILE TESTS
--   Part 2  Database accounts   App/reporter/auditor logins cannot edit or
--                               delete AuditLog, ApprovalDecision, Signature.
--   Part 3  Worklist view       A user only sees assignments that are theirs.
--   Part 4  Foreign key         A person cannot be assigned a role they do not hold.
--   Part 5  Stored procedures   Only the correct assignee can review, approve
--                               or sign.
--   Part 6  Stored procedure    Only the document owner can create a version.
--
-- TWO KINDS OF TEST
--   NEGATIVE ("expect reject")  An unauthorized attempt must FAIL, and must
--                               leave the workflow state exactly as it was.
--   POSITIVE ("expect ok")      An authorized action must SUCCEED, and the
--                               next workflow stage must wake up.
--
-- HOW TO READ THIS FILE
--   1. Skim "THE CAST" and "VARIABLE LEGEND" below.
--   2. SKIP the HELPER PROCEDURES section on a first read. Each helper has a
--      plain-English summary in the "HELPER QUICK REFERENCE" below.
--   3. Jump to "PART 1 - SETUP" and read straight down. Every test is
--      written as WHAT / WHY / EXPECT, followed by the code.
--
-- THE CAST (all created by the seed data)
--   Olivia Brooks    document OWNER   (not assigned to any workflow step)
--   Marcus Reed      REVIEWER         (step 1)
--   Daniel Cho       APPROVER         (step 2)
--   Sofia Alvarez    SIGNER           (step 3)
--   "Ghost"          user id 999999999, a user that does not exist
--
-- THE DEMO WORKFLOW
--   Step 1: Marcus REVIEWS  ->  Step 2: Daniel APPROVES  ->  Step 3: Sofia SIGNS
--   Only one step is ACTIVE at a time. Finishing a step activates the next.
--
-- VARIABLE LEGEND (MySQL session variables used in the main script)
--   @u_owner, @u_marcus, @u_daniel, @u_sofia, @u_ghost    user ids (see cast)
--   @d1   demo document id
--   @v1   demo document version id (version 1)
--   @w1   demo workflow id
--   @r1   Marcus's REVIEW assignment id    (WorkflowParticipantID)
--   @a1   Daniel's APPROVAL assignment id  (WorkflowParticipantID)
--   @s1   Sofia's SIGNATURE assignment id  (WorkflowParticipantID)
--   @ear_* and @x_*   short-lived scratch values for a single check
--
-- HELPER QUICK REFERENCE
--   sp__ear_check            Writes one PASS/FAIL row to the scoreboard.
--   sp__ear_snapshot         Takes a text "photo" of a workflow's state.
--   sp__ear_expect_reject    Runs a statement; PASS if it errors AND the
--                            "photo" before and after is identical.
--   sp__ear_expect_ok        Runs a statement; PASS if it does not error.
--   sp__ear_show_workflow    Prints the workflow as a friendly table.
--   sp__ear_make_doc         Creates a fresh demo document + version 1.
--   sp__ear_initiate         Starts the 3-step workflow on that document.
--   sp__ear_new_workflow     Shortcut: make_doc + initiate.
--
-- IMPORTANT
--   - Self-contained and re-runnable: it creates its own demo data.
--   - Run as a privileged account (it reads mysql.tables_priv / mysql.db).
--   - This file is NOT part of the normal build manifest.
-- ============================================================================


-- ============================================================================
-- SESSION SETUP
-- ============================================================================

-- Use identical SQL-mode settings on every machine so the demo behaves the
-- same everywhere. Save the caller's mode now; it is restored at the very end.
SET @ear_saved_sql_mode = @@SESSION.sql_mode;
SET SESSION sql_mode = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

-- The scoreboard. Every check adds one PASS or FAIL row here; the totals are
-- printed at the end. (Temporary table: disappears when the session closes.)
DROP TEMPORARY TABLE IF EXISTS ear_results;
CREATE TEMPORARY TABLE ear_results (
    seq        INT AUTO_INCREMENT PRIMARY KEY,
    area       VARCHAR(20),
    test_name  VARCHAR(200),
    result     VARCHAR(4),
    detail     TEXT
);


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
--     | DECISIONS=<count> | SIGNATURES=<count> | VERSIONS=<count>
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
            WHERE ws.WorkflowID = p_wf)),

        -- How many versions the document has
        CONCAT('VERSIONS=', (
            SELECT COUNT(*)
            FROM DocumentVersion dv
            JOIN Workflow w ON w.DocumentID = dv.DocumentID
            WHERE w.WorkflowID = p_wf))

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
-- sp__ear_show_workflow
--   Prints one row per assignment: step order, step type/status, who, role,
--   and the assignment's status. For the audience to eyeball.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__ear_show_workflow $$
CREATE PROCEDURE sp__ear_show_workflow(IN p_wf BIGINT UNSIGNED)
BEGIN
    SELECT w.WorkflowID,
           wr.Code AS WorkflowStatus,
           ws.SequenceNumber,
           st.Code AS StepType,
           ss.Code AS StepStatus,
           CONCAT(u.FirstName, ' ', u.LastName) AS Participant,
           r.RoleName,
           ps.Code AS AssignmentStatus
    FROM Workflow w
    JOIN ReferenceData wr ON wr.ReferenceDataID = w.WorkflowStatusID
    JOIN WorkflowStep ws ON ws.WorkflowID = w.WorkflowID
    JOIN ReferenceData st ON st.ReferenceDataID = ws.StepTypeID
    JOIN ReferenceData ss ON ss.ReferenceDataID = ws.StepStatusID
    JOIN WorkflowParticipant wp ON wp.WorkflowStepID = ws.WorkflowStepID
    JOIN `User` u ON u.UserID = wp.UserID
    JOIN Role r ON r.RoleID = wp.RoleID
    JOIN ReferenceData ps ON ps.ReferenceDataID = wp.AssignmentStatusID
    WHERE w.WorkflowID = p_wf
    ORDER BY ws.SequenceNumber, wp.WorkflowParticipantID;
END $$

-- ----------------------------------------------------------------------------
-- sp__ear_make_doc
--   Creates a brand-new DRAFT/INTERNAL document owned by Olivia, plus its
--   version 1 (via the real sp_create_document_version).
--   OUT o_doc = new DocumentID, OUT o_ver = new DocumentVersionID.
--   Never touches the real seeded documents.
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
    VALUES (p_title, 'Isolated document for the entitlement demo.', v_owner, v_class, v_status);
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

DELIMITER ;


-- ============================================================================
-- ============================================================================
--                         THE DEMO STARTS HERE
-- ============================================================================
-- ============================================================================


-- ============================================================================
-- PART 1 - SETUP
--   Look up the cast and build one fresh workflow to play with.
-- ============================================================================
SELECT '=== ENTITLEMENT DEMO - PART 1: SETUP ===' AS Section;

-- The cast, found by email address.
SET @u_owner  = (SELECT UserID FROM `User` WHERE Email = 'olivia.brooks@initech.example' LIMIT 1);
SET @u_marcus = (SELECT UserID FROM `User` WHERE Email = 'marcus.reed@initech.example' LIMIT 1);
SET @u_daniel = (SELECT UserID FROM `User` WHERE Email = 'daniel.cho@initech.example' LIMIT 1);
SET @u_sofia  = (SELECT UserID FROM `User` WHERE Email = 'sofia.alvarez@initech.example' LIMIT 1);
SET @u_ghost  = 999999999;   -- a user id that does not exist

-- Build the demo document + workflow.
--   outputs: @d1 doc, @v1 version, @w1 workflow,
--            @r1 Marcus's review, @a1 Daniel's approval, @s1 Sofia's signature
CALL sp__ear_new_workflow('EAR Demo - Entitlement Agreement', @d1, @v1, @w1, @r1, @a1, @s1);

SELECT 'Initial state: Marcus REVIEW -> Daniel APPROVAL -> Sofia SIGNATURE' AS Section;
CALL sp__ear_show_workflow(@w1);


-- ============================================================================
-- PART 2 - DATABASE ACCOUNT GRANTS
--   Layer: the database logins themselves.
--   Claim: the app, reporter and auditor logins cannot edit or delete the
--          audit log, approval decisions or signatures.
-- ============================================================================
SELECT '=== PART 2: DATABASE ACCOUNT GRANTS ===' AS Section;

-- 2.1  Informational: which business roles does each demo user hold?
SELECT '2.1 Business roles held by each demo user (UserRole)' AS Section;
SELECT CONCAT(u.FirstName, ' ', u.LastName) AS UserName,
       GROUP_CONCAT(r.RoleName ORDER BY r.RoleName SEPARATOR ', ') AS Roles
FROM `User` u
JOIN UserRole ur ON ur.UserID = u.UserID
JOIN Role r ON r.RoleID = ur.RoleID
WHERE u.UserID IN (@u_owner, @u_marcus, @u_daniel, @u_sofia)
GROUP BY u.UserID, u.FirstName, u.LastName;

-- 2.2  Informational: table-level grants held by the document_portal_* logins.
SELECT '2.2 Table-level grants for the document_portal_* accounts' AS Section;
SELECT User, Host, Db, Table_name, Table_priv
FROM mysql.tables_priv
WHERE User LIKE 'document\_portal\_%'
  AND Db IN (DATABASE(), REPLACE(DATABASE(), '_', '\\_'))
ORDER BY User, Table_name;

-- 2.3  Informational: routine-level grants (EXECUTE on controlled procedures).
SELECT '2.3 Routine-level grants (EXECUTE on controlled procedures)' AS Section;
SELECT User, Host, Db, Routine_name, Routine_type, Proc_priv
FROM mysql.procs_priv
WHERE User LIKE 'document\_portal\_%'
  AND Db IN (DATABASE(), REPLACE(DATABASE(), '_', '\\_'))
ORDER BY User, Routine_name;

-- CHECK 1 (scoreboard)
--   WHAT:   count dangerous grants held by the three application logins.
--   WHY:    if these logins could UPDATE/DELETE protected tables, the
--           procedure rules could be bypassed with a plain SQL statement.
--   EXPECT: both counts are 0.

-- (a) table-level UPDATE/DELETE on the three protected tables
SET @ear_bad_tbl = (
    SELECT COUNT(*)
    FROM mysql.tables_priv
    WHERE Db IN (DATABASE(), REPLACE(DATABASE(), '_', '\\_'))
      AND User IN ('document_portal_app', 'document_portal_reporter', 'document_portal_auditor')
      AND Table_name IN ('AuditLog', 'ApprovalDecision', 'Signature')
      AND (FIND_IN_SET('Update', Table_priv) > 0 OR FIND_IN_SET('Delete', Table_priv) > 0));

-- (b) database-wide UPDATE/DELETE (which would cover every table)
SET @ear_bad_db = (
    SELECT COUNT(*)
    FROM mysql.db
    WHERE Db IN (DATABASE(), REPLACE(DATABASE(), '_', '\\_'))
      AND User IN ('document_portal_app', 'document_portal_reporter', 'document_portal_auditor')
      AND (Update_priv = 'Y' OR Delete_priv = 'Y'));

CALL sp__ear_check('ENTITLEMENT',
    'App/reporter/auditor accounts hold no UPDATE/DELETE on AuditLog, ApprovalDecision, Signature',
    @ear_bad_tbl = 0 AND @ear_bad_db = 0,
    CONCAT('Offending table-level grants: ', @ear_bad_tbl,
           ' || offending db-level grants: ', @ear_bad_db));


-- ============================================================================
-- PART 3 - ROW-LEVEL VISIBILITY (the worklist view)
--   Layer: the view vw_ParticipantWorklist.
--   Claim: a person sees only the assignments that belong to them.
-- ============================================================================
SELECT '=== PART 3: ROW-LEVEL VISIBILITY (vw_ParticipantWorklist) ===' AS Section;

-- Informational: how many demo-workflow rows can each person see?
SELECT CONCAT(u.FirstName, ' ', u.LastName) AS Viewer,
       (SELECT COUNT(*)
        FROM vw_ParticipantWorklist pw
        WHERE pw.UserID = u.UserID AND pw.WorkflowID = @w1) AS WF1RowsVisible
FROM `User` u
WHERE u.UserID IN (@u_owner, @u_marcus, @u_daniel, @u_sofia);

-- CHECK 2 (scoreboard)
--   WHAT:   look at who appears in the worklist for our workflow.
--   WHY:    nobody should see an assignment that is not theirs.
--   EXPECT: - no rows for anyone except Marcus, Daniel, Sofia   (leak = 0)
--           - Olivia, the owner, has no assignment so sees 0    (owner = 0)
--           - Marcus sees at least his own row                  (marcus >= 1)
SET @ear_leak = (
    SELECT COUNT(*)
    FROM vw_ParticipantWorklist pw
    WHERE pw.WorkflowID = @w1
      AND pw.UserID NOT IN (@u_marcus, @u_daniel, @u_sofia));

SET @ear_owner_rows = (
    SELECT COUNT(*)
    FROM vw_ParticipantWorklist pw
    WHERE pw.WorkflowID = @w1 AND pw.UserID = @u_owner);

SET @ear_marcus_rows = (
    SELECT COUNT(*)
    FROM vw_ParticipantWorklist pw
    WHERE pw.WorkflowID = @w1 AND pw.UserID = @u_marcus);

CALL sp__ear_check('ENTITLEMENT',
    'Worklist shows rows only for assigned users (document owner with no assignment sees 0)',
    @ear_leak = 0 AND @ear_owner_rows = 0 AND @ear_marcus_rows >= 1,
    CONCAT('Rows for unassigned users: ', @ear_leak,
           ' || owner rows: ', @ear_owner_rows,
           ' || Marcus rows: ', @ear_marcus_rows));


-- ============================================================================
-- PART 4 - SCHEMA ENFORCEMENT (a person must hold the role)
--   Layer: a composite foreign key from WorkflowParticipant to UserRole.
--   Claim: even a direct INSERT cannot assign someone a role they lack.
-- ============================================================================
SELECT '=== PART 4: SCHEMA ENFORCEMENT - ASSIGNMENT REQUIRES THE ROLE ===' AS Section;

-- Pick the victim: the role is "Approver"; the user is whichever of
-- Marcus / Sofia does NOT hold that role (lowest UserID if both lack it).
SET @x_role = (SELECT RoleID FROM Role WHERE RoleName = 'Approver' LIMIT 1);

SET @x_user = (
    SELECT u.UserID
    FROM `User` u
    LEFT JOIN UserRole ur ON ur.UserID = u.UserID AND ur.RoleID = @x_role
    WHERE ur.UserID IS NULL
      AND u.UserID IN (@u_marcus, @u_sofia)
    ORDER BY u.UserID
    LIMIT 1);

-- CHECK 3 (scoreboard)
--   WHAT:   hand-insert that user as a participant on the Approval step (seq 2).
--   WHY:    the foreign key to UserRole should refuse it.
--   EXPECT: error raised AND the workflow state is unchanged.
--
-- The statement that gets run looks like:
--   INSERT INTO WorkflowParticipant (WorkflowStepID, UserID, RoleID, AssignedActionID,
--       AssignmentStatusID, RequiredFlag, DueDateTime)
--   VALUES ( <step 2 of this workflow>, <user without role>, <Approver role>,
--            <APPROVAL action>, <PENDING status>, TRUE, NOW() )
CALL sp__ear_expect_reject('ENTITLEMENT',
    'Direct INSERT assigning a user to a role they do not hold is rejected (composite FK to UserRole)',
    CONCAT(
        'INSERT INTO WorkflowParticipant (WorkflowStepID, UserID, RoleID, AssignedActionID, ',
        'AssignmentStatusID, RequiredFlag, DueDateTime) VALUES (',
        '(SELECT WorkflowStepID FROM WorkflowStep WHERE WorkflowID=', @w1, ' AND SequenceNumber=2),',
        @x_user, ',', @x_role, ',',
        '(SELECT ReferenceDataID FROM ReferenceData WHERE DomainName=''ASSIGNED_ACTION'' AND Code=''APPROVAL''),',
        '(SELECT ReferenceDataID FROM ReferenceData WHERE DomainName=''PARTICIPANT_STATUS'' AND Code=''PENDING''),',
        'TRUE, NOW())'),
    @w1);


-- ============================================================================
-- PART 5 - CONTROLLED PROCEDURES (the heart of the demo)
--   Layer: stored procedures that check WHO is acting and WHAT STATE we are in.
--   Pattern: for each action, the WRONG people try first (must be blocked),
--            then the RIGHT person does it (must work).
--
--   Timeline of this part:
--     5.1  Marcus reviews          -> Daniel's approval becomes ACTIVE
--     5.2  3 wrong people try to approve  (all blocked)
--     5.3  Daniel approves         -> Sofia's signature becomes ACTIVE
--     5.4  2 wrong people try to sign     (both blocked)
--     5.5  Sofia signs             -> workflow COMPLETED
-- ============================================================================
SELECT '=== PART 5: CONTROLLED PROCEDURES (assignment + state enforcement) ===' AS Section;

-- ----------------------------------------------------------------------------
-- 5.1  AUTHORIZED: Marcus completes his review
-- ----------------------------------------------------------------------------
SELECT '5.1 AUTHORIZED: Marcus (assigned reviewer) completes his review' AS Section;

-- CHECK 4:  Marcus is the assigned reviewer, so this must succeed.
--   Runs: CALL sp_complete_review_acknowledgement(<Marcus's review>, <Marcus>)
CALL sp__ear_expect_ok('ENTITLEMENT', 'Assigned reviewer can complete REVIEW',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r1, ',', @u_marcus, ')'));

-- CHECK 5:  finishing the review should activate the next stage.
--   EXPECT: Daniel's approval assignment (@a1) is now ACTIVE.
SET @ear_st = (
    SELECT rd.Code
    FROM WorkflowParticipant wp
    JOIN ReferenceData rd ON rd.ReferenceDataID = wp.AssignmentStatusID
    WHERE wp.WorkflowParticipantID = @a1);

CALL sp__ear_check('ENTITLEMENT', 'Completed review activated the approval assignment',
    @ear_st = 'ACTIVE',
    CONCAT('Daniel approval assignment = ', COALESCE(@ear_st, '?')));

-- ----------------------------------------------------------------------------
-- 5.2  UNAUTHORIZED: three wrong people try to do Daniel's approval
--      Daniel's approval is ACTIVE, so the only thing stopping these is that
--      the caller is not the assignee.
--      Each runs: CALL sp_record_approval_decision(<Daniel's approval>,
--                       <the wrong person>, 'APPROVED', 'unauthorized', NULL)
-- ----------------------------------------------------------------------------
SELECT '5.2 UNAUTHORIZED: three different users attempt Daniel''s APPROVAL' AS Section;

-- CHECK 6:  Marcus (a reviewer, not the approver)
CALL sp__ear_expect_reject('ENTITLEMENT',
    'Marcus (Reviewer, not assigned) cannot perform Daniel''s APPROVAL',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_marcus, ',''APPROVED'',''unauthorized'',NULL)'),
    @w1);

-- CHECK 7:  Olivia (document owner, no assignment at all)
CALL sp__ear_expect_reject('ENTITLEMENT',
    'Document owner (no assignment) cannot perform Daniel''s APPROVAL',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_owner, ',''APPROVED'',''unauthorized'',NULL)'),
    @w1);

-- CHECK 8:  a user id that does not exist
CALL sp__ear_expect_reject('ENTITLEMENT',
    'Non-existent user id cannot perform APPROVAL',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_ghost, ',''APPROVED'',''unauthorized'',NULL)'),
    @w1);

-- ----------------------------------------------------------------------------
-- 5.3  AUTHORIZED: Daniel performs the very same approval
-- ----------------------------------------------------------------------------
SELECT '5.3 AUTHORIZED: Daniel performs the same APPROVAL' AS Section;

-- CHECK 9:  identical call, but with the real assignee. Must succeed.
CALL sp__ear_expect_ok('ENTITLEMENT', 'Assigned approver can record APPROVAL',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_daniel, ',''APPROVED'',''EAR demo approval'',NULL)'));

-- CHECK 10:  approving should activate the next stage.
--   EXPECT: Sofia's signature assignment (@s1) is now ACTIVE.
SET @ear_st = (
    SELECT rd.Code
    FROM WorkflowParticipant wp
    JOIN ReferenceData rd ON rd.ReferenceDataID = wp.AssignmentStatusID
    WHERE wp.WorkflowParticipantID = @s1);

CALL sp__ear_check('ENTITLEMENT', 'Approval activated the signer assignment',
    @ear_st = 'ACTIVE',
    CONCAT('Sofia signature assignment = ', COALESCE(@ear_st, '?')));

-- ----------------------------------------------------------------------------
-- 5.4  UNAUTHORIZED: two wrong people try to sign
--      Sofia's assignment is ACTIVE, so signing is open; only the identity
--      of the caller should block these.
--      Each runs: CALL sp_record_signature(<Sofia's signature>, <wrong person>,
--                       <version>, 'SIGNED', 'TYPED_NAME', 'unauthorized')
-- ----------------------------------------------------------------------------
SELECT '5.4 UNAUTHORIZED: two users attempt Sofia''s SIGNATURE (her assignment is ACTIVE)' AS Section;

-- CHECK 11:  Marcus
CALL sp__ear_expect_reject('ENTITLEMENT',
    'Marcus cannot sign on Sofia''s assignment',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_marcus, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''unauthorized'')'),
    @w1);

-- CHECK 12:  Daniel
CALL sp__ear_expect_reject('ENTITLEMENT',
    'Daniel (Approver) cannot sign on Sofia''s assignment',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_daniel, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''unauthorized'')'),
    @w1);

-- ----------------------------------------------------------------------------
-- 5.5  AUTHORIZED: Sofia signs
-- ----------------------------------------------------------------------------
SELECT '5.5 AUTHORIZED: Sofia signs' AS Section;

-- CHECK 13:  the real signer signs. Must succeed.
CALL sp__ear_expect_ok('ENTITLEMENT', 'Assigned signer can record SIGNATURE',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_sofia, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''EAR-ENT-SIG-1'')'));

-- CHECK 14:  all three right people acted in order.
--   EXPECT: the whole workflow is now COMPLETED.
SET @ear_t = (
    SELECT rd.Code
    FROM Workflow w
    JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID
    WHERE w.WorkflowID = @w1);

CALL sp__ear_check('ENTITLEMENT', 'Authorized actions in order completed the workflow',
    @ear_t = 'COMPLETED',
    CONCAT('Workflow status = ', COALESCE(@ear_t, '?')));

SELECT 'Final state of the entitlement workflow' AS Section;
CALL sp__ear_show_workflow(@w1);


-- ============================================================================
-- PART 6 - SECOND PROTECTED ACTION: creating a document version (owner only)
--   Claim: only the document's owner (Olivia) may add a version.
-- ============================================================================
SELECT '=== PART 6: PROTECTED ACTION 2 - CREATE DOCUMENT VERSION (OWNER ONLY) ===' AS Section;

-- Setup: a new owner-Olivia document that has NO versions yet.
INSERT INTO Document (Title, BusinessDescription, OwnerUserID, ClassificationID, LifecycleStatusID)
VALUES ('EAR Demo - Entitlement Version Document',
        'Document with no versions; used to test who may create a version.',
        @u_owner,
        (SELECT ReferenceDataID FROM ReferenceData
          WHERE DomainName = 'DOCUMENT_CLASSIFICATION' AND Code = 'INTERNAL' LIMIT 1),
        (SELECT ReferenceDataID FROM ReferenceData
          WHERE DomainName = 'DOCUMENT_STATUS' AND Code = 'DRAFT' LIMIT 1));
SET @e_doc = LAST_INSERT_ID();

-- CHECK 15:  Marcus is not the owner, so this must be blocked.
--   Runs: CALL sp_create_document_version(<Marcus>, <document>, 1, 'unauthorized')
CALL sp__ear_expect_reject('ENTITLEMENT',
    'Non-owner (Marcus) cannot create a version of the owner''s document',
    CONCAT('CALL sp_create_document_version(', @u_marcus, ',', @e_doc, ',1,''unauthorized'')'),
    @w1);

-- CHECK 16:  the blocked attempt must have left nothing behind.
--   EXPECT: still 0 versions on this document.
SET @ear_vc = (SELECT COUNT(*) FROM DocumentVersion WHERE DocumentID = @e_doc);

CALL sp__ear_check('ENTITLEMENT', 'Rejected version creation left zero versions',
    @ear_vc = 0,
    CONCAT('Versions after rejected attempt: ', @ear_vc));

-- CHECK 17:  Olivia IS the owner, so the same call works for her.
CALL sp__ear_expect_ok('ENTITLEMENT', 'Document owner (Olivia) can create the version',
    CONCAT('CALL sp_create_document_version(', @u_owner, ',', @e_doc, ',1,''Owner-created version'')'));

-- CHECK 18:  exactly one version now exists.
SET @ear_vc = (SELECT COUNT(*) FROM DocumentVersion WHERE DocumentID = @e_doc);

CALL sp__ear_check('ENTITLEMENT', 'Owner-created version exists',
    @ear_vc = 1,
    CONCAT('Versions after owner attempt: ', @ear_vc));


-- ============================================================================
-- SCOREBOARD
--   If every row shows Failed = 0, every security rule held (18 checks total).
-- ============================================================================
SELECT '=== ENTITLEMENT SCOREBOARD ===' AS Section;
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
--   Remove the helper procedures and restore the caller's sql_mode.
-- ============================================================================
DROP PROCEDURE IF EXISTS sp__ear_new_workflow;
DROP PROCEDURE IF EXISTS sp__ear_initiate;
DROP PROCEDURE IF EXISTS sp__ear_make_doc;
DROP PROCEDURE IF EXISTS sp__ear_show_workflow;
DROP PROCEDURE IF EXISTS sp__ear_expect_ok;
DROP PROCEDURE IF EXISTS sp__ear_expect_reject;
DROP PROCEDURE IF EXISTS sp__ear_snapshot;
DROP PROCEDURE IF EXISTS sp__ear_check;

SET SESSION sql_mode = @ear_saved_sql_mode;