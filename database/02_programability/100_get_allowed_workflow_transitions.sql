-- ============================================================
-- File:
-- database/02_programability/100_get_allowed_workflow_transitions.sql
--
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Return the workflow actions currently available to a specific
--   user for a specific Workflow.
--
-- This is a READ procedure only.
--
-- It combines:
--   - current Workflow state
--   - transition metadata
--   - role metadata
--   - document ownership
--   - assignment context
--   - expiration context
--
-- The GUI should render actions from this result rather than
-- hard-coding status/action rules.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_allowed_workflow_transitions//

CREATE PROCEDURE sp_get_allowed_workflow_transitions (
    IN p_workflow_id BIGINT UNSIGNED,
    IN p_user_id BIGINT UNSIGNED
)
BEGIN

    DECLARE v_workflow_status_id BIGINT UNSIGNED;
    DECLARE v_document_id BIGINT UNSIGNED;
    DECLARE v_owner_user_id BIGINT UNSIGNED;
    DECLARE v_expiration_datetime DATETIME;


    -- --------------------------------------------------------
    -- Validate Workflow and retrieve current context.
    -- --------------------------------------------------------

    SELECT
        w.WorkflowStatusID,
        w.DocumentID,
        d.OwnerUserID,
        w.ExpirationDateTime

    INTO
        v_workflow_status_id,
        v_document_id,
        v_owner_user_id,
        v_expiration_datetime

    FROM Workflow w

    JOIN Document d
        ON d.DocumentID = w.DocumentID

    WHERE w.WorkflowID = p_workflow_id;


    IF v_workflow_status_id IS NULL THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow does not exist.';

    END IF;


    -- --------------------------------------------------------
    -- Return currently available HUMAN actions.
    --
    -- System-only transitions with no matching human role are
    -- intentionally not shown as ordinary GUI actions.
    -- --------------------------------------------------------

    SELECT DISTINCT

        wt.WorkflowStatusTransitionID,

        wt.TransitionCode,

        from_status.Code
            AS CurrentStatusCode,

        from_status.DisplayName
            AS CurrentStatusDisplayName,

        to_status.Code
            AS TargetStatusCode,

        to_status.DisplayName
            AS TargetStatusDisplayName,

        wt.Description,

        r.RoleName
            AS AuthorizedRole,

        CASE
            WHEN wt.TransitionCode = 'CANCEL_WORKFLOW'
                THEN TRUE

            WHEN wt.TransitionCode = 'REJECT_WORKFLOW'
                THEN TRUE

            ELSE FALSE
        END
            AS RequiresReasonFlag

    FROM WorkflowStatusTransition wt

    JOIN ReferenceData from_status
        ON from_status.ReferenceDataID =
           wt.FromStatusID
       AND from_status.DomainName =
           'WORKFLOW_STATUS'

    JOIN ReferenceData to_status
        ON to_status.ReferenceDataID =
           wt.ToStatusID
       AND to_status.DomainName =
           'WORKFLOW_STATUS'

    JOIN WorkflowTransitionRole wtr
        ON wtr.WorkflowStatusTransitionID =
           wt.WorkflowStatusTransitionID
       AND wtr.AllowedFlag = TRUE

    JOIN Role r
        ON r.RoleID = wtr.RoleID
       AND r.ActiveStatus = TRUE

    JOIN UserRole ur
        ON ur.RoleID = r.RoleID
       AND ur.UserID = p_user_id

    WHERE wt.FromStatusID =
          v_workflow_status_id

      AND wt.IsActive = TRUE

      AND
      (
          -- --------------------------------------------------
          -- Workflow activation:
          -- user must own this Document.
          -- --------------------------------------------------

          (
              wt.TransitionCode =
                  'ACTIVATE_WORKFLOW'

              AND
              r.RoleName =
                  'Document Owner'

              AND
              p_user_id =
                  v_owner_user_id
          )


          OR


          -- --------------------------------------------------
          -- Workflow cancellation:
          --
          -- Document Owner:
          --     must own THIS document
          --
          -- System Administrator:
          --     may cancel according to current project rules.
          -- --------------------------------------------------

          (
              wt.TransitionCode =
                  'CANCEL_WORKFLOW'

              AND
              (
                  (
                      r.RoleName =
                          'Document Owner'

                      AND
                      p_user_id =
                          v_owner_user_id
                  )

                  OR

                  r.RoleName =
                      'System Administrator'
              )
          )


          OR


          -- --------------------------------------------------
          -- Rejection:
          --
          -- General Approver role is not enough.
          -- User must have an ACTIVE approval assignment in
          -- this specific Workflow.
          -- --------------------------------------------------

          (
              wt.TransitionCode =
                  'REJECT_WORKFLOW'

              AND
              r.RoleName =
                  'Approver'

              AND EXISTS
              (
                  SELECT 1

                  FROM WorkflowParticipant wp

                  JOIN WorkflowStep ws
                      ON ws.WorkflowStepID =
                         wp.WorkflowStepID

                  JOIN ReferenceData action_ref
                      ON action_ref.ReferenceDataID =
                         wp.AssignedActionID
                     AND action_ref.DomainName =
                         'ASSIGNED_ACTION'
                     AND action_ref.Code =
                         'APPROVAL'

                  JOIN ReferenceData participant_status
                      ON participant_status.ReferenceDataID =
                         wp.AssignmentStatusID
                     AND participant_status.DomainName =
                         'PARTICIPANT_STATUS'
                     AND participant_status.Code =
                         'ACTIVE'

                  JOIN ReferenceData step_status
                      ON step_status.ReferenceDataID =
                         ws.StepStatusID
                     AND step_status.DomainName =
                         'STEP_STATUS'
                     AND step_status.Code =
                         'ACTIVE'

                  WHERE ws.WorkflowID =
                        p_workflow_id

                    AND wp.UserID =
                        p_user_id

                    AND wp.RoleID =
                        r.RoleID
              )
          )


          OR


          -- --------------------------------------------------
          -- Administrative expiration.
          --
          -- Only show this action once expiration time has
          -- actually been reached.
          -- --------------------------------------------------

          (
              wt.TransitionCode =
                  'EXPIRE_WORKFLOW'

              AND
              r.RoleName =
                  'System Administrator'

              AND
              v_expiration_datetime IS NOT NULL

              AND
              v_expiration_datetime <=
                  CURRENT_TIMESTAMP
          )
      )

    ORDER BY
        wt.TransitionCode;

END//

DELIMITER ;