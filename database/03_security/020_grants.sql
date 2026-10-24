-- ============================================================
-- File: database/03_security/020_grants.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Grant database privileges according to the security design.
--
-- Security principles:
--   1. Protected writes go through stored procedures.
--   2. Reporting uses approved views.
--   3. Audit access is read-only.
--   4. Immutable historical records are not directly modifiable.
--   5. Business-level row authorization remains enforced inside
--      procedures and application logic.
--
-- NOTE:
--   Replace document_portal with the final database name if
--   your schema name differs.
-- ============================================================


-- ============================================================
-- 1. APPLICATION ROLE
-- ============================================================
-- The normal application account can read necessary operational
-- data and execute approved business procedures.
--
-- It does NOT receive general UPDATE or DELETE access to the
-- underlying business tables.
-- ============================================================


-- ------------------------------------------------------------
-- Basic operational reads
-- ------------------------------------------------------------

GRANT SELECT ON `{{TARGET_DB}}`.ReferenceData
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.`User`
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.Role
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.UserRole
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.Document
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.DocumentVersion
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.Workflow
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.WorkflowStep
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.WorkflowParticipant
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.ApprovalDecision
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.Signature
TO 'document_portal_app';


-- ------------------------------------------------------------
-- Approved operational views
-- ------------------------------------------------------------

GRANT SELECT ON `{{TARGET_DB}}`.vw_ParticipantWorklist
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.vw_OutstandingActions
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.vw_WorkflowDetail
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.vw_DocumentVersionHistory
TO 'document_portal_app';


-- ------------------------------------------------------------
-- Stored procedures
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

GRANT EXECUTE ON PROCEDURE 
    `{{TARGET_DB}}`.sp_expire_workflows
TO 'document_portal_admin';


-- sp_advance_workflow is an internal helper.
--
-- Do NOT grant direct EXECUTE permission to ordinary application
-- accounts if users should not invoke it independently.


-- ============================================================
-- 2. REPORTING ROLE
-- ============================================================
-- Workflow Managers and reporting processes may use this
-- database role.
--
-- The role is intentionally read-only.
-- ============================================================

GRANT SELECT ON `{{TARGET_DB}}`.vw_OutstandingActions
TO 'document_portal_reporter';

GRANT SELECT ON `{{TARGET_DB}}`.vw_WorkflowDetail
TO 'document_portal_reporter';

GRANT SELECT ON `{{TARGET_DB}}`.vw_DocumentVersionHistory
TO 'document_portal_reporter';

GRANT SELECT ON `{{TARGET_DB}}`.vw_DocumentHistory
TO 'document_portal_reporter';


-- ============================================================
-- 3. AUDITOR ROLE
-- ============================================================
-- Read-only access to historical and audit data.
--
-- No INSERT / UPDATE / DELETE permissions are granted.
-- ============================================================

GRANT SELECT ON `{{TARGET_DB}}`.vw_DocumentHistory
TO 'document_portal_auditor';

GRANT SELECT ON `{{TARGET_DB}}`.vw_DocumentVersionHistory
TO 'document_portal_auditor';

GRANT SELECT ON `{{TARGET_DB}}`.vw_WorkflowDetail
TO 'document_portal_auditor';

GRANT SELECT ON `{{TARGET_DB}}`.vw_AuditHistory
TO 'document_portal_auditor';


-- ============================================================
-- 4. ADMINISTRATIVE ROLE
-- ============================================================
-- Administrative accounts need access to user/role/reference
-- information.
--
-- Initial implementation grants controlled DML on administrative
-- tables.
--
-- We deliberately do NOT grant UPDATE or DELETE privileges on:
--
--   ApprovalDecision
--   Signature
--   AuditLog
--
-- Those records are protected historical records.
-- ============================================================


-- User administration

GRANT SELECT, INSERT, UPDATE
ON `{{TARGET_DB}}`.`User`
TO 'document_portal_admin';


-- Business-role administration

GRANT SELECT, INSERT, UPDATE
ON `{{TARGET_DB}}`.Role
TO 'document_portal_admin';


GRANT SELECT, INSERT, DELETE
ON `{{TARGET_DB}}`.UserRole
TO 'document_portal_admin';


-- Reference-data administration

GRANT SELECT, INSERT, UPDATE
ON `{{TARGET_DB}}`.ReferenceData
TO 'document_portal_admin';


-- Operational visibility

GRANT SELECT
ON `{{TARGET_DB}}`.Document
TO 'document_portal_admin';

GRANT SELECT
ON `{{TARGET_DB}}`.DocumentVersion
TO 'document_portal_admin';

GRANT SELECT
ON `{{TARGET_DB}}`.Workflow
TO 'document_portal_admin';

GRANT SELECT
ON `{{TARGET_DB}}`.WorkflowStep
TO 'document_portal_admin';

GRANT SELECT
ON `{{TARGET_DB}}`.WorkflowParticipant
TO 'document_portal_admin';


-- Historical information is read-only.

GRANT SELECT
ON `{{TARGET_DB}}`.ApprovalDecision
TO 'document_portal_admin';

GRANT SELECT
ON `{{TARGET_DB}}`.Signature
TO 'document_portal_admin';

GRANT SELECT
ON `{{TARGET_DB}}`.AuditLog
TO 'document_portal_admin';


-- Administrative/reporting views.

GRANT SELECT
ON `{{TARGET_DB}}`.vw_DocumentHistory
TO 'document_portal_admin';

GRANT SELECT
ON `{{TARGET_DB}}`.vw_AuditHistory
TO 'document_portal_admin';


-- Allow administrator-authorized workflow cancellation.

GRANT EXECUTE ON PROCEDURE
    `{{TARGET_DB}}`.sp_cancel_workflow
TO 'document_portal_admin';