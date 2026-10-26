-- ============================================================
-- File: database/06_demo_tests/060_entitlement_demo.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Demonstrate entitlement enforcement: an authorized role or
--   assignee can perform a protected action, while an unauthorized
--   or unassigned user cannot perform the same action. Shows the
--   enforcement layers used by the project: database-account grants,
--   the per-user worklist view, controlled stored procedures, and
--   the composite foreign key requiring a user to hold the role.
--
-- Important:
--   - Self-contained and re-runnable; creates its own demo data.
--   - Run as a privileged account (reads mysql.tables_priv / mysql.db).
--   - This file is NOT part of the normal build manifest.
--
-- Database: MySQL 8.x
-- ============================================================

DROP TEMPORARY TABLE IF EXISTS ear_results;
CREATE TEMPORARY TABLE ear_results (
    seq        INT AUTO_INCREMENT PRIMARY KEY,
    area       VARCHAR(20),
    test_name  VARCHAR(200),
    result     VARCHAR(4),
    detail     TEXT
);

DELIMITER $$

DROP PROCEDURE IF EXISTS sp__ear_check $$
CREATE PROCEDURE sp__ear_check(IN p_area VARCHAR(20), IN p_name VARCHAR(200),
                               IN p_pass BOOLEAN, IN p_detail TEXT)
BEGIN
    INSERT INTO ear_results(area, test_name, result, detail)
    VALUES (p_area, p_name, IF(COALESCE(p_pass,0), 'PASS', 'FAIL'), p_detail);
    SELECT IF(COALESCE(p_pass,0), 'PASS', 'FAIL') AS Result,
           p_area AS Area, p_name AS Test, p_detail AS Detail;
END $$

DROP PROCEDURE IF EXISTS sp__ear_snapshot $$
CREATE PROCEDURE sp__ear_snapshot(IN p_wf BIGINT UNSIGNED, OUT p_snap TEXT)
BEGIN
    SELECT CONCAT_WS(' | ',
        CONCAT('WORKFLOW=', COALESCE((SELECT rd.Code FROM Workflow w
            JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID
            WHERE w.WorkflowID = p_wf), '?')),
        CONCAT('STEPS=', COALESCE((SELECT GROUP_CONCAT(CONCAT(ws.SequenceNumber, ':', rd.Code)
            ORDER BY ws.SequenceNumber SEPARATOR ',') FROM WorkflowStep ws
            JOIN ReferenceData rd ON rd.ReferenceDataID = ws.StepStatusID
            WHERE ws.WorkflowID = p_wf), '-')),
        CONCAT('ASSIGNMENTS=', COALESCE((SELECT GROUP_CONCAT(CONCAT(wp.WorkflowParticipantID, ':', rd.Code)
            ORDER BY wp.WorkflowParticipantID SEPARATOR ',') FROM WorkflowParticipant wp
            JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
            JOIN ReferenceData rd ON rd.ReferenceDataID = wp.AssignmentStatusID
            WHERE ws.WorkflowID = p_wf), '-')),
        CONCAT('DECISIONS=', (SELECT COUNT(*) FROM ApprovalDecision ad
            JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = ad.WorkflowParticipantID
            JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
            WHERE ws.WorkflowID = p_wf)),
        CONCAT('SIGNATURES=', (SELECT COUNT(*) FROM Signature s
            JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = s.WorkflowParticipantID
            JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
            WHERE ws.WorkflowID = p_wf)),
        CONCAT('VERSIONS=', (SELECT COUNT(*) FROM DocumentVersion dv
            JOIN Workflow w ON w.DocumentID = dv.DocumentID WHERE w.WorkflowID = p_wf))
    ) INTO p_snap;
END $$

-- Statement MUST be rejected AND the workflow state must be unchanged.
DROP PROCEDURE IF EXISTS sp__ear_expect_reject $$
CREATE PROCEDURE sp__ear_expect_reject(IN p_area VARCHAR(20), IN p_name VARCHAR(200),
                                       IN p_stmt TEXT, IN p_wf BIGINT UNSIGNED)
