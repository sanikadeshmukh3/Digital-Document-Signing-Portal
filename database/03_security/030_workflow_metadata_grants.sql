-- ============================================================
-- File:
-- database/03_security/030_workflow_metadata_grants.sql
--
-- Project:
-- Document Workflow and E-signing Portal
--
-- Purpose:
--   Restore approved routine grants after workflow procedures
--   were recreated, and grant access to new metadata-driven
--   workflow objects.
-- ============================================================


-- ============================================================
-- 1. APPLICATION ROLE
-- ============================================================

-- ------------------------------------------------------------
-- Public business procedures.
--
-- Re-grant these explicitly because several procedures were
-- DROPped and CREATEd again during the workflow refactor.
-- ------------------------------------------------------------

GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_initiate_workflow
TO 'document_portal_app';


GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_complete_review_acknowledgement
TO 'document_portal_app';


GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_record_approval_decision
TO 'document_portal_app';


GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_record_signature
TO 'document_portal_app';


GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_cancel_workflow
TO 'document_portal_app';


GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_create_document_version
TO 'document_portal_app';


-- ------------------------------------------------------------
-- Metadata-driven permission query.
-- ------------------------------------------------------------

GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_get_allowed_workflow_transitions
TO 'document_portal_app';


-- ------------------------------------------------------------
-- Display-ready workflow metadata.
-- ------------------------------------------------------------

GRANT SELECT
ON `{{TARGET_DB}}`.vw_WorkflowTransitionMetadata
TO 'document_portal_app';


-- ------------------------------------------------------------
-- Intentionally NOT granted:
--
--   sp_transition_workflow
--   sp_advance_workflow
--
-- Those remain internal helpers.
-- ------------------------------------------------------------


-- ============================================================
-- 2. REPORTING ROLE
-- ============================================================

GRANT SELECT
ON `{{TARGET_DB}}`.vw_WorkflowTransitionMetadata
TO 'document_portal_reporter';


-- ============================================================
-- 3. AUDITOR ROLE
-- ============================================================

GRANT SELECT
ON `{{TARGET_DB}}`.vw_WorkflowTransitionMetadata
TO 'document_portal_auditor';


-- ============================================================
-- 4. ADMINISTRATIVE ROLE
-- ============================================================

GRANT SELECT
ON `{{TARGET_DB}}`.vw_WorkflowTransitionMetadata
TO 'document_portal_admin';


GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_get_allowed_workflow_transitions
TO 'document_portal_admin';


-- Restore administrator cancellation privilege because
-- sp_cancel_workflow was recreated by the refactor.

GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_cancel_workflow
TO 'document_portal_admin';


-- Restore expiration privilege because sp_expire_workflows was
-- recreated by the refactor.

GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_expire_workflows
TO 'document_portal_admin';


-- ------------------------------------------------------------
-- Transition-definition administration.
-- ------------------------------------------------------------

GRANT SELECT, INSERT, UPDATE
ON `{{TARGET_DB}}`.WorkflowStatusTransition
TO 'document_portal_admin';


-- Do not DELETE WorkflowStatusTransition.
-- Retire transitions through IsActive instead.


GRANT SELECT, INSERT, UPDATE, DELETE
ON `{{TARGET_DB}}`.WorkflowTransitionRole
TO 'document_portal_admin';


-- ------------------------------------------------------------
-- Still intentionally NOT granted:
--
--   sp_transition_workflow
--   sp_advance_workflow
-- ------------------------------------------------------------