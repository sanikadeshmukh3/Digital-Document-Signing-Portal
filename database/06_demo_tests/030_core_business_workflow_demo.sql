-- ============================================================
-- File:
--   database/06_demo_tests/030_core_business_workflow_demo.sql
--
-- Project:
--   Document Workflow and E-signing Portal
--
-- Purpose:
--   Demonstrate the main business workflow required by the FRD:
--
--     1. Retrieve workflow state.
--     2. Execute a valid business transaction.
--     3. Show controlled workflow progression.
--     4. Show creation/update of related business records.
--     5. Attempt an unauthorized transaction.
--     6. Show that the invalid transaction is rejected.
--     7. Verify that rejected work leaves database state unchanged.
--
-- Demo scenario:
--
--   APPROVAL (ACTIVE)
--          |
--          | Daniel Cho approves
--          v
--   APPROVAL (COMPLETED)
--          |
--          v
--   SIGNATURE (ACTIVE)
--
--   Then Marcus Reed attempts Sofia Alvarez's signature.
--
--   Expected:
--       Unauthorized signature is rejected.
--       Signature step remains ACTIVE.
--       Sofia's assignment remains ACTIVE.
--       No Signature record is created.
--
-- IMPORTANT:
--   This script creates its own isolated demo data so that the
--   original seeded workflows remain unchanged for other demos.
--
-- Database:
--   MySQL 8.x
-- ============================================================


SELECT '============================================================'
    AS DemoSection;

SELECT 'CORE BUSINESS WORKFLOW DEMO'
    AS DemoSection;

SELECT '============================================================'
    AS DemoSection;



-- ============================================================
-- PART 0
-- Create isolated demo setup
-- ============================================================

SELECT
    'PART 0 - CREATE ISOLATED DEMO WORKFLOW'
    AS DemoSection;


-- ------------------------------------------------------------
-- Resolve users.
-- ------------------------------------------------------------

SET @demo_owner_id = (
    SELECT UserID
    FROM `User`
    WHERE Email = 'olivia.brooks@initech.example'
    LIMIT 1
);

SET @demo_approver_id = (
    SELECT UserID
    FROM `User`
    WHERE Email = 'daniel.cho@initech.example'
    LIMIT 1
);

SET @demo_signer_id = (
    SELECT UserID
    FROM `User`
    WHERE Email = 'sofia.alvarez@initech.example'
    LIMIT 1
);

-- Marcus is intentionally the WRONG user for the signature test.
SET @demo_wrong_user_id = (
    SELECT UserID
    FROM `User`
    WHERE Email = 'marcus.reed@initech.example'
    LIMIT 1
);


-- ------------------------------------------------------------
-- Resolve business roles.
-- ------------------------------------------------------------

SET @demo_approver_role_id = (
    SELECT RoleID
    FROM Role
    WHERE RoleName = 'Approver'
    LIMIT 1
);

SET @demo_signer_role_id = (
    SELECT RoleID
    FROM Role
    WHERE RoleName = 'Signer'
    LIMIT 1
);


-- ------------------------------------------------------------
-- Resolve controlled reference values.
-- ------------------------------------------------------------

SET @demo_document_active_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'DOCUMENT_STATUS'
      AND Code = 'ACTIVE'
    LIMIT 1
);

SET @demo_classification_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'DOCUMENT_CLASSIFICATION'
      AND Code = 'INTERNAL'
    LIMIT 1
);

SET @demo_version_locked_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'DOCUMENT_VERSION_STATUS'
      AND Code = 'LOCKED'
    LIMIT 1
);

SET @demo_workflow_active_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_STATUS'
      AND Code = 'ACTIVE'
    LIMIT 1
);

SET @demo_workflow_purpose_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_PURPOSE_TYPE'
      AND Code = 'FULL_REVIEW_APPROVAL_SIGNATURE'
    LIMIT 1
);

SET @demo_approval_step_type_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'STEP_TYPE'
      AND Code = 'APPROVAL'
    LIMIT 1
);

