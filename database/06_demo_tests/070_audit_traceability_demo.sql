-- ============================================================
-- File: database/06_demo_tests/070_audit_traceability_demo.sql
-- Project: Document Workflow and E-signing Portal
--
-- DEMO AREA 2 OF 3: AUDIT AND TRACEABILITY
--
--   * Perform audited business actions during the demo
--     (review, approval, signature, new document version) and prove
--     EACH ONE wrote audit rows
--   * Query audit/history: actor, event type, timestamp, affected
--     record, prior/new values, reason, transaction reference
--   * Prove finalized records and audit records cannot be silently
--     altered, back-dated or deleted
--   * Trace one record through its lifecycle (version -> workflow ->
--     steps -> decision -> signature -> completion -> next version)
--
-- Self-contained and re-runnable. Creates its own "EAR Demo" data.
-- NOT part of the normal build manifest.
--
-- ASSUMPTIONS (adjust helper calls if your procs differ):
--   sp_initiate_workflow(owner, doc, version, purpose_code, expiration, steps_json)
--   sp_create_document_version(owner, doc, version_no, effective_info)
--   sp_record_approval_decision(participant, user, decision, comments, reason)
--   sp_record_signature(participant, user, version, status, method, reference)
--   sp_complete_review_acknowledgement(participant, user)
--   Audit event type for version creation = DOCUMENT_VERSION_CREATED.
--   Column names: Signature.SignatureReference, ApprovalDecision.Comments.
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

-- Run a business action; it must succeed AND write at least one audit row.
DROP PROCEDURE IF EXISTS sp__ear_audited_action $$
CREATE PROCEDURE sp__ear_audited_action(IN p_name VARCHAR(200), IN p_stmt TEXT)
BEGIN
    DECLARE v_failed BOOLEAN DEFAULT FALSE;
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE v_max BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_n INT DEFAULT 0;
    DECLARE v_types TEXT DEFAULT NULL;

    SELECT COALESCE(MAX(AuditLogID), 0) INTO v_max FROM AuditLog;

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

    SELECT COUNT(*), GROUP_CONCAT(DISTINCT EventType ORDER BY EventType SEPARATOR ', ')
      INTO v_n, v_types
    FROM AuditLog WHERE AuditLogID > v_max;

    CALL sp__ear_check('AUDIT', p_name, NOT v_failed AND v_n >= 1,
        CONCAT('Error: ', COALESCE(v_msg, '(none)'),
               ' || New audit rows: ', v_n, ' || Event types: ', COALESCE(v_types, '(none)')));
END $$

-- Tamper attempt: DML must be rejected AND the row fingerprint must be unchanged.
-- p_probe:  SELECT MD5(...) INTO @ear_fp FROM <table> WHERE <pk>=<id>
DROP PROCEDURE IF EXISTS sp__ear_tamper $$
CREATE PROCEDURE sp__ear_tamper(IN p_name VARCHAR(200), IN p_dml TEXT, IN p_probe TEXT)
BEGIN
    DECLARE v_rejected BOOLEAN DEFAULT FALSE;
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE v_before VARCHAR(64);
    DECLARE v_after VARCHAR(64);

    SET @ear_probe = p_probe;
    SET @ear_fp = NULL;
    PREPARE ear_p FROM @ear_probe; EXECUTE ear_p; DEALLOCATE PREPARE ear_p;
    SET v_before = @ear_fp;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_rejected = TRUE;
        END;
        SET @ear_dml = p_dml;
        PREPARE ear_d FROM @ear_dml;
        EXECUTE ear_d;
        DEALLOCATE PREPARE ear_d;
    END;

    SET @ear_fp = NULL;
    PREPARE ear_p FROM @ear_probe; EXECUTE ear_p; DEALLOCATE PREPARE ear_p;
    SET v_after = @ear_fp;

    CALL sp__ear_check('AUDIT', p_name,
        v_rejected AND v_before IS NOT NULL AND v_before = v_after,
        CONCAT('Error raised: ', COALESCE(v_msg, '(NONE - tamper SUCCEEDED)'),
               ' || Row still exists and unchanged: ',
               IF(v_before IS NOT NULL AND v_before = v_after, 'yes', 'NO')));
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
    VALUES (p_title, 'Isolated document for the audit demo.', v_owner, v_class, v_status);
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
SELECT '=== AUDIT DEMO - PART 1: SETUP ===' AS Section;

