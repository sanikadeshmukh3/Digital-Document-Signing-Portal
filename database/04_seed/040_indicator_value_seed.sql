-- ============================================================
-- File: database/04_seed/040_indicator_value_seed.sql
-- Project: Document Workflow and E-signing Portal
--
-- Migration: 027
-- Schema Version: 1.4.0 - Principle 11 (Indicator Value pattern)
--
-- Purpose:
--   1. Give every existing ReferenceData row a DisplayOrder.
--   2. Move the coded domains that lived only in CHECK
--      constraints and procedure literals into ReferenceData.
--
-- Coded-domain inventory (20 coded columns, 12 tables):
--
--   Stored as ReferenceDataID (FK + indicator trigger)
--     User.AccountStatusID                    ACCOUNT_STATUS
--     Document.ClassificationID               DOCUMENT_CLASSIFICATION
--     Document.LifecycleStatusID              DOCUMENT_STATUS
--     DocumentVersion.CurrentVersionStatusID  DOCUMENT_VERSION_STATUS
--     Workflow.WorkflowPurposeTypeID          WORKFLOW_PURPOSE_TYPE
--     Workflow.WorkflowStatusID               WORKFLOW_STATUS
--     WorkflowStep.StepTypeID                 STEP_TYPE
--     WorkflowStep.StepStatusID               STEP_STATUS
--     WorkflowParticipant.AssignedActionID    ASSIGNED_ACTION
--     WorkflowParticipant.AssignmentStatusID  PARTICIPANT_STATUS
--     ApprovalDecision.DecisionValueID        APPROVAL_DECISION
--     Signature.SignatureStatusID             SIGNATURE_STATUS
--     WorkflowStatusTransition.FromStatusID   WORKFLOW_STATUS
--     WorkflowStatusTransition.ToStatusID     WORKFLOW_STATUS
--
--   Stored as Code (indicator trigger), NEW domains in 1.4.0
--     WorkflowStep.RequiredPolicy             REQUIRED_POLICY
--     Signature.SignatureMethod               SIGNATURE_METHOD
--     AuditLog.EventType                      AUDIT_EVENT_TYPE
--     AuditLog.AffectedRecordType             AUDIT_RECORD_TYPE
--     DatabaseBuild.BuildStatus               BUILD_STATUS
--     DatabaseObjectVersion.ObjectType        DATABASE_OBJECT_TYPE
--
-- Deliberately NOT converted (true/false properties, not coded
-- domains): Role.ActiveStatus, WorkflowParticipant.RequiredFlag,
-- ReferenceData.IsActive, WorkflowStatusTransition flags.
-- WorkflowStatusTransition.TransitionCode is the key of a
-- metadata table (Principle 4), not a column drawing from a list.
--
-- Re-run safe: DisplayOrder is only filled where still 0, and
-- new values use ON DUPLICATE KEY UPDATE against
-- UNIQUE (DomainName, Code).
-- ============================================================

START TRANSACTION;

-- ------------------------------------------------------------
-- 1. DisplayOrder for pre-existing values: original seed order
--    (ReferenceDataID) within each domain, in steps of 10 so a
--    value can later be slotted between two others.
-- ------------------------------------------------------------

DROP TEMPORARY TABLE IF EXISTS tmp_mig_027_display_order;

CREATE TEMPORARY TABLE tmp_mig_027_display_order AS
SELECT
    ReferenceDataID,
    ROW_NUMBER() OVER (
        PARTITION BY DomainName
        ORDER BY ReferenceDataID
    ) * 10 AS NewDisplayOrder
FROM ReferenceData;

UPDATE ReferenceData rd
JOIN tmp_mig_027_display_order o
    ON o.ReferenceDataID = rd.ReferenceDataID
SET rd.DisplayOrder = o.NewDisplayOrder
WHERE rd.DisplayOrder = 0;

DROP TEMPORARY TABLE tmp_mig_027_display_order;


-- ------------------------------------------------------------
-- 2. Newly data-driven domains.
-- ------------------------------------------------------------

INSERT INTO ReferenceData
    (DomainName, Code, DisplayName, Description, DisplayOrder)