SET @demo_signature_step_type_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'STEP_TYPE'
      AND Code = 'SIGNATURE'
    LIMIT 1
);

SET @demo_step_active_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'ACTIVE'
    LIMIT 1
);

SET @demo_step_pending_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'PENDING'
    LIMIT 1
);

SET @demo_participant_active_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'ACTIVE'
    LIMIT 1
);

SET @demo_participant_pending_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'PENDING'
    LIMIT 1
);

SET @demo_approval_action_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'ASSIGNED_ACTION'
      AND Code = 'APPROVAL'
    LIMIT 1
);

SET @demo_signature_action_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'ASSIGNED_ACTION'
      AND Code = 'SIGNATURE'
    LIMIT 1
);


-- ------------------------------------------------------------
-- Create dedicated demo Document.
--
-- We deliberately use a unique title so this is easy to identify
-- during the live demonstration.
-- ------------------------------------------------------------

INSERT INTO Document
(
    Title,
    BusinessDescription,
    OwnerUserID,
    ClassificationID,
    LifecycleStatusID
)
VALUES
(
    'Core Workflow Demo Agreement',
    'Isolated document used for the core business workflow demonstration.',
    @demo_owner_id,
    @demo_classification_id,
    @demo_document_active_id
);

SET @demo_document_id = LAST_INSERT_ID();


-- ------------------------------------------------------------
-- Create a locked DocumentVersion.
--
-- The workflow represents business activity against one exact,
-- immutable version.
-- ------------------------------------------------------------

INSERT INTO DocumentVersion
(
    DocumentID,
    VersionNumber,
    EffectiveInformation,
    CreatedDateTime,
    CreatedByUserID,
    CurrentVersionStatusID,
    LockedDateTime
)
VALUES
(
    @demo_document_id,
    1,
    'Version used for core workflow demo.',
    CURRENT_TIMESTAMP,
    @demo_owner_id,
    @demo_version_locked_id,
    CURRENT_TIMESTAMP
);

SET @demo_version_id = LAST_INSERT_ID();


-- ------------------------------------------------------------
-- Create ACTIVE Workflow.
-- ------------------------------------------------------------

INSERT INTO Workflow
(
    DocumentID,
    DocumentVersionID,
    InitiatorUserID,
    WorkflowPurposeTypeID,
    WorkflowStatusID,
    StartDateTime,
    ExpirationDateTime
)
VALUES
(
    @demo_document_id,
    @demo_version_id,
    @demo_owner_id,
    @demo_workflow_purpose_id,
    @demo_workflow_active_id,
    CURRENT_TIMESTAMP,
    DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 30 DAY)
);

SET @demo_workflow_id = LAST_INSERT_ID();


-- ------------------------------------------------------------
-- Step 1:
-- APPROVAL is initially ACTIVE.
-- ------------------------------------------------------------

INSERT INTO WorkflowStep
(
    WorkflowID,
    SequenceNumber,
    StepTypeID,
    RequiredPolicy,
    StepStatusID,
    ActivationDateTime,
    CompletionDateTime,
    DueDateTime
)
VALUES
(
    @demo_workflow_id,
    1,
    @demo_approval_step_type_id,
    'ALL_REQUIRED',
    @demo_step_active_id,
    CURRENT_TIMESTAMP,
    NULL,
    DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 7 DAY)
);

SET @demo_approval_step_id = LAST_INSERT_ID();


-- ------------------------------------------------------------
-- Step 2:
-- SIGNATURE is initially PENDING because the approval step has
-- not yet completed.
-- ------------------------------------------------------------

INSERT INTO WorkflowStep
(
    WorkflowID,
    SequenceNumber,
    StepTypeID,
    RequiredPolicy,
    StepStatusID,
    ActivationDateTime,
    CompletionDateTime,
    DueDateTime
)
VALUES
(
    @demo_workflow_id,
    2,
    @demo_signature_step_type_id,
    'ALL_REQUIRED',
    @demo_step_pending_id,
    NULL,
    NULL,
    DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 14 DAY)
);

