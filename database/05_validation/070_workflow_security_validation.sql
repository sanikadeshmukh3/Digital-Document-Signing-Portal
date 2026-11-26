-- ============================================================
-- File:
-- database/05_validation/070_workflow_security_validation.sql
--
-- Project:
-- Document Workflow and E-signing Portal
--
-- Purpose:
--   Validate the least-privilege security boundary for the
--   metadata-driven workflow implementation.
--
-- MySQL privilege sources used:
--
--   mysql.procs_priv  -> routine-specific privileges
--   mysql.tables_priv -> table/view-specific privileges
--   mysql.db          -> database-wide privileges
--   mysql.user        -> global privileges
--
-- Database: MySQL 8.x
-- ============================================================


SELECT '=== Workflow Security Validation ==='
    AS ValidationSection;


-- ============================================================
-- HUMAN-READABLE EVIDENCE
-- ============================================================


-- ------------------------------------------------------------
-- Routine-specific privileges
-- ------------------------------------------------------------

SELECT
    User,
    Host,
    Db,
    Routine_name,
    Routine_type,
    Proc_priv

FROM mysql.procs_priv

WHERE Db = DATABASE()
  AND User IN (
      'document_portal_app',
      'document_portal_admin'
  )

ORDER BY
    User,
    Routine_name;


-- ------------------------------------------------------------
-- Table/view-specific privileges
-- ------------------------------------------------------------

SELECT
    User,
    Host,
    Db,
    Table_name,
    Table_priv

FROM mysql.tables_priv

WHERE Db = DATABASE()
  AND User IN (
      'document_portal_app',
      'document_portal_admin',
      'document_portal_reporter',
      'document_portal_auditor'
  )
  AND Table_name IN (
      'Workflow',
      'WorkflowStatusTransition',
      'WorkflowTransitionRole',
      'vw_WorkflowTransitionMetadata'
  )

ORDER BY
    User,
    Table_name;


-- ============================================================
-- FAIL-CLOSED VALIDATION
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp__validate_workflow_security $$


