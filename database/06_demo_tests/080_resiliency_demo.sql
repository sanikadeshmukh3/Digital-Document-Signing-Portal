-- ============================================================
-- File: database/06_demo_tests/080_resiliency_demo.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Demonstrate resiliency. Forces controlled failures of a
--   multi-step transaction (a natural constraint failure and a
--   forced trigger failure) and proves everything rolls back, then
--   retries with corrected input; exercises duplicate, out-of-
--   sequence and wrong-version guards; shows business rejection with
--   correction, cancellation and expiration; and confirms the
--   database is still consistent after all of it.
--
-- Important:
--   - Self-contained and re-runnable; creates its own demo data.
--   - Creates and drops one temporary trigger,
--     trg_Test_EAR_ForceFailure. If the script is interrupted, run:
--         DROP TRIGGER IF EXISTS trg_Test_EAR_ForceFailure;
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

DROP TRIGGER IF EXISTS trg_Test_EAR_ForceFailure;

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
            WHERE ws.WorkflowID = p_wf))
    ) INTO p_snap;
END $$

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
    VALUES (p_title, 'Isolated document for the resiliency demo.', v_owner, v_class, v_status);
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

-- Failed multi-step initiation must roll back completely; corrected retry must succeed.
--   p_mode 'FK'      : step 2 references a role id that does not exist
--   p_mode 'TRIGGER' : step 2 is valid, but a temporary trigger raises an error on its insert
DROP PROCEDURE IF EXISTS sp__ear_test_initiation_rollback $$
CREATE PROCEDURE sp__ear_test_initiation_rollback(IN p_mode VARCHAR(10))
BEGIN
    DECLARE v_doc, v_ver, v_owner, v_marcus, v_daniel, v_rev_role, v_app_role, v_role2 BIGINT UNSIGNED;
    DECLARE v_w, v_r, v_a, v_s BIGINT UNSIGNED;
    DECLARE v_due2 VARCHAR(30);
    DECLARE v_failed BOOLEAN DEFAULT FALSE;
    DECLARE v_retry_failed BOOLEAN DEFAULT FALSE;
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE v_retry_msg TEXT DEFAULT NULL;
    DECLARE v_wf_b, v_wf_a, v_st_b, v_st_a, v_pt_b, v_pt_a, v_au_b, v_au_a INT DEFAULT 0;
    DECLARE v_wf_f, v_st_f, v_pt_f INT DEFAULT 0;
    DECLARE v_vs_b, v_vs_a VARCHAR(50);
    DECLARE v_lk_b, v_lk_a VARCHAR(40);

    CALL sp__ear_make_doc(CONCAT('EAR Demo - Rollback Agreement ', p_mode), v_doc, v_ver);

    SELECT OwnerUserID INTO v_owner FROM Document WHERE DocumentID = v_doc;
    SELECT UserID INTO v_marcus FROM `User` WHERE Email = 'marcus.reed@initech.example' LIMIT 1;
    SELECT UserID INTO v_daniel FROM `User` WHERE Email = 'daniel.cho@initech.example' LIMIT 1;
    SELECT RoleID INTO v_rev_role FROM Role WHERE RoleName = 'Reviewer' LIMIT 1;
    SELECT RoleID INTO v_app_role FROM Role WHERE RoleName = 'Approver' LIMIT 1;

    SET v_role2 = IF(p_mode = 'FK', 999999999, v_app_role);
    SET v_due2  = IF(p_mode = 'FK',
                     DATE_FORMAT(DATE_ADD(NOW(), INTERVAL 14 DAY), '%Y-%m-%d %H:%i:%s'),
                     '2099-12-31 23:59:59');

    SELECT COUNT(*) INTO v_wf_b FROM Workflow WHERE DocumentID = v_doc;
    SELECT COUNT(*) INTO v_st_b FROM WorkflowStep ws JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
        WHERE w.DocumentID = v_doc;
    SELECT COUNT(*) INTO v_pt_b FROM WorkflowParticipant wp
        JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
        JOIN Workflow w ON w.WorkflowID = ws.WorkflowID WHERE w.DocumentID = v_doc;
    SELECT COUNT(*) INTO v_au_b FROM AuditLog;
    SELECT rd.Code, COALESCE(CAST(dv.LockedDateTime AS CHAR), 'NULL') INTO v_vs_b, v_lk_b
        FROM DocumentVersion dv JOIN ReferenceData rd ON rd.ReferenceDataID = dv.CurrentVersionStatusID
        WHERE dv.DocumentVersionID = v_ver;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_failed = TRUE;
        END;
        CALL sp_initiate_workflow(v_owner, v_doc, v_ver, 'FULL_REVIEW_APPROVAL_SIGNATURE',
            DATE_ADD(NOW(), INTERVAL 30 DAY),
            JSON_ARRAY(
                JSON_OBJECT('sequence_number', 1, 'step_type', 'REVIEW',
                    'due_date', DATE_FORMAT(DATE_ADD(NOW(), INTERVAL 7 DAY), '%Y-%m-%d %H:%i:%s'),
                    'participants', JSON_ARRAY(JSON_OBJECT('user_id', v_marcus,
                        'role_id', v_rev_role, 'action', 'REVIEW', 'required', 1))),
                JSON_OBJECT('sequence_number', 2, 'step_type', 'APPROVAL',
                    'due_date', v_due2,
                    'participants', JSON_ARRAY(JSON_OBJECT('user_id', v_daniel,
                        'role_id', v_role2, 'action', 'APPROVAL', 'required', 1)))));
    END;

    SELECT COUNT(*) INTO v_wf_a FROM Workflow WHERE DocumentID = v_doc;
    SELECT COUNT(*) INTO v_st_a FROM WorkflowStep ws JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
        WHERE w.DocumentID = v_doc;
    SELECT COUNT(*) INTO v_pt_a FROM WorkflowParticipant wp
        JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
        JOIN Workflow w ON w.WorkflowID = ws.WorkflowID WHERE w.DocumentID = v_doc;
    SELECT COUNT(*) INTO v_au_a FROM AuditLog;
    SELECT rd.Code, COALESCE(CAST(dv.LockedDateTime AS CHAR), 'NULL') INTO v_vs_a, v_lk_a
        FROM DocumentVersion dv JOIN ReferenceData rd ON rd.ReferenceDataID = dv.CurrentVersionStatusID
        WHERE dv.DocumentVersionID = v_ver;

    CALL sp__ear_check('RESILIENCY',
        CONCAT('[', p_mode, '] Failed multi-step initiation leaves no partial workflow, steps, assignments, audit rows or version lock'),
        v_failed AND v_wf_b = v_wf_a AND v_st_b = v_st_a AND v_pt_b = v_pt_a
            AND v_au_b = v_au_a AND v_vs_b = v_vs_a AND v_lk_b = v_lk_a,
        CONCAT('Error: ', COALESCE(v_msg, '(none - failure was NOT raised)'),
               ' || workflows ', v_wf_b, '->', v_wf_a, ', steps ', v_st_b, '->', v_st_a,
               ', assignments ', v_pt_b, '->', v_pt_a, ', audit ', v_au_b, '->', v_au_a,
               ', version ', v_vs_b, '->', v_vs_a, ', locked ', v_lk_b, '->', v_lk_a));

    -- RETRY with corrected input on the SAME document and version.
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_retry_msg = MESSAGE_TEXT;
            SET v_retry_failed = TRUE;
        END;
        CALL sp__ear_initiate(v_doc, v_ver, v_w, v_r, v_a, v_s);
    END;

    SELECT COUNT(*) INTO v_wf_f FROM Workflow WHERE DocumentID = v_doc;
    SELECT COUNT(*) INTO v_st_f FROM WorkflowStep ws JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
        WHERE w.DocumentID = v_doc;
    SELECT COUNT(*) INTO v_pt_f FROM WorkflowParticipant wp
        JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
        JOIN Workflow w ON w.WorkflowID = ws.WorkflowID WHERE w.DocumentID = v_doc;

    CALL sp__ear_check('RESILIENCY',
        CONCAT('[', p_mode, '] Retry with corrected input succeeds after the rolled-back attempt'),
        NOT v_retry_failed AND v_wf_f = 1 AND v_st_f = 3 AND v_pt_f = 3,
        CONCAT('Retry error: ', COALESCE(v_retry_msg, '(none)'),
               ' || workflows=', v_wf_f, ', steps=', v_st_f, ', assignments=', v_pt_f));
