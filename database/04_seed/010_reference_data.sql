-- ============================================================
-- File: database/04_seed/010_reference_data.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Seed controlled lookup values into the generalized
--   ReferenceData table.
--
-- Scope:
--   ONLY controlled reference/lookup values belong here.
--   Users, business roles (Role table), documents, workflows,
--   and audit events are seeded in 020_sample_data.sql.
--
-- Database: MySQL 8.x
--
-- Notes:
--   - Columns supplied: (DomainName, Code, DisplayName, Description).
--     IsActive defaults TRUE and the timestamps default via the
--     schema, so every row seeded here is ACTIVE. Lookups elsewhere
--     match reference rows on IsActive = TRUE.
--   - Plain INSERTs, no upserts. UNIQUE (DomainName, Code) prevents
--     duplicates; re-running against an already-seeded database
--     errors on purpose, since the build always targets a fresh DB.
--   - Codes are kept consistent with the rest of the database:
--     WORKFLOW_STATUS uses COMPLETED (not COMPLETE); SIGNATURE_STATUS
--     has only SIGNED; PARTICIPANT_STATUS has no DECLINED; and
--     DOCUMENT_VERSION_STATUS (CURRENT/LOCKED) is included because
--     workflow initiation and the DocumentVersion triggers rely on it.
-- ============================================================

START TRANSACTION;

INSERT INTO ReferenceData
    (DomainName, Code, DisplayName, Description)
