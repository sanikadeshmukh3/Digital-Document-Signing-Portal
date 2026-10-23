-- ============================================================
-- File: database/02_programmability/010_views.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Create reusable views supporting operational worklists,
--   workflow detail, document history, version history,
--   and audit reporting.
--
-- Important:
--   These views expose reusable database result sets.
--   Role/row-level authorization is still enforced through
--   stored procedures, grants, or application authorization.
-- ============================================================


-- ============================================================
-- 1. Participant Worklist
-- ============================================================
-- Supports:
--   FR-08
--   FR-12
--   FR-17
--
-- Provides workflow assignments and related document data.
--
-- Consumers should filter by UserID so participants retrieve
-- only their own assignments.
-- ============================================================

CREATE OR REPLACE VIEW vw_ParticipantWorklist AS
SELECT
    wp.WorkflowParticipantID,
    wp.UserID,
    wp.RoleID,

    d.DocumentID,
    d.Title,

    dv.DocumentVersionID,
    dv.VersionNumber,

    w.WorkflowID,

    ws.WorkflowStepID,
    ws.SequenceNumber,

    step_type.Code AS StepType,
    step_type.DisplayName AS StepTypeName,

    assigned_action.Code AS AssignedAction,
    assigned_action.DisplayName AS AssignedActionName,

    participant_status.Code AS AssignmentStatus,
    participant_status.DisplayName AS AssignmentStatusName,

    workflow_status.Code AS WorkflowStatus,
    workflow_status.DisplayName AS WorkflowStatusName,

    wp.RequiredFlag,
    wp.ActivationDateTime,
    wp.CompletionDateTime,
    wp.DueDateTime,

    w.ExpirationDateTime

FROM WorkflowParticipant wp

JOIN WorkflowStep ws
    ON ws.WorkflowStepID = wp.WorkflowStepID

JOIN Workflow w
    ON w.WorkflowID = ws.WorkflowID

JOIN DocumentVersion dv
    ON dv.DocumentVersionID = w.DocumentVersionID

JOIN Document d
    ON d.DocumentID = w.DocumentID

JOIN ReferenceData step_type
    ON step_type.ReferenceDataID = ws.StepTypeID

JOIN ReferenceData assigned_action
    ON assigned_action.ReferenceDataID = wp.AssignedActionID

JOIN ReferenceData participant_status
    ON participant_status.ReferenceDataID = wp.AssignmentStatusID

JOIN ReferenceData workflow_status
    ON workflow_status.ReferenceDataID = w.WorkflowStatusID;


-- ============================================================
-- 2. Outstanding Actions
-- ============================================================
-- Supports:
--   FR-17
--
-- Shows workflow actions that are still Pending or Active.
--
-- Includes:
--   document
--   workflow
--   action type
--   participant
--   status
--   due date
--   expiration information
-- ============================================================

CREATE OR REPLACE VIEW vw_OutstandingActions AS
SELECT
    wp.WorkflowParticipantID,

    d.DocumentID,
    d.Title,

    w.WorkflowID,

    ws.WorkflowStepID,
    ws.SequenceNumber,

    wp.UserID,

    CONCAT(u.FirstName, ' ', u.LastName)
        AS ParticipantName,

    assigned_action.Code
        AS AssignedAction,

    assigned_action.DisplayName
        AS AssignedActionName,

    participant_status.Code
        AS AssignmentStatus,

    workflow_status.Code
        AS WorkflowStatus,

    wp.RequiredFlag,

    wp.ActivationDateTime,

    wp.DueDateTime,

    w.ExpirationDateTime

FROM WorkflowParticipant wp

JOIN `User` u
    ON u.UserID = wp.UserID

JOIN WorkflowStep ws
    ON ws.WorkflowStepID = wp.WorkflowStepID

JOIN Workflow w
    ON w.WorkflowID = ws.WorkflowID

JOIN DocumentVersion dv
    ON dv.DocumentVersionID = w.DocumentVersionID

JOIN Document d
    ON d.DocumentID = dv.DocumentID

JOIN ReferenceData assigned_action
    ON assigned_action.ReferenceDataID = wp.AssignedActionID

JOIN ReferenceData participant_status
    ON participant_status.ReferenceDataID = wp.AssignmentStatusID

JOIN ReferenceData workflow_status
    ON workflow_status.ReferenceDataID = w.WorkflowStatusID

WHERE participant_status.DomainName = 'PARTICIPANT_STATUS'
  AND participant_status.Code IN (
        'PENDING',
        'ACTIVE'
  );