SET @demo_signature_step_id = LAST_INSERT_ID();


-- ------------------------------------------------------------
-- Daniel Cho:
-- assigned Approver on Step 1.
-- ------------------------------------------------------------

INSERT INTO WorkflowParticipant
(
    WorkflowStepID,
    UserID,
    RoleID,
    AssignedActionID,
    AssignmentStatusID,
    RequiredFlag,
    ActivationDateTime,
    CompletionDateTime,
    DueDateTime
)
VALUES
(
    @demo_approval_step_id,
    @demo_approver_id,
    @demo_approver_role_id,
    @demo_approval_action_id,
    @demo_participant_active_id,
    TRUE,
    CURRENT_TIMESTAMP,
    NULL,
    DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 7 DAY)
);

SET @demo_approval_participant_id = LAST_INSERT_ID();


-- ------------------------------------------------------------
-- Sofia Alvarez:
-- assigned Signer on Step 2.
--
-- Her assignment starts PENDING because the approval step is
-- still incomplete.
-- ------------------------------------------------------------

INSERT INTO WorkflowParticipant
(
    WorkflowStepID,
    UserID,
    RoleID,
    AssignedActionID,
    AssignmentStatusID,
    RequiredFlag,
    ActivationDateTime,
    CompletionDateTime,
    DueDateTime
)
VALUES
(
    @demo_signature_step_id,
    @demo_signer_id,
    @demo_signer_role_id,
    @demo_signature_action_id,
    @demo_participant_pending_id,
    TRUE,
    NULL,
    NULL,
    DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 14 DAY)
);

SET @demo_signature_participant_id = LAST_INSERT_ID();



-- ============================================================
-- PART 1
-- Retrieve BEFORE state
-- ============================================================

SELECT
    'PART 1 - BEFORE VALID TRANSACTION'
    AS DemoSection;


SELECT
    d.Title                            AS Document,
    dv.VersionNumber                  AS VersionNumber,

    w.WorkflowID,
    wr.Code                           AS WorkflowStatus,

    ws.SequenceNumber,
    st.Code                           AS StepType,
    ss.Code                           AS StepStatus,

    wp.WorkflowParticipantID,
    CONCAT(u.FirstName, ' ', u.LastName)
                                       AS AssignedUser,
    r.RoleName                        AS AssignedRole,
    aa.Code                           AS AssignedAction,
    ps.Code                           AS ParticipantStatus

FROM Workflow w

JOIN Document d
  ON d.DocumentID = w.DocumentID

JOIN DocumentVersion dv
  ON dv.DocumentVersionID = w.DocumentVersionID

JOIN ReferenceData wr
  ON wr.ReferenceDataID = w.WorkflowStatusID

JOIN WorkflowStep ws
  ON ws.WorkflowID = w.WorkflowID

JOIN ReferenceData st
  ON st.ReferenceDataID = ws.StepTypeID

JOIN ReferenceData ss
  ON ss.ReferenceDataID = ws.StepStatusID

JOIN WorkflowParticipant wp
  ON wp.WorkflowStepID = ws.WorkflowStepID

JOIN `User` u
  ON u.UserID = wp.UserID

JOIN Role r
  ON r.RoleID = wp.RoleID

JOIN ReferenceData aa
  ON aa.ReferenceDataID = wp.AssignedActionID

JOIN ReferenceData ps
  ON ps.ReferenceDataID = wp.AssignmentStatusID

WHERE w.WorkflowID = @demo_workflow_id

ORDER BY
    ws.SequenceNumber,
    wp.WorkflowParticipantID;


-- Expected BEFORE state:
--
-- Workflow       ACTIVE
--
-- Sequence 1
--   APPROVAL      ACTIVE
--   Daniel Cho    ACTIVE
--
-- Sequence 2
--   SIGNATURE     PENDING
--   Sofia Alvarez PENDING



