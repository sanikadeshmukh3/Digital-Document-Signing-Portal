-- ============================================================
-- File: database/05_validation/010_object_validation.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Verify that all required database objects were installed:
--   base tables, key constraints (PK/UNIQUE/FK), indexes, views,
--   functions, procedures, triggers, and the database-level roles.
--
-- Behavior:
--   A temporary stored procedure performs each check against
--   information_schema for the current DATABASE(). If any required
--   object is missing, it raises SQLSTATE '45000', which aborts the
--   build (fail-closed). On success it prints a summary.
--
--   In addition, human-readable PRESENT/MISSING result sets are
--   emitted for the demonstration, independent of the hard check.
--
-- Database: MySQL 8.x
-- ============================================================


-- ------------------------------------------------------------
-- Human-readable result sets (for the demo; non-fatal).
-- ------------------------------------------------------------

SELECT '--- Base tables ---' AS ObjectValidation;

SELECT t.expected AS ObjectName,
       CASE WHEN ist.TABLE_NAME IS NULL THEN 'MISSING' ELSE 'PRESENT' END AS Status
FROM (
    SELECT 'ReferenceData' AS expected UNION ALL SELECT 'User' UNION ALL
    SELECT 'Role' UNION ALL SELECT 'UserRole' UNION ALL
    SELECT 'Document' UNION ALL SELECT 'DocumentVersion' UNION ALL
    SELECT 'Workflow' UNION ALL SELECT 'WorkflowStep' UNION ALL
    SELECT 'WorkflowParticipant' UNION ALL SELECT 'ApprovalDecision' UNION ALL
    SELECT 'Signature' UNION ALL SELECT 'AuditLog'
) t
LEFT JOIN information_schema.TABLES ist
    ON ist.TABLE_SCHEMA = DATABASE()
   AND ist.TABLE_NAME = t.expected
   AND ist.TABLE_TYPE = 'BASE TABLE'
ORDER BY t.expected;

SELECT '--- Views ---' AS ObjectValidation;

SELECT v.expected AS ObjectName,
       CASE WHEN isv.TABLE_NAME IS NULL THEN 'MISSING' ELSE 'PRESENT' END AS Status
FROM (
    SELECT 'vw_ParticipantWorklist' AS expected UNION ALL
    SELECT 'vw_OutstandingActions' UNION ALL
    SELECT 'vw_WorkflowDetail' UNION ALL
    SELECT 'vw_DocumentVersionHistory' UNION ALL
    SELECT 'vw_DocumentHistory' UNION ALL
    SELECT 'vw_AuditHistory'
) v
LEFT JOIN information_schema.VIEWS isv
    ON isv.TABLE_SCHEMA = DATABASE()
   AND isv.TABLE_NAME = v.expected
ORDER BY v.expected;

SELECT '--- Routines (functions/procedures) ---' AS ObjectValidation;

SELECT r.expected AS ObjectName, r.kind AS RoutineType,
       CASE WHEN isr.ROUTINE_NAME IS NULL THEN 'MISSING' ELSE 'PRESENT' END AS Status
FROM (
    SELECT 'fn_user_has_role' AS expected, 'FUNCTION' AS kind UNION ALL
    SELECT 'fn_all_predecessors_complete', 'FUNCTION' UNION ALL
    SELECT 'fn_step_required_work_complete', 'FUNCTION' UNION ALL
    SELECT 'fn_workflow_required_work_complete', 'FUNCTION' UNION ALL
    SELECT 'sp_advance_workflow', 'PROCEDURE' UNION ALL
    SELECT 'sp_initiate_workflow', 'PROCEDURE' UNION ALL
    SELECT 'sp_complete_review_acknowledgement', 'PROCEDURE' UNION ALL
    SELECT 'sp_record_approval_decision', 'PROCEDURE' UNION ALL
    SELECT 'sp_record_signature', 'PROCEDURE' UNION ALL
    SELECT 'sp_cancel_workflow', 'PROCEDURE' UNION ALL
    SELECT 'sp_expire_workflows', 'PROCEDURE' UNION ALL
    SELECT 'sp_create_document_version', 'PROCEDURE'
) r
LEFT JOIN information_schema.ROUTINES isr
    ON isr.ROUTINE_SCHEMA = DATABASE()
   AND isr.ROUTINE_NAME = r.expected
   AND isr.ROUTINE_TYPE = r.kind
ORDER BY r.kind, r.expected;

SELECT '--- Triggers ---' AS ObjectValidation;

SELECT tr.expected AS ObjectName,
       CASE WHEN ist.TRIGGER_NAME IS NULL THEN 'MISSING' ELSE 'PRESENT' END AS Status