-- ============================================================
-- 3. Workflow Detail
-- ============================================================
-- Supports:
--   workflow inspection
--   FR-18
--   reporting/query requirements
--
-- Shows the complete structure of a Workflow including its
-- document/version, steps, participants, approvals, and
-- signatures.
-- ============================================================

CREATE OR REPLACE VIEW vw_WorkflowDetail AS
SELECT
    w.WorkflowID,

    d.DocumentID,
    d.Title,

    dv.DocumentVersionID,
    dv.VersionNumber,

    workflow_status.Code
        AS WorkflowStatus,

    w.InitiatorUserID,
    w.StartDateTime,
    w.CompletionDateTime,
    w.CancellationDateTime,
    w.CancellationReason,
    w.ExpirationDateTime,

    ws.WorkflowStepID,
    ws.SequenceNumber,

    step_type.Code
        AS StepType,

    step_status.Code
        AS StepStatus,

    ws.RequiredPolicy,
    ws.ActivationDateTime
        AS StepActivationDateTime,
    ws.CompletionDateTime
        AS StepCompletionDateTime,
    ws.DueDateTime
        AS StepDueDateTime,

    wp.WorkflowParticipantID,
    wp.UserID,

    CONCAT(
        participant_user.FirstName,
        ' ',
        participant_user.LastName
    ) AS ParticipantName,

    r.RoleName,

    assigned_action.Code
        AS AssignedAction,

    participant_status.Code
        AS AssignmentStatus,

    wp.RequiredFlag,

    wp.ActivationDateTime
        AS ParticipantActivationDateTime,

    wp.CompletionDateTime
        AS ParticipantCompletionDateTime,

    ad.ApprovalID,

    approval_value.Code
        AS ApprovalDecision,

    ad.DecisionDateTime,

    ad.Comments
        AS ApprovalComments,

    ad.RejectionReason,

    s.SignatureID,
    s.SigningDateTime,

    signature_status.Code
        AS SignatureStatus,

    s.SignatureMethod,
    s.SignatureReference

FROM Workflow w

JOIN Document d
    ON d.DocumentID = w.DocumentID

JOIN DocumentVersion dv
    ON dv.DocumentVersionID = w.DocumentVersionID

JOIN ReferenceData workflow_status
    ON workflow_status.ReferenceDataID = w.WorkflowStatusID

LEFT JOIN WorkflowStep ws
    ON ws.WorkflowID = w.WorkflowID

LEFT JOIN ReferenceData step_type
    ON step_type.ReferenceDataID = ws.StepTypeID

LEFT JOIN ReferenceData step_status
    ON step_status.ReferenceDataID = ws.StepStatusID

LEFT JOIN WorkflowParticipant wp
    ON wp.WorkflowStepID = ws.WorkflowStepID

LEFT JOIN `User` participant_user
    ON participant_user.UserID = wp.UserID

LEFT JOIN Role r
    ON r.RoleID = wp.RoleID

LEFT JOIN ReferenceData assigned_action
    ON assigned_action.ReferenceDataID = wp.AssignedActionID

LEFT JOIN ReferenceData participant_status
    ON participant_status.ReferenceDataID =
       wp.AssignmentStatusID

LEFT JOIN ApprovalDecision ad
    ON ad.WorkflowParticipantID =
       wp.WorkflowParticipantID

LEFT JOIN ReferenceData approval_value
    ON approval_value.ReferenceDataID =
       ad.DecisionValueID

LEFT JOIN Signature s
    ON s.WorkflowParticipantID =
       wp.WorkflowParticipantID

LEFT JOIN ReferenceData signature_status
    ON signature_status.ReferenceDataID =
       s.SignatureStatusID;


-- ============================================================
-- 4. Document Version History
-- ============================================================
-- Supports:
--   FR-02
--   FR-18
--
-- Provides all versions belonging to a Document.
--
-- Because DocumentVersion is modeled as a weak entity,
-- VersionNumber is meaningful within its parent Document.
-- ============================================================

CREATE OR REPLACE VIEW vw_DocumentVersionHistory AS
SELECT
    d.DocumentID,
    d.Title,

    dv.DocumentVersionID,
    dv.VersionNumber,

    version_status.Code
        AS VersionStatus,

    dv.EffectiveInformation,

    dv.CreatedDateTime,

    dv.CreatedByUserID,

    CONCAT(
        creator.FirstName,
        ' ',
        creator.LastName
    ) AS CreatedByName,

    dv.LockedDateTime,

    COUNT(w.WorkflowID)
        AS WorkflowCount

FROM Document d

JOIN DocumentVersion dv
    ON dv.DocumentID = d.DocumentID

JOIN `User` creator
    ON creator.UserID = dv.CreatedByUserID

JOIN ReferenceData version_status
    ON version_status.ReferenceDataID =
       dv.CurrentVersionStatusID

