-- ============================================================
-- File:
-- database/05_validation/070_workflow_security_validation.sql
--
-- Purpose:
--   Validate the least-privilege security boundary for the
--   metadata-driven workflow implementation.
--
-- Important:
--   This validates GRANTS themselves using
--   information_schema rather than attempting destructive
--   operations during the normal build.
-- ============================================================


SELECT '=== Workflow Security Validation ==='
    AS ValidationSection;


-- ------------------------------------------------------------
-- Human-readable routine grants
-- ------------------------------------------------------------

SELECT
    GRANTEE,
    ROUTINE_NAME,
    PRIVILEGE_TYPE

FROM information_schema.ROUTINE_PRIVILEGES

WHERE ROUTINE_SCHEMA = DATABASE()
  AND GRANTEE IN (
      '''document_portal_app''@''%''',
      '''document_portal_admin''@''%'''
  )

ORDER BY
    GRANTEE,
    ROUTINE_NAME,
    PRIVILEGE_TYPE;


-- ------------------------------------------------------------
-- Human-readable table/view grants
-- ------------------------------------------------------------

SELECT
    GRANTEE,
    TABLE_NAME,
    PRIVILEGE_TYPE

FROM information_schema.TABLE_PRIVILEGES

WHERE TABLE_SCHEMA = DATABASE()
  AND GRANTEE IN (
      '''document_portal_app''@''%''',
      '''document_portal_admin''@''%''',
      '''document_portal_reporter''@''%''',
      '''document_portal_auditor''@''%'''
  )
  AND TABLE_NAME IN (
      'Workflow',
      'WorkflowStatusTransition',
      'WorkflowTransitionRole',
      'vw_WorkflowTransitionMetadata'
  )

ORDER BY
    GRANTEE,
    TABLE_NAME,
    PRIVILEGE_TYPE;


DELIMITER $$

DROP PROCEDURE IF EXISTS sp__validate_workflow_security $$

CREATE PROCEDURE sp__validate_workflow_security()
BEGIN

    DECLARE v_count INT;


    -- ========================================================
    -- 1. Application must be able to call the context-aware
    --    workflow metadata read procedure.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.ROUTINE_PRIVILEGES

    WHERE ROUTINE_SCHEMA = DATABASE()
      AND ROUTINE_NAME =
          'sp_get_allowed_workflow_transitions'
      AND PRIVILEGE_TYPE = 'EXECUTE'
      AND GRANTEE = '''document_portal_app''@''%''';

    IF v_count <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app cannot execute sp_get_allowed_workflow_transitions.';
    END IF;


    -- ========================================================
    -- 2. Application must NOT directly execute the internal
    --    state-transition procedure.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.ROUTINE_PRIVILEGES

    WHERE ROUTINE_SCHEMA = DATABASE()
      AND ROUTINE_NAME = 'sp_transition_workflow'
      AND PRIVILEGE_TYPE = 'EXECUTE'
      AND GRANTEE = '''document_portal_app''@''%''';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app must not directly execute sp_transition_workflow.';
    END IF;


    -- ========================================================
    -- 3. Application must NOT directly execute the internal
    --    workflow-advance helper.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.ROUTINE_PRIVILEGES

    WHERE ROUTINE_SCHEMA = DATABASE()
      AND ROUTINE_NAME = 'sp_advance_workflow'
      AND PRIVILEGE_TYPE = 'EXECUTE'
      AND GRANTEE = '''document_portal_app''@''%''';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app must not directly execute sp_advance_workflow.';
    END IF;


    -- ========================================================
    -- 4. Application must NOT have direct UPDATE privilege on
    --    Workflow.
    --
    -- This prevents bypassing public procedures.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.TABLE_PRIVILEGES

    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'Workflow'
      AND PRIVILEGE_TYPE = 'UPDATE'
      AND GRANTEE = '''document_portal_app''@''%''';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app has direct UPDATE privilege on Workflow.';
    END IF;


    -- ========================================================
    -- 5. Application must NOT directly modify workflow
    --    transition metadata.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.TABLE_PRIVILEGES

    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME IN (
          'WorkflowStatusTransition',
          'WorkflowTransitionRole'
      )
      AND PRIVILEGE_TYPE IN (
          'INSERT',
          'UPDATE',
          'DELETE'
      )
      AND GRANTEE = '''document_portal_app''@''%''';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app may not modify workflow transition metadata.';
    END IF;


    -- ========================================================
    -- 6. Application must be able to read the approved
    --    metadata view.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.TABLE_PRIVILEGES

    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME =
          'vw_WorkflowTransitionMetadata'
      AND PRIVILEGE_TYPE = 'SELECT'
      AND GRANTEE = '''document_portal_app''@''%''';

    IF v_count <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_app cannot SELECT workflow transition metadata view.';
    END IF;


    -- ========================================================
    -- 7. Administrator must be able to maintain transition
    --    definitions.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.TABLE_PRIVILEGES

    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME =
          'WorkflowStatusTransition'
      AND PRIVILEGE_TYPE IN (
          'SELECT',
          'INSERT',
          'UPDATE'
      )
      AND GRANTEE =
          '''document_portal_admin''@''%''';

    IF v_count <> 3 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_admin lacks required WorkflowStatusTransition privileges.';
    END IF;


    -- ========================================================
    -- 8. Administrator should NOT physically delete transition
    --    definitions; use IsActive instead.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.TABLE_PRIVILEGES

    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME =
          'WorkflowStatusTransition'
      AND PRIVILEGE_TYPE = 'DELETE'
      AND GRANTEE =
          '''document_portal_admin''@''%''';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: WorkflowStatusTransition should be retired through IsActive rather than DELETE.';
    END IF;


    -- ========================================================
    -- 9. Administrator may maintain role-transition mappings.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.TABLE_PRIVILEGES

    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME =
          'WorkflowTransitionRole'
      AND PRIVILEGE_TYPE IN (
          'SELECT',
          'INSERT',
          'UPDATE',
          'DELETE'
      )
      AND GRANTEE =
          '''document_portal_admin''@''%''';

    IF v_count <> 4 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Security validation failed: document_portal_admin lacks required WorkflowTransitionRole privileges.';
    END IF;


    SELECT
        'WORKFLOW SECURITY VALIDATION PASSED.'
        AS Result;

END $$

DELIMITER ;


CALL sp__validate_workflow_security();

DROP PROCEDURE sp__validate_workflow_security;