BEGIN
    DECLARE v_rejected BOOLEAN DEFAULT FALSE;
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE v_before TEXT;
    DECLARE v_after TEXT;
    DECLARE v_audit_before INT DEFAULT 0;
    DECLARE v_audit_after INT DEFAULT 0;

    CALL sp__ear_snapshot(p_wf, v_before);
    SELECT COUNT(*) INTO v_audit_before FROM AuditLog;

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

    CALL sp__ear_snapshot(p_wf, v_after);
    SELECT COUNT(*) INTO v_audit_after FROM AuditLog;

    CALL sp__ear_check(p_area, p_name,
        v_rejected AND v_before = v_after,
        CONCAT('Error raised: ', COALESCE(v_msg, '(NONE - action was NOT rejected)'),
               ' || State unchanged: ', IF(v_before = v_after, 'yes', 'NO'),
               ' || State: ', v_after,
               ' || Audit rows added: ', v_audit_after - v_audit_before));
END $$

-- Statement MUST succeed.
DROP PROCEDURE IF EXISTS sp__ear_expect_ok $$
CREATE PROCEDURE sp__ear_expect_ok(IN p_area VARCHAR(20), IN p_name VARCHAR(200), IN p_stmt TEXT)
BEGIN
    DECLARE v_failed BOOLEAN DEFAULT FALSE;
    DECLARE v_msg TEXT DEFAULT NULL;
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

DROP PROCEDURE IF EXISTS sp__ear_show_workflow $$
CREATE PROCEDURE sp__ear_show_workflow(IN p_wf BIGINT UNSIGNED)
BEGIN
    SELECT w.WorkflowID, wr.Code AS WorkflowStatus, ws.SequenceNumber,
           st.Code AS StepType, ss.Code AS StepStatus,
           CONCAT(u.FirstName, ' ', u.LastName) AS Participant,
           r.RoleName, ps.Code AS AssignmentStatus
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

DROP PROCEDURE IF EXISTS sp__ear_make_doc $$
CREATE PROCEDURE sp__ear_make_doc(IN p_title VARCHAR(200),
                                  OUT o_doc BIGINT UNSIGNED, OUT o_ver BIGINT UNSIGNED)
BEGIN
    DECLARE v_owner BIGINT UNSIGNED;
    DECLARE v_status BIGINT UNSIGNED;
    DECLARE v_class BIGINT UNSIGNED;

    SELECT UserID INTO v_owner FROM `User` WHERE Email = 'olivia.brooks@initech.example' LIMIT 1;
    SELECT ReferenceDataID INTO v_status FROM ReferenceData
        WHERE DomainName = 'DOCUMENT_STATUS' AND Code = 'DRAFT' LIMIT 1;
    SELECT ReferenceDataID INTO v_class FROM ReferenceData
        WHERE DomainName = 'DOCUMENT_CLASSIFICATION' AND Code = 'INTERNAL' LIMIT 1;

    INSERT INTO Document (Title, BusinessDescription, OwnerUserID, ClassificationID, LifecycleStatusID)
    VALUES (p_title, 'Isolated document for the entitlement demo.', v_owner, v_class, v_status);
    SET o_doc = LAST_INSERT_ID();

    CALL sp_create_document_version(v_owner, o_doc, 1, 'EAR demo version 1');

    SELECT DocumentVersionID INTO o_ver FROM DocumentVersion
        WHERE DocumentID = o_doc AND VersionNumber = 1 LIMIT 1;
END $$

DROP PROCEDURE IF EXISTS sp__ear_initiate $$
CREATE PROCEDURE sp__ear_initiate(IN p_doc BIGINT UNSIGNED, IN p_ver BIGINT UNSIGNED,
    OUT o_wf BIGINT UNSIGNED, OUT o_review BIGINT UNSIGNED,
    OUT o_approval BIGINT UNSIGNED, OUT o_sign BIGINT UNSIGNED)
