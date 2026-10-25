-- ============================================================
-- File: database/02_programmability/040_triggers.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Enforce database-level protection for immutable and
--   append-only historical records.
--
-- Triggers:
--   trg_DocumentVersion_PreventFinalizedUpdate
--   trg_DocumentVersion_PreventFinalizedDelete
--   trg_ApprovalDecision_PreventUpdate
--   trg_ApprovalDecision_PreventDelete
--   trg_Signature_PreventUpdate
--   trg_Signature_PreventDelete
--   trg_AuditLog_PreventUpdate
--   trg_AuditLog_PreventDelete
--
-- Notes:
--   Workflow progression and authorization logic belongs in
--   stored procedures rather than triggers.
-- ============================================================

DELIMITER //


-- ============================================================
-- 1. Prevent modification of finalized/locked DocumentVersion
-- ============================================================
-- Supports:
--   BR-12
--   RES-03
--
-- A DocumentVersion in LOCKED status is historical and may not
-- be modified through ordinary operations.
-- ============================================================

CREATE TRIGGER trg_DocumentVersion_PreventFinalizedUpdate
BEFORE UPDATE ON DocumentVersion
FOR EACH ROW
BEGIN
    DECLARE v_old_status_code VARCHAR(50);

    SELECT Code
    INTO v_old_status_code
    FROM ReferenceData
    WHERE ReferenceDataID = OLD.CurrentVersionStatusID
      AND DomainName = 'DOCUMENT_VERSION_STATUS';

    IF v_old_status_code = 'LOCKED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Locked DocumentVersion records may not be modified.';
    END IF;
END//


-- ============================================================
-- 2. Prevent deletion of finalized/locked DocumentVersion
-- ============================================================

CREATE TRIGGER trg_DocumentVersion_PreventFinalizedDelete
BEFORE DELETE ON DocumentVersion
FOR EACH ROW
BEGIN
    DECLARE v_status_code VARCHAR(50);

    SELECT Code
    INTO v_status_code
    FROM ReferenceData
    WHERE ReferenceDataID = OLD.CurrentVersionStatusID
      AND DomainName = 'DOCUMENT_VERSION_STATUS';

    IF v_status_code = 'LOCKED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Locked DocumentVersion records may not be deleted.';
    END IF;
END//


-- ============================================================
-- 3. Protect ApprovalDecision from UPDATE
-- ============================================================
-- Supports:
--   SEC-04
--   historical approval integrity
--
-- Approval decisions are append-only historical records.
-- Corrections must be represented through a separate controlled
-- correction/replacement process rather than editing the
-- original row.
-- ============================================================

CREATE TRIGGER trg_ApprovalDecision_PreventUpdate
BEFORE UPDATE ON ApprovalDecision
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'ApprovalDecision records are immutable and may not be updated.';
END//


-- ============================================================
-- 4. Protect ApprovalDecision from DELETE
-- ============================================================

CREATE TRIGGER trg_ApprovalDecision_PreventDelete
BEFORE DELETE ON ApprovalDecision
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'ApprovalDecision records are historical and may not be deleted.';
END//


-- ============================================================
-- 5. Protect Signature from UPDATE
-- ============================================================
-- Supports:
--   SEC-04
--   historical signature integrity
--
-- A recorded signature must remain tied to the exact
-- DocumentVersion originally signed.
-- ============================================================

CREATE TRIGGER trg_Signature_PreventUpdate
BEFORE UPDATE ON Signature
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Signature records are immutable and may not be updated.';
END//


-- ============================================================
-- 6. Protect Signature from DELETE
-- ============================================================

CREATE TRIGGER trg_Signature_PreventDelete
BEFORE DELETE ON Signature
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Signature records are historical and may not be deleted.';
END//


-- ============================================================
-- 7. Make AuditLog append-only
-- ============================================================
-- Supports:
--   FR-15
--   SEC-11
--   RES-06
--
-- Audit records may be inserted but may not be modified after
-- creation.
-- ============================================================

CREATE TRIGGER trg_AuditLog_PreventUpdate
BEFORE UPDATE ON AuditLog
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'AuditLog is append-only; existing audit records may not be updated.';
END//


-- ============================================================
-- 8. Prevent AuditLog deletion
-- ============================================================

CREATE TRIGGER trg_AuditLog_PreventDelete
BEFORE DELETE ON AuditLog
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'AuditLog records may not be deleted.';
END//

-- ============================================================
-- 9. Workflow Terminal Cascade
-- ============================================================