-- ============================================================
-- TEST 1
-- VALID BUSINESS TRANSACTION
--
-- Daniel Cho performs the approval assigned to him.
--
-- Requirements demonstrated:
--   FR-08  assigned actions
--   FR-10  approval decision
--   FR-12  authorization/state validation
--   FR-13  lifecycle progression
--   FR-14  controlled progression
--   FR-15  audit
--
-- Expected:
--
--   ApprovalDecision created.
--   Daniel assignment ACTIVE -> COMPLETED.
--   Approval step ACTIVE -> COMPLETED.
--   Signature step PENDING -> ACTIVE.
--   Sofia assignment PENDING -> ACTIVE.
--   Workflow remains ACTIVE because signature remains outstanding.
--
-- ============================================================

SELECT
    'TEST 1 - VALID APPROVAL TRANSACTION'
    AS DemoSection;


SELECT
    'Daniel Cho is the assigned approver. '
    'The stored procedure should accept this transaction.'
    AS ExpectedBehavior;


CALL sp_record_approval_decision(
    @demo_approval_participant_id,
    @demo_approver_id,
    'APPROVED',
    'Core workflow demo approval.',
    NULL
);



-- ============================================================
-- PART 2
-- Retrieve AFTER valid transaction
-- ============================================================

SELECT
    'PART 2 - AFTER VALID TRANSACTION'
    AS DemoSection;


SELECT
    d.Title                            AS Document,
    dv.VersionNumber                  AS VersionNumber,

    w.WorkflowID,
    wr.Code                           AS WorkflowStatus,

    ws.SequenceNumber,
    st.Code                           AS StepType,
    ss.Code                           AS StepStatus,

    wp.WorkflowParticipantID,
    CONCAT(u.FirstName, ' ', u.LastName)
                                       AS AssignedUser,
    r.RoleName                        AS AssignedRole,
    aa.Code                           AS AssignedAction,
    ps.Code                           AS ParticipantStatus,

    wp.ActivationDateTime,
    wp.CompletionDateTime

FROM Workflow w

JOIN Document d
  ON d.DocumentID = w.DocumentID

JOIN DocumentVersion dv
  ON dv.DocumentVersionID = w.DocumentVersionID

JOIN ReferenceData wr
  ON wr.ReferenceDataID = w.WorkflowStatusID

JOIN WorkflowStep ws
  ON ws.WorkflowID = w.WorkflowID

JOIN ReferenceData st
  ON st.ReferenceDataID = ws.StepTypeID

JOIN ReferenceData ss
  ON ss.ReferenceDataID = ws.StepStatusID

JOIN WorkflowParticipant wp
  ON wp.WorkflowStepID = ws.WorkflowStepID

JOIN `User` u
  ON u.UserID = wp.UserID

JOIN Role r
  ON r.RoleID = wp.RoleID

JOIN ReferenceData aa
  ON aa.ReferenceDataID = wp.AssignedActionID

JOIN ReferenceData ps
  ON ps.ReferenceDataID = wp.AssignmentStatusID

WHERE w.WorkflowID = @demo_workflow_id

ORDER BY
    ws.SequenceNumber,
    wp.WorkflowParticipantID;



-- ------------------------------------------------------------
-- Show record CREATED by the valid business transaction.
-- ------------------------------------------------------------

SELECT
    'APPROVAL DECISION CREATED'
    AS DemoSection;


SELECT
    ad.ApprovalID,
    ad.WorkflowParticipantID,
    CONCAT(u.FirstName, ' ', u.LastName)
        AS Approver,
    decision.Code
        AS Decision,
    ad.DecisionDateTime,
    ad.Comments,
    ad.RejectionReason

FROM ApprovalDecision ad

JOIN WorkflowParticipant wp
  ON wp.WorkflowParticipantID = ad.WorkflowParticipantID

JOIN `User` u
  ON u.UserID = wp.UserID

JOIN ReferenceData decision
  ON decision.ReferenceDataID = ad.DecisionValueID

WHERE ad.WorkflowParticipantID =
      @demo_approval_participant_id;



-- ------------------------------------------------------------
-- Demonstrate controlled status progression explicitly.
-- ------------------------------------------------------------

