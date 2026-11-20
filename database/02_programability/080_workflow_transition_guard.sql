-- ============================================================
-- File: database/02_programability/080_workflow_transition_guard.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Protect Workflow lifecycle transitions at the table boundary.
--
-- Rules:
--   - Workflow status may remain unchanged during ordinary updates.
--   - Any actual status change must exist as an active row in
--     WorkflowStatusTransition.
--   - Terminal workflows may not transition to another state.
--
-- This trigger provides defense in depth. Authorization and
-- transition-specific business rules remain enforced by
-- sp_transition_workflow.
--
-- Existing trg_Workflow_TerminalCascade remains responsible for
-- cancelling unfinished child records after terminal transitions.
-- ============================================================

DELIMITER //

DROP TRIGGER IF EXISTS trg_Workflow_ProtectStatusTransition//

CREATE TRIGGER trg_Workflow_ProtectStatusTransition
BEFORE UPDATE ON Workflow
FOR EACH ROW
BEGIN
    DECLARE v_old_status_code VARCHAR(50) DEFAULT NULL;
    DECLARE v_new_status_code VARCHAR(50) DEFAULT NULL;

    DECLARE v_transition_count INT DEFAULT 0;


    -- --------------------------------------------------------
    -- Only inspect actual Workflow status changes.
    --
    -- Updates to other Workflow attributes should continue
    -- normally.
    -- --------------------------------------------------------

    IF NOT (OLD.WorkflowStatusID <=> NEW.WorkflowStatusID) THEN


        -- ----------------------------------------------------
        -- Resolve and validate the existing Workflow status.
        -- ----------------------------------------------------

        SELECT Code
        INTO v_old_status_code
        FROM ReferenceData
        WHERE ReferenceDataID = OLD.WorkflowStatusID
          AND DomainName = 'WORKFLOW_STATUS'
          AND IsActive = TRUE
        LIMIT 1;


        IF v_old_status_code IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Workflow transition rejected: existing workflow status is invalid.';
        END IF;


        -- ----------------------------------------------------
        -- Resolve and validate the requested Workflow status.
        -- ----------------------------------------------------

        SELECT Code
        INTO v_new_status_code
        FROM ReferenceData
        WHERE ReferenceDataID = NEW.WorkflowStatusID
          AND DomainName = 'WORKFLOW_STATUS'
          AND IsActive = TRUE
        LIMIT 1;


        IF v_new_status_code IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Workflow transition rejected: target workflow status is invalid.';
        END IF;


        -- ----------------------------------------------------
        -- Terminal states are immutable.
        --
        -- COMPLETED
        -- REJECTED
        -- CANCELLED
        -- EXPIRED
        --
        -- There should also be no outgoing transition metadata
        -- for these states, but this explicit rule produces a
        -- clearer error and protects the historical lifecycle.
        -- ----------------------------------------------------

        IF v_old_status_code IN (
            'COMPLETED',
            'REJECTED',
            'CANCELLED',
            'EXPIRED'
        ) THEN

            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Workflow transition rejected: terminal workflow status may not be changed.';

        END IF;


        -- ----------------------------------------------------
        -- Every state change must exist in active transition
        -- metadata.
        -- ----------------------------------------------------

        SELECT COUNT(*)
        INTO v_transition_count
        FROM WorkflowStatusTransition wt
        WHERE wt.FromStatusID = OLD.WorkflowStatusID
          AND wt.ToStatusID = NEW.WorkflowStatusID
          AND wt.IsActive = TRUE;


        IF v_transition_count = 0 THEN

            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Workflow transition rejected: transition is not defined in active workflow metadata.';

        END IF;


    END IF;

END//

DELIMITER ;