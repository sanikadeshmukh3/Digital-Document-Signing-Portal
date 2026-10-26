-- ============================================================
-- File:
--   database/06_demo_tests/050_trigger_update_demo.sql
--
-- Project:
--   Document Workflow and E-signing Portal
--
-- Purpose:
--   Demonstrate that trg_Workflow_TerminalCascade performs
--   automatic database updates when a Workflow enters a
--   terminal state.
--
-- Demo:
--   BEFORE:
--      Workflow            ACTIVE
--      WorkflowStep        ACTIVE
--      WorkflowParticipant ACTIVE
--
--   ACTION:
--      UPDATE Workflow -> CANCELLED
--
--   TRIGGER EFFECT:
--      WorkflowStep        -> CANCELLED
--      WorkflowParticipant -> CANCELLED
--
-- Important:
--   The demo explicitly updates ONLY the Workflow table.
--   The child-table changes are made by the trigger.
--
-- Database:
--   MySQL 8.x
-- ============================================================


SELECT '============================================================'
    AS DemoSection;

SELECT 'TRIGGER UPDATE DEMONSTRATION'
    AS DemoSection;

SELECT 'trg_Workflow_TerminalCascade'
    AS TriggerBeingDemonstrated;

SELECT '============================================================'
    AS DemoSection;



-- ============================================================
-- PART 0
-- Resolve IDs needed for isolated demo setup
-- ============================================================

SET @demo_owner_id = (
    SELECT UserID
    FROM `User`
    WHERE Email = 'olivia.brooks@initech.example'
    LIMIT 1
);

SET @demo_reviewer_id = (
    SELECT UserID
    FROM `User`
    WHERE Email = 'marcus.reed@initech.example'
    LIMIT 1
);

SET @demo_reviewer_role_id = (
    SELECT RoleID
    FROM Role
    WHERE RoleName = 'Reviewer'
    LIMIT 1
);


SET @document_active_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'DOCUMENT_STATUS'
      AND Code = 'ACTIVE'
    LIMIT 1
);

SET @classification_internal_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'DOCUMENT_CLASSIFICATION'
      AND Code = 'INTERNAL'
    LIMIT 1
);

SET @version_locked_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'DOCUMENT_VERSION_STATUS'
      AND Code = 'LOCKED'
    LIMIT 1
);

SET @workflow_active_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_STATUS'
      AND Code = 'ACTIVE'
    LIMIT 1
);

SET @workflow_cancelled_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_STATUS'
      AND Code = 'CANCELLED'
    LIMIT 1
);

SET @workflow_purpose_review_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_PURPOSE_TYPE'
      AND Code = 'REVIEW'
    LIMIT 1
);

SET @review_step_type_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'STEP_TYPE'
      AND Code = 'REVIEW'
    LIMIT 1
);

SET @step_active_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'ACTIVE'
    LIMIT 1
);

SET @participant_active_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'ACTIVE'
    LIMIT 1
);

SET @review_action_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'ASSIGNED_ACTION'
      AND Code = 'REVIEW'
    LIMIT 1
);



-- ============================================================
-- PART 1
-- Create isolated ACTIVE workflow state
-- ============================================================

SELECT
    'PART 1 - CREATE ACTIVE WORKFLOW / STEP / PARTICIPANT'
    AS DemoSection;


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
    'Trigger Update Demo Document',
    'Isolated document used to demonstrate terminal workflow trigger behavior.',
    @demo_owner_id,
    @classification_internal_id,
    @document_active_id
);

SET @demo_document_id = LAST_INSERT_ID();


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
    'Trigger demo version.',
    CURRENT_TIMESTAMP,
    @demo_owner_id,
    @version_locked_id,
    CURRENT_TIMESTAMP
);

SET @demo_version_id = LAST_INSERT_ID();


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
    @workflow_purpose_review_id,
    @workflow_active_id,
    CURRENT_TIMESTAMP,
    DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 30 DAY)
);

SET @demo_workflow_id = LAST_INSERT_ID();


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
    @review_step_type_id,
    'ALL_REQUIRED',
    @step_active_id,
    CURRENT_TIMESTAMP,
    NULL,
    DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 7 DAY)
);

SET @demo_step_id = LAST_INSERT_ID();


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
    @demo_step_id,
    @demo_reviewer_id,
    @demo_reviewer_role_id,
    @review_action_id,
    @participant_active_id,
    TRUE,
    CURRENT_TIMESTAMP,
    NULL,
    DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 7 DAY)
);

SET @demo_participant_id = LAST_INSERT_ID();



-- ============================================================
-- PART 2
-- BEFORE trigger action
-- ============================================================

SELECT
    'PART 2 - BEFORE TRIGGER ACTION'
    AS DemoSection;


SELECT
    w.WorkflowID,
    workflow_status.Code AS WorkflowStatus,

    ws.WorkflowStepID,
    step_status.Code AS StepStatus,

    wp.WorkflowParticipantID,
    CONCAT(u.FirstName, ' ', u.LastName)
        AS Participant,

    participant_status.Code
        AS ParticipantStatus,

    ws.CompletionDateTime
        AS StepCompletionDateTime,

    wp.CompletionDateTime
        AS ParticipantCompletionDateTime

FROM Workflow w

JOIN ReferenceData workflow_status
  ON workflow_status.ReferenceDataID =
     w.WorkflowStatusID