SET @ear_audit_mark = (SELECT COALESCE(MAX(AuditLogID), 0) FROM AuditLog);

SET @u_owner  = (SELECT UserID FROM `User` WHERE Email = 'olivia.brooks@initech.example' LIMIT 1);
SET @u_marcus = (SELECT UserID FROM `User` WHERE Email = 'marcus.reed@initech.example' LIMIT 1);
SET @u_daniel = (SELECT UserID FROM `User` WHERE Email = 'daniel.cho@initech.example' LIMIT 1);
SET @u_sofia  = (SELECT UserID FROM `User` WHERE Email = 'sofia.alvarez@initech.example' LIMIT 1);

CALL sp__ear_new_workflow('EAR Demo - Audit Agreement', @d1, @v1, @w1, @r1, @a1, @s1);


-- ============================================================
-- PART 2 - AUDITED BUSINESS ACTIONS (each must write audit rows)
-- ============================================================
SELECT '=== PART 2: PERFORM AUDITED BUSINESS ACTIONS ===' AS Section;

CALL sp__ear_audited_action('Marcus completes REVIEW -> audit row(s) written',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r1, ',', @u_marcus, ')'));

CALL sp__ear_audited_action('Daniel records APPROVAL -> audit row(s) written',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_daniel, ',''APPROVED'',''Audit demo approval'',NULL)'));

CALL sp__ear_audited_action('Sofia records SIGNATURE -> audit row(s) written',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_sofia, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''EAR-AUDIT-SIG-1'')'));

CALL sp__ear_audited_action('Owner creates version 2 of the signed document -> audit row(s) written',
    CONCAT('CALL sp_create_document_version(', @u_owner, ',', @d1, ',2,''Audit demo: revised after signing'')'));

SET @v1b = (SELECT DocumentVersionID FROM DocumentVersion WHERE DocumentID = @d1 AND VersionNumber = 2);

SET @ear_t = (SELECT CONCAT(wr.Code, ' / signature version matches workflow version: ',
                            IF(s.DocumentVersionID = w.DocumentVersionID, 'yes', 'NO'))
              FROM Workflow w
              JOIN ReferenceData wr ON wr.ReferenceDataID = w.WorkflowStatusID
              LEFT JOIN Signature s ON s.WorkflowParticipantID = @s1
              WHERE w.WorkflowID = @w1);
CALL sp__ear_check('AUDIT', 'Workflow finalized (COMPLETED); signature tied to the exact version signed',
    @ear_t = 'COMPLETED / signature version matches workflow version: yes', @ear_t);


-- ============================================================
-- PART 3 - AUDIT QUERIES
-- ============================================================
SELECT '=== PART 3: AUDIT QUERIES ===' AS Section;

SELECT '3.1 Raw AuditLog rows written during this demo' AS Section;
SELECT al.AuditLogID, al.EventDateTime,
       COALESCE(CONCAT(u.FirstName, ' ', u.LastName), 'SYSTEM') AS Actor,
       al.EventType, al.AffectedRecordType, al.AffectedRecordID,
       al.TransactionReference, al.PriorValueContext, al.NewValueContext, al.ChangeReason
FROM AuditLog al
LEFT JOIN `User` u ON u.UserID = al.ActorUserID
WHERE al.AuditLogID > @ear_audit_mark
ORDER BY al.EventDateTime, al.AuditLogID;

SELECT '3.2 Same period through the project view vw_AuditHistory' AS Section;
SELECT AuditLogID, EventDateTime, ActorName, EventType, AffectedRecordType,
       AffectedRecordID, ChangeReason
FROM vw_AuditHistory
WHERE AuditLogID > @ear_audit_mark
ORDER BY EventDateTime, AuditLogID;

SELECT '3.3 Audit quality checks' AS Section;
SET @ear_nulls = (SELECT COUNT(*) FROM AuditLog WHERE AuditLogID > @ear_audit_mark
    AND (EventDateTime IS NULL OR EventType IS NULL OR AffectedRecordType IS NULL OR AffectedRecordID IS NULL));
CALL sp__ear_check('AUDIT', 'Every new audit row has timestamp, event type, record type and record id',
    @ear_nulls = 0, CONCAT('Rows with missing fields: ', @ear_nulls));