SELECT
    CASE
        WHEN approval_step_status.Code = 'COMPLETED'
         AND approval_participant_status.Code = 'COMPLETED'
         AND signature_step_status.Code = 'ACTIVE'
         AND signature_participant_status.Code = 'ACTIVE'
         AND workflow_status.Code = 'ACTIVE'
        THEN 'PASS'
        ELSE 'FAIL'
    END AS Result,

    'TEST 1 - Valid approval completed current step and activated next sequence'
        AS TestName,

    workflow_status.Code
        AS WorkflowStatus,

    approval_step_status.Code
        AS ApprovalStepStatus,

    approval_participant_status.Code
        AS ApproverStatus,

    signature_step_status.Code
        AS SignatureStepStatus,

    signature_participant_status.Code
        AS SignerStatus

FROM Workflow w

JOIN ReferenceData workflow_status
  ON workflow_status.ReferenceDataID =
     w.WorkflowStatusID

JOIN WorkflowStep approval_step
  ON approval_step.WorkflowStepID =
     @demo_approval_step_id

JOIN ReferenceData approval_step_status
  ON approval_step_status.ReferenceDataID =
     approval_step.StepStatusID

JOIN WorkflowParticipant approval_participant
  ON approval_participant.WorkflowParticipantID =
     @demo_approval_participant_id

JOIN ReferenceData approval_participant_status
  ON approval_participant_status.ReferenceDataID =
     approval_participant.AssignmentStatusID

JOIN WorkflowStep signature_step
  ON signature_step.WorkflowStepID =
     @demo_signature_step_id

JOIN ReferenceData signature_step_status
  ON signature_step_status.ReferenceDataID =
     signature_step.StepStatusID

JOIN WorkflowParticipant signature_participant
  ON signature_participant.WorkflowParticipantID =
     @demo_signature_participant_id

JOIN ReferenceData signature_participant_status
  ON signature_participant_status.ReferenceDataID =
     signature_participant.AssignmentStatusID

WHERE w.WorkflowID = @demo_workflow_id;



-- ============================================================
-- TEST 2
-- UNAUTHORIZED BUSINESS TRANSACTION
--
-- Marcus Reed attempts to complete the signature assigned
-- specifically to Sofia Alvarez.
--
-- This demonstrates an invalid/unauthorized transaction.
--
-- Expected:
--
--   Procedure raises an exception.
--   No Signature is created.
--   Sofia's assignment remains ACTIVE.
--   Signature step remains ACTIVE.
--   Workflow remains ACTIVE.
--
-- ============================================================

SELECT
    'TEST 2 - UNAUTHORIZED SIGNATURE TRANSACTION'
    AS DemoSection;



-- ============================================================
-- Capture BEFORE state for invalid transaction
-- ============================================================

SELECT
    'BEFORE INVALID TRANSACTION'
    AS DemoSection;


SET @before_signature_count = (
    SELECT COUNT(*)
    FROM Signature
    WHERE WorkflowParticipantID =
          @demo_signature_participant_id
);

SET @before_signature_participant_status = (
    SELECT AssignmentStatusID
    FROM WorkflowParticipant
    WHERE WorkflowParticipantID =
          @demo_signature_participant_id
);

SET @before_signature_step_status = (
    SELECT StepStatusID
    FROM WorkflowStep
    WHERE WorkflowStepID =
          @demo_signature_step_id
);

SET @before_workflow_status = (
    SELECT WorkflowStatusID
    FROM Workflow
    WHERE WorkflowID =
          @demo_workflow_id
);


SELECT
    w.WorkflowID,
    wr.Code AS WorkflowStatus,

    ws.WorkflowStepID,
    ss.Code AS SignatureStepStatus,

    wp.WorkflowParticipantID,

    CONCAT(u.FirstName, ' ', u.LastName)
        AS AssignedSigner,

    ps.Code AS SignerAssignmentStatus,

    @before_signature_count
        AS SignatureRows

FROM Workflow w

JOIN ReferenceData wr
  ON wr.ReferenceDataID = w.WorkflowStatusID

