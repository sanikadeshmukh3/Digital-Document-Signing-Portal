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

GRANT SELECT ON document_portal.ReferenceData
TO 'document_portal_app';

GRANT SELECT ON document_portal.`User`
TO 'document_portal_app';

GRANT SELECT ON document_portal.Role
TO 'document_portal_app';

GRANT SELECT ON document_portal.UserRole
TO 'document_portal_app';

GRANT SELECT ON document_portal.Document
TO 'document_portal_app';

GRANT SELECT ON document_portal.DocumentVersion
TO 'document_portal_app';

GRANT SELECT ON document_portal.Workflow
TO 'document_portal_app';

GRANT SELECT ON document_portal.WorkflowStep
TO 'document_portal_app';

GRANT SELECT ON document_portal.WorkflowParticipant
TO 'document_portal_app';

GRANT SELECT ON document_portal.ApprovalDecision
TO 'document_portal_app';

GRANT SELECT ON document_portal.Signature
TO 'document_portal_app';


-- ------------------------------------------------------------
-- Approved operational views
-- ------------------------------------------------------------

GRANT SELECT ON document_portal.vw_ParticipantWorklist
TO 'document_portal_app';

GRANT SELECT ON document_portal.vw_OutstandingActions
TO 'document_portal_app';

GRANT SELECT ON document_portal.vw_WorkflowDetail
TO 'document_portal_app';

GRANT SELECT ON document_portal.vw_DocumentVersionHistory
TO 'document_portal_app';


-- ------------------------------------------------------------
-- Stored procedures
-- ------------------------------------------------------------

GRANT EXECUTE ON PROCEDURE
    document_portal.sp_initiate_workflow
TO 'document_portal_app';


GRANT EXECUTE ON PROCEDURE
    document_portal.sp_complete_review_acknowledgement
TO 'document_portal_app';


GRANT EXECUTE ON PROCEDURE
    document_portal.sp_record_approval_decision
TO 'document_portal_app';


GRANT EXECUTE ON PROCEDURE
    document_portal.sp_record_signature
TO 'document_portal_app';


GRANT EXECUTE ON PROCEDURE
    document_portal.sp_cancel_workflow
TO 'document_portal_app';


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

GRANT SELECT ON document_portal.vw_OutstandingActions
TO 'document_portal_reporter';

GRANT SELECT ON document_portal.vw_WorkflowDetail
TO 'document_portal_reporter';

GRANT SELECT ON document_portal.vw_DocumentVersionHistory
TO 'document_portal_reporter';

GRANT SELECT ON document_portal.vw_DocumentHistory
TO 'document_portal_reporter';


-- ============================================================
-- 3. AUDITOR ROLE
-- ============================================================
-- Read-only access to historical and audit data.
--
-- No INSERT / UPDATE / DELETE permissions are granted.
-- ============================================================

GRANT SELECT ON document_portal.vw_DocumentHistory
TO 'document_portal_auditor';

GRANT SELECT ON document_portal.vw_DocumentVersionHistory
TO 'document_portal_auditor';

GRANT SELECT ON document_portal.vw_WorkflowDetail
TO 'document_portal_auditor';

GRANT SELECT ON document_portal.vw_AuditHistory
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
ON document_portal.`User`
TO 'document_portal_admin';


-- Business-role administration

GRANT SELECT, INSERT, UPDATE
ON document_portal.Role
TO 'document_portal_admin';


GRANT SELECT, INSERT, DELETE
ON document_portal.UserRole
TO 'document_portal_admin';


-- Reference-data administration

GRANT SELECT, INSERT, UPDATE
ON document_portal.ReferenceData
TO 'document_portal_admin';


-- Operational visibility

GRANT SELECT
ON document_portal.Document
TO 'document_portal_admin';

GRANT SELECT
ON document_portal.DocumentVersion
TO 'document_portal_admin';

GRANT SELECT
ON document_portal.Workflow
TO 'document_portal_admin';

GRANT SELECT
ON document_portal.WorkflowStep
TO 'document_portal_admin';

GRANT SELECT
ON document_portal.WorkflowParticipant
TO 'document_portal_admin';


-- Historical information is read-only.

GRANT SELECT
ON document_portal.ApprovalDecision
TO 'document_portal_admin';

GRANT SELECT
ON document_portal.Signature
TO 'document_portal_admin';

GRANT SELECT
ON document_portal.AuditLog
TO 'document_portal_admin';


-- Administrative/reporting views.

GRANT SELECT
ON document_portal.vw_DocumentHistory
TO 'document_portal_admin';

GRANT SELECT
ON document_portal.vw_AuditHistory
TO 'document_portal_admin';


-- Allow administrator-authorized workflow cancellation.

GRANT EXECUTE ON PROCEDURE
    document_portal.sp_cancel_workflow
TO 'document_portal_admin';