SET @ear_m = (SELECT COUNT(*) FROM AuditLog WHERE AuditLogID > @ear_audit_mark AND ActorUserID = @u_marcus);
SET @ear_d = (SELECT COUNT(*) FROM AuditLog WHERE AuditLogID > @ear_audit_mark AND ActorUserID = @u_daniel);
SET @ear_s = (SELECT COUNT(*) FROM AuditLog WHERE AuditLogID > @ear_audit_mark AND ActorUserID = @u_sofia);
SET @ear_o = (SELECT COUNT(*) FROM AuditLog WHERE AuditLogID > @ear_audit_mark AND ActorUserID = @u_owner);
CALL sp__ear_check('AUDIT', 'Each action is attributed to the correct actor (Marcus, Daniel, Sofia, owner)',
    @ear_m >= 1 AND @ear_d >= 1 AND @ear_s >= 1 AND @ear_o >= 1,
    CONCAT('Audit rows - Marcus: ', @ear_m, ', Daniel: ', @ear_d, ', Sofia: ', @ear_s, ', Owner: ', @ear_o));

SET @ear_ctx = (SELECT COUNT(*) FROM AuditLog WHERE AuditLogID > @ear_audit_mark
    AND (PriorValueContext IS NOT NULL OR NewValueContext IS NOT NULL));
CALL sp__ear_check('AUDIT', 'Audit rows capture prior/new value context for changes',
    @ear_ctx >= 1, CONCAT('Rows with prior/new context: ', @ear_ctx));

SET @ear_ver = (SELECT COUNT(*) FROM AuditLog WHERE EventType = 'DOCUMENT_VERSION_CREATED'
    AND AffectedRecordType = 'DocumentVersion' AND AffectedRecordID = @v1b);
CALL sp__ear_check('AUDIT', 'Version-2 creation is audited against the new DocumentVersion record',
    @ear_ver = 1, CONCAT('DOCUMENT_VERSION_CREATED rows for version 2: ', @ear_ver));


-- ============================================================
-- PART 4 - TAMPER ATTEMPTS (finalized + audit records are immutable)
-- ============================================================
SELECT '=== PART 4: TAMPER ATTEMPTS MUST FAIL ===' AS Section;

SET @al = (SELECT MAX(AuditLogID) FROM AuditLog);
SET @probe_al = CONCAT('SELECT MD5(CONCAT_WS(''|'',AuditLogID,EventDateTime,EventType,AffectedRecordType,AffectedRecordID,COALESCE(ChangeReason,''''))) INTO @ear_fp FROM AuditLog WHERE AuditLogID=', @al);
CALL sp__ear_tamper('AuditLog: UPDATE event type blocked',
    CONCAT('UPDATE AuditLog SET EventType=''TAMPERED'' WHERE AuditLogID=', @al), @probe_al);
CALL sp__ear_tamper('AuditLog: BACK-DATING the timestamp blocked',
    CONCAT('UPDATE AuditLog SET EventDateTime=''2000-01-01 00:00:00'' WHERE AuditLogID=', @al), @probe_al);
CALL sp__ear_tamper('AuditLog: changing the actor blocked',
    CONCAT('UPDATE AuditLog SET ActorUserID=', @u_owner, ' WHERE AuditLogID=', @al), @probe_al);
CALL sp__ear_tamper('AuditLog: DELETE blocked',
    CONCAT('DELETE FROM AuditLog WHERE AuditLogID=', @al), @probe_al);

SET @ad = (SELECT ApprovalID FROM ApprovalDecision WHERE WorkflowParticipantID = @a1);
SET @probe_ad = CONCAT('SELECT MD5(CONCAT_WS(''|'',ApprovalID,WorkflowParticipantID,DecisionValueID,DecisionDateTime,COALESCE(Comments,''''))) INTO @ear_fp FROM ApprovalDecision WHERE ApprovalID=', @ad);
CALL sp__ear_tamper('ApprovalDecision: UPDATE blocked',
    CONCAT('UPDATE ApprovalDecision SET Comments=''TAMPERED'' WHERE ApprovalID=', @ad), @probe_ad);
CALL sp__ear_tamper('ApprovalDecision: DELETE blocked',
    CONCAT('DELETE FROM ApprovalDecision WHERE ApprovalID=', @ad), @probe_ad);