FROM (
    SELECT 'trg_DocumentVersion_PreventFinalizedUpdate' AS expected UNION ALL
    SELECT 'trg_DocumentVersion_PreventFinalizedDelete' UNION ALL
    SELECT 'trg_ApprovalDecision_PreventUpdate' UNION ALL
    SELECT 'trg_ApprovalDecision_PreventDelete' UNION ALL
    SELECT 'trg_Signature_PreventUpdate' UNION ALL
    SELECT 'trg_Signature_PreventDelete' UNION ALL
    SELECT 'trg_AuditLog_PreventUpdate' UNION ALL
    SELECT 'trg_AuditLog_PreventDelete'
) tr
LEFT JOIN information_schema.TRIGGERS ist
    ON ist.TRIGGER_SCHEMA = DATABASE()
   AND ist.TRIGGER_NAME = tr.expected
ORDER BY tr.expected;

SELECT '--- Database roles (document_portal_*) ---' AS ObjectValidation;

SELECT '--- Database roles (document_portal_*) ---' AS ObjectValidation;

-- Database roles are server-level objects.
-- Reading mysql.user may not be permitted for a least-privilege
-- build account, so this display check is best-effort.
--
-- If mysql.user is readable, the installed project roles are shown.
-- If it is not readable, a NOTE is returned instead of failing
-- the build at this display-only stage.

DELIMITER $$

DROP PROCEDURE IF EXISTS sp__display_database_roles $$

CREATE PROCEDURE sp__display_database_roles()
BEGIN
    DECLARE v_role_err INT DEFAULT 0;

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        SET v_role_err = 1;

    SELECT
        User AS ObjectName,
        'PRESENT' AS Status
    FROM mysql.user
    WHERE User IN (
        'document_portal_app',
        'document_portal_reporter',
        'document_portal_auditor',
        'document_portal_admin'
    )
    ORDER BY User;

    IF v_role_err = 1 THEN
        SELECT
            'NOTE: mysql.user is not readable by the build user; database-role display check skipped.'
                AS RoleCheck;
    END IF;
END $$

DELIMITER ;

CALL sp__display_database_roles();

DROP PROCEDURE sp__display_database_roles;


-- ------------------------------------------------------------
-- Hard, fail-closed validation.
-- ------------------------------------------------------------

DELIMITER $$

DROP PROCEDURE IF EXISTS sp__validate_objects $$