END $$

-- Correction after rejection: new version + new workflow; rejected history preserved.
DROP PROCEDURE IF EXISTS sp__ear_test_correction $$
CREATE PROCEDURE sp__ear_test_correction(IN p_doc BIGINT UNSIGNED, IN p_old_wf BIGINT UNSIGNED)
BEGIN
    DECLARE v_owner, v_v2, v_w, v_r, v_a, v_s BIGINT UNSIGNED;
    DECLARE v_failed BOOLEAN DEFAULT FALSE;
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE v_old_status VARCHAR(50);
    DECLARE v_v1_status VARCHAR(50);
    DECLARE v_wf_count INT DEFAULT 0;

    SELECT OwnerUserID INTO v_owner FROM Document WHERE DocumentID = p_doc;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_failed = TRUE;
        END;
        CALL sp_create_document_version(v_owner, p_doc, 2, 'Corrected after rejection');
        SELECT DocumentVersionID INTO v_v2 FROM DocumentVersion
            WHERE DocumentID = p_doc AND VersionNumber = 2 LIMIT 1;
        CALL sp__ear_initiate(p_doc, v_v2, v_w, v_r, v_a, v_s);
    END;

    SELECT rd.Code INTO v_old_status FROM Workflow w
        JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID
        WHERE w.WorkflowID = p_old_wf;
    SELECT rd.Code INTO v_v1_status FROM DocumentVersion dv
        JOIN ReferenceData rd ON rd.ReferenceDataID = dv.CurrentVersionStatusID
        WHERE dv.DocumentID = p_doc AND dv.VersionNumber = 1;
    SELECT COUNT(*) INTO v_wf_count FROM Workflow WHERE DocumentID = p_doc;

    CALL sp__ear_check('RESILIENCY',
        'Correction after rejection: new version v2 + new workflow; rejected history preserved',
        NOT v_failed AND v_wf_count = 2 AND v_old_status = 'REJECTED' AND v_v1_status = 'LOCKED',
        CONCAT('Error: ', COALESCE(v_msg, '(none)'), ' || workflows on document=', v_wf_count,
               ' || original workflow still ', COALESCE(v_old_status, '?'),
               ' || v1 still ', COALESCE(v_v1_status, '?')));
