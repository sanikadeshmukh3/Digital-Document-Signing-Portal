-- ============================================================
-- File:
-- database/03_security/030_workflow_metadata_grants.sql
--
-- Project:
-- Document Workflow and E-signing Portal
--
-- Purpose:
--   Extend the existing security model for metadata-driven
--   workflow transitions.
--
-- Security design:
--   - Application clients may ASK which actions are allowed.
--   - Application clients execute approved public procedures.
--   - Internal transition helpers are NOT directly exposed.
--   - System administrators may maintain transition metadata.
-- ============================================================


-- ============================================================
-- 1. APPLICATION ROLE
-- ============================================================

-- ------------------------------------------------------------
-- Allow the application to read display-ready workflow
-- transition metadata.
--
-- The application does NOT need direct SELECT access to
-- WorkflowStatusTransition or WorkflowTransitionRole.
-- ------------------------------------------------------------

GRANT SELECT
ON `{{TARGET_DB}}`.vw_WorkflowTransitionMetadata
TO 'document_portal_app';


-- ------------------------------------------------------------
-- Allow the application to ask:
--
-- "What workflow actions may this particular user take on this
-- particular workflow?"
-- ------------------------------------------------------------

GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_get_allowed_workflow_transitions
TO 'document_portal_app';


-- ------------------------------------------------------------
-- IMPORTANT:
--
-- Do NOT grant EXECUTE on:
--
--   sp_transition_workflow
--   sp_advance_workflow
--
-- These are internal workflow helpers.
--
-- sp_transition_workflow includes system-transition behavior,
-- so exposing it directly to the application would allow the
-- application layer to bypass the intended public business
-- procedure boundary.
-- ------------------------------------------------------------


-- ============================================================
-- 2. REPORTING ROLE
-- ============================================================

-- Reporting processes may inspect transition metadata for
-- documentation/reporting purposes, but cannot modify it.

GRANT SELECT
ON `{{TARGET_DB}}`.vw_WorkflowTransitionMetadata
TO 'document_portal_reporter';


-- ============================================================
-- 3. AUDITOR ROLE
-- ============================================================

-- Auditors may inspect the configured workflow lifecycle and
-- role permissions but cannot modify them.

GRANT SELECT
ON `{{TARGET_DB}}`.vw_WorkflowTransitionMetadata
TO 'document_portal_auditor';


-- ============================================================
-- 4. ADMINISTRATIVE ROLE
-- ============================================================

-- System administrators may inspect the display-ready metadata.

GRANT SELECT
ON `{{TARGET_DB}}`.vw_WorkflowTransitionMetadata
TO 'document_portal_admin';


-- ------------------------------------------------------------
-- Administrators maintain workflow-transition metadata.
--
-- UPDATE is needed for:
--   - activating/deactivating transitions
--   - changing labels
--   - confirmation/reason settings
--   - display ordering
--
-- INSERT allows new workflow transitions to be introduced
-- through metadata.
--
-- DELETE is intentionally withheld. Existing metadata should
-- normally be retired using IsActive instead of being removed.
-- ------------------------------------------------------------

GRANT SELECT, INSERT, UPDATE
ON `{{TARGET_DB}}`.WorkflowStatusTransition
TO 'document_portal_admin';


-- ------------------------------------------------------------
-- Administrators may assign/remove roles from workflow
-- transitions.
--
-- DELETE is appropriate here because this is a current
-- entitlement mapping rather than immutable business history.
-- ------------------------------------------------------------

GRANT SELECT, INSERT, UPDATE, DELETE
ON `{{TARGET_DB}}`.WorkflowTransitionRole
TO 'document_portal_admin';


-- ------------------------------------------------------------
-- Allow administrators to use the context-aware metadata read
-- procedure as well.
-- ------------------------------------------------------------

GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_get_allowed_workflow_transitions
TO 'document_portal_admin';


-- ------------------------------------------------------------
-- Still intentionally NOT granted:
--
-- sp_transition_workflow
-- sp_advance_workflow
--
-- Administrative workflow actions should still enter through
-- public procedures such as sp_cancel_workflow and
-- sp_expire_workflows.
-- ------------------------------------------------------------