BEGIN
    DECLARE v_owner, v_marcus, v_daniel, v_sofia BIGINT UNSIGNED;
    DECLARE v_rev_role, v_app_role, v_sig_role BIGINT UNSIGNED;
    DECLARE v_steps JSON;

    SELECT OwnerUserID INTO v_owner FROM Document WHERE DocumentID = p_doc;
    SELECT UserID INTO v_marcus FROM `User` WHERE Email = 'marcus.reed@initech.example' LIMIT 1;
    SELECT UserID INTO v_daniel FROM `User` WHERE Email = 'daniel.cho@initech.example' LIMIT 1;
    SELECT UserID INTO v_sofia  FROM `User` WHERE Email = 'sofia.alvarez@initech.example' LIMIT 1;
    SELECT RoleID INTO v_rev_role FROM Role WHERE RoleName = 'Reviewer' LIMIT 1;
    SELECT RoleID INTO v_app_role FROM Role WHERE RoleName = 'Approver' LIMIT 1;
    SELECT RoleID INTO v_sig_role FROM Role WHERE RoleName = 'Signer' LIMIT 1;

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

    CALL sp_initiate_workflow(v_owner, p_doc, p_ver, 'FULL_REVIEW_APPROVAL_SIGNATURE',
                              DATE_ADD(NOW(), INTERVAL 30 DAY), v_steps);

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

DROP PROCEDURE IF EXISTS sp__ear_new_workflow $$
CREATE PROCEDURE sp__ear_new_workflow(IN p_title VARCHAR(200),
    OUT o_doc BIGINT UNSIGNED, OUT o_ver BIGINT UNSIGNED, OUT o_wf BIGINT UNSIGNED,
    OUT o_review BIGINT UNSIGNED, OUT o_approval BIGINT UNSIGNED, OUT o_sign BIGINT UNSIGNED)
BEGIN
    CALL sp__ear_make_doc(p_title, o_doc, o_ver);
    CALL sp__ear_initiate(o_doc, o_ver, o_wf, o_review, o_approval, o_sign);
END $$

DELIMITER ;


-- ============================================================
-- PART 1 - SETUP
-- ============================================================
SELECT '=== ENTITLEMENT DEMO - PART 1: SETUP ===' AS Section;

SET @u_owner  = (SELECT UserID FROM `User` WHERE Email = 'olivia.brooks@initech.example' LIMIT 1);
SET @u_marcus = (SELECT UserID FROM `User` WHERE Email = 'marcus.reed@initech.example' LIMIT 1);
SET @u_daniel = (SELECT UserID FROM `User` WHERE Email = 'daniel.cho@initech.example' LIMIT 1);
SET @u_sofia  = (SELECT UserID FROM `User` WHERE Email = 'sofia.alvarez@initech.example' LIMIT 1);
SET @u_ghost  = 999999999;   -- user id that does not exist

CALL sp__ear_new_workflow('EAR Demo - Entitlement Agreement', @d1, @v1, @w1, @r1, @a1, @s1);

SELECT 'Initial state: Marcus REVIEW -> Daniel APPROVAL -> Sofia SIGNATURE' AS Section;
CALL sp__ear_show_workflow(@w1);


-- ============================================================
-- PART 2 - PRIVILEGE LAYER (role grants)
-- ============================================================
SELECT '=== PART 2: DATABASE ACCOUNT GRANTS ===' AS Section;

SELECT '2.1 Business roles held by each demo user (UserRole)' AS Section;
SELECT CONCAT(u.FirstName, ' ', u.LastName) AS UserName,
       GROUP_CONCAT(r.RoleName ORDER BY r.RoleName SEPARATOR ', ') AS Roles
FROM `User` u
JOIN UserRole ur ON ur.UserID = u.UserID
JOIN Role r ON r.RoleID = ur.RoleID
WHERE u.UserID IN (@u_owner, @u_marcus, @u_daniel, @u_sofia)
GROUP BY u.UserID, u.FirstName, u.LastName;

SELECT '2.2 Table-level grants for the document_portal_* accounts' AS Section;
SELECT User, Host, Db, Table_name, Table_priv
FROM mysql.tables_priv
WHERE User LIKE 'document\_portal\_%' AND Db IN (DATABASE(), REPLACE(DATABASE(), '_', '\\_'))
ORDER BY User, Table_name;