END $$

-- Temporary, test-only failure injector (dropped again right after use).
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


-- ============================================================
-- PART 1 - SETUP
-- ============================================================
SELECT '=== RESILIENCY DEMO - PART 1: SETUP ===' AS Section;

SET @u_owner  = (SELECT UserID FROM `User` WHERE Email = 'olivia.brooks@initech.example' LIMIT 1);
SET @u_marcus = (SELECT UserID FROM `User` WHERE Email = 'marcus.reed@initech.example' LIMIT 1);
SET @u_daniel = (SELECT UserID FROM `User` WHERE Email = 'daniel.cho@initech.example' LIMIT 1);
SET @u_sofia  = (SELECT UserID FROM `User` WHERE Email = 'sofia.alvarez@initech.example' LIMIT 1);

-- WF1: guards.  WF2: rejection + correction.  WF3: cancellation.  WF4: expiration.
CALL sp__ear_new_workflow('EAR Demo - Guards Agreement',       @d1, @v1, @w1, @r1, @a1, @s1);
CALL sp__ear_new_workflow('EAR Demo - Rejection Agreement',    @d2, @v2, @w2, @r2, @a2, @s2);
CALL sp__ear_new_workflow('EAR Demo - Cancellation Agreement', @d3, @v3, @w3, @r3, @a3, @s3);
CALL sp__ear_new_workflow('EAR Demo - Expiration Agreement',   @d4, @v4, @w4, @r4, @a4, @s4);


-- ============================================================
-- PART 2 - FAILED MULTI-STEP TRANSACTION + RETRY
-- ============================================================
SELECT '=== PART 2: CONTROLLED FAILURE OF A MULTI-STEP TRANSACTION ===' AS Section;

SELECT '2.1 Natural failure: step 2 references a non-existent role' AS Section;
CALL sp__ear_test_initiation_rollback('FK');

SELECT '2.2 Forced mid-transaction failure: step 1 inserted, trigger fails step 2 insert' AS Section;
CALL sp__ear_test_initiation_rollback('TRIGGER');