CREATE PROCEDURE sp__validate_workflow_security()
BEGIN

    DECLARE v_count INT;


    -- ========================================================
    -- 1. APP must be able to execute the context-aware
    --    workflow metadata procedure.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.procs_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_app'
      AND Routine_name =
          'sp_get_allowed_workflow_transitions'
      AND Routine_type = 'PROCEDURE'
      AND FIND_IN_SET('Execute', Proc_priv) > 0;


    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app cannot execute sp_get_allowed_workflow_transitions.';
    END IF;


    -- ========================================================
    -- 2. APP must NOT have a routine-specific EXECUTE grant
    --    on sp_transition_workflow.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.procs_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_app'
      AND Routine_name = 'sp_transition_workflow'
      AND Routine_type = 'PROCEDURE'
      AND FIND_IN_SET('Execute', Proc_priv) > 0;


    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app may not directly execute sp_transition_workflow.';
    END IF;


    -- ========================================================
    -- 3. APP must NOT have a routine-specific EXECUTE grant
    --    on sp_advance_workflow.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.procs_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_app'
      AND Routine_name = 'sp_advance_workflow'
      AND Routine_type = 'PROCEDURE'
      AND FIND_IN_SET('Execute', Proc_priv) > 0;


    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app may not directly execute sp_advance_workflow.';
    END IF;


    -- ========================================================
    -- 4. APP must not have broad database-level EXECUTE.
    --
    -- Otherwise absence of a routine-specific grant would not
    -- actually protect the internal procedures.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.db

    WHERE Db = DATABASE()
      AND User = 'document_portal_app'
      AND Execute_priv = 'Y';


    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app has broad database-level EXECUTE privilege.';
    END IF;


    -- ========================================================
    -- 5. APP must not have global EXECUTE privilege.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.user

    WHERE User = 'document_portal_app'
      AND Execute_priv = 'Y';


    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app has global EXECUTE privilege.';
    END IF;


    -- ========================================================
    -- 6. APP must NOT have direct table-level UPDATE privilege
    --    on Workflow.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.tables_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_app'
      AND Table_name = 'Workflow'
      AND FIND_IN_SET('Update', Table_priv) > 0;


    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app has direct UPDATE privilege on Workflow.';
    END IF;


    -- ========================================================
    -- 7. APP must also not have database-wide UPDATE privilege.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.db

    WHERE Db = DATABASE()
      AND User = 'document_portal_app'
      AND Update_priv = 'Y';


    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app has database-wide UPDATE privilege.';
    END IF;


    -- ========================================================
    -- 8. APP must not have global UPDATE privilege.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.user

    WHERE User = 'document_portal_app'
      AND Update_priv = 'Y';


    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app has global UPDATE privilege.';
    END IF;


    -- ========================================================
    -- 9. APP must not modify WorkflowStatusTransition.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.tables_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_app'
      AND Table_name = 'WorkflowStatusTransition'
      AND (
             FIND_IN_SET('Insert', Table_priv) > 0
          OR FIND_IN_SET('Update', Table_priv) > 0
          OR FIND_IN_SET('Delete', Table_priv) > 0
      );


    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app may not modify WorkflowStatusTransition.';
    END IF;


    -- ========================================================
    -- 10. APP must not modify WorkflowTransitionRole.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.tables_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_app'
      AND Table_name = 'WorkflowTransitionRole'
      AND (
             FIND_IN_SET('Insert', Table_priv) > 0
          OR FIND_IN_SET('Update', Table_priv) > 0
          OR FIND_IN_SET('Delete', Table_priv) > 0
      );


    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app may not modify WorkflowTransitionRole.';
    END IF;


    -- ========================================================
    -- 11. APP must be able to SELECT the metadata view.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.tables_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_app'
      AND Table_name = 'vw_WorkflowTransitionMetadata'
      AND FIND_IN_SET('Select', Table_priv) > 0;


    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app cannot SELECT vw_WorkflowTransitionMetadata.';
    END IF;


    -- ========================================================
    -- 12. REPORTER must have read-only access to the metadata
    --     view.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.tables_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_reporter'
      AND Table_name = 'vw_WorkflowTransitionMetadata'
      AND FIND_IN_SET('Select', Table_priv) > 0;


    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_reporter cannot SELECT vw_WorkflowTransitionMetadata.';
    END IF;


    -- ========================================================
    -- 13. AUDITOR must have read-only access to the metadata
    --     view.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.tables_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_auditor'
      AND Table_name = 'vw_WorkflowTransitionMetadata'
      AND FIND_IN_SET('Select', Table_priv) > 0;


    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_auditor cannot SELECT vw_WorkflowTransitionMetadata.';
    END IF;


    -- ========================================================
    -- 14. ADMIN must have SELECT, INSERT, UPDATE on
    --     WorkflowStatusTransition.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.tables_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_admin'
      AND Table_name = 'WorkflowStatusTransition'

      AND FIND_IN_SET('Select', Table_priv) > 0
      AND FIND_IN_SET('Insert', Table_priv) > 0
      AND FIND_IN_SET('Update', Table_priv) > 0;


    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_admin lacks required WorkflowStatusTransition privileges.';
    END IF;


    -- ========================================================
    -- 15. ADMIN must NOT DELETE WorkflowStatusTransition rows.
    --
    --     We retire transition definitions with IsActive.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.tables_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_admin'
      AND Table_name = 'WorkflowStatusTransition'
      AND FIND_IN_SET('Delete', Table_priv) > 0;


    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: WorkflowStatusTransition must be retired with IsActive rather than DELETE.';
    END IF;


    -- ========================================================
    -- 16. ADMIN needs full entitlement-maintenance privileges
    --     on WorkflowTransitionRole.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.tables_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_admin'
      AND Table_name = 'WorkflowTransitionRole'

      AND FIND_IN_SET('Select', Table_priv) > 0
      AND FIND_IN_SET('Insert', Table_priv) > 0
      AND FIND_IN_SET('Update', Table_priv) > 0
      AND FIND_IN_SET('Delete', Table_priv) > 0;


    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_admin lacks required WorkflowTransitionRole privileges.';
    END IF;


    -- ========================================================
    -- 17. ADMIN must be able to execute the allowed-transition
    --     read procedure.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.procs_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_admin'
      AND Routine_name =
          'sp_get_allowed_workflow_transitions'
      AND Routine_type = 'PROCEDURE'
      AND FIND_IN_SET('Execute', Proc_priv) > 0;


    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_admin cannot execute sp_get_allowed_workflow_transitions.';
    END IF;


    -- ========================================================
    -- 18. ADMIN still must NOT directly execute
    --     sp_transition_workflow.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM mysql.procs_priv

    WHERE Db = DATABASE()
      AND User = 'document_portal_admin'
      AND Routine_name = 'sp_transition_workflow'
      AND Routine_type = 'PROCEDURE'
      AND FIND_IN_SET('Execute', Proc_priv) > 0;


    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_admin may not directly execute sp_transition_workflow.';
    END IF;


    SELECT
        'WORKFLOW SECURITY VALIDATION PASSED.'
        AS Result;

END $$


DELIMITER ;


CALL sp__validate_workflow_security();

DROP PROCEDURE sp__validate_workflow_security;