LEFT JOIN Workflow w
    ON w.DocumentVersionID = dv.DocumentVersionID

GROUP BY
    d.DocumentID,
    d.Title,
    dv.DocumentVersionID,
    dv.VersionNumber,
    version_status.Code,
    dv.EffectiveInformation,
    dv.CreatedDateTime,
    dv.CreatedByUserID,
    creator.FirstName,
    creator.LastName,
    dv.LockedDateTime;


-- ============================================================
-- 5. Document History
-- ============================================================
-- Supports:
--   FR-18
--
-- Provides a joined historical view of:
--   Document
--   DocumentVersion
--   Workflow
--   WorkflowStep
--   WorkflowParticipant
--   ApprovalDecision
--   Signature
--
-- Intended primarily for Workflow Manager / Auditor reporting.
-- ============================================================

CREATE OR REPLACE VIEW vw_DocumentHistory AS
SELECT
    d.DocumentID,
    d.Title,
    d.OwnerUserID,

    document_status.Code
        AS DocumentStatus,

    dv.DocumentVersionID,
    dv.VersionNumber,
    dv.CreatedDateTime
        AS VersionCreatedDateTime,
    dv.LockedDateTime,

    w.WorkflowID,

    workflow_status.Code
        AS WorkflowStatus,

    w.StartDateTime,
    w.CompletionDateTime,
    w.CancellationDateTime,
    w.ExpirationDateTime,

    ws.WorkflowStepID,
    ws.SequenceNumber,

    step_type.Code
        AS StepType,

    step_status.Code
        AS StepStatus,

    wp.WorkflowParticipantID,
    wp.UserID
        AS ParticipantUserID,

    assigned_action.Code
        AS AssignedAction,

    participant_status.Code
        AS AssignmentStatus,

    wp.CompletionDateTime
        AS ParticipantCompletionDateTime,

    ad.ApprovalID,

    approval_value.Code
        AS ApprovalDecision,

    ad.DecisionDateTime,

    s.SignatureID,
    s.SigningDateTime,

    signature_status.Code
        AS SignatureStatus

FROM Document d

JOIN ReferenceData document_status
    ON document_status.ReferenceDataID =
       d.LifecycleStatusID

LEFT JOIN DocumentVersion dv
    ON dv.DocumentID = d.DocumentID

LEFT JOIN Workflow w
    ON w.DocumentVersionID =
       dv.DocumentVersionID

LEFT JOIN ReferenceData workflow_status
    ON workflow_status.ReferenceDataID =
       w.WorkflowStatusID

LEFT JOIN WorkflowStep ws
    ON ws.WorkflowID = w.WorkflowID

LEFT JOIN ReferenceData step_type
    ON step_type.ReferenceDataID =
       ws.StepTypeID

LEFT JOIN ReferenceData step_status
    ON step_status.ReferenceDataID =
       ws.StepStatusID

LEFT JOIN WorkflowParticipant wp
    ON wp.WorkflowStepID =
       ws.WorkflowStepID

LEFT JOIN ReferenceData assigned_action
    ON assigned_action.ReferenceDataID =
       wp.AssignedActionID

LEFT JOIN ReferenceData participant_status
    ON participant_status.ReferenceDataID =
       wp.AssignmentStatusID

LEFT JOIN ApprovalDecision ad
    ON ad.WorkflowParticipantID =
       wp.WorkflowParticipantID

LEFT JOIN ReferenceData approval_value
    ON approval_value.ReferenceDataID =
       ad.DecisionValueID

LEFT JOIN Signature s
    ON s.WorkflowParticipantID =
       wp.WorkflowParticipantID

LEFT JOIN ReferenceData signature_status
    ON signature_status.ReferenceDataID =
       s.SignatureStatusID;


-- ============================================================
-- 6. Audit History
-- ============================================================
-- Supports:
--   FR-15
--   FR-18
--
-- AuditLog is append-only.
-- This view provides a readable audit-history representation.
-- ============================================================

CREATE OR REPLACE VIEW vw_AuditHistory AS
SELECT
    a.AuditLogID,

    a.EventDateTime,

    a.ActorUserID,

    CASE
        WHEN a.ActorUserID IS NULL
            THEN 'SYSTEM'
        ELSE CONCAT(
            u.FirstName,
            ' ',
            u.LastName
        )
    END AS ActorName,

    a.EventType,

    a.AffectedRecordType,

    a.AffectedRecordID,

    a.TransactionReference,

    a.PriorValueContext,

    a.NewValueContext,

    a.ChangeReason

FROM AuditLog a

LEFT JOIN `User` u
    ON u.UserID = a.ActorUserID;