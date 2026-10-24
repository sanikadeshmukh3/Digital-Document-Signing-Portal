-- ============================================================
-- File: database/06_demo_tests/010_exception_transaction_tests.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Demonstrate exception handling, authorization enforcement,
--   invalid-state rejection, and transactional rollback.
--
-- Important:
--   - These tests intentionally perform invalid operations.
--   - Expected exceptions are caught by temporary test procedures
--     so the entire test file can continue running.
--   - Tests verify both:
--         1. the invalid operation was rejected
--         2. database state remained consistent afterward
--   - This file is NOT part of the normal build manifest.
--
-- Database: MySQL 8.x
-- ============================================================


SELECT
    '============================================================'
        AS TestSection;

SELECT
    'EXCEPTION AND TRANSACTION TESTS'
        AS TestSection;

SELECT
    '============================================================'
        AS TestSection;



-- ============================================================
-- TEST 1
-- Unauthorized participant action
--
-- Requirement:
--   FR-12 / SEC-08
--
-- Scenario:
--   Scenario B contains an ACTIVE approval assignment belonging
--   to Daniel Cho.
--
--   Marcus Reed attempts to perform Daniel's approval.
--
-- Expected:
--   - procedure raises an exception
--   - no ApprovalDecision is created
--   - participant remains ACTIVE
--   - workflow remains ACTIVE
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp__test_unauthorized_approval $$

CREATE PROCEDURE sp__test_unauthorized_approval()
BEGIN
    DECLARE v_participant_id BIGINT UNSIGNED;
    DECLARE v_wrong_user_id BIGINT UNSIGNED;

    DECLARE v_before_decisions INT;
    DECLARE v_after_decisions INT;

    DECLARE v_assignment_status VARCHAR(50);
    DECLARE v_workflow_status VARCHAR(50);

    DECLARE v_error_caught BOOLEAN DEFAULT FALSE;


    -- --------------------------------------------------------
    -- Catch the exception that SHOULD be raised.
    -- --------------------------------------------------------

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            SET v_error_caught = TRUE;


        -- Find Daniel Cho's ACTIVE approval assignment
        -- in the active Master Services Agreement v2 workflow.

        SELECT wp.WorkflowParticipantID
        INTO v_participant_id
        FROM WorkflowParticipant wp
        JOIN WorkflowStep ws
            ON ws.WorkflowStepID = wp.WorkflowStepID
        JOIN Workflow w
            ON w.WorkflowID = ws.WorkflowID
        JOIN Document d
            ON d.DocumentID = w.DocumentID
        JOIN DocumentVersion dv
            ON dv.DocumentVersionID = w.DocumentVersionID
        JOIN `User` u
            ON u.UserID = wp.UserID
        JOIN ReferenceData action_ref
            ON action_ref.ReferenceDataID = wp.AssignedActionID
        JOIN ReferenceData participant_status
            ON participant_status.ReferenceDataID =
               wp.AssignmentStatusID
        WHERE d.Title = 'Master Services Agreement'
          AND dv.VersionNumber = 2
          AND u.Email = 'daniel.cho@initech.example'
          AND action_ref.Code = 'APPROVAL'
          AND participant_status.Code = 'ACTIVE'
        LIMIT 1;


        -- Marcus is NOT assigned to this approval.

        SELECT UserID
        INTO v_wrong_user_id
        FROM `User`
        WHERE Email = 'marcus.reed@initech.example';


        SELECT COUNT(*)
        INTO v_before_decisions
        FROM ApprovalDecision
        WHERE WorkflowParticipantID = v_participant_id;


        -- ----------------------------------------------------
        -- EXPECTED TO FAIL
        -- ----------------------------------------------------

        CALL sp_record_approval_decision(
            v_participant_id,
            v_wrong_user_id,
            'APPROVED',
            'Unauthorized approval attempt.',
            NULL
        );

    END;


    -- --------------------------------------------------------
    -- Verification after rejected transaction
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_after_decisions
    FROM ApprovalDecision
    WHERE WorkflowParticipantID = v_participant_id;


    SELECT status_ref.Code
    INTO v_assignment_status
    FROM WorkflowParticipant wp
    JOIN ReferenceData status_ref
        ON status_ref.ReferenceDataID =
           wp.AssignmentStatusID
    WHERE wp.WorkflowParticipantID = v_participant_id;


    SELECT wf_status.Code
    INTO v_workflow_status
    FROM WorkflowParticipant wp
    JOIN WorkflowStep ws
        ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w
        ON w.WorkflowID = ws.WorkflowID
    JOIN ReferenceData wf_status
        ON wf_status.ReferenceDataID =
           w.WorkflowStatusID
    WHERE wp.WorkflowParticipantID = v_participant_id;


    -- --------------------------------------------------------
    -- Assertions
    -- --------------------------------------------------------

    IF v_error_caught = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 1 FAILED: unauthorized approval was not rejected.';
    END IF;


    IF v_after_decisions <> v_before_decisions THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 1 FAILED: unauthorized approval created an ApprovalDecision.';
    END IF;


    IF v_assignment_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 1 FAILED: participant state changed after unauthorized approval.';
    END IF;


    IF v_workflow_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 1 FAILED: workflow state changed after unauthorized approval.';
    END IF;


    SELECT
        'PASS' AS Result,
        'TEST 1 - Unauthorized approval rejected with no state change'
            AS TestName,
        v_before_decisions AS DecisionsBefore,
        v_after_decisions AS DecisionsAfter,
        v_assignment_status AS AssignmentStatus,
        v_workflow_status AS WorkflowStatus;

