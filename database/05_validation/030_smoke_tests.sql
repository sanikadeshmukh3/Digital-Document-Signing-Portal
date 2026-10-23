-- ============================================================
-- File: database/05_validation/030_smoke_tests.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Demonstrate that the built database is usable: representative
--   read queries over the operational views plus a few
--   SIGNAL-guarded assertions. All statements are read-only.
--
-- Database: MySQL 8.x
-- ============================================================


-- ============================================================
-- Test 1 - Outstanding-actions worklist   (FR-17)
-- ============================================================
-- All currently-outstanding assignments (PENDING/ACTIVE) in
-- active workflows, with document, participant, action, due date.
-- ============================================================

SELECT '=== Test 1: Outstanding actions worklist (FR-17) ===' AS SmokeTest;

SELECT
    WorkflowParticipantID, DocumentID, Title, WorkflowID,
    ParticipantName, AssignedAction, AssignmentStatus,
    DueDateTime, ExpirationDateTime
FROM vw_OutstandingActions
ORDER BY DueDateTime, WorkflowParticipantID;


-- ============================================================
-- Test 2 - Participant-specific worklist   (FR-08 / FR-17)
-- ============================================================
-- Same worklist, filtered to one seeded user (the Scenario B
-- approver, Daniel Cho) to show a per-participant view.
-- ============================================================

SELECT '=== Test 2: Per-participant worklist for Daniel Cho (FR-08) ===' AS SmokeTest;

SELECT
    pw.WorkflowParticipantID, pw.Title, pw.VersionNumber,
    pw.StepType, pw.AssignedAction, pw.AssignmentStatus,
    pw.WorkflowStatus, pw.DueDateTime
FROM vw_ParticipantWorklist pw
WHERE pw.UserID = (
    SELECT UserID FROM `User` WHERE Email = 'daniel.cho@initech.example'
)
ORDER BY pw.WorkflowID, pw.SequenceNumber;


-- ============================================================
-- Test 3 - Document history   (FR-18)
-- ============================================================
-- Full historical view for the completed-workflow document
-- (Master Services Agreement).
-- ============================================================

SELECT '=== Test 3: Document history for Master Services Agreement (FR-18) ===' AS SmokeTest;

SELECT
    DocumentID, Title, DocumentStatus, VersionNumber,
    WorkflowID, WorkflowStatus, SequenceNumber, StepType, StepStatus,
    AssignedAction, AssignmentStatus, ApprovalDecision, SignatureStatus
FROM vw_DocumentHistory
WHERE DocumentID = (
    SELECT DocumentID FROM Document WHERE Title = 'Master Services Agreement'
)
ORDER BY VersionNumber, WorkflowID, SequenceNumber, WorkflowParticipantID;


-- ============================================================
-- Test 4 - Workflow detail for the COMPLETED workflow   (FR-18)
-- ============================================================

SELECT '=== Test 4: Workflow detail for the completed MSA v1 workflow (FR-18) ===' AS SmokeTest;

SELECT
    WorkflowID, Title, VersionNumber, WorkflowStatus,
    SequenceNumber, StepType, StepStatus,
    ParticipantName, RoleName, AssignedAction, AssignmentStatus,
    ApprovalDecision, SignatureStatus, SignatureMethod
FROM vw_WorkflowDetail
WHERE Title = 'Master Services Agreement'
  AND WorkflowStatus = 'COMPLETED'
ORDER BY SequenceNumber, WorkflowParticipantID;


-- ============================================================
-- Test 5 - Document version history incl. versions w/o workflows (FR-02/FR-18)
-- ============================================================
-- The DRAFT handbook (Scenario A) has a CURRENT version and NO
-- workflow; it must still appear here with WorkflowCount = 0.
-- Assertion: every seeded DocumentVersion appears in the view
-- (guards against a missing DOCUMENT_VERSION_STATUS reference row,
-- which would drop versions from this INNER-joined view).
-- ============================================================

SELECT '=== Test 5: Document version history, all documents (FR-02/FR-18) ===' AS SmokeTest;

SELECT
    DocumentID, Title, VersionNumber, VersionStatus,
    CreatedByName, LockedDateTime, WorkflowCount
FROM vw_DocumentVersionHistory
ORDER BY DocumentID, VersionNumber;

