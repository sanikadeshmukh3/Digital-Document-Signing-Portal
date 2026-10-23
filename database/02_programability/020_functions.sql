-- ============================================================
-- File: database/02_programmability/020_functions.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Create reusable functions for workflow authorization and
--   completion-state validation.
--
-- Functions:
--   fn_user_has_role
--   fn_all_predecessors_complete
--   fn_step_required_work_complete
--   fn_workflow_required_work_complete
--
-- Notes:
--   - These functions are read-only.
--   - They do not modify workflow state.
--   - Stored procedures will use them during protected
--     transactions.
-- ============================================================

DELIMITER //


-- ============================================================
-- 1. fn_user_has_role
-- ============================================================
-- Purpose:
--   Determine whether a User currently holds a given Role.
--
-- Supports:
--   FR-05
--   FR-06
--   FR-12
--
-- Returns:
--   1 = role assignment exists and Role is active
--   0 = role assignment does not exist or Role is inactive
-- ============================================================

CREATE FUNCTION fn_user_has_role (
    p_user_id BIGINT UNSIGNED,
    p_role_id BIGINT UNSIGNED
)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_has_role BOOLEAN DEFAULT FALSE;

    SELECT EXISTS (
        SELECT 1
        FROM UserRole ur
        JOIN Role r
            ON r.RoleID = ur.RoleID
        WHERE ur.UserID = p_user_id
          AND ur.RoleID = p_role_id
          AND r.ActiveStatus = TRUE
    )
    INTO v_has_role;

    RETURN v_has_role;
END//


-- ============================================================
-- 2. fn_all_predecessors_complete
-- ============================================================
-- Purpose:
--   Determine whether all required predecessor sequence groups
--   have completed before a WorkflowStep may become actionable.
--
-- Supports:
--   FR-12
--   BR-08
--   sequential / parallel workflow rules
--
-- Important:
--   Multiple WorkflowSteps may share the same SequenceNumber.
--   Every required assignment in all lower sequence numbers
--   must be complete before this step can proceed.
--
-- Returns:
--   1 = all required predecessor work is complete
--   0 = at least one required predecessor assignment is not
--       complete
-- ============================================================

CREATE FUNCTION fn_all_predecessors_complete (
    p_workflow_step_id BIGINT UNSIGNED
)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_workflow_id BIGINT UNSIGNED;
    DECLARE v_sequence_number INT UNSIGNED;
    DECLARE v_incomplete_count INT DEFAULT 0;

    SELECT
        WorkflowID,
        SequenceNumber
    INTO
        v_workflow_id,
        v_sequence_number
    FROM WorkflowStep
    WHERE WorkflowStepID = p_workflow_step_id;

    IF v_workflow_id IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT COUNT(*)
    INTO v_incomplete_count
    FROM WorkflowStep ws
    JOIN WorkflowParticipant wp
        ON wp.WorkflowStepID = ws.WorkflowStepID
    JOIN ReferenceData participant_status
        ON participant_status.ReferenceDataID =
           wp.AssignmentStatusID
    WHERE ws.WorkflowID = v_workflow_id
      AND ws.SequenceNumber < v_sequence_number
      AND wp.RequiredFlag = TRUE
      AND NOT (
          participant_status.DomainName = 'PARTICIPANT_STATUS'
          AND participant_status.Code = 'COMPLETED'
      );

    RETURN v_incomplete_count = 0;
END//


-- ============================================================
-- 3. fn_step_required_work_complete
-- ============================================================
-- Purpose:
--   Determine whether every required WorkflowParticipant
--   assignment for one WorkflowStep has completed.
--
-- Supports:
--   FR-13
--   FR-14
--   BR-09
--
-- Returns:
--   1 = all required assignments are complete
--   0 = one or more required assignments remain incomplete
--
-- Note:
--   Optional assignments do not block progression.
-- ============================================================

CREATE FUNCTION fn_step_required_work_complete (
    p_workflow_step_id BIGINT UNSIGNED
)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_required_count INT DEFAULT 0;
    DECLARE v_incomplete_count INT DEFAULT 0;

    SELECT COUNT(*)
    INTO v_required_count
    FROM WorkflowParticipant
    WHERE WorkflowStepID = p_workflow_step_id
      AND RequiredFlag = TRUE;

    -- A workflow step with no required assignments should not
    -- automatically be treated as complete.
    IF v_required_count = 0 THEN
        RETURN FALSE;
    END IF;

    SELECT COUNT(*)
    INTO v_incomplete_count
    FROM WorkflowParticipant wp
    JOIN ReferenceData participant_status
        ON participant_status.ReferenceDataID =
           wp.AssignmentStatusID
    WHERE wp.WorkflowStepID = p_workflow_step_id
      AND wp.RequiredFlag = TRUE
      AND NOT (
          participant_status.DomainName = 'PARTICIPANT_STATUS'
          AND participant_status.Code = 'COMPLETED'
      );

    RETURN v_incomplete_count = 0;
END//


-- ============================================================
-- 4. fn_workflow_required_work_complete
-- ============================================================
-- Purpose:
--   Determine whether all required participant work across a
--   Workflow has completed.
--
-- Supports:
--   FR-14
--   BR-09
--
-- Returns:
--   1 = all required workflow assignments are complete
--   0 = at least one required assignment remains incomplete
--
-- This function does not change WorkflowStatus.
-- The workflow-completion procedure performs the transition.
-- ============================================================

CREATE FUNCTION fn_workflow_required_work_complete (
    p_workflow_id BIGINT UNSIGNED
)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_required_count INT DEFAULT 0;
    DECLARE v_incomplete_count INT DEFAULT 0;

    SELECT COUNT(*)
    INTO v_required_count
    FROM WorkflowStep ws
    JOIN WorkflowParticipant wp
        ON wp.WorkflowStepID = ws.WorkflowStepID
    WHERE ws.WorkflowID = p_workflow_id
      AND wp.RequiredFlag = TRUE;

    IF v_required_count = 0 THEN
        RETURN FALSE;
    END IF;

    SELECT COUNT(*)
    INTO v_incomplete_count
    FROM WorkflowStep ws
    JOIN WorkflowParticipant wp
        ON wp.WorkflowStepID = ws.WorkflowStepID
    JOIN ReferenceData participant_status
        ON participant_status.ReferenceDataID =
           wp.AssignmentStatusID
    WHERE ws.WorkflowID = p_workflow_id
      AND wp.RequiredFlag = TRUE
      AND NOT (
          participant_status.DomainName = 'PARTICIPANT_STATUS'
          AND participant_status.Code = 'COMPLETED'
      );

    RETURN v_incomplete_count = 0;
END//


DELIMITER ;