DROP TRIGGER IF EXISTS trg_Test_EAR_ForceFailure;


-- ============================================================
-- PART 3 - GUARDS (duplicate, out-of-sequence, wrong version)
-- ============================================================
SELECT '=== PART 3: GUARDS ON WF1 ===' AS Section;

CALL sp__ear_expect_reject('RESILIENCY',
    'Out-of-sequence: approval before the review step is complete is rejected',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_daniel, ',''APPROVED'',''too early'',NULL)'), @w1);
CALL sp__ear_expect_reject('RESILIENCY',
    'Out-of-sequence: signature before approval is complete is rejected',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_sofia, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''too early'')'), @w1);

CALL sp__ear_expect_ok('RESILIENCY', 'Review completed normally',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r1, ',', @u_marcus, ')'));
CALL sp__ear_expect_reject('RESILIENCY',
    'Duplicate review completion (replay) is rejected',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r1, ',', @u_marcus, ')'), @w1);

CALL sp__ear_expect_ok('RESILIENCY', 'Approval recorded normally',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_daniel, ',''APPROVED'',''guards demo'',NULL)'));
CALL sp__ear_expect_reject('RESILIENCY',
    'Duplicate approval (double-click / replay) is rejected; still exactly 1 decision',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_daniel, ',''APPROVED'',''replay'',NULL)'), @w1);

CALL sp__ear_expect_reject('RESILIENCY',
    'Signature bound to the WRONG document version is rejected',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_sofia, ',', @v2, ',''SIGNED'',''TYPED_NAME'',''wrong-version'')'), @w1);

CALL sp__ear_expect_ok('RESILIENCY', 'Signature recorded normally against the correct version',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_sofia, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''EAR-RES-SIG-1'')'));
CALL sp__ear_expect_reject('RESILIENCY',
    'Duplicate signature on an already-signed assignment is rejected',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_sofia, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''replay'')'), @w1);

SET @ear_t = (SELECT rd.Code FROM Workflow w
    JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID WHERE w.WorkflowID = @w1);
CALL sp__ear_check('RESILIENCY', 'After replays and bad attempts, WF1 is still cleanly COMPLETED',
    @ear_t = 'COMPLETED', CONCAT('Workflow status = ', COALESCE(@ear_t, '?')));


-- ============================================================
-- PART 4 - BUSINESS REJECTION AND CORRECTION (WF2)
-- ============================================================
SELECT '=== PART 4: REJECTION (BUSINESS OUTCOME) AND CORRECTION ===' AS Section;

CALL sp__ear_expect_ok('RESILIENCY', 'WF2: Marcus completes review',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r2, ',', @u_marcus, ')'));
CALL sp__ear_expect_reject('RESILIENCY',
    'WF2: rejection WITHOUT a reason is refused; nothing changes',
    CONCAT('CALL sp_record_approval_decision(', @a2, ',', @u_daniel, ',''REJECTED'',''no reason given'',NULL)'), @w2);
CALL sp__ear_expect_ok('RESILIENCY',
    'WF2: rejection WITH a reason is accepted as a valid business outcome (not a crash)',
    CONCAT('CALL sp_record_approval_decision(', @a2, ',', @u_daniel, ',''REJECTED'',''EAR demo rejection'',''Terms unacceptable'')'));

SET @ear_t = (SELECT CONCAT(wr.Code, ' / decisions=',
        (SELECT COUNT(*) FROM ApprovalDecision WHERE WorkflowParticipantID = @a2),
        ' / reason=', COALESCE(ad.RejectionReason, '(none)'))
    FROM Workflow w
    JOIN ReferenceData wr ON wr.ReferenceDataID = w.WorkflowStatusID
    LEFT JOIN ApprovalDecision ad ON ad.WorkflowParticipantID = @a2
    WHERE w.WorkflowID = @w2);
CALL sp__ear_check('RESILIENCY', 'WF2 ends REJECTED with the reason stored',
    @ear_t = 'REJECTED / decisions=1 / reason=Terms unacceptable', @ear_t);

CALL sp__ear_expect_reject('RESILIENCY', 'Signing a REJECTED workflow is refused',
    CONCAT('CALL sp_record_signature(', @s2, ',', @u_sofia, ',', @v2, ',''SIGNED'',''TYPED_NAME'',''after rejection'')'), @w2);