JOIN WorkflowStep ws
  ON ws.WorkflowStepID =
     @demo_signature_step_id

JOIN ReferenceData ss
  ON ss.ReferenceDataID = ws.StepStatusID

JOIN WorkflowParticipant wp
  ON wp.WorkflowParticipantID =
     @demo_signature_participant_id

JOIN `User` u
  ON u.UserID = wp.UserID

JOIN ReferenceData ps
  ON ps.ReferenceDataID =
     wp.AssignmentStatusID

WHERE w.WorkflowID = @demo_workflow_id;



-- ============================================================
-- Temporary wrapper catches the expected exception so the
-- demonstration script can continue and print AFTER evidence.
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp__demo_unauthorized_signature $$

CREATE PROCEDURE sp__demo_unauthorized_signature()
BEGIN

    DECLARE v_rejected BOOLEAN DEFAULT FALSE;

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        SET v_rejected = TRUE;
    END;


    -- --------------------------------------------------------
    -- INVALID ATTEMPT
    --
    -- The participant assignment belongs to Sofia Alvarez.
    -- Marcus Reed is supplied as CurrentUserID.
    --
    -- sp_record_signature parameter order:
    --
    --   1. WorkflowParticipantID
    --   2. CurrentUserID
    --   3. DocumentVersionID
    --   4. Signature status code
    --   5. Signature method
    --   6. Signature reference
    -- --------------------------------------------------------

    CALL sp_record_signature(
        @demo_signature_participant_id,
        @demo_wrong_user_id,
        @demo_version_id,
        'SIGNED',
        'TYPED_NAME',
        'UNAUTHORIZED-DEMO-SIGNATURE'
    );


    IF v_rejected = TRUE THEN

        SELECT
            'PASS' AS Result,
            'Unauthorized signature transaction was correctly rejected.'
                AS ExpectedResult;

    ELSE

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 2 FAILED: unauthorized signature was not rejected.';

    END IF;

END $$

DELIMITER ;


CALL sp__demo_unauthorized_signature();

DROP PROCEDURE sp__demo_unauthorized_signature;



-- ============================================================
-- PART 3
-- AFTER invalid transaction
-- ============================================================

SELECT
    'AFTER INVALID TRANSACTION'
    AS DemoSection;


SET @after_signature_count = (
    SELECT COUNT(*)
    FROM Signature
    WHERE WorkflowParticipantID =
          @demo_signature_participant_id
);

SET @after_signature_participant_status = (
    SELECT AssignmentStatusID
    FROM WorkflowParticipant
    WHERE WorkflowParticipantID =
          @demo_signature_participant_id
);

SET @after_signature_step_status = (
    SELECT StepStatusID
    FROM WorkflowStep
    WHERE WorkflowStepID =
          @demo_signature_step_id
);

SET @after_workflow_status = (
    SELECT WorkflowStatusID
    FROM Workflow
    WHERE WorkflowID =
          @demo_workflow_id
);


SELECT
    w.WorkflowID,
    wr.Code AS WorkflowStatus,

    ws.WorkflowStepID,
    ss.Code AS SignatureStepStatus,

    wp.WorkflowParticipantID,

    CONCAT(u.FirstName, ' ', u.LastName)
        AS AssignedSigner,

    ps.Code AS SignerAssignmentStatus,

    @after_signature_count
        AS SignatureRows

FROM Workflow w

JOIN ReferenceData wr
  ON wr.ReferenceDataID = w.WorkflowStatusID

JOIN WorkflowStep ws
  ON ws.WorkflowStepID =
     @demo_signature_step_id

JOIN ReferenceData ss
  ON ss.ReferenceDataID = ws.StepStatusID

JOIN WorkflowParticipant wp
  ON wp.WorkflowParticipantID =
     @demo_signature_participant_id

JOIN `User` u
  ON u.UserID = wp.UserID

JOIN ReferenceData ps
  ON ps.ReferenceDataID =
     wp.AssignmentStatusID

WHERE w.WorkflowID = @demo_workflow_id;