VALUES
    -- --------------------------------------------------------
    -- ACCOUNT_STATUS  (User.AccountStatusID)
    -- --------------------------------------------------------
    ('ACCOUNT_STATUS', 'ACTIVE',
     'Active', 'User account is enabled and may participate.'),
    ('ACCOUNT_STATUS', 'INACTIVE',
     'Inactive', 'User account is disabled.'),

    -- --------------------------------------------------------
    -- DOCUMENT_STATUS  (Document.LifecycleStatusID)
    -- --------------------------------------------------------
    ('DOCUMENT_STATUS', 'DRAFT',
     'Draft', 'Document is being prepared.'),
    ('DOCUMENT_STATUS', 'ACTIVE',
     'Active', 'Document is available for workflow use.'),
    ('DOCUMENT_STATUS', 'ARCHIVED',
     'Archived', 'Document is archived and no longer active.'),

    -- --------------------------------------------------------
    -- DOCUMENT_CLASSIFICATION  (Document.ClassificationID)
    -- --------------------------------------------------------
    ('DOCUMENT_CLASSIFICATION', 'INTERNAL',
     'Internal', 'Internal business document.'),
    ('DOCUMENT_CLASSIFICATION', 'CONFIDENTIAL',
     'Confidential', 'Confidential business document.'),
    ('DOCUMENT_CLASSIFICATION', 'RESTRICTED',
     'Restricted', 'Access-restricted business document.'),

    -- --------------------------------------------------------
    -- DOCUMENT_VERSION_STATUS  (DocumentVersion.CurrentVersionStatusID)
    -- Required by sp_initiate_workflow and DocumentVersion triggers.
    -- --------------------------------------------------------
    ('DOCUMENT_VERSION_STATUS', 'CURRENT',
     'Current', 'Active, editable current version of a document.'),
    ('DOCUMENT_VERSION_STATUS', 'LOCKED',
     'Locked', 'Finalized, immutable version bound to a workflow.'),

    -- --------------------------------------------------------
    -- WORKFLOW_STATUS  (Workflow.WorkflowStatusID)
    -- Completion code is COMPLETED (not COMPLETE).
    -- --------------------------------------------------------
    ('WORKFLOW_STATUS', 'DRAFT',
     'Draft', 'Workflow is being configured and not yet started.'),
    ('WORKFLOW_STATUS', 'ACTIVE',
     'Active', 'Workflow is in progress.'),
    ('WORKFLOW_STATUS', 'COMPLETED',
     'Completed', 'All required workflow work has finished.'),
    ('WORKFLOW_STATUS', 'REJECTED',
     'Rejected', 'Workflow ended because an approval was rejected.'),
    ('WORKFLOW_STATUS', 'CANCELLED',
     'Cancelled', 'Workflow was cancelled before completion.'),
    ('WORKFLOW_STATUS', 'EXPIRED',
     'Expired', 'Workflow passed its expiration date.'),

    -- --------------------------------------------------------
    -- WORKFLOW_PURPOSE_TYPE  (Workflow.WorkflowPurposeTypeID)
    -- --------------------------------------------------------
    ('WORKFLOW_PURPOSE_TYPE', 'REVIEW',
     'Review', 'Review-only workflow.'),
    ('WORKFLOW_PURPOSE_TYPE', 'APPROVAL',
     'Approval', 'Approval workflow.'),
    ('WORKFLOW_PURPOSE_TYPE', 'SIGNATURE',
     'Signature', 'Signature workflow.'),
    ('WORKFLOW_PURPOSE_TYPE', 'FULL_REVIEW_APPROVAL_SIGNATURE',
     'Full Review, Approval and Signature',
     'Combined review, approval, and signature workflow.'),

    -- --------------------------------------------------------
    -- STEP_TYPE  (WorkflowStep.StepTypeID)
    -- --------------------------------------------------------
    ('STEP_TYPE', 'REVIEW',
     'Review', 'Review step.'),
    ('STEP_TYPE', 'APPROVAL',
     'Approval', 'Approval step.'),
    ('STEP_TYPE', 'ACKNOWLEDGEMENT',
     'Acknowledgement', 'Acknowledgement step.'),
    ('STEP_TYPE', 'SIGNATURE',
     'Signature', 'Signature step.'),

    -- --------------------------------------------------------
    -- STEP_STATUS  (WorkflowStep.StepStatusID)
    -- --------------------------------------------------------
    ('STEP_STATUS', 'PENDING',
     'Pending', 'Step is waiting on predecessor work.'),
    ('STEP_STATUS', 'ACTIVE',
     'Active', 'Step is currently actionable.'),
    ('STEP_STATUS', 'COMPLETED',
     'Completed', 'Step finished successfully.'),
    ('STEP_STATUS', 'CANCELLED',
     'Cancelled', 'Step was cancelled.'),

    -- --------------------------------------------------------
    -- PARTICIPANT_STATUS  (WorkflowParticipant.AssignmentStatusID)
    -- No DECLINED code.
    -- --------------------------------------------------------
    ('PARTICIPANT_STATUS', 'PENDING',
     'Pending', 'Assignment is waiting to become actionable.'),
    ('PARTICIPANT_STATUS', 'ACTIVE',
     'Active', 'Assignment is currently actionable.'),
    ('PARTICIPANT_STATUS', 'COMPLETED',
     'Completed', 'Assignment has been completed.'),
    ('PARTICIPANT_STATUS', 'REJECTED',
     'Rejected', 'Assignment ended in a rejection decision.'),
    ('PARTICIPANT_STATUS', 'CANCELLED',
     'Cancelled', 'Assignment was cancelled.'),

    -- --------------------------------------------------------
    -- ASSIGNED_ACTION  (WorkflowParticipant.AssignedActionID)
    -- --------------------------------------------------------
    ('ASSIGNED_ACTION', 'REVIEW',
     'Review', 'Participant must review.'),
    ('ASSIGNED_ACTION', 'APPROVAL',
     'Approval', 'Participant must approve or reject.'),
    ('ASSIGNED_ACTION', 'ACKNOWLEDGEMENT',
     'Acknowledgement', 'Participant must acknowledge.'),
    ('ASSIGNED_ACTION', 'SIGNATURE',
     'Signature', 'Participant must sign.'),

    -- --------------------------------------------------------
    -- APPROVAL_DECISION  (ApprovalDecision.DecisionValueID)
    -- --------------------------------------------------------
    ('APPROVAL_DECISION', 'APPROVED',
     'Approved', 'Approval was granted.'),
    ('APPROVAL_DECISION', 'REJECTED',
     'Rejected', 'Approval was rejected.'),

    -- --------------------------------------------------------
    -- SIGNATURE_STATUS  (Signature.SignatureStatusID)
    -- Only SIGNED is defined for the initial release.
    -- --------------------------------------------------------
    ('SIGNATURE_STATUS', 'SIGNED',
     'Signed', 'The participant has signed the document version.');

COMMIT;