DELIMITER $$
DROP PROCEDURE IF EXISTS sp__smoke_assert_versions $$
CREATE PROCEDURE sp__smoke_assert_versions()
BEGIN
    DECLARE v_seeded INT;
    DECLARE v_in_view INT;

    SELECT COUNT(*) INTO v_seeded FROM DocumentVersion;
    SELECT COUNT(*) INTO v_in_view FROM vw_DocumentVersionHistory;

    IF v_in_view <> v_seeded THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Smoke test failed: vw_DocumentVersionHistory is missing seeded DocumentVersion rows (check DOCUMENT_VERSION_STATUS reference data).';
    END IF;
END $$
DELIMITER ;
CALL sp__smoke_assert_versions();
DROP PROCEDURE sp__smoke_assert_versions;


-- ============================================================
-- Test 6 - Approval decisions joined to participant   (FR-10)
-- ============================================================

SELECT '=== Test 6: Approval decisions with participant (FR-10) ===' AS SmokeTest;

SELECT
    ad.ApprovalID,
    CONCAT(u.FirstName, ' ', u.LastName) AS ApproverName,
    d.Title,
    decision.Code AS Decision,
    ad.DecisionDateTime,
    ad.RejectionReason
FROM ApprovalDecision ad
JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = ad.WorkflowParticipantID
JOIN `User` u ON u.UserID = wp.UserID
JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
JOIN Document d ON d.DocumentID = w.DocumentID
JOIN ReferenceData decision ON decision.ReferenceDataID = ad.DecisionValueID
ORDER BY ad.DecisionDateTime;


-- ============================================================
-- Test 7 - Signature/version cross-check   (FR-11)
-- ============================================================
-- Returns rows ONLY when a signature's version differs from its
-- workflow's version. Must be empty; asserted via SIGNAL.
-- ============================================================

SELECT '=== Test 7: Signature/version cross-check (FR-11) - expect zero mismatches ===' AS SmokeTest;

SELECT
    s.SignatureID,
    s.DocumentVersionID        AS SignatureVersionID,
    w.DocumentVersionID        AS WorkflowVersionID
FROM Signature s
JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = s.WorkflowParticipantID
JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
WHERE s.DocumentVersionID <> w.DocumentVersionID;

DELIMITER $$
DROP PROCEDURE IF EXISTS sp__smoke_assert_signatures $$
CREATE PROCEDURE sp__smoke_assert_signatures()
BEGIN
    DECLARE v_mismatch INT;

    SELECT COUNT(*) INTO v_mismatch
    FROM Signature s
    JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = s.WorkflowParticipantID
    JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
    WHERE s.DocumentVersionID <> w.DocumentVersionID;

    IF v_mismatch <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Smoke test failed: a Signature references a DocumentVersion different from its workflow version.';
    END IF;
END $$
DELIMITER ;
CALL sp__smoke_assert_signatures();
DROP PROCEDURE sp__smoke_assert_signatures;


-- ============================================================
-- Test 8 - Audit history incl. SYSTEM (NULL actor) row   (FR-15/FR-18)
-- ============================================================

SELECT '=== Test 8: Audit history, incl. SYSTEM actor (FR-15/FR-18) ===' AS SmokeTest;

SELECT
    AuditLogID, EventDateTime, ActorName, EventType,
    AffectedRecordType, AffectedRecordID, ChangeReason
FROM vw_AuditHistory
ORDER BY EventDateTime, AuditLogID;


-- ============================================================
-- Test 9 - EXPLAIN on the participant worklist query
-- ============================================================
-- Targets idx_WorkflowParticipant_User_Status_DueDate
-- (UserID, AssignmentStatusID, DueDateTime). On a tiny seeded
-- dataset the optimizer MAY choose a full scan instead of the
-- index; the ACTUAL plan should be recorded from this output,
-- not assumed. The index exists and covers this access path.
-- ============================================================

SELECT '=== Test 9: EXPLAIN participant worklist (index idx_WorkflowParticipant_User_Status_DueDate) ===' AS SmokeTest;

EXPLAIN
SELECT *
FROM WorkflowParticipant
WHERE UserID = (
        SELECT UserID FROM `User` WHERE Email = 'daniel.cho@initech.example'
      )
  AND AssignmentStatusID = (
        SELECT ReferenceDataID FROM ReferenceData
        WHERE DomainName = 'PARTICIPANT_STATUS' AND Code = 'ACTIVE'
      )
ORDER BY DueDateTime;


SELECT 'SMOKE TESTS COMPLETED.' AS Result;