CALL sp__ear_test_correction(@d2, @w2);


-- ============================================================
-- PART 5 - CANCELLATION (WF3)
-- ============================================================
SELECT '=== PART 5: CANCELLATION (trigger cascade; later actions refused) ===' AS Section;

CALL sp__ear_expect_ok('RESILIENCY', 'WF3: cancel workflow (only the Workflow row is updated)',
    CONCAT('UPDATE Workflow SET WorkflowStatusID=(SELECT ReferenceDataID FROM ReferenceData ',
           'WHERE DomainName=''WORKFLOW_STATUS'' AND Code=''CANCELLED''), ',
           'CancellationDateTime=NOW(), CancellationReason=''EAR demo: cancelled'' WHERE WorkflowID=', @w3));

SET @ear_out = (SELECT COUNT(*) FROM WorkflowParticipant wp
        JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
        JOIN ReferenceData rd ON rd.ReferenceDataID = wp.AssignmentStatusID
        WHERE ws.WorkflowID = @w3 AND rd.Code <> 'CANCELLED')
    + (SELECT COUNT(*) FROM WorkflowStep ws
        JOIN ReferenceData rd ON rd.ReferenceDataID = ws.StepStatusID
        WHERE ws.WorkflowID = @w3 AND rd.Code <> 'CANCELLED');
CALL sp__ear_check('RESILIENCY', 'Trigger cascaded CANCELLED to every step and assignment of WF3',
    @ear_out = 0, CONCAT('Steps/assignments not CANCELLED: ', @ear_out));

CALL sp__ear_expect_reject('RESILIENCY', 'Review on a CANCELLED workflow is refused',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r3, ',', @u_marcus, ')'), @w3);


-- ============================================================
-- PART 6 - EXPIRATION (WF4)
-- ============================================================
SELECT '=== PART 6: EXPIRATION (batch procedure; later actions refused) ===' AS Section;

CALL sp__ear_expect_ok('RESILIENCY', 'WF4: make workflow overdue (test setup only)',
    CONCAT('UPDATE Workflow SET StartDateTime=DATE_SUB(NOW(), INTERVAL 2 DAY), ',
           'ExpirationDateTime=DATE_SUB(NOW(), INTERVAL 1 DAY) WHERE WorkflowID=', @w4));
CALL sp__ear_expect_ok('RESILIENCY',
    'sp_expire_workflows runs (batch; may also expire other overdue seeded workflows)',
    'CALL sp_expire_workflows(NULL)');

SET @ear_ex = (SELECT rd.Code FROM Workflow w
    JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID WHERE w.WorkflowID = @w4);
SET @ear_out = (SELECT COUNT(*) FROM WorkflowParticipant wp
        JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
        JOIN ReferenceData rd ON rd.ReferenceDataID = wp.AssignmentStatusID
        WHERE ws.WorkflowID = @w4 AND rd.Code IN ('PENDING', 'ACTIVE'))
    + (SELECT COUNT(*) FROM WorkflowStep ws
        JOIN ReferenceData rd ON rd.ReferenceDataID = ws.StepStatusID
        WHERE ws.WorkflowID = @w4 AND rd.Code IN ('PENDING', 'ACTIVE'));
SET @ear_exa = (SELECT COUNT(*) FROM AuditLog WHERE EventType = 'WORKFLOW_EXPIRED'
    AND AffectedRecordType = 'Workflow' AND AffectedRecordID = @w4);
CALL sp__ear_check('RESILIENCY', 'WF4 is EXPIRED, no outstanding work remains, expiry is audited',
    @ear_ex = 'EXPIRED' AND @ear_out = 0 AND @ear_exa >= 1,
    CONCAT('Status: ', COALESCE(@ear_ex, '?'), ' || outstanding: ', @ear_out,
           ' || expiry audit rows: ', @ear_exa));

CALL sp__ear_expect_reject('RESILIENCY', 'Review on an EXPIRED workflow is refused',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r4, ',', @u_marcus, ')'), @w4);


-- ============================================================
-- PART 7 - FINAL CONSISTENCY SWEEP
-- ============================================================
SELECT '=== PART 7: DATABASE IS STILL CONSISTENT AFTER EVERYTHING ABOVE ===' AS Section;

