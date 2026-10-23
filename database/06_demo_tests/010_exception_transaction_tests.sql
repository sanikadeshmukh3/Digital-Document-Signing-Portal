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
-- Multi-table transaction rollback
--
-- Requirement:
--   TX-01 / resiliency and recovery
--
-- Scenario:
--   Attempt to initiate a workflow for the CURRENT
--   Employee Handbook version.
--
--   The workflow configuration intentionally assigns
--   Marcus Reed to an APPROVAL action using the Approver role.
--
--   Marcus does NOT hold the Approver role.
--
-- Expected:
--   sp_initiate_workflow begins its transaction but eventually
--   rejects the invalid participant.
--
--   ROLLBACK must leave:
--      - no new Workflow
--      - no new WorkflowStep
--      - no new WorkflowParticipant
--      - no new AuditLog
--      - DocumentVersion still CURRENT
--      - LockedDateTime still NULL
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp__test_workflow_initiation_rollback $$

CREATE PROCEDURE sp__test_workflow_initiation_rollback()
BEGIN
    DECLARE v_document_id BIGINT UNSIGNED;
    DECLARE v_version_id BIGINT UNSIGNED;
    DECLARE v_owner_id BIGINT UNSIGNED;
    DECLARE v_bad_user_id BIGINT UNSIGNED;
    DECLARE v_approver_role_id BIGINT UNSIGNED;

    DECLARE v_workflows_before INT;
    DECLARE v_workflows_after INT;

    DECLARE v_steps_before INT;
    DECLARE v_steps_after INT;

    DECLARE v_participants_before INT;
    DECLARE v_participants_after INT;

    DECLARE v_audit_before INT;
    DECLARE v_audit_after INT;

    DECLARE v_version_status VARCHAR(50);
    DECLARE v_locked_datetime DATETIME;

    DECLARE v_error_caught BOOLEAN DEFAULT FALSE;


    -- --------------------------------------------------------
    -- Resolve test records.
    -- --------------------------------------------------------

    SELECT DocumentID, OwnerUserID
    INTO v_document_id, v_owner_id
    FROM Document
    WHERE Title = 'Employee Handbook';


    SELECT DocumentVersionID
    INTO v_version_id
    FROM DocumentVersion
    WHERE DocumentID = v_document_id
      AND VersionNumber = 1;


    SELECT UserID
    INTO v_bad_user_id
    FROM `User`
    WHERE Email = 'marcus.reed@initech.example';


    SELECT RoleID
    INTO v_approver_role_id
    FROM Role
    WHERE RoleName = 'Approver';


    -- --------------------------------------------------------
    -- Capture BEFORE state.
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
    -- Perform invalid multi-table transaction.
    -- --------------------------------------------------------

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            SET v_error_caught = TRUE;


        CALL sp_initiate_workflow(
            v_owner_id,
            v_document_id,
            v_version_id,
            'APPROVAL',
            '2026-12-31 17:00:00',

            JSON_ARRAY(
                JSON_OBJECT(
                    'sequence_number', 1,
                    'step_type', 'APPROVAL',
                    'due_date', '2026-12-15 17:00:00',

                    'participants',
                    JSON_ARRAY(
                        JSON_OBJECT(
                            'user_id', v_bad_user_id,
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
    -- Capture AFTER state.
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


    SELECT version_status.Code,
           dv.LockedDateTime
    INTO v_version_status,
         v_locked_datetime
    FROM DocumentVersion dv
    JOIN ReferenceData version_status
        ON version_status.ReferenceDataID =
           dv.CurrentVersionStatusID
    WHERE dv.DocumentVersionID = v_version_id;


    -- --------------------------------------------------------
    -- Assertions
    -- --------------------------------------------------------

    IF v_error_caught = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: invalid workflow initiation was not rejected.';
    END IF;


    IF v_workflows_after <> v_workflows_before THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: rollback left a Workflow row behind.';
    END IF;


    IF v_steps_after <> v_steps_before THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: rollback left a WorkflowStep row behind.';
    END IF;


    IF v_participants_after <> v_participants_before THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: rollback left a WorkflowParticipant row behind.';
    END IF;


    IF v_audit_after <> v_audit_before THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: rollback left an AuditLog row behind.';
    END IF;


    IF v_version_status <> 'CURRENT' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: DocumentVersion was not restored to CURRENT.';
    END IF;


    IF v_locked_datetime IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 4 FAILED: DocumentVersion retained a LockedDateTime after rollback.';
    END IF;


    SELECT
        'PASS' AS Result,
        'TEST 4 - Failed workflow initiation rolled back completely'
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


CALL sp__test_workflow_initiation_rollback();

DROP PROCEDURE sp__test_workflow_initiation_rollback;



-- ============================================================
-- TEST 5
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