SELECT '2.3 Routine-level grants (EXECUTE on controlled procedures)' AS Section;
SELECT User, Host, Db, Routine_name, Routine_type, Proc_priv
FROM mysql.procs_priv
WHERE User LIKE 'document\_portal\_%' AND Db IN (DATABASE(), REPLACE(DATABASE(), '_', '\\_'))
ORDER BY User, Routine_name;

SET @ear_bad_tbl = (SELECT COUNT(*) FROM mysql.tables_priv
    WHERE Db IN (DATABASE(), REPLACE(DATABASE(), '_', '\\_'))
      AND User IN ('document_portal_app', 'document_portal_reporter', 'document_portal_auditor')
      AND Table_name IN ('AuditLog', 'ApprovalDecision', 'Signature')
      AND (FIND_IN_SET('Update', Table_priv) > 0 OR FIND_IN_SET('Delete', Table_priv) > 0));
SET @ear_bad_db = (SELECT COUNT(*) FROM mysql.db
    WHERE Db IN (DATABASE(), REPLACE(DATABASE(), '_', '\\_'))
      AND User IN ('document_portal_app', 'document_portal_reporter', 'document_portal_auditor')
      AND (Update_priv = 'Y' OR Delete_priv = 'Y'));
CALL sp__ear_check('ENTITLEMENT',
    'App/reporter/auditor accounts hold no UPDATE/DELETE on AuditLog, ApprovalDecision, Signature',
    @ear_bad_tbl = 0 AND @ear_bad_db = 0,
    CONCAT('Offending table-level grants: ', @ear_bad_tbl, ' || offending db-level grants: ', @ear_bad_db));

-- LIVE DEMO (optional, second terminal) - connect as a low-privilege account:
--   mysql -u document_portal_reporter -p <db>
--   SELECT COUNT(*) FROM vw_OutstandingActions;                     -- allowed
--   UPDATE AuditLog SET EventType = 'X' WHERE AuditLogID = 1;       -- ERROR 1142 denied
--   CALL sp_record_approval_decision(1, 1, 'APPROVED', 'x', NULL);  -- ERROR 1370 denied (no EXECUTE)


-- ============================================================
-- PART 3 - ROW-LEVEL VISIBILITY (protected view)
-- ============================================================
SELECT '=== PART 3: ROW-LEVEL VISIBILITY (vw_ParticipantWorklist) ===' AS Section;

SELECT CONCAT(u.FirstName, ' ', u.LastName) AS Viewer,
       (SELECT COUNT(*) FROM vw_ParticipantWorklist pw
         WHERE pw.UserID = u.UserID AND pw.WorkflowID = @w1) AS WF1RowsVisible
FROM `User` u WHERE u.UserID IN (@u_owner, @u_marcus, @u_daniel, @u_sofia);

SET @ear_leak = (SELECT COUNT(*) FROM vw_ParticipantWorklist pw
    WHERE pw.WorkflowID = @w1 AND pw.UserID NOT IN (@u_marcus, @u_daniel, @u_sofia));
SET @ear_owner_rows = (SELECT COUNT(*) FROM vw_ParticipantWorklist pw
    WHERE pw.WorkflowID = @w1 AND pw.UserID = @u_owner);
SET @ear_marcus_rows = (SELECT COUNT(*) FROM vw_ParticipantWorklist pw
    WHERE pw.WorkflowID = @w1 AND pw.UserID = @u_marcus);
CALL sp__ear_check('ENTITLEMENT',
    'Worklist shows rows only for assigned users (document owner with no assignment sees 0)',
    @ear_leak = 0 AND @ear_owner_rows = 0 AND @ear_marcus_rows >= 1,
    CONCAT('Rows for unassigned users: ', @ear_leak, ' || owner rows: ', @ear_owner_rows,
           ' || Marcus rows: ', @ear_marcus_rows));


-- ============================================================
-- PART 4 - SCHEMA-LEVEL ENFORCEMENT (user must hold the role)
-- ============================================================
SELECT '=== PART 4: SCHEMA ENFORCEMENT - ASSIGNMENT REQUIRES THE ROLE ===' AS Section;

