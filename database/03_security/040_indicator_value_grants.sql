-- ============================================================
-- File: database/03_security/040_indicator_value_grants.sql
-- Project: Document Workflow and E-signing Portal
--
-- Migration: 029
-- Schema Version: 1.4.0 - Principle 11 (Indicator Value pattern)
--
-- Purpose:
--   Grant the generic list-of-values service, validation
--   functions and decode views to the existing database roles.
--
--   sp_assert_indicator_id/_code are NOT granted: only the
--   indicator triggers call them, with definer rights.
--
--   Privileges on the replaced views vw_WorkflowDetail and
--   vw_AuditHistory survive CREATE OR REPLACE VIEW, so they are
--   not re-granted here.
--
--   Adding an indicator value stays an administrator data change:
--   document_portal_admin already holds SELECT, INSERT, UPDATE on
--   ReferenceData (020_grants.sql).
-- ============================================================


-- ------------------------------------------------------------
-- Application: combo boxes + submitted-value validation
-- ------------------------------------------------------------

GRANT EXECUTE ON PROCEDURE `{{TARGET_DB}}`.sp_get_indicator_values
TO 'document_portal_app';

GRANT EXECUTE ON FUNCTION `{{TARGET_DB}}`.fn_is_indicator_member
TO 'document_portal_app';

GRANT EXECUTE ON FUNCTION `{{TARGET_DB}}`.fn_is_indicator_id_member
TO 'document_portal_app';

GRANT EXECUTE ON FUNCTION `{{TARGET_DB}}`.fn_decode_indicator
TO 'document_portal_app';

GRANT SELECT ON `{{TARGET_DB}}`.vw_IndicatorValue
TO 'document_portal_app';


-- ------------------------------------------------------------
-- Reporting: report filters + decoding
-- ------------------------------------------------------------

GRANT EXECUTE ON PROCEDURE `{{TARGET_DB}}`.sp_get_indicator_values
TO 'document_portal_reporter';

GRANT EXECUTE ON FUNCTION `{{TARGET_DB}}`.fn_decode_indicator
TO 'document_portal_reporter';

GRANT SELECT ON `{{TARGET_DB}}`.vw_IndicatorValue
TO 'document_portal_reporter';


-- ------------------------------------------------------------
-- Auditor: decoded integrity report (read-only)
-- ------------------------------------------------------------

GRANT SELECT ON `{{TARGET_DB}}`.vw_IndicatorValue
TO 'document_portal_auditor';

GRANT SELECT ON `{{TARGET_DB}}`.vw_CodedValueIntegrity
TO 'document_portal_auditor';


-- ------------------------------------------------------------
-- Administrator: maintains indicator values
-- ------------------------------------------------------------

GRANT EXECUTE ON PROCEDURE `{{TARGET_DB}}`.sp_get_indicator_values
TO 'document_portal_admin';

GRANT SELECT ON `{{TARGET_DB}}`.vw_IndicatorValue
TO 'document_portal_admin';

GRANT SELECT ON `{{TARGET_DB}}`.vw_CodedValueIntegrity
TO 'document_portal_admin';