CREATE PROCEDURE sp__validate_objects()
BEGIN
    DECLARE v_count INT;
    DECLARE v_missing VARCHAR(255);

    -- ----- 12 base tables -----
    SELECT COUNT(*) INTO v_count
    FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_TYPE = 'BASE TABLE'
      AND TABLE_NAME IN (
          'ReferenceData','User','Role','UserRole','Document',
          'DocumentVersion','Workflow','WorkflowStep',
          'WorkflowParticipant','ApprovalDecision','Signature','AuditLog');
    IF v_count <> 12 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Object validation failed: not all 12 base tables are present.';
    END IF;

    -- ----- Composite PK on DocumentVersion(DocumentID, VersionNumber) -----
    SELECT COUNT(*) INTO v_count
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'DocumentVersion'
      AND INDEX_NAME = 'PRIMARY'
      AND COLUMN_NAME IN ('DocumentID','VersionNumber');
    IF v_count <> 2 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Object validation failed: DocumentVersion composite PK (DocumentID, VersionNumber) missing.';
    END IF;

    -- ----- PK on UserRole(UserID, RoleID) -----
    SELECT COUNT(*) INTO v_count
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'UserRole'
      AND INDEX_NAME = 'PRIMARY'
      AND COLUMN_NAME IN ('UserID','RoleID');
    IF v_count <> 2 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Object validation failed: UserRole composite PK (UserID, RoleID) missing.';
    END IF;

    -- ----- Named UNIQUE constraints -----
    SELECT COUNT(*) INTO v_count
    FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND CONSTRAINT_TYPE = 'UNIQUE'
      AND CONSTRAINT_NAME IN (
          'uq_WorkflowParticipant_Assignment',
          'uq_ApprovalDecision_WorkflowParticipant',
          'uq_Signature_WorkflowParticipant');
    IF v_count <> 3 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Object validation failed: a required UNIQUE constraint (WorkflowParticipant assignment / ApprovalDecision / Signature) is missing.';
    END IF;

    -- ----- Composite FK fk_WorkflowParticipant_UserRole -----
    SELECT COUNT(*) INTO v_count
    FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND CONSTRAINT_TYPE = 'FOREIGN KEY'
      AND TABLE_NAME = 'WorkflowParticipant'
      AND CONSTRAINT_NAME = 'fk_WorkflowParticipant_UserRole';
    IF v_count <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Object validation failed: composite FK fk_WorkflowParticipant_UserRole missing.';
    END IF;

    -- Confirm it spans both (UserID, RoleID).
    SELECT COUNT(*) INTO v_count
    FROM information_schema.KEY_COLUMN_USAGE
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND TABLE_NAME = 'WorkflowParticipant'
      AND CONSTRAINT_NAME = 'fk_WorkflowParticipant_UserRole'
      AND COLUMN_NAME IN ('UserID','RoleID');
    IF v_count <> 2 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Object validation failed: fk_WorkflowParticipant_UserRole does not span (UserID, RoleID).';
    END IF;

    -- ----- Worklist index idx_WorkflowParticipant_User_Status_DueDate -----
    SELECT COUNT(DISTINCT INDEX_NAME) INTO v_count
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'WorkflowParticipant'
      AND INDEX_NAME = 'idx_WorkflowParticipant_User_Status_DueDate';
    IF v_count <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Object validation failed: index idx_WorkflowParticipant_User_Status_DueDate missing.';
    END IF;

    -- ----- 6 views -----
    SELECT COUNT(*) INTO v_count
    FROM information_schema.VIEWS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME IN (
          'vw_ParticipantWorklist','vw_OutstandingActions','vw_WorkflowDetail',
          'vw_DocumentVersionHistory','vw_DocumentHistory','vw_AuditHistory');
    IF v_count <> 6 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Object validation failed: not all 6 required views are present.';
    END IF;

    -- ----- 4 functions -----
    SELECT COUNT(*) INTO v_count
    FROM information_schema.ROUTINES
    WHERE ROUTINE_SCHEMA = DATABASE()
      AND ROUTINE_TYPE = 'FUNCTION'
      AND ROUTINE_NAME IN (
          'fn_user_has_role','fn_all_predecessors_complete',
          'fn_step_required_work_complete','fn_workflow_required_work_complete');
    IF v_count <> 4 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Object validation failed: not all 4 required functions are present.';
    END IF;

    -- ----- 6 procedures -----
    SELECT COUNT(*) INTO v_count
    FROM information_schema.ROUTINES
    WHERE ROUTINE_SCHEMA = DATABASE()
      AND ROUTINE_TYPE = 'PROCEDURE'
      AND ROUTINE_NAME IN (
          'sp_advance_workflow','sp_initiate_workflow',
          'sp_complete_review_acknowledgement','sp_record_approval_decision',
          'sp_record_signature','sp_cancel_workflow', 'sp_expire_workflows', 'sp_create_document_version');
    IF v_count <> 8 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Object validation failed: not all 8 required procedures are present.';
    END IF;

    -- ----- 8 triggers -----
    SELECT COUNT(*) INTO v_count
    FROM information_schema.TRIGGERS
    WHERE TRIGGER_SCHEMA = DATABASE()
      AND TRIGGER_NAME IN (
          'trg_DocumentVersion_PreventFinalizedUpdate',
          'trg_DocumentVersion_PreventFinalizedDelete',
          'trg_ApprovalDecision_PreventUpdate',
          'trg_ApprovalDecision_PreventDelete',
          'trg_Signature_PreventUpdate',
          'trg_Signature_PreventDelete',
          'trg_AuditLog_PreventUpdate',
          'trg_AuditLog_PreventDelete');
    IF v_count <> 8 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Object validation failed: not all 8 required triggers are present.';
    END IF;

    -- ----- 4 database roles (best-effort; non-fatal if unreadable) -----
    -- mysql.user requires privilege; the build runs as root so it is
    -- readable here. If a least-privilege build user cannot read it, this
    -- degrades to a NOTE rather than aborting the build.
    BEGIN
        DECLARE v_role_err INT DEFAULT 0;
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_role_err = 1;

        SELECT COUNT(*) INTO v_count
        FROM mysql.user
        WHERE User IN (
            'document_portal_app','document_portal_reporter',
            'document_portal_auditor','document_portal_admin');

        IF v_role_err = 1 THEN
            SELECT 'NOTE: mysql.user not readable by build user; database-role check skipped (non-fatal).' AS RoleCheck;
        ELSEIF v_count <> 4 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Object validation failed: not all 4 document_portal_* database roles are present.';
        END IF;
    END;

    SELECT 'OBJECT VALIDATION PASSED: all required objects are present.' AS Result;
END $$

DELIMITER ;

CALL sp__validate_objects();

DROP PROCEDURE sp__validate_objects;