JOIN WorkflowStep ws
  ON ws.WorkflowID = w.WorkflowID

JOIN ReferenceData step_status
  ON step_status.ReferenceDataID =
     ws.StepStatusID

JOIN WorkflowParticipant wp
  ON wp.WorkflowStepID =
     ws.WorkflowStepID

JOIN `User` u
  ON u.UserID =
     wp.UserID

JOIN ReferenceData participant_status
  ON participant_status.ReferenceDataID =
     wp.AssignmentStatusID

WHERE w.WorkflowID =
      @demo_workflow_id;



-- Expected BEFORE:
--
-- WorkflowStatus    = ACTIVE
-- StepStatus        = ACTIVE
-- ParticipantStatus = ACTIVE



-- ============================================================
-- PART 3
-- ACTION THAT CAUSES TRIGGER
--
-- IMPORTANT:
--
-- We update ONLY the Workflow row.
--
-- We do NOT issue:
--
--   UPDATE WorkflowStep ...
--   UPDATE WorkflowParticipant ...
--
-- Those updates are performed automatically by:
--
--   trg_Workflow_TerminalCascade
-- ============================================================

SELECT
    'PART 3 - UPDATE ONLY WORKFLOW TO CANCELLED'
    AS DemoSection;


UPDATE Workflow

SET
    WorkflowStatusID = @workflow_cancelled_id,
    CancellationDateTime = CURRENT_TIMESTAMP,
    CancellationReason =
        'Trigger update demonstration.'

WHERE WorkflowID =
      @demo_workflow_id;



-- ============================================================
-- PART 4
-- AFTER trigger action
-- ============================================================

SELECT
    'PART 4 - AFTER TRIGGER ACTION'
    AS DemoSection;


SELECT
    w.WorkflowID,
    workflow_status.Code AS WorkflowStatus,

    ws.WorkflowStepID,
    step_status.Code AS StepStatus,

    wp.WorkflowParticipantID,
    CONCAT(u.FirstName, ' ', u.LastName)
        AS Participant,

    participant_status.Code
        AS ParticipantStatus,

    ws.CompletionDateTime
        AS StepCompletionDateTime,

    wp.CompletionDateTime
        AS ParticipantCompletionDateTime

FROM Workflow w

JOIN ReferenceData workflow_status
  ON workflow_status.ReferenceDataID =
     w.WorkflowStatusID

JOIN WorkflowStep ws
  ON ws.WorkflowID = w.WorkflowID

JOIN ReferenceData step_status
  ON step_status.ReferenceDataID =
     ws.StepStatusID

JOIN WorkflowParticipant wp
  ON wp.WorkflowStepID =
     ws.WorkflowStepID

JOIN `User` u
  ON u.UserID =
     wp.UserID

JOIN ReferenceData participant_status
  ON participant_status.ReferenceDataID =
     wp.AssignmentStatusID

WHERE w.WorkflowID =
      @demo_workflow_id;



-- Expected AFTER:
--
-- WorkflowStatus    = CANCELLED
-- StepStatus        = CANCELLED
-- ParticipantStatus = CANCELLED
--
-- CompletionDateTime should also now be populated for the
-- outstanding step and assignment.



-- ============================================================
-- PART 5
-- Explicit PASS / FAIL verification
-- ============================================================

SELECT
    'PART 5 - VERIFY AUTOMATIC CHILD UPDATES'
    AS DemoSection;


SELECT
    CASE

        WHEN workflow_status.Code = 'CANCELLED'
         AND step_status.Code = 'CANCELLED'
         AND participant_status.Code = 'CANCELLED'
         AND ws.CompletionDateTime IS NOT NULL
         AND wp.CompletionDateTime IS NOT NULL

        THEN 'PASS'

        ELSE 'FAIL'

    END AS Result,

    'Workflow terminal-state update automatically cascaded to outstanding child records'
        AS TestName,

    workflow_status.Code
        AS WorkflowStatus,

    step_status.Code
        AS StepStatus,

    participant_status.Code
        AS ParticipantStatus

FROM Workflow w

JOIN ReferenceData workflow_status
  ON workflow_status.ReferenceDataID =
     w.WorkflowStatusID

JOIN WorkflowStep ws
  ON ws.WorkflowID =
     w.WorkflowID

JOIN ReferenceData step_status
  ON step_status.ReferenceDataID =
     ws.StepStatusID

JOIN WorkflowParticipant wp
  ON wp.WorkflowStepID =
     ws.WorkflowStepID

JOIN ReferenceData participant_status
  ON participant_status.ReferenceDataID =
     wp.AssignmentStatusID

WHERE w.WorkflowID =
      @demo_workflow_id;



-- ============================================================
-- PART 6
-- Show trigger definition for explanation
-- ============================================================

SELECT
    'PART 6 - TRIGGER DEFINITION'
    AS DemoSection;


SHOW CREATE TRIGGER trg_Workflow_TerminalCascade;



-- ============================================================
-- FINAL RESULT
-- ============================================================

SELECT '============================================================'
    AS DemoSection;

SELECT
    'TRIGGER UPDATE DEMO COMPLETED'
    AS DemoSection;

SELECT
    'Only Workflow was directly updated; child Step and Participant rows were changed automatically by the trigger.'
    AS Evidence;

SELECT '============================================================'
    AS DemoSection;