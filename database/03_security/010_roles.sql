-- ============================================================
-- File: database/03_security/010_roles.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Create database-level roles used to restrict access to
--   protected database objects.
--
-- IMPORTANT:
--   These are MySQL database roles.
--
--   They are NOT the same as the business roles stored in the
--   Role and UserRole tables.
--
-- Database roles:
--   document_portal_app
--   document_portal_reporter
--   document_portal_auditor
--   document_portal_admin
-- ============================================================


-- ------------------------------------------------------------
-- Application role
-- ------------------------------------------------------------
-- Used by the application/service account for ordinary business
-- operations.
--
-- The application should perform protected modifications through
-- stored procedures rather than direct table UPDATE/DELETE.
-- ------------------------------------------------------------

CREATE ROLE IF NOT EXISTS
    'document_portal_app';


-- ------------------------------------------------------------
-- Reporting role
-- ------------------------------------------------------------
-- Used for operational reporting.
--
-- Receives SELECT access to approved reporting views, but no
-- direct modification privileges.
-- ------------------------------------------------------------

CREATE ROLE IF NOT EXISTS
    'document_portal_reporter';


-- ------------------------------------------------------------
-- Auditor role
-- ------------------------------------------------------------
-- Used for read-only historical/audit retrieval.
--
-- Receives SELECT access to approved history and audit views.
-- Does not receive INSERT, UPDATE, or DELETE access.
-- ------------------------------------------------------------

CREATE ROLE IF NOT EXISTS
    'document_portal_auditor';


-- ------------------------------------------------------------
-- Administrative role
-- ------------------------------------------------------------
-- Used by authorized administrative database/application
-- accounts.
--
-- This role may administer users, roles, and reference data
-- through controlled procedures.
--
-- It still should NOT receive unrestricted UPDATE or DELETE
-- privileges over immutable ApprovalDecision, Signature, or
-- AuditLog history.
-- ------------------------------------------------------------

CREATE ROLE IF NOT EXISTS
    'document_portal_admin';