SET @ear_i1 = (SELECT COUNT(DISTINCT w.WorkflowID) FROM Workflow w
    JOIN ReferenceData wr ON wr.ReferenceDataID = w.WorkflowStatusID
    JOIN WorkflowStep st ON st.WorkflowID = w.WorkflowID
    JOIN WorkflowParticipant wp ON wp.WorkflowStepID = st.WorkflowStepID
    JOIN ReferenceData ps ON ps.ReferenceDataID = wp.AssignmentStatusID
    WHERE wr.Code = 'COMPLETED' AND ps.Code IN ('PENDING', 'ACTIVE'));
SET @ear_i2 = (SELECT COUNT(*) FROM Signature s
    JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = s.WorkflowParticipantID
    JOIN WorkflowStep st ON st.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w ON w.WorkflowID = st.WorkflowID
    WHERE s.DocumentVersionID <> w.DocumentVersionID);
SET @ear_i3 = (SELECT COUNT(*) FROM WorkflowParticipant wp
    LEFT JOIN UserRole ur ON ur.UserID = wp.UserID AND ur.RoleID = wp.RoleID
    WHERE ur.UserID IS NULL);
SET @ear_i4 = (SELECT COUNT(*) FROM ApprovalDecision ad
    JOIN ReferenceData dv ON dv.ReferenceDataID = ad.DecisionValueID
    WHERE dv.Code = 'REJECTED' AND (ad.RejectionReason IS NULL OR TRIM(ad.RejectionReason) = ''));
SET @ear_i5 = (SELECT COUNT(*) FROM Workflow w
    JOIN ReferenceData wr ON wr.ReferenceDataID = w.WorkflowStatusID
    WHERE wr.Code = 'CANCELLED' AND (w.CancellationReason IS NULL OR TRIM(w.CancellationReason) = ''));
SET @ear_i6 = (SELECT COUNT(*) FROM Workflow w
    LEFT JOIN WorkflowStep st ON st.WorkflowID = w.WorkflowID
    WHERE st.WorkflowStepID IS NULL);
CALL sp__ear_check('RESILIENCY', 'Global invariants hold after all tests (see detail)',
    @ear_i1 = 0 AND @ear_i2 = 0 AND @ear_i3 = 0 AND @ear_i4 = 0 AND @ear_i5 = 0 AND @ear_i6 = 0,
    CONCAT('completed-with-open-work=', @ear_i1, ', signature/version mismatches=', @ear_i2,
           ', assignment/role mismatches=', @ear_i3, ', rejections without reason=', @ear_i4,
           ', cancellations without reason=', @ear_i5, ', workflows with no steps (partial inits)=', @ear_i6));

-- Tip: re-run 05_validation/020_data_validation.sql now; it must still PASS
-- with all demo data included.

-- ------------------------------------------------------------
-- MANUAL CONCURRENCY / ISOLATION DEMO (needs two terminals; not automated)
--   Session A:  START TRANSACTION;
--               CALL sp_record_approval_decision(<participant>, <user>, 'APPROVED', 'A', NULL);
--               -- do NOT commit yet
--   Session B:  CALL sp_record_approval_decision(<same participant>, <same user>, 'APPROVED', 'B', NULL);
--               -- blocks on the row lock (or errors) until A finishes
--   Session A:  COMMIT;
--   Session B:  now fails as a duplicate; verify exactly ONE ApprovalDecision row exists.
-- ------------------------------------------------------------


-- ============================================================
-- SCOREBOARD
-- ============================================================
SELECT '=== RESILIENCY SCOREBOARD ===' AS Section;
SELECT COALESCE(area, 'ALL') AS Area, SUM(result = 'PASS') AS Passed,
       SUM(result = 'FAIL') AS Failed, COUNT(*) AS Total
FROM ear_results GROUP BY area WITH ROLLUP;

SELECT '=== FAILURES (should be empty) ===' AS Section;
SELECT seq, test_name, detail FROM ear_results WHERE result = 'FAIL' ORDER BY seq;

SELECT '=== FULL RESULT LOG ===' AS Section;
SELECT seq, result, test_name FROM ear_results ORDER BY seq;

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