CREATE TRIGGER trg_Workflow_TerminalCascade
AFTER UPDATE ON Workflow
FOR EACH ROW
BEGIN
    DECLARE v_new_status_code VARCHAR(50);

    DECLARE v_pending_step_status_id BIGINT UNSIGNED;
    DECLARE v_active_step_status_id BIGINT UNSIGNED;
    DECLARE v_cancelled_step_status_id BIGINT UNSIGNED;

    DECLARE v_pending_participant_status_id BIGINT UNSIGNED;
    DECLARE v_active_participant_status_id BIGINT UNSIGNED;
    DECLARE v_cancelled_participant_status_id BIGINT UNSIGNED;


    -- Only do work when the WorkflowStatusID actually changes.
    IF NOT (OLD.WorkflowStatusID <=> NEW.WorkflowStatusID) THEN

        SELECT Code
        INTO v_new_status_code
        FROM ReferenceData
        WHERE ReferenceDataID = NEW.WorkflowStatusID
          AND DomainName = 'WORKFLOW_STATUS'
        LIMIT 1;


        -- Terminal workflow states.
        IF v_new_status_code IN (
            'CANCELLED',
            'EXPIRED',
            'REJECTED'
        ) THEN

            -- -----------------------------------------------
            -- Resolve step statuses.
            -- -----------------------------------------------

            SELECT ReferenceDataID
            INTO v_pending_step_status_id
            FROM ReferenceData
            WHERE DomainName = 'STEP_STATUS'
              AND Code = 'PENDING'
            LIMIT 1;


            SELECT ReferenceDataID
            INTO v_active_step_status_id
            FROM ReferenceData
            WHERE DomainName = 'STEP_STATUS'
              AND Code = 'ACTIVE'
            LIMIT 1;


            SELECT ReferenceDataID
            INTO v_cancelled_step_status_id
            FROM ReferenceData
            WHERE DomainName = 'STEP_STATUS'
              AND Code = 'CANCELLED'
            LIMIT 1;


            -- -----------------------------------------------
--
-- This provides database-level lifecycle enforcement even if a
-- terminal workflow transition occurs outside the normal
-- procedure path.
--
-- Historical COMPLETED / REJECTED / DECLINED records are not
-- modified.
-- ============================================================

DELIMITER $$

DROP TRIGGER IF EXISTS trg_Workflow_TerminalCascade $$

CREATE TRIGGER trg_Workflow_TerminalCascade
AFTER UPDATE ON Workflow
FOR EACH ROW
BEGIN
    DECLARE v_new_status_code VARCHAR(50);

    DECLARE v_pending_step_status_id BIGINT UNSIGNED;
    DECLARE v_active_step_status_id BIGINT UNSIGNED;
    DECLARE v_cancelled_step_status_id BIGINT UNSIGNED;

    DECLARE v_pending_participant_status_id BIGINT UNSIGNED;
    DECLARE v_active_participant_status_id BIGINT UNSIGNED;
    DECLARE v_cancelled_participant_status_id BIGINT UNSIGNED;


    -- Only do work when the WorkflowStatusID actually changes.
    IF NOT (OLD.WorkflowStatusID <=> NEW.WorkflowStatusID) THEN

        SELECT Code
        INTO v_new_status_code
        FROM ReferenceData
        WHERE ReferenceDataID = NEW.WorkflowStatusID
          AND DomainName = 'WORKFLOW_STATUS'
        LIMIT 1;


        -- Terminal workflow states.
        IF v_new_status_code IN (
            'CANCELLED',
            'EXPIRED',
            'REJECTED'
        ) THEN

            -- -----------------------------------------------
            -- Resolve step statuses.
            -- -----------------------------------------------

            SELECT ReferenceDataID
            INTO v_pending_step_status_id
            FROM ReferenceData
            WHERE DomainName = 'STEP_STATUS'
              AND Code = 'PENDING'
            LIMIT 1;


            SELECT ReferenceDataID
            INTO v_active_step_status_id
            FROM ReferenceData
            WHERE DomainName = 'STEP_STATUS'
              AND Code = 'ACTIVE'
            LIMIT 1;


            SELECT ReferenceDataID
            INTO v_cancelled_step_status_id
            FROM ReferenceData
            WHERE DomainName = 'STEP_STATUS'
              AND Code = 'CANCELLED'
            LIMIT 1;


            -- -----------------------------------------------
            -- Resolve participant statuses.
            -- -----------------------------------------------

            SELECT ReferenceDataID
            INTO v_pending_participant_status_id
            FROM ReferenceData
            WHERE DomainName = 'PARTICIPANT_STATUS'
              AND Code = 'PENDING'
            LIMIT 1;


            SELECT ReferenceDataID
            INTO v_active_participant_status_id
            FROM ReferenceData
            WHERE DomainName = 'PARTICIPANT_STATUS'
              AND Code = 'ACTIVE'
            LIMIT 1;


            SELECT ReferenceDataID
            INTO v_cancelled_participant_status_id
            FROM ReferenceData
            WHERE DomainName = 'PARTICIPANT_STATUS'
              AND Code = 'CANCELLED'
            LIMIT 1;


            -- -----------------------------------------------
            -- Cancel outstanding participant assignments.
            -- Completed/rejected/declined history is preserved.
            -- -----------------------------------------------

            UPDATE WorkflowParticipant wp
            JOIN WorkflowStep ws
              ON ws.WorkflowStepID = wp.WorkflowStepID
            SET
                wp.AssignmentStatusID =
                    v_cancelled_participant_status_id,
                wp.CompletionDateTime =
                    COALESCE(
                        wp.CompletionDateTime,
                        CURRENT_TIMESTAMP
                    )
            WHERE ws.WorkflowID = NEW.WorkflowID
              AND wp.AssignmentStatusID IN (
                  v_pending_participant_status_id,
                  v_active_participant_status_id
              );


            -- -----------------------------------------------
            -- Cancel outstanding steps.
            -- -----------------------------------------------

            UPDATE WorkflowStep
            SET
                StepStatusID = v_cancelled_step_status_id,
                CompletionDateTime =
                    COALESCE(
                        CompletionDateTime,
                        CURRENT_TIMESTAMP
                    )
            WHERE WorkflowID = NEW.WorkflowID
              AND StepStatusID IN (
                  v_pending_step_status_id,
                  v_active_step_status_id
              );

        END IF;

    END IF;

END $$

DELIMITER ;