END $$

DELIMITER ;


CALL sp__test_unauthorized_approval();

DROP PROCEDURE sp__test_unauthorized_approval;



-- ============================================================
-- TEST 2
-- Action attempted against CANCELLED workflow
--
-- Requirement:
--   FR-16 / SEC-09
--
-- Scenario:
--   Scenario E contains a CANCELLED workflow for
--   Data Processing Addendum v2.
--
--   Marcus Reed attempts to complete the cancelled REVIEW.
--
-- Expected:
--   - procedure rejects action
--   - participant remains CANCELLED
--   - workflow remains CANCELLED
--   - completion timestamp does not change
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp__test_cancelled_workflow_action $$

CREATE PROCEDURE sp__test_cancelled_workflow_action()
BEGIN
    DECLARE v_participant_id BIGINT UNSIGNED;
    DECLARE v_user_id BIGINT UNSIGNED;

    DECLARE v_before_completion DATETIME;
    DECLARE v_after_completion DATETIME;

    DECLARE v_assignment_status VARCHAR(50);
    DECLARE v_workflow_status VARCHAR(50);

    DECLARE v_error_caught BOOLEAN DEFAULT FALSE;


    SELECT wp.WorkflowParticipantID,
           wp.CompletionDateTime
    INTO v_participant_id,
         v_before_completion
    FROM WorkflowParticipant wp
    JOIN WorkflowStep ws
        ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w
        ON w.WorkflowID = ws.WorkflowID
    JOIN Document d
        ON d.DocumentID = w.DocumentID
    JOIN DocumentVersion dv
        ON dv.DocumentVersionID = w.DocumentVersionID
    JOIN `User` u
        ON u.UserID = wp.UserID
    JOIN ReferenceData action_ref
        ON action_ref.ReferenceDataID = wp.AssignedActionID
    JOIN ReferenceData wf_status
        ON wf_status.ReferenceDataID = w.WorkflowStatusID
    WHERE d.Title = 'Data Processing Addendum'
      AND dv.VersionNumber = 2
      AND u.Email = 'marcus.reed@initech.example'
      AND action_ref.Code = 'REVIEW'
      AND wf_status.Code = 'CANCELLED'
    LIMIT 1;


    SELECT UserID
    INTO v_user_id
    FROM `User`
    WHERE Email = 'marcus.reed@initech.example';


    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            SET v_error_caught = TRUE;


        -- ----------------------------------------------------
        -- EXPECTED TO FAIL
        -- ----------------------------------------------------

        CALL sp_complete_review_acknowledgement(
            v_participant_id,
            v_user_id
        );

    END;


    -- --------------------------------------------------------
    -- Verify nothing changed.
    -- --------------------------------------------------------

    SELECT
        wp.CompletionDateTime,
        participant_status.Code,
        workflow_status.Code
    INTO
        v_after_completion,
        v_assignment_status,
        v_workflow_status
    FROM WorkflowParticipant wp
    JOIN WorkflowStep ws
        ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w
        ON w.WorkflowID = ws.WorkflowID
    JOIN ReferenceData participant_status
        ON participant_status.ReferenceDataID =
           wp.AssignmentStatusID
    JOIN ReferenceData workflow_status
        ON workflow_status.ReferenceDataID =
           w.WorkflowStatusID
    WHERE wp.WorkflowParticipantID = v_participant_id;


    IF v_error_caught = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 2 FAILED: action on cancelled workflow was not rejected.';
    END IF;


    IF NOT (
        v_before_completion <=> v_after_completion
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 2 FAILED: completion timestamp changed after rejected action.';
    END IF;


    IF v_assignment_status <> 'CANCELLED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 2 FAILED: cancelled participant changed state.';
    END IF;


    IF v_workflow_status <> 'CANCELLED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 2 FAILED: cancelled workflow changed state.';
    END IF;


    SELECT
        'PASS' AS Result,
        'TEST 2 - Action on cancelled workflow rejected'
            AS TestName,
        v_assignment_status AS AssignmentStatus,
        v_workflow_status AS WorkflowStatus;

END $$

DELIMITER ;


CALL sp__test_cancelled_workflow_action();

DROP PROCEDURE sp__test_cancelled_workflow_action;



-- ============================================================
-- TEST 3
-- Rejection without required rejection reason
--
-- Requirement:
--   Business rule:
--   rejected approvals require RejectionReason.
--
-- Scenario:
--   Daniel Cho has an ACTIVE approval in Scenario B.
--
-- Expected:
--   - procedure rejects the transaction
--   - no ApprovalDecision is created
--   - assignment remains ACTIVE
--   - workflow remains ACTIVE
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp__test_missing_rejection_reason $$

CREATE PROCEDURE sp__test_missing_rejection_reason()
BEGIN
    DECLARE v_participant_id BIGINT UNSIGNED;
    DECLARE v_user_id BIGINT UNSIGNED;

    DECLARE v_before_decisions INT;
    DECLARE v_after_decisions INT;

    DECLARE v_assignment_status VARCHAR(50);
    DECLARE v_workflow_status VARCHAR(50);

    DECLARE v_error_caught BOOLEAN DEFAULT FALSE;


    SELECT wp.WorkflowParticipantID,
           wp.UserID
    INTO v_participant_id,
         v_user_id
    FROM WorkflowParticipant wp
    JOIN WorkflowStep ws
        ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w
        ON w.WorkflowID = ws.WorkflowID
    JOIN Document d
        ON d.DocumentID = w.DocumentID
    JOIN DocumentVersion dv
        ON dv.DocumentVersionID = w.DocumentVersionID
    JOIN `User` u
        ON u.UserID = wp.UserID
    JOIN ReferenceData action_ref
        ON action_ref.ReferenceDataID = wp.AssignedActionID
    JOIN ReferenceData participant_status
        ON participant_status.ReferenceDataID =
           wp.AssignmentStatusID
    WHERE d.Title = 'Master Services Agreement'
      AND dv.VersionNumber = 2
      AND u.Email = 'daniel.cho@initech.example'
      AND action_ref.Code = 'APPROVAL'
      AND participant_status.Code = 'ACTIVE'
    LIMIT 1;


    SELECT COUNT(*)
    INTO v_before_decisions
    FROM ApprovalDecision
    WHERE WorkflowParticipantID = v_participant_id;


    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            SET v_error_caught = TRUE;


        -- ----------------------------------------------------
        -- EXPECTED TO FAIL:
        -- REJECTED requires RejectionReason.
        -- ----------------------------------------------------

        CALL sp_record_approval_decision(
            v_participant_id,
            v_user_id,
            'REJECTED',
            'Approval rejected during exception test.',
            NULL
        );

    END;


    SELECT COUNT(*)
    INTO v_after_decisions
    FROM ApprovalDecision
    WHERE WorkflowParticipantID = v_participant_id;


    SELECT participant_status.Code,
           workflow_status.Code
    INTO v_assignment_status,
         v_workflow_status
    FROM WorkflowParticipant wp
    JOIN WorkflowStep ws
        ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w
        ON w.WorkflowID = ws.WorkflowID
    JOIN ReferenceData participant_status
        ON participant_status.ReferenceDataID =
           wp.AssignmentStatusID
    JOIN ReferenceData workflow_status
        ON workflow_status.ReferenceDataID =
           w.WorkflowStatusID
    WHERE wp.WorkflowParticipantID = v_participant_id;


    IF v_error_caught = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 3 FAILED: rejection without reason was accepted.';
    END IF;


    IF v_after_decisions <> v_before_decisions THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 3 FAILED: invalid rejection created an ApprovalDecision.';
    END IF;


    IF v_assignment_status <> 'ACTIVE'
       OR v_workflow_status <> 'ACTIVE' THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 3 FAILED: invalid rejection changed workflow state.';

    END IF;


    SELECT
        'PASS' AS Result,
        'TEST 3 - Missing rejection reason rejected'
            AS TestName,
        v_before_decisions AS DecisionsBefore,
        v_after_decisions AS DecisionsAfter,
        v_assignment_status AS AssignmentStatus,
        v_workflow_status AS WorkflowStatus;

END $$

DELIMITER ;


CALL sp__test_missing_rejection_reason();

DROP PROCEDURE sp__test_missing_rejection_reason;



-- ============================================================
-- TEST 4
-- Forced mid-transaction workflow-initiation failure.
--
-- Purpose:
--   Prove that sp_initiate_workflow rolls back work that has
--   already begun, rather than merely rejecting bad input before
--   any inserts occur.
--
-- Strategy:
--   1. Create a temporary TEST-ONLY trigger on WorkflowParticipant.
--   2. Initiate a workflow containing:
--        - Step 1: valid REVIEW participant
--        - Step 2: valid APPROVAL participant
--   3. The second participant uses a sentinel DueDateTime.
--   4. The temporary trigger throws an exception only for that row.
--   5. Verify that Workflow, WorkflowStep, WorkflowParticipant,
--      AuditLog, and DocumentVersion state all return to the
--      pre-transaction values.
-- ============================================================


-- Make sure an old test trigger was not accidentally left behind.
DROP TRIGGER IF EXISTS trg_Test_ForceWorkflowParticipantFailure;


DELIMITER $$

CREATE TRIGGER trg_Test_ForceWorkflowParticipantFailure
BEFORE INSERT ON WorkflowParticipant
FOR EACH ROW
BEGIN
    IF NEW.DueDateTime = '2099-12-31 23:59:59' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Forced TEST failure during second participant insert.';
    END IF;
END $$

DELIMITER ;


DELIMITER $$

DROP PROCEDURE IF EXISTS sp_test_04_mid_transaction_rollback $$

CREATE PROCEDURE sp_test_04_mid_transaction_rollback()
BEGIN
    DECLARE v_error_caught BOOLEAN DEFAULT FALSE;

    DECLARE v_document_id BIGINT UNSIGNED;
    DECLARE v_version_id BIGINT UNSIGNED;
    DECLARE v_owner_user_id BIGINT UNSIGNED;

    DECLARE v_reviewer_user_id BIGINT UNSIGNED;
    DECLARE v_reviewer_role_id BIGINT UNSIGNED;

    DECLARE v_approver_user_id BIGINT UNSIGNED;
    DECLARE v_approver_role_id BIGINT UNSIGNED;

    DECLARE v_workflows_before INT DEFAULT 0;
    DECLARE v_workflows_after INT DEFAULT 0;

    DECLARE v_steps_before INT DEFAULT 0;
    DECLARE v_steps_after INT DEFAULT 0;

    DECLARE v_participants_before INT DEFAULT 0;
    DECLARE v_participants_after INT DEFAULT 0;

    DECLARE v_audit_before INT DEFAULT 0;
    DECLARE v_audit_after INT DEFAULT 0;

    DECLARE v_version_status VARCHAR(50);
    DECLARE v_locked_datetime DATETIME;


    -- --------------------------------------------------------
    -- Identify the clean/current Employee Handbook version.
    -- --------------------------------------------------------

    SELECT d.DocumentID,
           dv.DocumentVersionID,
           d.OwnerUserID
    INTO v_document_id,
         v_version_id,
         v_owner_user_id
    FROM Document d
    JOIN DocumentVersion dv
      ON dv.DocumentID = d.DocumentID
    JOIN ReferenceData rds
      ON rds.ReferenceDataID = dv.CurrentVersionStatusID
    WHERE d.Title = 'Employee Handbook'
      AND dv.VersionNumber = 1
      AND rds.DomainName = 'DOCUMENT_VERSION_STATUS'
      AND rds.Code = 'CURRENT'
    LIMIT 1;


    -- Valid REVIEW participant.
    SELECT u.UserID,
           r.RoleID
    INTO v_reviewer_user_id,
         v_reviewer_role_id
    FROM `User` u
    JOIN UserRole ur
      ON ur.UserID = u.UserID
    JOIN Role r
      ON r.RoleID = ur.RoleID
    WHERE u.Email = 'marcus.reed@initech.example'
      AND r.RoleName = 'Reviewer'
    LIMIT 1;


    -- Valid APPROVAL participant.
    SELECT u.UserID,
           r.RoleID
    INTO v_approver_user_id,
         v_approver_role_id
    FROM `User` u
    JOIN UserRole ur
      ON ur.UserID = u.UserID
    JOIN Role r
      ON r.RoleID = ur.RoleID
    WHERE u.Email = 'daniel.cho@initech.example'
      AND r.RoleName = 'Approver'
    LIMIT 1;


    -- --------------------------------------------------------
    -- Capture pre-transaction state.
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_workflows_before
    FROM Workflow
    WHERE DocumentID = v_document_id;


    SELECT COUNT(*)
    INTO v_steps_before
    FROM WorkflowStep ws
    JOIN Workflow w
      ON w.WorkflowID = ws.WorkflowID
    WHERE w.DocumentID = v_document_id;


    SELECT COUNT(*)
    INTO v_participants_before
    FROM WorkflowParticipant wp
    JOIN WorkflowStep ws
      ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w
      ON w.WorkflowID = ws.WorkflowID
    WHERE w.DocumentID = v_document_id;


    SELECT COUNT(*)
    INTO v_audit_before
    FROM AuditLog;


    -- --------------------------------------------------------
    -- Attempt the transaction.
    --
    -- Step 1 is completely valid.
    -- Step 2 is also logically valid, but its sentinel due date
    -- causes the TEST trigger to raise an exception during INSERT.
    -- --------------------------------------------------------

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            SET v_error_caught = TRUE;

        CALL sp_initiate_workflow(
            v_owner_user_id,
            v_document_id,
            v_version_id,
            'FULL_REVIEW_APPROVAL_SIGNATURE',
            '2099-12-31 22:00:00',

            JSON_ARRAY(

                -- Step 1: VALID and should be inserted first.
                JSON_OBJECT(
                    'sequence_number', 1,
                    'step_type', 'REVIEW',
                    'due_date', '2099-12-30 17:00:00',
                    'participants',
                    JSON_ARRAY(
                        JSON_OBJECT(
                            'user_id', v_reviewer_user_id,
                            'role_id', v_reviewer_role_id,
                            'action', 'REVIEW',
                            'required', TRUE
                        )
                    )
                ),

                -- Step 2: VALID business data, but the special
                -- DueDateTime activates the test-only trigger.
                JSON_OBJECT(
                    'sequence_number', 2,
                    'step_type', 'APPROVAL',
                    'due_date', '2099-12-31 23:59:59',
                    'participants',
                    JSON_ARRAY(
                        JSON_OBJECT(
                            'user_id', v_approver_user_id,
                            'role_id', v_approver_role_id,
                            'action', 'APPROVAL',
                            'required', TRUE
                        )
                    )
                )
            )
        );
    END;


    -- --------------------------------------------------------
    -- Capture post-failure state.
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_workflows_after
    FROM Workflow
    WHERE DocumentID = v_document_id;


    SELECT COUNT(*)
    INTO v_steps_after
    FROM WorkflowStep ws
    JOIN Workflow w
      ON w.WorkflowID = ws.WorkflowID
    WHERE w.DocumentID = v_document_id;


    SELECT COUNT(*)
    INTO v_participants_after
    FROM WorkflowParticipant wp
    JOIN WorkflowStep ws
      ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w
      ON w.WorkflowID = ws.WorkflowID
    WHERE w.DocumentID = v_document_id;


    SELECT COUNT(*)
    INTO v_audit_after
    FROM AuditLog;


    SELECT rds.Code,
           dv.LockedDateTime
    INTO v_version_status,
         v_locked_datetime
    FROM DocumentVersion dv
    JOIN ReferenceData rds
      ON rds.ReferenceDataID = dv.CurrentVersionStatusID
    WHERE dv.DocumentVersionID = v_version_id;


    -- --------------------------------------------------------
    -- Assertions
    -- --------------------------------------------------------

    IF v_error_caught = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: forced transaction error was not raised.';
    END IF;


    IF v_workflows_before <> v_workflows_after THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: partial Workflow row remained after rollback.';
    END IF;


    IF v_steps_before <> v_steps_after THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: partial WorkflowStep rows remained after rollback.';
    END IF;


    IF v_participants_before <> v_participants_after THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: partial WorkflowParticipant rows remained after rollback.';
    END IF;


    IF v_audit_before <> v_audit_after THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: AuditLog changed despite transaction rollback.';
    END IF;


    IF v_version_status <> 'CURRENT'
       OR v_locked_datetime IS NOT NULL THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: document version lock state was not rolled back.';
    END IF;


    SELECT
        'PASS' AS Result,
        'TEST 4 - Forced mid-transaction workflow initiation rolled back completely'
            AS TestName,
        v_workflows_before AS WorkflowsBefore,
        v_workflows_after AS WorkflowsAfter,
        v_steps_before AS StepsBefore,
        v_steps_after AS StepsAfter,
        v_participants_before AS ParticipantsBefore,
        v_participants_after AS ParticipantsAfter,
        v_audit_before AS AuditRowsBefore,
        v_audit_after AS AuditRowsAfter,
        v_version_status AS VersionStatus,
        v_locked_datetime AS LockedDateTime;

END $$

DELIMITER ;


CALL sp_test_04_mid_transaction_rollback();

DROP PROCEDURE sp_test_04_mid_transaction_rollback;

-- Remove the test-only failure mechanism immediately afterward.
DROP TRIGGER trg_Test_ForceWorkflowParticipantFailure;

-- ============================================================
-- TEST 5
-- Direct UNIQUE constraint enforcement.
--
-- Proves that duplicate workflow participant assignments are
-- rejected at the physical schema level.
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_test_05_duplicate_participant_constraint $$

CREATE PROCEDURE sp_test_05_duplicate_participant_constraint()
BEGIN
    DECLARE v_error_caught BOOLEAN DEFAULT FALSE;

    DECLARE v_participant_id BIGINT UNSIGNED;

    DECLARE v_step_id BIGINT UNSIGNED;
    DECLARE v_user_id BIGINT UNSIGNED;
    DECLARE v_role_id BIGINT UNSIGNED;
    DECLARE v_action_id BIGINT UNSIGNED;

    DECLARE v_status_id BIGINT UNSIGNED;
    DECLARE v_required BOOLEAN;
    DECLARE v_activation DATETIME;
    DECLARE v_completion DATETIME;
    DECLARE v_due DATETIME;

    DECLARE v_count_before INT DEFAULT 0;
    DECLARE v_count_after INT DEFAULT 0;


    -- Use an existing participant as the source for the
    -- intentionally duplicated assignment.
    SELECT
        WorkflowParticipantID,
        WorkflowStepID,
        UserID,
        RoleID,
        AssignedActionID,
        AssignmentStatusID,
        RequiredFlag,
        ActivationDateTime,
        CompletionDateTime,
        DueDateTime
    INTO
        v_participant_id,
        v_step_id,
        v_user_id,
        v_role_id,
        v_action_id,
        v_status_id,
        v_required,
        v_activation,
        v_completion,
        v_due
    FROM WorkflowParticipant
    ORDER BY WorkflowParticipantID
    LIMIT 1;


    SELECT COUNT(*)
    INTO v_count_before
    FROM WorkflowParticipant
    WHERE WorkflowStepID = v_step_id
      AND UserID = v_user_id
      AND AssignedActionID = v_action_id;


    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            SET v_error_caught = TRUE;

        INSERT INTO WorkflowParticipant
        (
            WorkflowStepID,
            UserID,
            RoleID,
            AssignedActionID,
            AssignmentStatusID,
            RequiredFlag,
            ActivationDateTime,
            CompletionDateTime,
            DueDateTime
        )
        VALUES
        (
            v_step_id,
            v_user_id,
            v_role_id,
            v_action_id,
            v_status_id,
            v_required,
            v_activation,
            v_completion,
            v_due
        );
    END;


    SELECT COUNT(*)
    INTO v_count_after
    FROM WorkflowParticipant
    WHERE WorkflowStepID = v_step_id
      AND UserID = v_user_id
      AND AssignedActionID = v_action_id;


    IF v_error_caught = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 5 FAILED: duplicate assignment was not rejected.';
    END IF;


    IF v_count_before <> v_count_after THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 5 FAILED: duplicate assignment changed row count.';
    END IF;


    SELECT
        'PASS' AS Result,
        'TEST 5 - UNIQUE constraint rejected duplicate WorkflowParticipant'
            AS TestName,
        v_participant_id AS ExistingParticipantID,
        v_count_before AS RowsBefore,
        v_count_after AS RowsAfter;

END $$

DELIMITER ;


CALL sp_test_05_duplicate_participant_constraint();

DROP PROCEDURE sp_test_05_duplicate_participant_constraint;

-- ============================================================
-- TEST 6
-- AuditLog append-only / immutability enforcement.
--
-- Proves that an existing audit record cannot be silently
-- changed or deleted.
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_test_06_audit_immutability $$

CREATE PROCEDURE sp_test_06_audit_immutability()
BEGIN
    DECLARE v_update_error BOOLEAN DEFAULT FALSE;
    DECLARE v_delete_error BOOLEAN DEFAULT FALSE;

    DECLARE v_audit_id BIGINT UNSIGNED;
    DECLARE v_event_before VARCHAR(255);
    DECLARE v_event_after VARCHAR(255);

    DECLARE v_count_before INT DEFAULT 0;
    DECLARE v_count_after INT DEFAULT 0;


    SELECT AuditLogID,
           EventType
    INTO v_audit_id,
         v_event_before
    FROM AuditLog
    ORDER BY AuditLogID
    LIMIT 1;


    SELECT COUNT(*)
    INTO v_count_before
    FROM AuditLog
    WHERE AuditLogID = v_audit_id;


    -- --------------------------------------------------------
    -- Attempt prohibited UPDATE.
    -- --------------------------------------------------------

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            SET v_update_error = TRUE;

        UPDATE AuditLog
        SET EventType = 'TEST_TAMPER_ATTEMPT'
        WHERE AuditLogID = v_audit_id;
    END;


    -- --------------------------------------------------------
    -- Attempt prohibited DELETE.
    -- --------------------------------------------------------

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            SET v_delete_error = TRUE;

        DELETE FROM AuditLog
        WHERE AuditLogID = v_audit_id;
    END;


    -- --------------------------------------------------------
    -- Verify original record survived unchanged.
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_count_after
    FROM AuditLog
    WHERE AuditLogID = v_audit_id;


    SELECT EventType
    INTO v_event_after
    FROM AuditLog
    WHERE AuditLogID = v_audit_id;


    IF v_update_error = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 6 FAILED: AuditLog UPDATE was not blocked.';
    END IF;


    IF v_delete_error = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 6 FAILED: AuditLog DELETE was not blocked.';
    END IF;


    IF v_count_before <> 1
       OR v_count_after <> 1 THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 6 FAILED: AuditLog row was deleted or duplicated.';
    END IF;


    IF NOT (v_event_before <=> v_event_after) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 6 FAILED: AuditLog content changed.';
    END IF;


    SELECT
        'PASS' AS Result,
        'TEST 6 - AuditLog update and delete blocked'
            AS TestName,
        v_audit_id AS AuditLogID,
        v_event_before AS EventBefore,
        v_event_after AS EventAfter,
        v_count_before AS RowsBefore,
        v_count_after AS RowsAfter;

END $$

DELIMITER ;


CALL sp_test_06_audit_immutability();

DROP PROCEDURE sp_test_06_audit_immutability;

-- ============================================================
-- TEST 7
-- Finalized / LOCKED DocumentVersion immutability.
--
-- Proves that a locked historical version cannot be changed
-- or deleted.
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_test_07_locked_version_immutability $$

CREATE PROCEDURE sp_test_07_locked_version_immutability()
BEGIN
    DECLARE v_update_error BOOLEAN DEFAULT FALSE;
    DECLARE v_delete_error BOOLEAN DEFAULT FALSE;

    DECLARE v_document_id BIGINT UNSIGNED;
    DECLARE v_version_id BIGINT UNSIGNED;

    DECLARE v_effective_before VARCHAR(255);
    DECLARE v_effective_after VARCHAR(255);

    DECLARE v_status_before VARCHAR(50);
    DECLARE v_status_after VARCHAR(50);

    DECLARE v_count_before INT DEFAULT 0;
    DECLARE v_count_after INT DEFAULT 0;


    SELECT
        d.DocumentID,
        dv.DocumentVersionID,
        dv.EffectiveInformation,
        rd.Code
    INTO
        v_document_id,
        v_version_id,
        v_effective_before,
        v_status_before
    FROM Document d
    JOIN DocumentVersion dv
      ON dv.DocumentID = d.DocumentID
    JOIN ReferenceData rd
      ON rd.ReferenceDataID = dv.CurrentVersionStatusID
    WHERE d.Title = 'Master Services Agreement'
      AND dv.VersionNumber = 1
      AND rd.DomainName = 'DOCUMENT_VERSION_STATUS'
      AND rd.Code = 'LOCKED'
    LIMIT 1;


    SELECT COUNT(*)
    INTO v_count_before
    FROM DocumentVersion
    WHERE DocumentVersionID = v_version_id;


    -- --------------------------------------------------------
    -- Attempt prohibited UPDATE.
    -- --------------------------------------------------------

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            SET v_update_error = TRUE;

        UPDATE DocumentVersion
        SET EffectiveInformation =
            'TEST - unauthorized modification of locked version'
        WHERE DocumentVersionID = v_version_id;
    END;


    -- --------------------------------------------------------
    -- Attempt prohibited DELETE.
    -- --------------------------------------------------------

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            SET v_delete_error = TRUE;

        DELETE FROM DocumentVersion
        WHERE DocumentVersionID = v_version_id;
    END;


    -- --------------------------------------------------------
    -- Verify historical version survived unchanged.
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_count_after
    FROM DocumentVersion
    WHERE DocumentVersionID = v_version_id;


    SELECT
        dv.EffectiveInformation,
        rd.Code
    INTO
        v_effective_after,
        v_status_after
    FROM DocumentVersion dv
    JOIN ReferenceData rd
      ON rd.ReferenceDataID = dv.CurrentVersionStatusID
    WHERE dv.DocumentVersionID = v_version_id;


    IF v_update_error = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 7 FAILED: LOCKED DocumentVersion UPDATE was not blocked.';
    END IF;


    IF v_delete_error = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 7 FAILED: LOCKED DocumentVersion DELETE was not blocked.';
    END IF;


    IF v_count_before <> 1
       OR v_count_after <> 1 THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 7 FAILED: locked DocumentVersion was deleted.';
    END IF;


    IF NOT (v_effective_before <=> v_effective_after) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 7 FAILED: locked DocumentVersion content changed.';
    END IF;


    IF v_status_before <> 'LOCKED'
       OR v_status_after <> 'LOCKED' THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 7 FAILED: finalized version status changed.';
    END IF;


    SELECT
        'PASS' AS Result,
        'TEST 7 - LOCKED DocumentVersion update and delete blocked'
            AS TestName,
        v_document_id AS DocumentID,
        v_version_id AS DocumentVersionID,
        v_status_before AS StatusBefore,
        v_status_after AS StatusAfter,
        v_count_before AS RowsBefore,
        v_count_after AS RowsAfter;

END $$

DELIMITER ;


CALL sp_test_07_locked_version_immutability();

DROP PROCEDURE sp_test_07_locked_version_immutability;

-- ============================================================
-- TEST 8
-- Final summary
-- ============================================================

SELECT
    '============================================================'
        AS TestSection;

SELECT
    'ALL EXCEPTION / TRANSACTION TESTS PASSED'
        AS Result;

SELECT
    '============================================================'
        AS TestSection;