SET @x_role = (SELECT RoleID FROM Role WHERE RoleName = 'Approver' LIMIT 1);
SET @x_user = (SELECT u.UserID FROM `User` u
    LEFT JOIN UserRole ur ON ur.UserID = u.UserID AND ur.RoleID = @x_role
    WHERE ur.UserID IS NULL AND u.UserID IN (@u_marcus, @u_sofia)
    ORDER BY u.UserID LIMIT 1);

CALL sp__ear_expect_reject('ENTITLEMENT',
    'Direct INSERT assigning a user to a role they do not hold is rejected (composite FK to UserRole)',
    CONCAT('INSERT INTO WorkflowParticipant (WorkflowStepID, UserID, RoleID, AssignedActionID, ',
           'AssignmentStatusID, RequiredFlag, DueDateTime) VALUES (',
           '(SELECT WorkflowStepID FROM WorkflowStep WHERE WorkflowID=', @w1, ' AND SequenceNumber=2),',
           @x_user, ',', @x_role, ',',
           '(SELECT ReferenceDataID FROM ReferenceData WHERE DomainName=''ASSIGNED_ACTION'' AND Code=''APPROVAL''),',
           '(SELECT ReferenceDataID FROM ReferenceData WHERE DomainName=''PARTICIPANT_STATUS'' AND Code=''PENDING''),',
           'TRUE, NOW())'), @w1);


-- ============================================================
-- PART 5 - CONTROLLED PROCEDURES: SAME ACTION, AUTHORIZED vs NOT
-- ============================================================
SELECT '=== PART 5: CONTROLLED PROCEDURES (assignment + state enforcement) ===' AS Section;

SELECT '5.1 AUTHORIZED: Marcus (assigned reviewer) completes his review' AS Section;
CALL sp__ear_expect_ok('ENTITLEMENT', 'Assigned reviewer can complete REVIEW',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r1, ',', @u_marcus, ')'));

SET @ear_st = (SELECT rd.Code FROM WorkflowParticipant wp
    JOIN ReferenceData rd ON rd.ReferenceDataID = wp.AssignmentStatusID
    WHERE wp.WorkflowParticipantID = @a1);
CALL sp__ear_check('ENTITLEMENT', 'Completed review activated the approval assignment',
    @ear_st = 'ACTIVE', CONCAT('Daniel approval assignment = ', COALESCE(@ear_st, '?')));

SELECT '5.2 UNAUTHORIZED: three different users attempt Daniel''s APPROVAL' AS Section;
CALL sp__ear_expect_reject('ENTITLEMENT',
    'Marcus (Reviewer, not assigned) cannot perform Daniel''s APPROVAL',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_marcus, ',''APPROVED'',''unauthorized'',NULL)'), @w1);
CALL sp__ear_expect_reject('ENTITLEMENT',
    'Document owner (no assignment) cannot perform Daniel''s APPROVAL',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_owner, ',''APPROVED'',''unauthorized'',NULL)'), @w1);
CALL sp__ear_expect_reject('ENTITLEMENT',
    'Non-existent user id cannot perform APPROVAL',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_ghost, ',''APPROVED'',''unauthorized'',NULL)'), @w1);

SELECT '5.3 AUTHORIZED: Daniel performs the same APPROVAL' AS Section;
CALL sp__ear_expect_ok('ENTITLEMENT', 'Assigned approver can record APPROVAL',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_daniel, ',''APPROVED'',''EAR demo approval'',NULL)'));

SET @ear_st = (SELECT rd.Code FROM WorkflowParticipant wp
    JOIN ReferenceData rd ON rd.ReferenceDataID = wp.AssignmentStatusID
    WHERE wp.WorkflowParticipantID = @s1);
CALL sp__ear_check('ENTITLEMENT', 'Approval activated the signer assignment',
    @ear_st = 'ACTIVE', CONCAT('Sofia signature assignment = ', COALESCE(@ear_st, '?')));

SELECT '5.4 UNAUTHORIZED: two users attempt Sofia''s SIGNATURE (her assignment is ACTIVE)' AS Section;
CALL sp__ear_expect_reject('ENTITLEMENT',
    'Marcus cannot sign on Sofia''s assignment',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_marcus, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''unauthorized'')'), @w1);
