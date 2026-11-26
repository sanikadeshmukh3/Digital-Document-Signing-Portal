-- ============================================================
-- File:
-- database/05_validation/050_workflow_metadata_data_validation.sql
--
-- Purpose:
--   Validate the CONTENT and invariants of the workflow
--   transition metadata.
--
-- Database: MySQL 8.x
-- ============================================================


SELECT '=== Workflow Metadata Data Validation ==='
    AS ValidationSection;


-- ------------------------------------------------------------
-- Human-readable metadata output
-- ------------------------------------------------------------

SELECT
    TransitionCode,
    FromStatusCode,
    ToStatusCode,
    ActionDisplayName,
    RequiresReasonFlag,
    ReasonLabel,
    ConfirmationRequiredFlag,
    DisplayOrder,
    RoleName,
    SystemAllowedFlag,
    AllowedFlag
FROM vw_WorkflowTransitionMetadata
ORDER BY
    DisplayOrder,
    TransitionCode,
    RoleName;


DELIMITER $$

DROP PROCEDURE IF EXISTS sp__validate_workflow_metadata_data $$

CREATE PROCEDURE sp__validate_workflow_metadata_data()
BEGIN
    DECLARE v_count INT;


    -- ========================================================
    -- 1. Exactly five required lifecycle transitions must exist
    --    and be active.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM WorkflowStatusTransition
    WHERE IsActive = TRUE
      AND TransitionCode IN (
          'ACTIVATE_WORKFLOW',
          'COMPLETE_WORKFLOW',
          'REJECT_WORKFLOW',
          'CANCEL_WORKFLOW',
          'EXPIRE_WORKFLOW'
      );

    IF v_count <> 5 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata validation failed: all five required active workflow transitions are not present.';
    END IF;


    -- ========================================================
    -- 2. Verify the exact lifecycle edges.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM WorkflowStatusTransition wt

    JOIN ReferenceData from_status
        ON from_status.ReferenceDataID = wt.FromStatusID

    JOIN ReferenceData to_status
        ON to_status.ReferenceDataID = wt.ToStatusID

    WHERE wt.IsActive = TRUE
      AND (
             (
                 wt.TransitionCode = 'ACTIVATE_WORKFLOW'
                 AND from_status.Code = 'DRAFT'
                 AND to_status.Code = 'ACTIVE'
             )

          OR (
                 wt.TransitionCode = 'COMPLETE_WORKFLOW'
                 AND from_status.Code = 'ACTIVE'
                 AND to_status.Code = 'COMPLETED'
             )

          OR (
                 wt.TransitionCode = 'REJECT_WORKFLOW'
                 AND from_status.Code = 'ACTIVE'
                 AND to_status.Code = 'REJECTED'
             )

          OR (
                 wt.TransitionCode = 'CANCEL_WORKFLOW'
                 AND from_status.Code = 'ACTIVE'
                 AND to_status.Code = 'CANCELLED'
             )

          OR (
                 wt.TransitionCode = 'EXPIRE_WORKFLOW'
                 AND from_status.Code = 'ACTIVE'
                 AND to_status.Code = 'EXPIRED'
             )
      );

    IF v_count <> 5 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata validation failed: one or more required lifecycle edges are incorrect.';
    END IF;


    -- ========================================================
    -- 3. Both FromStatus and ToStatus MUST belong to the
    --    WORKFLOW_STATUS reference domain.
    --
    --    This matters because the FK alone only proves that the
    --    ReferenceData row exists; it does not prove its domain.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM WorkflowStatusTransition wt

    JOIN ReferenceData from_status
        ON from_status.ReferenceDataID = wt.FromStatusID

    JOIN ReferenceData to_status
        ON to_status.ReferenceDataID = wt.ToStatusID

    WHERE from_status.DomainName <> 'WORKFLOW_STATUS'
       OR to_status.DomainName <> 'WORKFLOW_STATUS';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata validation failed: transition status references must belong to WORKFLOW_STATUS.';
    END IF;


    -- ========================================================
    -- 4. UI display metadata must be usable.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM WorkflowStatusTransition
    WHERE IsActive = TRUE
      AND (
             ActionDisplayName IS NULL
          OR TRIM(ActionDisplayName) = ''
          OR DisplayOrder < 0
      );

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata validation failed: active transition has invalid UI display metadata.';
    END IF;


    -- ========================================================
    -- 5. A transition requiring a reason must have a reason
    --    label for the GUI.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM WorkflowStatusTransition
    WHERE IsActive = TRUE
      AND RequiresReasonFlag = TRUE
      AND (
             ReasonLabel IS NULL
          OR TRIM(ReasonLabel) = ''
      );

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata validation failed: a reason-required transition has no ReasonLabel.';
    END IF;


    -- ========================================================
    -- 6. Expected role authorization mappings.
    --
    -- ACTIVATE -> Document Owner
    -- REJECT   -> Approver
    -- CANCEL   -> Document Owner
    -- CANCEL   -> System Administrator
    -- EXPIRE   -> System Administrator
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count

    FROM WorkflowTransitionRole wtr

    JOIN WorkflowStatusTransition wt
        ON wt.WorkflowStatusTransitionID =
           wtr.WorkflowStatusTransitionID

    JOIN Role r
        ON r.RoleID = wtr.RoleID

    WHERE wtr.AllowedFlag = TRUE
      AND (
             (
                 wt.TransitionCode = 'ACTIVATE_WORKFLOW'
                 AND r.RoleName = 'Document Owner'
             )

          OR (
                 wt.TransitionCode = 'REJECT_WORKFLOW'
                 AND r.RoleName = 'Approver'
             )

          OR (
                 wt.TransitionCode = 'CANCEL_WORKFLOW'
                 AND r.RoleName = 'Document Owner'
             )

          OR (
                 wt.TransitionCode = 'CANCEL_WORKFLOW'
                 AND r.RoleName = 'System Administrator'
             )

          OR (
                 wt.TransitionCode = 'EXPIRE_WORKFLOW'
                 AND r.RoleName = 'System Administrator'
             )
      );

    IF v_count <> 5 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata validation failed: required transition-role mappings are incomplete.';
    END IF;


    -- ========================================================
    -- 7. COMPLETE and EXPIRE are the intended system-capable
    --    transitions.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM WorkflowStatusTransition
    WHERE IsActive = TRUE
      AND SystemAllowedFlag = TRUE
      AND TransitionCode IN (
          'COMPLETE_WORKFLOW',
          'EXPIRE_WORKFLOW'
      );

    IF v_count <> 2 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata validation failed: COMPLETE/EXPIRE system transition flags are incorrect.';
    END IF;


    -- Make sure no unexpected transition is system-enabled.
    SELECT COUNT(*)
    INTO v_count
    FROM WorkflowStatusTransition
    WHERE IsActive = TRUE
      AND SystemAllowedFlag = TRUE
      AND TransitionCode NOT IN (
          'COMPLETE_WORKFLOW',
          'EXPIRE_WORKFLOW'
      );

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata validation failed: an unexpected transition is marked system-allowed.';
    END IF;


    -- ========================================================
    -- 8. Terminal states must not have outgoing active edges.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM WorkflowStatusTransition wt

    JOIN ReferenceData from_status
        ON from_status.ReferenceDataID = wt.FromStatusID

    WHERE wt.IsActive = TRUE
      AND from_status.Code IN (
          'COMPLETED',
          'REJECTED',
          'CANCELLED',
          'EXPIRED'
      );

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata validation failed: a terminal workflow status has an active outgoing transition.';
    END IF;


    -- ========================================================
    -- 9. No same-state transitions.
    --    The CHECK constraint should already enforce this, but
    --    validation makes it visible in build evidence.
    -- ========================================================

    SELECT COUNT(*)
    INTO v_count
    FROM WorkflowStatusTransition
    WHERE FromStatusID = ToStatusID;

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata validation failed: a same-state workflow transition exists.';
    END IF;


    SELECT
        'WORKFLOW METADATA DATA VALIDATION PASSED.'
        AS Result;

END $$

DELIMITER ;


CALL sp__validate_workflow_metadata_data();

DROP PROCEDURE sp__validate_workflow_metadata_data;