SET @sg = (SELECT SignatureID FROM Signature WHERE WorkflowParticipantID = @s1);
SET @probe_sg = CONCAT('SELECT MD5(CONCAT_WS(''|'',SignatureID,WorkflowParticipantID,DocumentVersionID,SigningDateTime,COALESCE(SignatureReference,''''))) INTO @ear_fp FROM Signature WHERE SignatureID=', @sg);
CALL sp__ear_tamper('Signature: UPDATE blocked',
    CONCAT('UPDATE Signature SET SignatureReference=''TAMPERED'' WHERE SignatureID=', @sg), @probe_sg);
CALL sp__ear_tamper('Signature: re-pointing to a different version blocked',
    CONCAT('UPDATE Signature SET DocumentVersionID=', @v1b, ' WHERE SignatureID=', @sg), @probe_sg);
CALL sp__ear_tamper('Signature: DELETE blocked',
    CONCAT('DELETE FROM Signature WHERE SignatureID=', @sg), @probe_sg);

SET @probe_dv = CONCAT('SELECT MD5(CONCAT_WS(''|'',DocumentVersionID,VersionNumber,COALESCE(EffectiveInformation,''''),CurrentVersionStatusID,COALESCE(LockedDateTime,''''))) INTO @ear_fp FROM DocumentVersion WHERE DocumentVersionID=', @v1);
CALL sp__ear_tamper('Locked DocumentVersion: UPDATE content blocked',
    CONCAT('UPDATE DocumentVersion SET EffectiveInformation=''TAMPERED'' WHERE DocumentVersionID=', @v1), @probe_dv);
CALL sp__ear_tamper('Locked DocumentVersion: UNLOCK attempt blocked',
    CONCAT('UPDATE DocumentVersion SET LockedDateTime=NULL WHERE DocumentVersionID=', @v1), @probe_dv);
CALL sp__ear_tamper('Locked DocumentVersion: DELETE blocked',
    CONCAT('DELETE FROM DocumentVersion WHERE DocumentVersionID=', @v1), @probe_dv);


-- ============================================================
-- PART 5 - HISTORY / LIFECYCLE TRACE REPORTS
-- ============================================================
SELECT '=== PART 5: LIFECYCLE TRACE OF ONE DOCUMENT ===' AS Section;

SELECT '5.1 Project view vw_DocumentHistory for the traced document' AS Section;
SELECT DocumentID, Title, DocumentStatus, VersionNumber, WorkflowID, WorkflowStatus,
       SequenceNumber, StepType, StepStatus, AssignedAction, AssignmentStatus,
       ApprovalDecision, SignatureStatus
FROM vw_DocumentHistory
WHERE DocumentID = @d1
ORDER BY VersionNumber, WorkflowID, SequenceNumber, WorkflowParticipantID;

SELECT '5.2 Project view vw_DocumentVersionHistory (v1 locked, v2 created after signing)' AS Section;
SELECT DocumentID, Title, VersionNumber, VersionStatus, CreatedByName, LockedDateTime, WorkflowCount
FROM vw_DocumentVersionHistory
WHERE DocumentID = @d1
ORDER BY VersionNumber;

SELECT '5.3 Chronological trace: versions, workflow, steps, decision, signature, completion' AS Section;
SELECT ts AS EventTime, source AS Record, event AS Event, actor AS Actor, detail AS Detail
FROM (
    SELECT dv.CreatedDateTime AS ts, 'DocumentVersion' AS source, 'VERSION_CREATED' AS event,
           CONCAT(cu.FirstName, ' ', cu.LastName) AS actor, CONCAT('v', dv.VersionNumber) AS detail
    FROM DocumentVersion dv JOIN `User` cu ON cu.UserID = dv.CreatedByUserID
    WHERE dv.DocumentID = @d1
    UNION ALL
    SELECT dv.LockedDateTime, 'DocumentVersion', 'VERSION_LOCKED', '(system)', CONCAT('v', dv.VersionNumber)
    FROM DocumentVersion dv WHERE dv.DocumentID = @d1
    UNION ALL
    SELECT w.StartDateTime, 'Workflow', 'WORKFLOW_STARTED',
           CONCAT(iu.FirstName, ' ', iu.LastName), CONCAT('Workflow ', w.WorkflowID)
    FROM Workflow w JOIN `User` iu ON iu.UserID = w.InitiatorUserID WHERE w.WorkflowID = @w1
    UNION ALL
    SELECT ws.ActivationDateTime, 'WorkflowStep', 'STEP_ACTIVATED', '(system)',
           CONCAT('Seq ', ws.SequenceNumber, ' ', st.Code)
    FROM WorkflowStep ws JOIN ReferenceData st ON st.ReferenceDataID = ws.StepTypeID
    WHERE ws.WorkflowID = @w1
    UNION ALL
    SELECT ws.CompletionDateTime, 'WorkflowStep', 'STEP_COMPLETED', '(system)',
           CONCAT('Seq ', ws.SequenceNumber, ' ', st.Code)
    FROM WorkflowStep ws JOIN ReferenceData st ON st.ReferenceDataID = ws.StepTypeID
    WHERE ws.WorkflowID = @w1
    UNION ALL
    SELECT ad.DecisionDateTime, 'ApprovalDecision', CONCAT('DECISION_', dc.Code),
           CONCAT(u.FirstName, ' ', u.LastName), COALESCE(ad.Comments, '')
    FROM ApprovalDecision ad
    JOIN ReferenceData dc ON dc.ReferenceDataID = ad.DecisionValueID
    JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = ad.WorkflowParticipantID
    JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN `User` u ON u.UserID = wp.UserID
    WHERE ws.WorkflowID = @w1
    UNION ALL
    SELECT s.SigningDateTime, 'Signature', 'SIGNED', CONCAT(u.FirstName, ' ', u.LastName),
           CONCAT('Version ', dv.VersionNumber, ' via ', COALESCE(s.SignatureMethod, '?'))
    FROM Signature s
    JOIN DocumentVersion dv ON dv.DocumentVersionID = s.DocumentVersionID
    JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = s.WorkflowParticipantID
    JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN `User` u ON u.UserID = wp.UserID
    WHERE ws.WorkflowID = @w1
    UNION ALL
    SELECT w.CompletionDateTime, 'Workflow', 'WORKFLOW_COMPLETED', '(system)', CONCAT('Workflow ', w.WorkflowID)
    FROM Workflow w WHERE w.WorkflowID = @w1
) trace
WHERE ts IS NOT NULL
ORDER BY ts, event;

SELECT '5.4 AuditLog entries for the same workflow and versions' AS Section;
SELECT al.AuditLogID, al.EventDateTime,
       COALESCE(CONCAT(u.FirstName, ' ', u.LastName), 'SYSTEM') AS Actor,
       al.EventType, al.AffectedRecordType, al.AffectedRecordID,
       al.PriorValueContext, al.NewValueContext, al.ChangeReason
FROM AuditLog al
LEFT JOIN `User` u ON u.UserID = al.ActorUserID
WHERE (al.AffectedRecordType = 'Workflow' AND al.AffectedRecordID = @w1)
   OR (al.AffectedRecordType = 'DocumentVersion' AND al.AffectedRecordID IN (@v1, @v1b))
ORDER BY al.EventDateTime, al.AuditLogID;

SET @ear_ms = (SELECT (w.CompletionDateTime IS NOT NULL)
        AND (dv.LockedDateTime IS NOT NULL)
        AND ((SELECT COUNT(*) FROM WorkflowStep WHERE WorkflowID = @w1 AND CompletionDateTime IS NOT NULL) = 3)
        AND EXISTS (SELECT 1 FROM ApprovalDecision WHERE WorkflowParticipantID = @a1)
        AND EXISTS (SELECT 1 FROM Signature WHERE WorkflowParticipantID = @s1)
        AND ((SELECT COUNT(*) FROM DocumentVersion WHERE DocumentID = @d1) = 2)
    FROM Workflow w JOIN DocumentVersion dv ON dv.DocumentVersionID = w.DocumentVersionID
    WHERE w.WorkflowID = @w1);
CALL sp__ear_check('AUDIT',
    'Trace is complete: version locked, 3 steps completed, decision, signature, workflow completed, v2 exists',
    @ear_ms = 1, CONCAT('Milestone check = ', COALESCE(@ear_ms, 'NULL')));


-- ============================================================
-- SCOREBOARD
-- ============================================================
SELECT '=== AUDIT SCOREBOARD ===' AS Section;
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
DROP PROCEDURE IF EXISTS sp__ear_tamper;
DROP PROCEDURE IF EXISTS sp__ear_audited_action;
DROP PROCEDURE IF EXISTS sp__ear_check;