CALL sp__ear_expect_reject('ENTITLEMENT',
    'Daniel (Approver) cannot sign on Sofia''s assignment',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_daniel, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''unauthorized'')'), @w1);

SELECT '5.5 AUTHORIZED: Sofia signs' AS Section;
CALL sp__ear_expect_ok('ENTITLEMENT', 'Assigned signer can record SIGNATURE',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_sofia, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''EAR-ENT-SIG-1'')'));

SET @ear_t = (SELECT rd.Code FROM Workflow w
    JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID WHERE w.WorkflowID = @w1);
CALL sp__ear_check('ENTITLEMENT', 'Authorized actions in order completed the workflow',
    @ear_t = 'COMPLETED', CONCAT('Workflow status = ', COALESCE(@ear_t, '?')));

SELECT 'Final state of the entitlement workflow' AS Section;
CALL sp__ear_show_workflow(@w1);


-- ============================================================
-- PART 6 - SECOND PROTECTED ACTION: version creation (owner only)
-- ============================================================
SELECT '=== PART 6: PROTECTED ACTION 2 - CREATE DOCUMENT VERSION (OWNER ONLY) ===' AS Section;

INSERT INTO Document (Title, BusinessDescription, OwnerUserID, ClassificationID, LifecycleStatusID)
VALUES ('EAR Demo - Entitlement Version Document',
        'Document with no versions; used to test who may create a version.',
        @u_owner,
        (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_CLASSIFICATION' AND Code='INTERNAL' LIMIT 1),
        (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_STATUS' AND Code='DRAFT' LIMIT 1));
SET @e_doc = LAST_INSERT_ID();

CALL sp__ear_expect_reject('ENTITLEMENT',
    'Non-owner (Marcus) cannot create a version of the owner''s document',
    CONCAT('CALL sp_create_document_version(', @u_marcus, ',', @e_doc, ',1,''unauthorized'')'), @w1);
SET @ear_vc = (SELECT COUNT(*) FROM DocumentVersion WHERE DocumentID = @e_doc);
CALL sp__ear_check('ENTITLEMENT', 'Rejected version creation left zero versions',
    @ear_vc = 0, CONCAT('Versions after rejected attempt: ', @ear_vc));

CALL sp__ear_expect_ok('ENTITLEMENT', 'Document owner (Olivia) can create the version',
    CONCAT('CALL sp_create_document_version(', @u_owner, ',', @e_doc, ',1,''Owner-created version'')'));
SET @ear_vc = (SELECT COUNT(*) FROM DocumentVersion WHERE DocumentID = @e_doc);
CALL sp__ear_check('ENTITLEMENT', 'Owner-created version exists',
    @ear_vc = 1, CONCAT('Versions after owner attempt: ', @ear_vc));


-- ============================================================
-- SCOREBOARD
-- ============================================================
SELECT '=== ENTITLEMENT SCOREBOARD ===' AS Section;
SELECT COALESCE(area, 'ALL') AS Area, SUM(result = 'PASS') AS Passed,
       SUM(result = 'FAIL') AS Failed, COUNT(*) AS Total
FROM ear_results GROUP BY area WITH ROLLUP;

SELECT '=== FAILURES (should be empty) ===' AS Section;
SELECT seq, test_name, detail FROM ear_results WHERE result = 'FAIL' ORDER BY seq;

SELECT '=== FULL RESULT LOG ===' AS Section;
SELECT seq, result, test_name FROM ear_results ORDER BY seq;

DROP PROCEDURE IF EXISTS sp__ear_new_workflow;
DROP PROCEDURE IF EXISTS sp__ear_initiate;
DROP PROCEDURE IF EXISTS sp__ear_make_doc;
DROP PROCEDURE IF EXISTS sp__ear_show_workflow;
DROP PROCEDURE IF EXISTS sp__ear_expect_ok;
DROP PROCEDURE IF EXISTS sp__ear_expect_reject;
DROP PROCEDURE IF EXISTS sp__ear_snapshot;
DROP PROCEDURE IF EXISTS sp__ear_check;