-- ============================================================
-- Verify INVALID transaction made NO state changes.
-- ============================================================

SELECT
    CASE

        WHEN @before_signature_count =
             @after_signature_count

         AND @before_signature_count = 0

         AND @before_signature_participant_status =
             @after_signature_participant_status

         AND @before_signature_step_status =
             @after_signature_step_status

         AND @before_workflow_status =
             @after_workflow_status

        THEN 'PASS'

        ELSE 'FAIL'

    END AS Result,

    'TEST 2 - Unauthorized signature rejected with no state change'
        AS TestName,

    @before_signature_count
        AS SignatureRowsBefore,

    @after_signature_count
        AS SignatureRowsAfter;



-- ============================================================
-- Show final workflow state
-- ============================================================

SELECT
    'FINAL WORKFLOW STATE'
    AS DemoSection;


SELECT
    d.Title                            AS Document,
    dv.VersionNumber                  AS VersionNumber,

    w.WorkflowID,
    wr.Code                           AS WorkflowStatus,

    ws.SequenceNumber,
    st.Code                           AS StepType,
    ss.Code                           AS StepStatus,

    CONCAT(u.FirstName, ' ', u.LastName)
                                       AS Participant,

    aa.Code                           AS AssignedAction,
    ps.Code                           AS ParticipantStatus

FROM Workflow w

JOIN Document d
  ON d.DocumentID = w.DocumentID

JOIN DocumentVersion dv
  ON dv.DocumentVersionID = w.DocumentVersionID

JOIN ReferenceData wr
  ON wr.ReferenceDataID = w.WorkflowStatusID

JOIN WorkflowStep ws
  ON ws.WorkflowID = w.WorkflowID

JOIN ReferenceData st
  ON st.ReferenceDataID = ws.StepTypeID

JOIN ReferenceData ss
  ON ss.ReferenceDataID = ws.StepStatusID

JOIN WorkflowParticipant wp
  ON wp.WorkflowStepID = ws.WorkflowStepID

JOIN `User` u
  ON u.UserID = wp.UserID

JOIN ReferenceData aa
  ON aa.ReferenceDataID = wp.AssignedActionID

JOIN ReferenceData ps
  ON ps.ReferenceDataID = wp.AssignmentStatusID

WHERE w.WorkflowID = @demo_workflow_id

ORDER BY
    ws.SequenceNumber,
    wp.WorkflowParticipantID;



-- ============================================================
-- Show audit evidence created by the valid transaction.
-- ============================================================

SELECT
    'AUDIT EVIDENCE FROM VALID TRANSACTION'
    AS DemoSection;


SELECT
    al.AuditLogID,
    al.EventDateTime,

    COALESCE(
        CONCAT(u.FirstName, ' ', u.LastName),
        'SYSTEM'
    ) AS Actor,

    al.EventType,
    al.AffectedRecordType,
    al.AffectedRecordID,
    al.TransactionReference,
    al.ChangeReason

FROM AuditLog al

LEFT JOIN `User` u
  ON u.UserID = al.ActorUserID

WHERE
      al.ActorUserID = @demo_approver_id

  AND (
        al.AffectedRecordID =
            @demo_workflow_id

        OR al.AffectedRecordID =
            @demo_approval_participant_id

        OR al.AffectedRecordID IN (
            SELECT ApprovalID
            FROM ApprovalDecision
            WHERE WorkflowParticipantID =
                  @demo_approval_participant_id
        )
      )

ORDER BY
    al.EventDateTime,
    al.AuditLogID;



-- ============================================================
-- FINAL RESULT
-- ============================================================

SELECT
    '============================================================'
    AS DemoSection;

SELECT
    'CORE BUSINESS WORKFLOW DEMO COMPLETED'
    AS DemoSection;

SELECT
    'Valid transaction: approval accepted and workflow progressed.'
    AS Test1;

SELECT
    'Invalid transaction: unauthorized signature rejected with no state change.'
    AS Test2;

SELECT
    '============================================================'
    AS DemoSection;