-- ============================================================
-- File:
-- database/05_validation/040_workflow_metadata_object_validation.sql
--
-- Purpose:
--   Validate the workflow-transition metadata objects added
--   for metadata-driven workflow enforcement and UI behavior.
--
-- Behavior:
--   Fail closed when a required object is missing.
-- ============================================================


SELECT '=== Workflow Metadata Object Validation ==='
    AS ValidationSection;


-- ------------------------------------------------------------
-- Human-readable object listing
-- ------------------------------------------------------------

SELECT '--- Tables ---' AS ObjectValidation;

SELECT expected.ObjectName,
       CASE
           WHEN actual.TABLE_NAME IS NULL THEN 'MISSING'
           ELSE 'PRESENT'
       END AS Status
FROM (
    SELECT 'WorkflowStatusTransition' AS ObjectName
    UNION ALL
    SELECT 'WorkflowTransitionRole'
) expected
LEFT JOIN information_schema.TABLES actual
    ON actual.TABLE_SCHEMA = DATABASE()
   AND actual.TABLE_NAME = expected.ObjectName
   AND actual.TABLE_TYPE = 'BASE TABLE'
ORDER BY expected.ObjectName;


SELECT '--- Views ---' AS ObjectValidation;

SELECT expected.ObjectName,
       CASE
           WHEN actual.TABLE_NAME IS NULL THEN 'MISSING'
           ELSE 'PRESENT'
       END AS Status
FROM (
    SELECT 'vw_WorkflowTransitionMetadata' AS ObjectName
) expected
LEFT JOIN information_schema.VIEWS actual
    ON actual.TABLE_SCHEMA = DATABASE()
   AND actual.TABLE_NAME = expected.ObjectName;


SELECT '--- Procedures ---' AS ObjectValidation;

SELECT expected.ObjectName,
       CASE
           WHEN actual.ROUTINE_NAME IS NULL THEN 'MISSING'
           ELSE 'PRESENT'
       END AS Status
FROM (
    SELECT 'sp_transition_workflow' AS ObjectName
    UNION ALL
    SELECT 'sp_get_allowed_workflow_transitions'
) expected
LEFT JOIN information_schema.ROUTINES actual
    ON actual.ROUTINE_SCHEMA = DATABASE()
   AND actual.ROUTINE_NAME = expected.ObjectName
   AND actual.ROUTINE_TYPE = 'PROCEDURE'
ORDER BY expected.ObjectName;


SELECT '--- Triggers ---' AS ObjectValidation;

SELECT expected.ObjectName,
       CASE
           WHEN actual.TRIGGER_NAME IS NULL THEN 'MISSING'
           ELSE 'PRESENT'
       END AS Status
FROM (
    SELECT 'trg_Workflow_ProtectStatusTransition' AS ObjectName
    UNION ALL
    SELECT 'trg_Workflow_TerminalCascade'
) expected
LEFT JOIN information_schema.TRIGGERS actual
    ON actual.TRIGGER_SCHEMA = DATABASE()
   AND actual.TRIGGER_NAME = expected.ObjectName
ORDER BY expected.ObjectName;


-- ------------------------------------------------------------
-- Fail-closed validation
-- ------------------------------------------------------------

DELIMITER $$

DROP PROCEDURE IF EXISTS sp__validate_workflow_metadata_objects $$

CREATE PROCEDURE sp__validate_workflow_metadata_objects()
BEGIN
    DECLARE v_count INT;


    -- ========================================================
    -- 1. Both metadata tables must exist.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_TYPE = 'BASE TABLE'
      AND TABLE_NAME IN (
          'WorkflowStatusTransition',
          'WorkflowTransitionRole'
      );

    IF v_count <> 2 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata object validation failed: required transition metadata tables are missing.';
    END IF;


    -- ========================================================
    -- 2. Workflow transition metadata view must exist.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.VIEWS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'vw_WorkflowTransitionMetadata';

    IF v_count <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata object validation failed: vw_WorkflowTransitionMetadata is missing.';
    END IF;


    -- ========================================================
    -- 3. Both new procedures must exist.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.ROUTINES
    WHERE ROUTINE_SCHEMA = DATABASE()
      AND ROUTINE_TYPE = 'PROCEDURE'
      AND ROUTINE_NAME IN (
          'sp_transition_workflow',
          'sp_get_allowed_workflow_transitions'
      );

    IF v_count <> 2 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata object validation failed: required workflow metadata procedures are missing.';
    END IF;


    -- ========================================================
    -- 4. Both workflow lifecycle triggers must exist.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.TRIGGERS
    WHERE TRIGGER_SCHEMA = DATABASE()
      AND TRIGGER_NAME IN (
          'trg_Workflow_ProtectStatusTransition',
          'trg_Workflow_TerminalCascade'
      );

    IF v_count <> 2 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata object validation failed: required workflow lifecycle triggers are missing.';
    END IF;


    -- ========================================================
    -- 5. Required UI metadata columns must exist.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'WorkflowStatusTransition'
      AND COLUMN_NAME IN (
          'ActionDisplayName',
          'RequiresReasonFlag',
          'ReasonLabel',
          'ConfirmationRequiredFlag',
          'DisplayOrder'
      );

    IF v_count <> 5 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata object validation failed: one or more workflow UI metadata columns are missing.';
    END IF;


    SELECT
        'WORKFLOW METADATA OBJECT VALIDATION PASSED.'
        AS Result;

END $$

DELIMITER ;


CALL sp__validate_workflow_metadata_objects();

DROP PROCEDURE sp__validate_workflow_metadata_objects;