VALUES
    -- --------------------------------------------------------
    -- REQUIRED_POLICY  (WorkflowStep.RequiredPolicy)
    -- The workflow engine implements ALL_REQUIRED semantics,
    -- so it is the only policy offered in this release.
    -- --------------------------------------------------------
    ('REQUIRED_POLICY', 'ALL_REQUIRED',
     'All Required',
     'Every required participant assignment in the step must complete.',
     10),

    -- --------------------------------------------------------
    -- SIGNATURE_METHOD  (Signature.SignatureMethod)
    -- TDD: "Supported internal signature method".
    -- --------------------------------------------------------
    ('SIGNATURE_METHOD', 'TYPED_NAME',
     'Typed Name',
     'Signer types their full legal name as the simulated electronic signature.',
     10),

    -- --------------------------------------------------------
    -- AUDIT_EVENT_TYPE  (AuditLog.EventType)
    -- Every event type emitted by procedures (including
    -- sp_transition_workflow), seed data and the scale-data
    -- generator.
    -- --------------------------------------------------------
    ('AUDIT_EVENT_TYPE', 'DOCUMENT_VERSION_CREATED',
     'Document Version Created', 'A new DocumentVersion was created.', 10),
    ('AUDIT_EVENT_TYPE', 'WORKFLOW_INITIATED',
     'Workflow Initiated', 'A workflow was configured and activated.', 20),
    ('AUDIT_EVENT_TYPE', 'REVIEW_COMPLETED',
     'Review Completed', 'A participant completed a review assignment.', 30),
    ('AUDIT_EVENT_TYPE', 'ACKNOWLEDGEMENT_COMPLETED',
     'Acknowledgement Completed', 'A participant completed an acknowledgement assignment.', 40),
    ('AUDIT_EVENT_TYPE', 'APPROVAL_RECORDED',
     'Approval Recorded', 'An approver recorded an approval decision.', 50),
    ('AUDIT_EVENT_TYPE', 'APPROVAL_REJECTED',
     'Approval Rejected', 'An approver rejected; the workflow was terminated.', 60),
    ('AUDIT_EVENT_TYPE', 'SIGNATURE_RECORDED',
     'Signature Recorded', 'A signer executed a signature.', 70),
    ('AUDIT_EVENT_TYPE', 'WORKFLOW_PROGRESS',
     'Workflow Progress', 'A workflow advanced but has not yet finished.', 80),
    ('AUDIT_EVENT_TYPE', 'WORKFLOW_COMPLETED',
     'Workflow Completed', 'All required workflow work finished.', 90),
    ('AUDIT_EVENT_TYPE', 'WORKFLOW_REJECTED',
     'Workflow Rejected', 'The workflow transitioned to REJECTED.', 100),
    ('AUDIT_EVENT_TYPE', 'WORKFLOW_CANCELLED',
     'Workflow Cancelled', 'A workflow was cancelled before completion.', 110),
    ('AUDIT_EVENT_TYPE', 'WORKFLOW_EXPIRED',
     'Workflow Expired', 'A workflow passed its expiration date and was closed.', 120),
    ('AUDIT_EVENT_TYPE', 'WORKFLOW_STATUS_CHANGED',
     'Workflow Status Changed', 'Any other governed workflow status transition.', 130),
    ('AUDIT_EVENT_TYPE', 'WORKFLOW_EXPIRY_SCAN',
     'Workflow Expiry Scan', 'Scheduled expiration scan executed.', 140),

    -- --------------------------------------------------------
    -- AUDIT_RECORD_TYPE  (AuditLog.AffectedRecordType)
    -- Codes are the entity (table) names already stored.
    -- --------------------------------------------------------
    ('AUDIT_RECORD_TYPE', 'DocumentVersion',
     'Document Version', 'AffectedRecordID is a DocumentVersionID.', 10),
    ('AUDIT_RECORD_TYPE', 'Workflow',
     'Workflow', 'AffectedRecordID is a WorkflowID.', 20),
    ('AUDIT_RECORD_TYPE', 'WorkflowParticipant',
     'Workflow Participant', 'AffectedRecordID is a WorkflowParticipantID.', 30),
    ('AUDIT_RECORD_TYPE', 'ApprovalDecision',
     'Approval Decision', 'AffectedRecordID is an ApprovalID.', 40),
    ('AUDIT_RECORD_TYPE', 'Signature',
     'Signature', 'AffectedRecordID is a SignatureID.', 50),

    -- --------------------------------------------------------
    -- BUILD_STATUS  (DatabaseBuild.BuildStatus)
    -- --------------------------------------------------------
    ('BUILD_STATUS', 'STARTED',
     'Started', 'Database build/upgrade is in progress.', 10),
    ('BUILD_STATUS', 'COMPLETED',
     'Completed', 'Database build/upgrade finished successfully.', 20),
    ('BUILD_STATUS', 'FAILED',
     'Failed', 'Database build/upgrade did not finish.', 30),

    -- --------------------------------------------------------
    -- DATABASE_OBJECT_TYPE  (DatabaseObjectVersion.ObjectType)
    -- --------------------------------------------------------
    ('DATABASE_OBJECT_TYPE', 'VIEW',
     'View', 'Version stamp for a view.', 10),
    ('DATABASE_OBJECT_TYPE', 'FUNCTION',
     'Function', 'Version stamp for a stored function.', 20),
    ('DATABASE_OBJECT_TYPE', 'PROCEDURE',
     'Procedure', 'Version stamp for a stored procedure.', 30),
    ('DATABASE_OBJECT_TYPE', 'TRIGGER',
     'Trigger', 'Version stamp for a trigger.', 40)

ON DUPLICATE KEY UPDATE
    -- No-op on re-run: keep any later admin changes.
    ReferenceDataID = ReferenceDataID;

COMMIT;
