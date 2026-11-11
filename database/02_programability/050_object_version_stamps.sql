-- ============================================================
-- File: database/02_programability/050_object_version_stamps.sql
-- Project: Document Workflow and E-signing Portal
--
-- Migration: 015
-- Schema Version: 1.2.0
--
-- Purpose:
--   Establish baseline version stamps for programmable
--   database objects.
--
--   Existing objects begin at object version 1.0.0.
--   Future changes to an individual object should be made
--   through a new migration that also updates that object's
--   version stamp.
-- ============================================================


-- ------------------------------------------------------------
-- Views
-- ------------------------------------------------------------

INSERT INTO DatabaseObjectVersion (
    ObjectType,
    ObjectName,
    ObjectVersion,
    StampedSchemaVersion,
    StampMigrationVersion
)
VALUES
    (
        'VIEW',
        'vw_ParticipantWorklist',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'VIEW',
        'vw_OutstandingActions',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'VIEW',
        'vw_WorkflowDetail',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'VIEW',
        'vw_DocumentVersionHistory',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'VIEW',
        'vw_DocumentHistory',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'VIEW',
        'vw_AuditHistory',
        '1.0.0',
        '1.2.0',
        '015'
    );


-- ------------------------------------------------------------
-- Functions
-- ------------------------------------------------------------

INSERT INTO DatabaseObjectVersion (
    ObjectType,
    ObjectName,
    ObjectVersion,
    StampedSchemaVersion,
    StampMigrationVersion
)
VALUES
    (
        'FUNCTION',
        'fn_user_has_role',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'FUNCTION',
        'fn_all_predecessors_complete',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'FUNCTION',
        'fn_step_required_work_complete',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'FUNCTION',
        'fn_workflow_required_work_complete',
        '1.0.0',
        '1.2.0',
        '015'
    );


-- ------------------------------------------------------------
-- Procedures
-- ------------------------------------------------------------

INSERT INTO DatabaseObjectVersion (
    ObjectType,
    ObjectName,
    ObjectVersion,
    StampedSchemaVersion,
    StampMigrationVersion
)
VALUES
    (
        'PROCEDURE',
        'sp_advance_workflow',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'PROCEDURE',
        'sp_initiate_workflow',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'PROCEDURE',
        'sp_complete_review_acknowledgement',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'PROCEDURE',
        'sp_record_approval_decision',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'PROCEDURE',
        'sp_record_signature',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'PROCEDURE',
        'sp_cancel_workflow',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'PROCEDURE',
        'sp_create_document_version',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'PROCEDURE',
        'sp_expire_workflows',
        '1.0.0',
        '1.2.0',
        '015'
    );


-- ------------------------------------------------------------
-- Triggers
-- ------------------------------------------------------------

INSERT INTO DatabaseObjectVersion (
    ObjectType,
    ObjectName,
    ObjectVersion,
    StampedSchemaVersion,
    StampMigrationVersion
)
VALUES
    (
        'TRIGGER',
        'trg_DocumentVersion_PreventFinalizedUpdate',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'TRIGGER',
        'trg_DocumentVersion_PreventFinalizedDelete',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'TRIGGER',
        'trg_ApprovalDecision_PreventUpdate',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'TRIGGER',
        'trg_ApprovalDecision_PreventDelete',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'TRIGGER',
        'trg_Signature_PreventUpdate',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'TRIGGER',
        'trg_Signature_PreventDelete',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'TRIGGER',
        'trg_AuditLog_PreventUpdate',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'TRIGGER',
        'trg_AuditLog_PreventDelete',
        '1.0.0',
        '1.2.0',
        '015'
    ),
    (
        'TRIGGER',
        'trg_Workflow_TerminalCascade',
        '1.0.0',
        '1.2.0',
        '015'
    );