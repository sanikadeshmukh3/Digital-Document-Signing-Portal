-- ============================================================================
-- File:     database/06_demo_tests/070_audit_traceability_demo.sql
-- Project:  Document Workflow and E-signing Portal
-- Database: MySQL 8.x
-- ============================================================================
--
-- PURPOSE
--   Prove the system keeps a complete, tamper-proof paper trail.
--
-- WHAT THIS FILE PROVES
--   Part 2  Audited actions   Review, approval, signature and new-version
--                             each write at least one audit row.
--   Part 3  Audit queries     The audit rows say WHO did WHAT, WHEN, to WHICH
--                             record, with BEFORE/AFTER values.
--   Part 4  Tamper attempts   Finalized and audit records cannot be silently
--                             edited, back-dated, re-attributed or deleted.
--   Part 5  Lifecycle trace   One document can be followed from creation to
--                             completion in a single timeline.
--
-- HOW TO READ THIS FILE
--   1. Skim "THE CAST", "VARIABLE LEGEND" and "HELPER QUICK REFERENCE".
--   2. SKIP the HELPER PROCEDURES section on a first read.
--   3. Jump to "PART 1 - SETUP" and read straight down. Each test is
--      written as WHAT / WHY / EXPECT, followed by the code.
--
-- THE CAST (all created by the seed data)
--   Olivia Brooks  document OWNER
--   Marcus Reed    REVIEWER   (step 1)
--   Daniel Cho     APPROVER   (step 2)
--   Sofia Alvarez  SIGNER     (step 3)
--
-- THE DEMO WORKFLOW
--   Step 1: Marcus REVIEWS -> Step 2: Daniel APPROVES -> Step 3: Sofia SIGNS
--   After it completes, Olivia creates version 2 of the (locked) document.
--
-- VARIABLE LEGEND
--   @u_owner, @u_marcus, @u_daniel, @u_sofia   user ids (see cast)
--   @d1   demo document id
--   @v1   version 1 of the demo document (the one that gets signed + locked)
--   @v1b  version 2 of the demo document (created after signing)
--   @w1   demo workflow id
--   @r1 / @a1 / @s1   Marcus's review / Daniel's approval / Sofia's signature
--                     assignment ids (WorkflowParticipantID)
--   @ear_audit_mark   highest AuditLogID BEFORE the demo's actions; later we
--                     look only at rows with a bigger id (the demo's own trail)
--   @al, @ad, @sg     the AuditLog / ApprovalDecision / Signature row we
--                     try to tamper with in Part 4
--   @probe_*          the SQL text that "fingerprints" a row (see sp__ear_tamper)
--   @ear_*            short-lived scratch values for a single check
--
-- HELPER QUICK REFERENCE
--   sp__ear_check          Writes one PASS/FAIL row to the scoreboard.
--   sp__ear_audited_action Runs a business action; PASS if it succeeds AND
--                          writes at least one new audit row.
--   sp__ear_tamper         Tries to change/delete a row; PASS if the attempt
--                          is rejected AND the row's MD5 fingerprint is the same.
--   sp__ear_make_doc       Creates a fresh demo document + version 1.
--   sp__ear_initiate       Starts the 3-step workflow on that document.
--   sp__ear_new_workflow   Shortcut: make_doc + initiate.
--
-- IMPORTANT
--   - Self-contained and re-runnable: it creates its own demo data.
--   - This file is NOT part of the normal build manifest.
-- ============================================================================


-- ============================================================================
-- SESSION SETUP
-- ============================================================================

-- Pin a portable, strict session sql_mode for this script and restore the
-- caller's mode at the very end, so the demo behaves identically everywhere.
-- In particular this clears IGNORE_SPACE. Under IGNORE_SPACE a built-in call
-- such as MD5(...) can be mis-resolved to a stored function and fail with
-- "FUNCTION <db>.MD5 does not exist". Part 4 relies on MD5() as a fingerprint.
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
-- sp__ear_audited_action
--   Runs a real business action (p_stmt) and proves it leaves a paper trail.
--   PASS only if BOTH are true:
--     1. the action ran without error, and
--     2. at least one new AuditLog row appeared while it ran.
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__ear_audited_action $$
CREATE PROCEDURE sp__ear_audited_action(IN p_name VARCHAR(200), IN p_stmt TEXT)
BEGIN
    DECLARE v_failed BOOLEAN DEFAULT FALSE;           -- did the action error?
    DECLARE v_msg    TEXT    DEFAULT NULL;            -- the error message, if any
    DECLARE v_max    BIGINT UNSIGNED DEFAULT 0;       -- highest audit id before
    DECLARE v_n      INT     DEFAULT 0;               -- how many new audit rows
    DECLARE v_types  TEXT    DEFAULT NULL;            -- their event types

    -- Step 1: remember the highest audit id right now.
    SELECT COALESCE(MAX(AuditLogID), 0) INTO v_max FROM AuditLog;

    -- Step 2: run the action; if it errors, remember that instead of crashing.
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

    -- Step 3: count and describe the audit rows added since step 1.
    SELECT COUNT(*), GROUP_CONCAT(DISTINCT EventType ORDER BY EventType SEPARATOR ', ')
      INTO v_n, v_types
    FROM AuditLog
    WHERE AuditLogID > v_max;

    -- Step 4: PASS = no error AND at least one new audit row.
    CALL sp__ear_check('AUDIT', p_name, NOT v_failed AND v_n >= 1,
        CONCAT('Error: ', COALESCE(v_msg, '(none)'),
               ' || New audit rows: ', v_n,
               ' || Event types: ', COALESCE(v_types, '(none)')));
END $$

-- ----------------------------------------------------------------------------
-- sp__ear_tamper
--   A deliberate cheating attempt.
--     p_dml    the UPDATE or DELETE we try (expected to be refused)
--     p_probe  a SQL statement of the form
--                SELECT MD5(<columns joined together>) INTO @ear_fp
--                FROM <table> WHERE <primary key> = <id>
--              It produces a "fingerprint" of the row: if any watched column
--              changes, the MD5 changes. If the row is deleted, the
--              fingerprint becomes NULL.
--   PASS only if ALL are true:
--     1. the fingerprint existed before (the row was there),
--     2. the cheating statement raised an error, and
--     3. the fingerprint is identical after (the row is untouched).
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp__ear_tamper $$
CREATE PROCEDURE sp__ear_tamper(IN p_name VARCHAR(200), IN p_dml TEXT, IN p_probe TEXT)
BEGIN
    DECLARE v_rejected BOOLEAN DEFAULT FALSE;   -- did the cheat attempt error?
    DECLARE v_msg      TEXT    DEFAULT NULL;
    DECLARE v_before   VARCHAR(64);             -- fingerprint before
    DECLARE v_after    VARCHAR(64);             -- fingerprint after

    -- Step 1: take the fingerprint BEFORE.
    SET @ear_probe = p_probe;
    SET @ear_fp = NULL;
    PREPARE ear_p FROM @ear_probe;
    EXECUTE ear_p;
    DEALLOCATE PREPARE ear_p;
    SET v_before = @ear_fp;

    -- Step 2: attempt the tampering; if it errors, remember that.
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

    -- Step 3: take the fingerprint AFTER.
    SET @ear_fp = NULL;
    PREPARE ear_p FROM @ear_probe;
    EXECUTE ear_p;
    DEALLOCATE PREPARE ear_p;
    SET v_after = @ear_fp;

    -- Step 4: PASS = rejected AND row existed AND row unchanged.
    CALL sp__ear_check('AUDIT', p_name,
        v_rejected AND v_before IS NOT NULL AND v_before = v_after,
        CONCAT('Error raised: ', COALESCE(v_msg, '(NONE - tamper SUCCEEDED)'),
               ' || Row still exists and unchanged: ',
               IF(v_before IS NOT NULL AND v_before = v_after, 'yes', 'NO')));
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
    VALUES (p_title, 'Isolated document for the audit demo.', v_owner, v_class, v_status);
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
--   Drop a "you are here" marker in the audit log, then build one workflow.
-- ============================================================================
SELECT '=== AUDIT DEMO - PART 1: SETUP ===' AS Section;

-- Remember the highest audit id right now. Later we only look at rows with a
-- bigger id, which isolates the trail created by THIS demo.
SET @ear_audit_mark = (SELECT COALESCE(MAX(AuditLogID), 0) FROM AuditLog);

-- The cast, found by email address.
SET @u_owner  = (SELECT UserID FROM `User` WHERE Email = 'olivia.brooks@initech.example' LIMIT 1);
SET @u_marcus = (SELECT UserID FROM `User` WHERE Email = 'marcus.reed@initech.example' LIMIT 1);
SET @u_daniel = (SELECT UserID FROM `User` WHERE Email = 'daniel.cho@initech.example' LIMIT 1);
SET @u_sofia  = (SELECT UserID FROM `User` WHERE Email = 'sofia.alvarez@initech.example' LIMIT 1);

-- Build the demo document + workflow.
--   outputs: @d1 doc, @v1 version, @w1 workflow,
--            @r1 Marcus's review, @a1 Daniel's approval, @s1 Sofia's signature
CALL sp__ear_new_workflow('EAR Demo - Audit Agreement', @d1, @v1, @w1, @r1, @a1, @s1);


-- ============================================================================
-- PART 2 - AUDITED BUSINESS ACTIONS
--   Do four real actions. Each must succeed AND leave at least one audit row
--   behind (like a security camera recording every step).
--   CHECKS 1-5
-- ============================================================================
SELECT '=== PART 2: PERFORM AUDITED BUSINESS ACTIONS ===' AS Section;

-- CHECK 1:  Marcus completes his review.
--   Runs: CALL sp_complete_review_acknowledgement(<Marcus's review>, <Marcus>)
CALL sp__ear_audited_action('Marcus completes REVIEW -> audit row(s) written',
    CONCAT('CALL sp_complete_review_acknowledgement(', @r1, ',', @u_marcus, ')'));

-- CHECK 2:  Daniel approves.
--   Runs: CALL sp_record_approval_decision(<Daniel's approval>, <Daniel>,
--                  'APPROVED', 'Audit demo approval', NULL)
CALL sp__ear_audited_action('Daniel records APPROVAL -> audit row(s) written',
    CONCAT('CALL sp_record_approval_decision(', @a1, ',', @u_daniel, ',''APPROVED'',''Audit demo approval'',NULL)'));

-- CHECK 3:  Sofia signs version 1.
--   Runs: CALL sp_record_signature(<Sofia's signature>, <Sofia>, <v1>,
--                  'SIGNED', 'TYPED_NAME', 'EAR-AUDIT-SIG-1')
CALL sp__ear_audited_action('Sofia records SIGNATURE -> audit row(s) written',
    CONCAT('CALL sp_record_signature(', @s1, ',', @u_sofia, ',', @v1, ',''SIGNED'',''TYPED_NAME'',''EAR-AUDIT-SIG-1'')'));

-- CHECK 4:  Olivia creates version 2 of the already-signed document.
--   Runs: CALL sp_create_document_version(<Olivia>, <document>, 2,
--                  'Audit demo: revised after signing')
CALL sp__ear_audited_action('Owner creates version 2 of the signed document -> audit row(s) written',
    CONCAT('CALL sp_create_document_version(', @u_owner, ',', @d1, ',2,''Audit demo: revised after signing'')'));

-- Remember version 2's id for later.
SET @v1b = (SELECT DocumentVersionID FROM DocumentVersion WHERE DocumentID = @d1 AND VersionNumber = 2);

-- CHECK 5
--   WHAT:   read the workflow status and compare the signature's version
--           with the workflow's version.
--   WHY:    a finished workflow must be COMPLETED, and the signature must be
--           bound to the exact version that was signed (not v2).
--   EXPECT: 'COMPLETED / signature version matches workflow version: yes'
SET @ear_t = (
    SELECT CONCAT(wr.Code,
                  ' / signature version matches workflow version: ',
                  IF(s.DocumentVersionID = w.DocumentVersionID, 'yes', 'NO'))
    FROM Workflow w
    JOIN ReferenceData wr ON wr.ReferenceDataID = w.WorkflowStatusID
    LEFT JOIN Signature s ON s.WorkflowParticipantID = @s1
    WHERE w.WorkflowID = @w1);

CALL sp__ear_check('AUDIT',
    'Workflow finalized (COMPLETED); signature tied to the exact version signed',
    @ear_t = 'COMPLETED / signature version matches workflow version: yes',
    @ear_t);


-- ============================================================================
-- PART 3 - AUDIT QUERIES
--   Read the trail back and check it answers: who, what, when, which record,
--   before/after values, and that each action is credited to the right person.
--   CHECKS 6-9
-- ============================================================================
SELECT '=== PART 3: AUDIT QUERIES ===' AS Section;

-- 3.1  Informational: the raw audit rows this demo created.
SELECT '3.1 Raw AuditLog rows written during this demo' AS Section;
SELECT al.AuditLogID,
       al.EventDateTime,
       COALESCE(CONCAT(u.FirstName, ' ', u.LastName), 'SYSTEM') AS Actor,
       al.EventType,
       al.AffectedRecordType,
       al.AffectedRecordID,
       al.TransactionReference,
       al.PriorValueContext,
       al.NewValueContext,
       al.ChangeReason
FROM AuditLog al
LEFT JOIN `User` u ON u.UserID = al.ActorUserID
WHERE al.AuditLogID > @ear_audit_mark
ORDER BY al.EventDateTime, al.AuditLogID;

-- 3.2  Informational: the same rows through the project's own view.
SELECT '3.2 Same period through the project view vw_AuditHistory' AS Section;
SELECT AuditLogID, EventDateTime, ActorName, EventType, AffectedRecordType,
       AffectedRecordID, ChangeReason
FROM vw_AuditHistory
WHERE AuditLogID > @ear_audit_mark
ORDER BY EventDateTime, AuditLogID;

SELECT '3.3 Audit quality checks' AS Section;

-- CHECK 6
--   WHAT:   count new audit rows missing a timestamp, event type, record type
--           or record id.
--   WHY:    an audit row that cannot say when / what / which record is useless.
--   EXPECT: 0.
SET @ear_nulls = (
    SELECT COUNT(*)
    FROM AuditLog
    WHERE AuditLogID > @ear_audit_mark
      AND (EventDateTime IS NULL
        OR EventType IS NULL
        OR AffectedRecordType IS NULL
        OR AffectedRecordID IS NULL));

CALL sp__ear_check('AUDIT',
    'Every new audit row has timestamp, event type, record type and record id',
    @ear_nulls = 0,
    CONCAT('Rows with missing fields: ', @ear_nulls));

-- CHECK 7
--   WHAT:   count new audit rows credited to each person.
--   WHY:    every action must be pinned to the person who really did it.
--   EXPECT: at least 1 row each for Marcus, Daniel, Sofia and Olivia.
SET @ear_m = (SELECT COUNT(*) FROM AuditLog WHERE AuditLogID > @ear_audit_mark AND ActorUserID = @u_marcus);
SET @ear_d = (SELECT COUNT(*) FROM AuditLog WHERE AuditLogID > @ear_audit_mark AND ActorUserID = @u_daniel);
SET @ear_s = (SELECT COUNT(*) FROM AuditLog WHERE AuditLogID > @ear_audit_mark AND ActorUserID = @u_sofia);
SET @ear_o = (SELECT COUNT(*) FROM AuditLog WHERE AuditLogID > @ear_audit_mark AND ActorUserID = @u_owner);

CALL sp__ear_check('AUDIT',
    'Each action is attributed to the correct actor (Marcus, Daniel, Sofia, owner)',
    @ear_m >= 1 AND @ear_d >= 1 AND @ear_s >= 1 AND @ear_o >= 1,
    CONCAT('Audit rows - Marcus: ', @ear_m, ', Daniel: ', @ear_d,
           ', Sofia: ', @ear_s, ', Owner: ', @ear_o));

-- CHECK 8
--   WHAT:   count new audit rows that carry a "before" or "after" value.
--   WHY:    the trail should remember what changed, not only that something did.
--   EXPECT: at least 1.
SET @ear_ctx = (
    SELECT COUNT(*)
    FROM AuditLog
    WHERE AuditLogID > @ear_audit_mark
      AND (PriorValueContext IS NOT NULL OR NewValueContext IS NOT NULL));

CALL sp__ear_check('AUDIT',
    'Audit rows capture prior/new value context for changes',
    @ear_ctx >= 1,
    CONCAT('Rows with prior/new context: ', @ear_ctx));

-- CHECK 9
--   WHAT:   find the audit row for "version 2 created".
--   WHY:    it must point at the correct new DocumentVersion record.
--   EXPECT: exactly 1 row.
SET @ear_ver = (
    SELECT COUNT(*)
    FROM AuditLog
    WHERE EventType = 'DOCUMENT_VERSION_CREATED'
      AND AffectedRecordType = 'DocumentVersion'
      AND AffectedRecordID = @v1b);

CALL sp__ear_check('AUDIT',
    'Version-2 creation is audited against the new DocumentVersion record',
    @ear_ver = 1,
    CONCAT('DOCUMENT_VERSION_CREATED rows for version 2: ', @ear_ver));


-- ============================================================================
-- PART 4 - TAMPER ATTEMPTS (finalized + audit records are immutable)
--   We TRY TO CHEAT on purpose. Every attempt must be refused, and the row
--   must be byte-for-byte unchanged afterwards (same MD5 fingerprint).
--   CHECKS 10-21
--
--   How each check below is built (see sp__ear_tamper):
--     1. @probe_xx = SQL that fingerprints one specific row with MD5
--     2. CALL sp__ear_tamper(name, <the cheating UPDATE/DELETE>, @probe_xx)
-- ============================================================================
SELECT '=== PART 4: TAMPER ATTEMPTS MUST FAIL ===' AS Section;

-- ----------------------------------------------------------------------------
-- Group A: the AuditLog itself  (checks 10-13)
--   Target: the newest audit row.
--   Fingerprint covers: id, timestamp, event type, record type, record id,
--                       change reason.
-- ----------------------------------------------------------------------------
SET @al = (SELECT MAX(AuditLogID) FROM AuditLog);

SET @probe_al = CONCAT(
    'SELECT MD5(CONCAT_WS(''|'',',
    'AuditLogID,EventDateTime,EventType,AffectedRecordType,AffectedRecordID,',
    'COALESCE(ChangeReason,''''))) INTO @ear_fp ',
    'FROM AuditLog WHERE AuditLogID=', @al);

-- CHECK 10:  rewrite what kind of event it was
CALL sp__ear_tamper('AuditLog: UPDATE event type blocked',
    CONCAT('UPDATE AuditLog SET EventType=''TAMPERED'' WHERE AuditLogID=', @al),
    @probe_al);

-- CHECK 11:  back-date it to the year 2000
CALL sp__ear_tamper('AuditLog: BACK-DATING the timestamp blocked',
    CONCAT('UPDATE AuditLog SET EventDateTime=''2000-01-01 00:00:00'' WHERE AuditLogID=', @al),
    @probe_al);

-- CHECK 12:  blame someone else (change the actor to Olivia)
CALL sp__ear_tamper('AuditLog: changing the actor blocked',
    CONCAT('UPDATE AuditLog SET ActorUserID=', @u_owner, ' WHERE AuditLogID=', @al),
    @probe_al);

-- CHECK 13:  delete it
CALL sp__ear_tamper('AuditLog: DELETE blocked',
    CONCAT('DELETE FROM AuditLog WHERE AuditLogID=', @al),
    @probe_al);

-- ----------------------------------------------------------------------------
-- Group B: a finished approval decision  (checks 14-15)
--   Target: Daniel's approval decision.
--   Fingerprint covers: id, assignment, decision value, timestamp, comments.
-- ----------------------------------------------------------------------------
SET @ad = (SELECT ApprovalID FROM ApprovalDecision WHERE WorkflowParticipantID = @a1);

SET @probe_ad = CONCAT(
    'SELECT MD5(CONCAT_WS(''|'',',
    'ApprovalID,WorkflowParticipantID,DecisionValueID,DecisionDateTime,',
    'COALESCE(Comments,''''))) INTO @ear_fp ',
    'FROM ApprovalDecision WHERE ApprovalID=', @ad);

-- CHECK 14:  edit the comment
CALL sp__ear_tamper('ApprovalDecision: UPDATE blocked',
    CONCAT('UPDATE ApprovalDecision SET Comments=''TAMPERED'' WHERE ApprovalID=', @ad),
    @probe_ad);

-- CHECK 15:  delete the decision
CALL sp__ear_tamper('ApprovalDecision: DELETE blocked',
    CONCAT('DELETE FROM ApprovalDecision WHERE ApprovalID=', @ad),
    @probe_ad);

-- ----------------------------------------------------------------------------
-- Group C: a signature  (checks 16-18)
--   Target: Sofia's signature.
--   Fingerprint covers: id, assignment, version, signing time, reference.
-- ----------------------------------------------------------------------------
SET @sg = (SELECT SignatureID FROM Signature WHERE WorkflowParticipantID = @s1);

SET @probe_sg = CONCAT(
    'SELECT MD5(CONCAT_WS(''|'',',
    'SignatureID,WorkflowParticipantID,DocumentVersionID,SigningDateTime,',
    'COALESCE(SignatureReference,''''))) INTO @ear_fp ',
    'FROM Signature WHERE SignatureID=', @sg);

-- CHECK 16:  edit the signature reference
CALL sp__ear_tamper('Signature: UPDATE blocked',
    CONCAT('UPDATE Signature SET SignatureReference=''TAMPERED'' WHERE SignatureID=', @sg),
    @probe_sg);

-- CHECK 17:  re-point the signature at version 2 (pretend v2 was signed)
CALL sp__ear_tamper('Signature: re-pointing to a different version blocked',
    CONCAT('UPDATE Signature SET DocumentVersionID=', @v1b, ' WHERE SignatureID=', @sg),
    @probe_sg);

-- CHECK 18:  delete the signature
CALL sp__ear_tamper('Signature: DELETE blocked',
    CONCAT('DELETE FROM Signature WHERE SignatureID=', @sg),
    @probe_sg);

-- ----------------------------------------------------------------------------
-- Group D: a locked document version  (checks 19-21)
--   Target: version 1, which was locked when the workflow started.
--   Fingerprint covers: id, version number, effective info, status, lock time.
-- ----------------------------------------------------------------------------
SET @probe_dv = CONCAT(
    'SELECT MD5(CONCAT_WS(''|'',',
    'DocumentVersionID,VersionNumber,COALESCE(EffectiveInformation,''''),',
    'CurrentVersionStatusID,COALESCE(LockedDateTime,''''))) INTO @ear_fp ',
    'FROM DocumentVersion WHERE DocumentVersionID=', @v1);

-- CHECK 19:  change the content
CALL sp__ear_tamper('Locked DocumentVersion: UPDATE content blocked',
    CONCAT('UPDATE DocumentVersion SET EffectiveInformation=''TAMPERED'' WHERE DocumentVersionID=', @v1),
    @probe_dv);

-- CHECK 20:  unlock it (clear the lock timestamp)
CALL sp__ear_tamper('Locked DocumentVersion: UNLOCK attempt blocked',
    CONCAT('UPDATE DocumentVersion SET LockedDateTime=NULL WHERE DocumentVersionID=', @v1),
    @probe_dv);

-- CHECK 21:  delete it
CALL sp__ear_tamper('Locked DocumentVersion: DELETE blocked',
    CONCAT('DELETE FROM DocumentVersion WHERE DocumentVersionID=', @v1),
    @probe_dv);


-- ============================================================================
-- PART 5 - LIFECYCLE TRACE OF ONE DOCUMENT
--   Follow ONE document's whole story, start to finish, like a timeline.
--   CHECK 22
-- ============================================================================
SELECT '=== PART 5: LIFECYCLE TRACE OF ONE DOCUMENT ===' AS Section;

-- 5.1  Informational: the project's document-history view.
SELECT '5.1 Project view vw_DocumentHistory for the traced document' AS Section;
SELECT DocumentID, Title, DocumentStatus, VersionNumber, WorkflowID, WorkflowStatus,
       SequenceNumber, StepType, StepStatus, AssignedAction, AssignmentStatus,
       ApprovalDecision, SignatureStatus
FROM vw_DocumentHistory
WHERE DocumentID = @d1
ORDER BY VersionNumber, WorkflowID, SequenceNumber, WorkflowParticipantID;

-- 5.2  Informational: the project's version-history view.
SELECT '5.2 Project view vw_DocumentVersionHistory (v1 locked, v2 created after signing)' AS Section;
SELECT DocumentID, Title, VersionNumber, VersionStatus, CreatedByName,
       LockedDateTime, WorkflowCount
FROM vw_DocumentVersionHistory
WHERE DocumentID = @d1
ORDER BY VersionNumber;

-- 5.3  Informational: ONE chronological timeline.
--      Each SELECT below contributes one kind of event; UNION ALL glues them
--      together; the outer query sorts by time. Read the output top to bottom.
--      Columns: ts (when), source (which table), event, actor, detail.
SELECT '5.3 Chronological trace: versions, workflow, steps, decision, signature, completion' AS Section;
SELECT ts      AS EventTime,
       source  AS Record,
       event   AS Event,
       actor   AS Actor,
       detail  AS Detail
FROM (

    -- Each version was created
    SELECT dv.CreatedDateTime AS ts,
           'DocumentVersion'  AS source,
           'VERSION_CREATED'  AS event,
           CONCAT(cu.FirstName, ' ', cu.LastName) AS actor,
           CONCAT('v', dv.VersionNumber)          AS detail
    FROM DocumentVersion dv
    JOIN `User` cu ON cu.UserID = dv.CreatedByUserID
    WHERE dv.DocumentID = @d1

    UNION ALL
    -- Each version was locked
    SELECT dv.LockedDateTime, 'DocumentVersion', 'VERSION_LOCKED', '(system)',
           CONCAT('v', dv.VersionNumber)
    FROM DocumentVersion dv
    WHERE dv.DocumentID = @d1

    UNION ALL
    -- The workflow started
    SELECT w.StartDateTime, 'Workflow', 'WORKFLOW_STARTED',
           CONCAT(iu.FirstName, ' ', iu.LastName),
           CONCAT('Workflow ', w.WorkflowID)
    FROM Workflow w
    JOIN `User` iu ON iu.UserID = w.InitiatorUserID
    WHERE w.WorkflowID = @w1

    UNION ALL
    -- Each step became active
    SELECT ws.ActivationDateTime, 'WorkflowStep', 'STEP_ACTIVATED', '(system)',
           CONCAT('Seq ', ws.SequenceNumber, ' ', st.Code)
    FROM WorkflowStep ws
    JOIN ReferenceData st ON st.ReferenceDataID = ws.StepTypeID
    WHERE ws.WorkflowID = @w1

    UNION ALL
    -- Each step completed
    SELECT ws.CompletionDateTime, 'WorkflowStep', 'STEP_COMPLETED', '(system)',
           CONCAT('Seq ', ws.SequenceNumber, ' ', st.Code)
    FROM WorkflowStep ws
    JOIN ReferenceData st ON st.ReferenceDataID = ws.StepTypeID
    WHERE ws.WorkflowID = @w1

    UNION ALL
    -- The approval decision
    SELECT ad.DecisionDateTime, 'ApprovalDecision', CONCAT('DECISION_', dc.Code),
           CONCAT(u.FirstName, ' ', u.LastName),
           COALESCE(ad.Comments, '')
    FROM ApprovalDecision ad
    JOIN ReferenceData dc ON dc.ReferenceDataID = ad.DecisionValueID
    JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = ad.WorkflowParticipantID
    JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN `User` u ON u.UserID = wp.UserID
    WHERE ws.WorkflowID = @w1

    UNION ALL
    -- The signature
    SELECT s.SigningDateTime, 'Signature', 'SIGNED',
           CONCAT(u.FirstName, ' ', u.LastName),
           CONCAT('Version ', dv.VersionNumber, ' via ', COALESCE(s.SignatureMethod, '?'))
    FROM Signature s
    JOIN DocumentVersion dv ON dv.DocumentVersionID = s.DocumentVersionID
    JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = s.WorkflowParticipantID
    JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN `User` u ON u.UserID = wp.UserID
    WHERE ws.WorkflowID = @w1

    UNION ALL
    -- The workflow completed
    SELECT w.CompletionDateTime, 'Workflow', 'WORKFLOW_COMPLETED', '(system)',
           CONCAT('Workflow ', w.WorkflowID)
    FROM Workflow w
    WHERE w.WorkflowID = @w1

) trace
WHERE ts IS NOT NULL           -- skip milestones that have no timestamp
ORDER BY ts, event;

-- 5.4  Informational: the audit-log rows for the same workflow and versions.
SELECT '5.4 AuditLog entries for the same workflow and versions' AS Section;
SELECT al.AuditLogID,
       al.EventDateTime,
       COALESCE(CONCAT(u.FirstName, ' ', u.LastName), 'SYSTEM') AS Actor,
       al.EventType,
       al.AffectedRecordType,
       al.AffectedRecordID,
       al.PriorValueContext,
       al.NewValueContext,
       al.ChangeReason
FROM AuditLog al
LEFT JOIN `User` u ON u.UserID = al.ActorUserID
WHERE (al.AffectedRecordType = 'Workflow'        AND al.AffectedRecordID = @w1)
   OR (al.AffectedRecordType = 'DocumentVersion' AND al.AffectedRecordID IN (@v1, @v1b))
ORDER BY al.EventDateTime, al.AuditLogID;

-- CHECK 22 (final)
--   WHAT:   confirm every milestone of the story is present.
--   EXPECT: all of these are true (the query returns 1):
--             - the workflow has a completion time
--             - version 1 has a lock time
--             - all 3 steps have a completion time
--             - Daniel's approval decision exists
--             - Sofia's signature exists
--             - the document has exactly 2 versions
SET @ear_ms = (
    SELECT (w.CompletionDateTime IS NOT NULL)
       AND (dv.LockedDateTime IS NOT NULL)
       AND ((SELECT COUNT(*) FROM WorkflowStep
              WHERE WorkflowID = @w1 AND CompletionDateTime IS NOT NULL) = 3)
       AND EXISTS (SELECT 1 FROM ApprovalDecision WHERE WorkflowParticipantID = @a1)
       AND EXISTS (SELECT 1 FROM Signature        WHERE WorkflowParticipantID = @s1)
       AND ((SELECT COUNT(*) FROM DocumentVersion WHERE DocumentID = @d1) = 2)
    FROM Workflow w
    JOIN DocumentVersion dv ON dv.DocumentVersionID = w.DocumentVersionID
    WHERE w.WorkflowID = @w1);

CALL sp__ear_check('AUDIT',
    'Trace is complete: version locked, 3 steps completed, decision, signature, workflow completed, v2 exists',
    @ear_ms = 1,
    CONCAT('Milestone check = ', COALESCE(@ear_ms, 'NULL')));


-- ============================================================================
-- SCOREBOARD
--   If every row shows Failed = 0, the audit trail is complete and
--   tamper-proof (22 checks total).
-- ============================================================================
SELECT '=== AUDIT SCOREBOARD ===' AS Section;
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
DROP PROCEDURE IF EXISTS sp__ear_tamper;
DROP PROCEDURE IF EXISTS sp__ear_audited_action;
DROP PROCEDURE IF EXISTS sp__ear_check;

SET SESSION sql_mode = @ear_saved_sql_mode;