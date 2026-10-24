-- ============================================================
-- File: database/02_programmability/030_procedures.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Implement protected, transactional business operations.
--
-- Core procedures:
--   sp_advance_workflow
--   sp_initiate_workflow
--   sp_complete_review_acknowledgement
--   sp_record_approval_decision
--   sp_record_signature
--   sp_cancel_workflow
--
-- All externally invoked state-changing procedures:
--   - validate authorization
--   - validate current workflow state
--   - use transactions
--   - roll back on failure
--   - create audit records
-- ============================================================

DELIMITER //


-- ============================================================
-- 1. sp_advance_workflow
-- ============================================================
-- INTERNAL HELPER PROCEDURE
--
-- Purpose:
--   Reevaluate workflow progression after a participant action.
--
-- Performs:
--   1. Completes eligible active steps.
--   2. Activates the next sequence group when appropriate.
--   3. Activates participant assignments in that group.
--   4. Completes the Workflow when all required work is done.
--
-- IMPORTANT:
--   This procedure does NOT start or commit a transaction.
--   It is intended to execute inside the calling procedure's
--   transaction.
-- ============================================================

CREATE PROCEDURE sp_advance_workflow (
    IN p_workflow_id BIGINT UNSIGNED
)
BEGIN
    DECLARE v_step_active_id BIGINT UNSIGNED;
    DECLARE v_step_pending_id BIGINT UNSIGNED;
    DECLARE v_step_completed_id BIGINT UNSIGNED;

    DECLARE v_participant_active_id BIGINT UNSIGNED;
    DECLARE v_participant_pending_id BIGINT UNSIGNED;

    DECLARE v_workflow_active_id BIGINT UNSIGNED;
    DECLARE v_workflow_completed_id BIGINT UNSIGNED;

    DECLARE v_active_step_count INT DEFAULT 0;
    DECLARE v_next_sequence INT UNSIGNED DEFAULT NULL;


    -- --------------------------------------------------------
    -- Retrieve required status identifiers.
    -- --------------------------------------------------------

    SELECT ReferenceDataID
    INTO v_step_active_id
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'ACTIVE'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_step_pending_id
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'PENDING'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_step_completed_id
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'COMPLETED'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_participant_active_id
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'ACTIVE'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_participant_pending_id
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'PENDING'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_workflow_active_id
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_STATUS'
      AND Code = 'ACTIVE'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_workflow_completed_id
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_STATUS'
      AND Code = 'COMPLETED'
      AND IsActive = TRUE;


    -- --------------------------------------------------------
    -- Complete active steps whose required assignments
    -- have all completed.
    -- --------------------------------------------------------

    UPDATE WorkflowStep
    SET
        StepStatusID = v_step_completed_id,
        CompletionDateTime = CURRENT_TIMESTAMP
    WHERE WorkflowID = p_workflow_id
      AND StepStatusID = v_step_active_id
      AND fn_step_required_work_complete(WorkflowStepID) = TRUE;


    -- --------------------------------------------------------
    -- Determine whether any active steps remain.
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_active_step_count
    FROM WorkflowStep
    WHERE WorkflowID = p_workflow_id
      AND StepStatusID = v_step_active_id;


    -- --------------------------------------------------------
    -- Only advance when the current parallel sequence group
    -- has completely finished.
    -- --------------------------------------------------------

    IF v_active_step_count = 0 THEN

        -- If all required workflow work is complete,
        -- complete the workflow.

        IF fn_workflow_required_work_complete(p_workflow_id) = TRUE THEN

            UPDATE Workflow
            SET
                WorkflowStatusID = v_workflow_completed_id,
                CompletionDateTime = CURRENT_TIMESTAMP
            WHERE WorkflowID = p_workflow_id
              AND WorkflowStatusID = v_workflow_active_id;

        ELSE

            -- Find the next eligible sequence.

            SELECT MIN(SequenceNumber)
            INTO v_next_sequence
            FROM WorkflowStep
            WHERE WorkflowID = p_workflow_id
              AND StepStatusID = v_step_pending_id;


            IF v_next_sequence IS NOT NULL THEN

                -- Activate all parallel steps having the same
                -- SequenceNumber.

                UPDATE WorkflowStep
                SET
                    StepStatusID = v_step_active_id,
                    ActivationDateTime = CURRENT_TIMESTAMP
                WHERE WorkflowID = p_workflow_id
                  AND SequenceNumber = v_next_sequence
                  AND StepStatusID = v_step_pending_id
                  AND fn_all_predecessors_complete(
                        WorkflowStepID
                      ) = TRUE;


                -- Activate assignments belonging to the newly
                -- activated steps.

                UPDATE WorkflowParticipant wp
                JOIN WorkflowStep ws
                    ON ws.WorkflowStepID =
                       wp.WorkflowStepID
                SET
                    wp.AssignmentStatusID =
                        v_participant_active_id,

                    wp.ActivationDateTime =
                        CURRENT_TIMESTAMP

                WHERE ws.WorkflowID = p_workflow_id
                  AND ws.SequenceNumber = v_next_sequence
                  AND ws.StepStatusID = v_step_active_id
                  AND wp.AssignmentStatusID =
                      v_participant_pending_id;

            END IF;

        END IF;

    END IF;

END//


-- ============================================================
-- 2. sp_initiate_workflow
-- ============================================================
-- Supports:
--   FR-03
--   FR-06
--   FR-07
--   FR-12
--   FR-13
--   FR-15
--   TX-01
--
-- Creates:
--   Workflow
--   WorkflowSteps
--   WorkflowParticipants
--
-- as one atomic transaction.
--
-- p_steps JSON format:
--
-- [
--   {
--     "sequence_number": 1,
--     "step_type": "REVIEW",
--     "due_date": "2026-11-01 17:00:00",
--     "participants": [
--       {
--         "user_id": 2,
--         "role_id": 2,
--         "action": "REVIEW",
--         "required": 1
--       }
--     ]
--   },
--   {
--     "sequence_number": 2,
--     "step_type": "APPROVAL",
--     "participants": [
--       {
--         "user_id": 3,
--         "role_id": 3,
--         "action": "APPROVAL",
--         "required": 1
--       }
--     ]
--   }
-- ]
-- ============================================================

CREATE PROCEDURE sp_initiate_workflow (
    IN p_owner_user_id BIGINT UNSIGNED,
    IN p_document_id BIGINT UNSIGNED,
    IN p_document_version_id BIGINT UNSIGNED,
    IN p_workflow_purpose_code VARCHAR(50),
    IN p_expiration_datetime DATETIME,
    IN p_steps JSON
)
BEGIN
    DECLARE v_workflow_id BIGINT UNSIGNED;
    DECLARE v_workflow_purpose_id BIGINT UNSIGNED;

    DECLARE v_workflow_draft_id BIGINT UNSIGNED;
    DECLARE v_workflow_active_id BIGINT UNSIGNED;

    DECLARE v_step_pending_id BIGINT UNSIGNED;
    DECLARE v_step_active_id BIGINT UNSIGNED;

    DECLARE v_participant_pending_id BIGINT UNSIGNED;
    DECLARE v_participant_active_id BIGINT UNSIGNED;

    DECLARE v_version_current_id BIGINT UNSIGNED;
    DECLARE v_version_locked_id BIGINT UNSIGNED;

    DECLARE v_step_count INT DEFAULT 0;
    DECLARE v_step_index INT DEFAULT 0;

    DECLARE v_participant_count INT DEFAULT 0;
    DECLARE v_participant_index INT DEFAULT 0;

    DECLARE v_sequence_number INT UNSIGNED;
    DECLARE v_step_type_code VARCHAR(50);
    DECLARE v_step_type_id BIGINT UNSIGNED;
    DECLARE v_step_due_date DATETIME;
    DECLARE v_workflow_step_id BIGINT UNSIGNED;

    DECLARE v_user_id BIGINT UNSIGNED;
    DECLARE v_role_id BIGINT UNSIGNED;
    DECLARE v_action_code VARCHAR(50);
    DECLARE v_action_id BIGINT UNSIGNED;
    DECLARE v_required_flag BOOLEAN;

    DECLARE v_valid_count INT DEFAULT 0;
    DECLARE v_min_sequence INT UNSIGNED;

    DECLARE v_transaction_reference VARCHAR(100);


    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;


    START TRANSACTION;

    SET v_transaction_reference = UUID();


    -- --------------------------------------------------------
    -- Validate owner.
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_valid_count
    FROM Document d
    JOIN UserRole ur
        ON ur.UserID = d.OwnerUserID
    JOIN Role r
        ON r.RoleID = ur.RoleID
    WHERE d.DocumentID = p_document_id
      AND d.OwnerUserID = p_owner_user_id
      AND r.RoleName = 'Document Owner'
      AND r.ActiveStatus = TRUE;

    IF v_valid_count = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'User is not authorized to initiate a workflow for this document.';
    END IF;


    -- --------------------------------------------------------
    -- Retrieve version-status values.
    -- --------------------------------------------------------

    SELECT ReferenceDataID
    INTO v_version_current_id
    FROM ReferenceData
    WHERE DomainName = 'DOCUMENT_VERSION_STATUS'
      AND Code = 'CURRENT'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_version_locked_id
    FROM ReferenceData
    WHERE DomainName = 'DOCUMENT_VERSION_STATUS'
      AND Code = 'LOCKED'
      AND IsActive = TRUE;


    -- --------------------------------------------------------
    -- Validate selected DocumentVersion.
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_valid_count
    FROM DocumentVersion
    WHERE DocumentVersionID = p_document_version_id
      AND DocumentID = p_document_id
      AND CurrentVersionStatusID =
          v_version_current_id;

    IF v_valid_count = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Document version is invalid or is not the current version.';
    END IF;


    -- --------------------------------------------------------
    -- Validate workflow configuration.
    -- --------------------------------------------------------

    IF p_steps IS NULL
       OR JSON_VALID(p_steps) = FALSE
       OR JSON_LENGTH(p_steps) = 0 THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow must contain at least one workflow step.';

    END IF;


    -- --------------------------------------------------------
    -- Retrieve Workflow reference IDs.
    -- --------------------------------------------------------

    SELECT ReferenceDataID
    INTO v_workflow_purpose_id
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_PURPOSE_TYPE'
      AND Code = p_workflow_purpose_code
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_workflow_draft_id
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_STATUS'
      AND Code = 'DRAFT'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_workflow_active_id
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_STATUS'
      AND Code = 'ACTIVE'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_step_pending_id
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'PENDING'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_step_active_id
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'ACTIVE'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_participant_pending_id
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'PENDING'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_participant_active_id
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'ACTIVE'
      AND IsActive = TRUE;


    -- --------------------------------------------------------
    -- Create Workflow in Draft state.
    -- --------------------------------------------------------

    INSERT INTO Workflow (
        DocumentID,
        DocumentVersionID,
        InitiatorUserID,
        WorkflowPurposeTypeID,
        WorkflowStatusID,
        ExpirationDateTime
    )
    VALUES (
        p_document_id,
        p_document_version_id,
        p_owner_user_id,
        v_workflow_purpose_id,
        v_workflow_draft_id,
        p_expiration_datetime
    );

    SET v_workflow_id = LAST_INSERT_ID();


    -- --------------------------------------------------------
    -- Create WorkflowSteps and WorkflowParticipants.
    -- --------------------------------------------------------

    SET v_step_count = JSON_LENGTH(p_steps);
    SET v_step_index = 0;


    WHILE v_step_index < v_step_count DO

        SET v_sequence_number =
            CAST(
                JSON_UNQUOTE(
                    JSON_EXTRACT(
                        p_steps,
                        CONCAT(
                            '$[',
                            v_step_index,
                            '].sequence_number'
                        )
                    )
                ) AS UNSIGNED
            );


        SET v_step_type_code =
            JSON_UNQUOTE(
                JSON_EXTRACT(
                    p_steps,
                    CONCAT(
                        '$[',
                        v_step_index,
                        '].step_type'
                    )
                )
            );


        SET v_step_due_date =
            NULLIF(
                JSON_UNQUOTE(
                    JSON_EXTRACT(
                        p_steps,
                        CONCAT(
                            '$[',
                            v_step_index,
                            '].due_date'
                        )
                    )
                ),
                'null'
            );


        IF v_sequence_number IS NULL
           OR v_sequence_number = 0 THEN

            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'SequenceNumber must be greater than zero.';

        END IF;


        SELECT ReferenceDataID
        INTO v_step_type_id
        FROM ReferenceData
        WHERE DomainName = 'STEP_TYPE'
          AND Code = v_step_type_code
          AND IsActive = TRUE;


        INSERT INTO WorkflowStep (
            WorkflowID,
            SequenceNumber,
            StepTypeID,
            RequiredPolicy,
            StepStatusID,
            DueDateTime
        )
        VALUES (
            v_workflow_id,
            v_sequence_number,
            v_step_type_id,
            'ALL_REQUIRED',
            v_step_pending_id,
            v_step_due_date
        );

        SET v_workflow_step_id = LAST_INSERT_ID();


        -- ----------------------------------------------------
        -- Participants for this step.
        -- ----------------------------------------------------

        SET v_participant_count =
            JSON_LENGTH(
                JSON_EXTRACT(
                    p_steps,
                    CONCAT(
                        '$[',
                        v_step_index,
                        '].participants'
                    )
                )
            );


        IF v_participant_count IS NULL
           OR v_participant_count = 0 THEN

            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Every workflow step must contain at least one participant.';

        END IF;


        SET v_participant_index = 0;


        WHILE v_participant_index <
              v_participant_count DO

            SET v_user_id =
                CAST(
                    JSON_UNQUOTE(
                        JSON_EXTRACT(
                            p_steps,
                            CONCAT(
                                '$[',
                                v_step_index,
                                '].participants[',
                                v_participant_index,
                                '].user_id'
                            )
                        )
                    ) AS UNSIGNED
                );


            SET v_role_id =
                CAST(
                    JSON_UNQUOTE(
                        JSON_EXTRACT(
                            p_steps,
                            CONCAT(
                                '$[',
                                v_step_index,
                                '].participants[',
                                v_participant_index,
                                '].role_id'
                            )
                        )
                    ) AS UNSIGNED
                );


            SET v_action_code =
                JSON_UNQUOTE(
                    JSON_EXTRACT(
                        p_steps,
                        CONCAT(
                            '$[',
                            v_step_index,
                            '].participants[',
                            v_participant_index,
                            '].action'
                        )
                    )
                );


            SET v_required_flag =
                CAST(
                    JSON_UNQUOTE(
                        JSON_EXTRACT(
                            p_steps,
                            CONCAT(
                                '$[',
                                v_step_index,
                                '].participants[',
                                v_participant_index,
                                '].required'
                            )
                        )
                    ) AS UNSIGNED
                );


            -- Action must correspond to StepType.

            IF v_action_code <> v_step_type_code THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT =
                        'Participant action must match WorkflowStep type.';
            END IF;


            -- Validate that user holds the role required
            -- for the action.

            SELECT COUNT(*)
            INTO v_valid_count
            FROM UserRole ur
            JOIN Role r
                ON r.RoleID = ur.RoleID
            WHERE ur.UserID = v_user_id
              AND ur.RoleID = v_role_id
              AND r.ActiveStatus = TRUE
              AND (
                    (
                        v_action_code IN (
                            'REVIEW',
                            'ACKNOWLEDGEMENT'
                        )
                        AND r.RoleName = 'Reviewer'
                    )
                    OR
                    (
                        v_action_code = 'APPROVAL'
                        AND r.RoleName = 'Approver'
                    )
                    OR
                    (
                        v_action_code = 'SIGNATURE'
                        AND r.RoleName = 'Signer'
                    )
              );


            IF v_valid_count = 0 THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT =
                        'Participant does not hold the required role for this action.';
            END IF;


            SELECT ReferenceDataID
            INTO v_action_id
            FROM ReferenceData
            WHERE DomainName = 'ASSIGNED_ACTION'
              AND Code = v_action_code
              AND IsActive = TRUE;


            INSERT INTO WorkflowParticipant (
                WorkflowStepID,
                UserID,
                RoleID,
                AssignedActionID,
                AssignmentStatusID,
                RequiredFlag,
                DueDateTime
            )
            VALUES (
                v_workflow_step_id,
                v_user_id,
                v_role_id,
                v_action_id,
                v_participant_pending_id,
                v_required_flag,
                v_step_due_date
            );


            SET v_participant_index =
                v_participant_index + 1;

        END WHILE;


        SET v_step_index = v_step_index + 1;

    END WHILE;


    -- --------------------------------------------------------
    -- Activate Workflow.
    -- --------------------------------------------------------

    UPDATE Workflow
    SET
        WorkflowStatusID = v_workflow_active_id,
        StartDateTime = CURRENT_TIMESTAMP
    WHERE WorkflowID = v_workflow_id;


    -- --------------------------------------------------------
    -- Lock exact DocumentVersion.
    -- --------------------------------------------------------

    UPDATE DocumentVersion
    SET
        CurrentVersionStatusID = v_version_locked_id,
        LockedDateTime = CURRENT_TIMESTAMP
    WHERE DocumentVersionID = p_document_version_id;


    -- --------------------------------------------------------
    -- Activate first sequence group.
    -- --------------------------------------------------------

    SELECT MIN(SequenceNumber)
    INTO v_min_sequence
    FROM WorkflowStep
    WHERE WorkflowID = v_workflow_id;


    UPDATE WorkflowStep
    SET
        StepStatusID = v_step_active_id,
        ActivationDateTime = CURRENT_TIMESTAMP
    WHERE WorkflowID = v_workflow_id
      AND SequenceNumber = v_min_sequence;


    UPDATE WorkflowParticipant wp
    JOIN WorkflowStep ws
        ON ws.WorkflowStepID = wp.WorkflowStepID
    SET
        wp.AssignmentStatusID =
            v_participant_active_id,

        wp.ActivationDateTime =
            CURRENT_TIMESTAMP

    WHERE ws.WorkflowID = v_workflow_id
      AND ws.SequenceNumber = v_min_sequence;


    -- --------------------------------------------------------
    -- Audit successful initiation.
    -- --------------------------------------------------------

    INSERT INTO AuditLog (
        ActorUserID,
        EventType,
        AffectedRecordType,
        AffectedRecordID,
        TransactionReference,
        NewValueContext,
        ChangeReason
    )
    VALUES (
        p_owner_user_id,
        'WORKFLOW_INITIATED',
        'Workflow',
        v_workflow_id,
        v_transaction_reference,
        CONCAT(
            'Workflow activated for DocumentVersionID=',
            p_document_version_id
        ),
        'Document Owner initiated workflow'
    );


    COMMIT;


    -- Return created workflow identifier.
    SELECT v_workflow_id AS WorkflowID;

END//


-- ============================================================
-- 3. sp_complete_review_acknowledgement
-- ============================================================
-- Supports:
--   FR-09
--   FR-12
--   FR-13
--   FR-14
--   FR-15
--
-- Completes REVIEW or ACKNOWLEDGEMENT assignments.
-- ============================================================

CREATE PROCEDURE sp_complete_review_acknowledgement (
    IN p_workflow_participant_id BIGINT UNSIGNED,
    IN p_current_user_id BIGINT UNSIGNED
)
BEGIN
    DECLARE v_assigned_user_id BIGINT UNSIGNED;
    DECLARE v_role_id BIGINT UNSIGNED;
    DECLARE v_workflow_step_id BIGINT UNSIGNED;
    DECLARE v_workflow_id BIGINT UNSIGNED;

    DECLARE v_action_code VARCHAR(50);
    DECLARE v_assignment_status VARCHAR(50);
    DECLARE v_step_status VARCHAR(50);
    DECLARE v_workflow_status VARCHAR(50);

    DECLARE v_completed_status_id BIGINT UNSIGNED;

    DECLARE v_transaction_reference VARCHAR(100);


    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;


    START TRANSACTION;

    SET v_transaction_reference = UUID();


    -- Lock assignment during validation/completion.

    SELECT
        wp.UserID,
        wp.RoleID,
        wp.WorkflowStepID,
        ws.WorkflowID,
        action_ref.Code,
        participant_status.Code,
        step_status.Code,
        workflow_status.Code

    INTO
        v_assigned_user_id,
        v_role_id,
        v_workflow_step_id,
        v_workflow_id,
        v_action_code,
        v_assignment_status,
        v_step_status,
        v_workflow_status

    FROM WorkflowParticipant wp

    JOIN WorkflowStep ws
        ON ws.WorkflowStepID = wp.WorkflowStepID

    JOIN Workflow w
        ON w.WorkflowID = ws.WorkflowID

    JOIN ReferenceData action_ref
        ON action_ref.ReferenceDataID =
           wp.AssignedActionID

    JOIN ReferenceData participant_status
        ON participant_status.ReferenceDataID =
           wp.AssignmentStatusID

    JOIN ReferenceData step_status
        ON step_status.ReferenceDataID =
           ws.StepStatusID

    JOIN ReferenceData workflow_status
        ON workflow_status.ReferenceDataID =
           w.WorkflowStatusID

    WHERE wp.WorkflowParticipantID =
          p_workflow_participant_id

    FOR UPDATE;


    IF v_assigned_user_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow participant assignment does not exist.';
    END IF;


    IF v_assigned_user_id <> p_current_user_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Current user is not assigned to this workflow action.';
    END IF;


    IF v_action_code NOT IN (
        'REVIEW',
        'ACKNOWLEDGEMENT'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Assignment is not a review or acknowledgement action.';
    END IF;


    IF v_workflow_status <> 'ACTIVE'
       OR v_step_status <> 'ACTIVE'
       OR v_assignment_status <> 'ACTIVE' THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow action is not currently active.';

    END IF;


    IF fn_user_has_role(
        p_current_user_id,
        v_role_id
    ) = FALSE THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Current user does not hold the required role.';

    END IF;


    IF fn_all_predecessors_complete(
        v_workflow_step_id
    ) = FALSE THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Required predecessor workflow work is incomplete.';

    END IF;


    SELECT ReferenceDataID
    INTO v_completed_status_id
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'COMPLETED'
      AND IsActive = TRUE;


    UPDATE WorkflowParticipant
    SET
        AssignmentStatusID =
            v_completed_status_id,

        CompletionDateTime =
            CURRENT_TIMESTAMP

    WHERE WorkflowParticipantID =
          p_workflow_participant_id;


    INSERT INTO AuditLog (
        ActorUserID,
        EventType,
        AffectedRecordType,
        AffectedRecordID,
        TransactionReference,
        NewValueContext
    )
    VALUES (
        p_current_user_id,
        CONCAT(v_action_code, '_COMPLETED'),
        'WorkflowParticipant',
        p_workflow_participant_id,
        v_transaction_reference,
        'Assignment completed'
    );


    CALL sp_advance_workflow(v_workflow_id);


    COMMIT;

END//


-- ============================================================
-- 4. sp_record_approval_decision
-- ============================================================
-- Supports:
--   FR-10
--   FR-12
--   FR-13
--   FR-14
--   FR-15
--
-- Initial implementation supports:
--   APPROVED
--   REJECTED
--
-- A rejection terminates ordinary workflow progression.
-- ============================================================

CREATE PROCEDURE sp_record_approval_decision (
    IN p_workflow_participant_id BIGINT UNSIGNED,
    IN p_current_user_id BIGINT UNSIGNED,
    IN p_decision_code VARCHAR(50),
    IN p_comments TEXT,
    IN p_rejection_reason VARCHAR(500)
)
BEGIN
    DECLARE v_assigned_user_id BIGINT UNSIGNED;
    DECLARE v_role_id BIGINT UNSIGNED;
    DECLARE v_workflow_step_id BIGINT UNSIGNED;
    DECLARE v_workflow_id BIGINT UNSIGNED;

    DECLARE v_action_code VARCHAR(50);
    DECLARE v_assignment_status VARCHAR(50);
    DECLARE v_step_status VARCHAR(50);
    DECLARE v_workflow_status VARCHAR(50);

    DECLARE v_decision_value_id BIGINT UNSIGNED;

    DECLARE v_participant_completed_id BIGINT UNSIGNED;
    DECLARE v_participant_rejected_id BIGINT UNSIGNED;
    DECLARE v_participant_cancelled_id BIGINT UNSIGNED;

    DECLARE v_step_cancelled_id BIGINT UNSIGNED;

    DECLARE v_workflow_rejected_id BIGINT UNSIGNED;

    DECLARE v_transaction_reference VARCHAR(100);


    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;


    START TRANSACTION;

    SET v_transaction_reference = UUID();


    SELECT
        wp.UserID,
        wp.RoleID,
        wp.WorkflowStepID,
        ws.WorkflowID,
        action_ref.Code,
        participant_status.Code,
        step_status.Code,
        workflow_status.Code

    INTO
        v_assigned_user_id,
        v_role_id,
        v_workflow_step_id,
        v_workflow_id,
        v_action_code,
        v_assignment_status,
        v_step_status,
        v_workflow_status

    FROM WorkflowParticipant wp

    JOIN WorkflowStep ws
        ON ws.WorkflowStepID = wp.WorkflowStepID

    JOIN Workflow w
        ON w.WorkflowID = ws.WorkflowID

    JOIN ReferenceData action_ref
        ON action_ref.ReferenceDataID =
           wp.AssignedActionID

    JOIN ReferenceData participant_status
        ON participant_status.ReferenceDataID =
           wp.AssignmentStatusID

    JOIN ReferenceData step_status
        ON step_status.ReferenceDataID =
           ws.StepStatusID

    JOIN ReferenceData workflow_status
        ON workflow_status.ReferenceDataID =
           w.WorkflowStatusID

    WHERE wp.WorkflowParticipantID =
          p_workflow_participant_id

    FOR UPDATE;


    IF v_assigned_user_id <> p_current_user_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Current user is not assigned to this approval.';
    END IF;


    IF v_action_code <> 'APPROVAL' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Assignment is not an approval action.';
    END IF;


    IF v_workflow_status <> 'ACTIVE'
       OR v_step_status <> 'ACTIVE'
       OR v_assignment_status <> 'ACTIVE' THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Approval action is not currently active.';

    END IF;


    IF fn_user_has_role(
        p_current_user_id,
        v_role_id
    ) = FALSE THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'User does not hold the required approval role.';

    END IF;


    IF fn_all_predecessors_complete(
        v_workflow_step_id
    ) = FALSE THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Required predecessor work is incomplete.';

    END IF;


    IF p_decision_code NOT IN (
        'APPROVED',
        'REJECTED'
    ) THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Unsupported approval decision.';

    END IF;


    IF p_decision_code = 'REJECTED'
       AND (
           p_rejection_reason IS NULL
           OR TRIM(p_rejection_reason) = ''
       ) THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'RejectionReason is required for a rejected approval.';

    END IF;


    SELECT ReferenceDataID
    INTO v_decision_value_id
    FROM ReferenceData
    WHERE DomainName = 'APPROVAL_DECISION'
      AND Code = p_decision_code
      AND IsActive = TRUE;


    INSERT INTO ApprovalDecision (
        WorkflowParticipantID,
        DecisionValueID,
        DecisionDateTime,
        Comments,
        RejectionReason
    )
    VALUES (
        p_workflow_participant_id,
        v_decision_value_id,
        CURRENT_TIMESTAMP,
        p_comments,
        p_rejection_reason
    );


    -- --------------------------------------------------------
    -- APPROVED
    -- --------------------------------------------------------

    IF p_decision_code = 'APPROVED' THEN

        SELECT ReferenceDataID
        INTO v_participant_completed_id
        FROM ReferenceData
        WHERE DomainName = 'PARTICIPANT_STATUS'
          AND Code = 'COMPLETED'
          AND IsActive = TRUE;


        UPDATE WorkflowParticipant
        SET
            AssignmentStatusID =
                v_participant_completed_id,

            CompletionDateTime =
                CURRENT_TIMESTAMP

        WHERE WorkflowParticipantID =
              p_workflow_participant_id;


        INSERT INTO AuditLog (
            ActorUserID,
            EventType,
            AffectedRecordType,
            AffectedRecordID,
            TransactionReference,
            NewValueContext
        )
        VALUES (
            p_current_user_id,
            'APPROVAL_RECORDED',
            'ApprovalDecision',
            LAST_INSERT_ID(),
            v_transaction_reference,
            'APPROVED'
        );


        CALL sp_advance_workflow(v_workflow_id);


    -- --------------------------------------------------------
    -- REJECTED
    -- --------------------------------------------------------

    ELSE

        SELECT ReferenceDataID
        INTO v_participant_rejected_id
        FROM ReferenceData
        WHERE DomainName = 'PARTICIPANT_STATUS'
          AND Code = 'REJECTED'
          AND IsActive = TRUE;


        SELECT ReferenceDataID
        INTO v_participant_cancelled_id
        FROM ReferenceData
        WHERE DomainName = 'PARTICIPANT_STATUS'
          AND Code = 'CANCELLED'
          AND IsActive = TRUE;


        SELECT ReferenceDataID
        INTO v_step_cancelled_id
        FROM ReferenceData
        WHERE DomainName = 'STEP_STATUS'
          AND Code = 'CANCELLED'
          AND IsActive = TRUE;


        SELECT ReferenceDataID
        INTO v_workflow_rejected_id
        FROM ReferenceData
        WHERE DomainName = 'WORKFLOW_STATUS'
          AND Code = 'REJECTED'
          AND IsActive = TRUE;


        UPDATE WorkflowParticipant
        SET
            AssignmentStatusID =
                v_participant_rejected_id,

            CompletionDateTime =
                CURRENT_TIMESTAMP

        WHERE WorkflowParticipantID =
              p_workflow_participant_id;


        -- Cancel all other unfinished assignments.

        UPDATE WorkflowParticipant wp
        JOIN WorkflowStep ws
            ON ws.WorkflowStepID =
               wp.WorkflowStepID
        JOIN ReferenceData status_ref
            ON status_ref.ReferenceDataID =
               wp.AssignmentStatusID
        SET
            wp.AssignmentStatusID =
                v_participant_cancelled_id

        WHERE ws.WorkflowID = v_workflow_id
          AND wp.WorkflowParticipantID <>
              p_workflow_participant_id
          AND status_ref.Code IN (
              'PENDING',
              'ACTIVE'
          );


        -- Cancel unfinished workflow steps.

        UPDATE WorkflowStep ws
        JOIN ReferenceData step_status
            ON step_status.ReferenceDataID =
               ws.StepStatusID
        SET
            ws.StepStatusID =
                v_step_cancelled_id

        WHERE ws.WorkflowID = v_workflow_id
          AND step_status.Code IN (
              'PENDING',
              'ACTIVE'
          );


        UPDATE Workflow
        SET WorkflowStatusID =
            v_workflow_rejected_id
        WHERE WorkflowID = v_workflow_id;


        INSERT INTO AuditLog (
            ActorUserID,
            EventType,
            AffectedRecordType,
            AffectedRecordID,
            TransactionReference,
            NewValueContext,
            ChangeReason
        )
        VALUES (
            p_current_user_id,
            'APPROVAL_REJECTED',
            'Workflow',
            v_workflow_id,
            v_transaction_reference,
            'Workflow transitioned to REJECTED',
            p_rejection_reason
        );

    END IF;


    COMMIT;

END//


-- ============================================================
-- 5. sp_record_signature
-- ============================================================
-- Supports:
--   FR-11
--   FR-12
--   FR-13
--   FR-14
--   FR-15
--
-- Records a Signature against the exact DocumentVersion
-- associated with the Workflow.
-- ============================================================

CREATE PROCEDURE sp_record_signature (
    IN p_workflow_participant_id BIGINT UNSIGNED,
    IN p_current_user_id BIGINT UNSIGNED,
    IN p_document_version_id BIGINT UNSIGNED,
    IN p_signature_status_code VARCHAR(50),
    IN p_signature_method VARCHAR(100),
    IN p_signature_reference VARCHAR(255)
)
BEGIN
    DECLARE v_assigned_user_id BIGINT UNSIGNED;
    DECLARE v_role_id BIGINT UNSIGNED;
    DECLARE v_workflow_step_id BIGINT UNSIGNED;
    DECLARE v_workflow_id BIGINT UNSIGNED;
    DECLARE v_expected_version_id BIGINT UNSIGNED;

    DECLARE v_action_code VARCHAR(50);
    DECLARE v_assignment_status VARCHAR(50);
    DECLARE v_step_status VARCHAR(50);
    DECLARE v_workflow_status VARCHAR(50);

    DECLARE v_signature_status_id BIGINT UNSIGNED;
    DECLARE v_completed_status_id BIGINT UNSIGNED;

    DECLARE v_signature_id BIGINT UNSIGNED;

    DECLARE v_transaction_reference VARCHAR(100);


    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;


    START TRANSACTION;

    SET v_transaction_reference = UUID();


    SELECT
        wp.UserID,
        wp.RoleID,
        wp.WorkflowStepID,
        ws.WorkflowID,
        w.DocumentVersionID,
        action_ref.Code,
        participant_status.Code,
        step_status.Code,
        workflow_status.Code

    INTO
        v_assigned_user_id,
        v_role_id,
        v_workflow_step_id,
        v_workflow_id,
        v_expected_version_id,
        v_action_code,
        v_assignment_status,
        v_step_status,
        v_workflow_status

    FROM WorkflowParticipant wp

    JOIN WorkflowStep ws
        ON ws.WorkflowStepID =
           wp.WorkflowStepID

    JOIN Workflow w
        ON w.WorkflowID =
           ws.WorkflowID

    JOIN ReferenceData action_ref
        ON action_ref.ReferenceDataID =
           wp.AssignedActionID

    JOIN ReferenceData participant_status
        ON participant_status.ReferenceDataID =
           wp.AssignmentStatusID

    JOIN ReferenceData step_status
        ON step_status.ReferenceDataID =
           ws.StepStatusID

    JOIN ReferenceData workflow_status
        ON workflow_status.ReferenceDataID =
           w.WorkflowStatusID

    WHERE wp.WorkflowParticipantID =
          p_workflow_participant_id

    FOR UPDATE;


    IF v_assigned_user_id <> p_current_user_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Current user is not the assigned signer.';
    END IF;


    IF v_action_code <> 'SIGNATURE' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Assignment is not a signature action.';
    END IF;


    IF v_workflow_status <> 'ACTIVE'
       OR v_step_status <> 'ACTIVE'
       OR v_assignment_status <> 'ACTIVE' THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Signature action is not currently active.';

    END IF;


    IF v_expected_version_id <>
       p_document_version_id THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Signature must reference the exact DocumentVersion used by the workflow.';

    END IF;


    IF fn_user_has_role(
        p_current_user_id,
        v_role_id
    ) = FALSE THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Current user does not hold the required signer role.';

    END IF;


    IF fn_all_predecessors_complete(
        v_workflow_step_id
    ) = FALSE THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Required predecessor work is incomplete.';

    END IF;


    IF p_signature_method IS NULL
       OR TRIM(p_signature_method) = '' THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Signature method is required.';

    END IF;


    SELECT ReferenceDataID
    INTO v_signature_status_id
    FROM ReferenceData
    WHERE DomainName = 'SIGNATURE_STATUS'
      AND Code = p_signature_status_code
      AND IsActive = TRUE;


    INSERT INTO Signature (
        WorkflowParticipantID,
        DocumentVersionID,
        SigningDateTime,
        SignatureStatusID,
        SignatureMethod,
        SignatureReference
    )
    VALUES (
        p_workflow_participant_id,
        p_document_version_id,
        CURRENT_TIMESTAMP,
        v_signature_status_id,
        p_signature_method,
        p_signature_reference
    );


    SET v_signature_id = LAST_INSERT_ID();


    SELECT ReferenceDataID
    INTO v_completed_status_id
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'COMPLETED'
      AND IsActive = TRUE;


    UPDATE WorkflowParticipant
    SET
        AssignmentStatusID =
            v_completed_status_id,

        CompletionDateTime =
            CURRENT_TIMESTAMP

    WHERE WorkflowParticipantID =
          p_workflow_participant_id;


    INSERT INTO AuditLog (
        ActorUserID,
        EventType,
        AffectedRecordType,
        AffectedRecordID,
        TransactionReference,
        NewValueContext
    )
    VALUES (
        p_current_user_id,
        'SIGNATURE_RECORDED',
        'Signature',
        v_signature_id,
        v_transaction_reference,
        CONCAT(
            'DocumentVersionID=',
            p_document_version_id
        )
    );


    CALL sp_advance_workflow(v_workflow_id);


    COMMIT;

END//


-- ============================================================
-- 6. sp_cancel_workflow
-- ============================================================
-- Supports:
--   FR-16
--   SEC rules
--   TX-04
--
-- Authorized:
--   Document Owner of the associated Document
--   OR
--   System Administrator
--
-- Only an Active Workflow may be cancelled.
-- CancellationReason is required.
-- ============================================================

CREATE PROCEDURE sp_cancel_workflow (
    IN p_workflow_id BIGINT UNSIGNED,
    IN p_current_user_id BIGINT UNSIGNED,
    IN p_cancellation_reason VARCHAR(500)
)
BEGIN
    DECLARE v_owner_user_id BIGINT UNSIGNED;
    DECLARE v_current_status VARCHAR(50);

    DECLARE v_is_admin BOOLEAN DEFAULT FALSE;

    DECLARE v_workflow_cancelled_id BIGINT UNSIGNED;
    DECLARE v_step_cancelled_id BIGINT UNSIGNED;
    DECLARE v_participant_cancelled_id BIGINT UNSIGNED;

    DECLARE v_transaction_reference VARCHAR(100);


    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;


    START TRANSACTION;

    SET v_transaction_reference = UUID();


    IF p_cancellation_reason IS NULL
       OR TRIM(p_cancellation_reason) = '' THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'CancellationReason is required.';

    END IF;


    -- Lock workflow during cancellation.

    SELECT
        d.OwnerUserID,
        status_ref.Code

    INTO
        v_owner_user_id,
        v_current_status

    FROM Workflow w

    JOIN Document d
        ON d.DocumentID = w.DocumentID

    JOIN ReferenceData status_ref
        ON status_ref.ReferenceDataID =
           w.WorkflowStatusID

    WHERE w.WorkflowID = p_workflow_id

    FOR UPDATE;


    IF v_owner_user_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow does not exist.';
    END IF;


    -- Determine administrator authorization.

    SELECT EXISTS (
        SELECT 1
        FROM UserRole ur
        JOIN Role r
            ON r.RoleID = ur.RoleID
        WHERE ur.UserID =
              p_current_user_id
          AND r.RoleName =
              'System Administrator'
          AND r.ActiveStatus = TRUE
    )
    INTO v_is_admin;


    IF p_current_user_id <> v_owner_user_id
       AND v_is_admin = FALSE THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Current user is not authorized to cancel this workflow.';

    END IF;


    IF v_current_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Only an Active workflow may be cancelled.';
    END IF;


    SELECT ReferenceDataID
    INTO v_workflow_cancelled_id
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_STATUS'
      AND Code = 'CANCELLED'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_step_cancelled_id
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'CANCELLED'
      AND IsActive = TRUE;


    SELECT ReferenceDataID
    INTO v_participant_cancelled_id
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'CANCELLED'
      AND IsActive = TRUE;


    -- --------------------------------------------------------
    -- Cancel workflow.
    -- --------------------------------------------------------

    UPDATE Workflow
    SET
        WorkflowStatusID =
            v_workflow_cancelled_id,

        CancellationDateTime =
            CURRENT_TIMESTAMP,

        CancellationReason =
            p_cancellation_reason

    WHERE WorkflowID = p_workflow_id;


    -- --------------------------------------------------------
    -- Cancel unfinished steps.
    -- --------------------------------------------------------

    UPDATE WorkflowStep ws
    JOIN ReferenceData step_status
        ON step_status.ReferenceDataID =
           ws.StepStatusID

    SET ws.StepStatusID =
            v_step_cancelled_id

    WHERE ws.WorkflowID = p_workflow_id
      AND step_status.Code IN (
          'PENDING',
          'ACTIVE'
      );


    -- --------------------------------------------------------
    -- Cancel unfinished participant assignments.
    -- --------------------------------------------------------

    UPDATE WorkflowParticipant wp

    JOIN WorkflowStep ws
        ON ws.WorkflowStepID =
           wp.WorkflowStepID

    JOIN ReferenceData participant_status
        ON participant_status.ReferenceDataID =
           wp.AssignmentStatusID

    SET wp.AssignmentStatusID =
            v_participant_cancelled_id

    WHERE ws.WorkflowID = p_workflow_id
      AND participant_status.Code IN (
          'PENDING',
          'ACTIVE'
      );


    -- --------------------------------------------------------
    -- Audit cancellation.
    -- --------------------------------------------------------

    INSERT INTO AuditLog (
        ActorUserID,
        EventType,
        AffectedRecordType,
        AffectedRecordID,
        TransactionReference,
        PriorValueContext,
        NewValueContext,
        ChangeReason
    )
    VALUES (
        p_current_user_id,
        'WORKFLOW_CANCELLED',
        'Workflow',
        p_workflow_id,
        v_transaction_reference,
        'ACTIVE',
        'CANCELLED',
        p_cancellation_reason
    );


    COMMIT;

END//

-- ============================================================
-- 7. sp_create_document_version
--
-- Purpose:
--   Create a new CURRENT DocumentVersion for a document owned
--   by the requesting user.
--
-- Rules:
--   - Document must exist.
--   - Requesting user must own the document.
--   - VersionNumber must be positive and unique within document.
--   - No other CURRENT version may already exist.
--   - New version is created as CURRENT.
--   - Audit row is created in same transaction.
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_create_document_version $$

CREATE PROCEDURE sp_create_document_version(
    IN p_owner_user_id BIGINT UNSIGNED,
    IN p_document_id BIGINT UNSIGNED,
    IN p_version_number INT UNSIGNED,
    IN p_effective_information VARCHAR(255)
)
BEGIN
    DECLARE v_owner_user_id BIGINT UNSIGNED;
    DECLARE v_current_status_id BIGINT UNSIGNED;

    DECLARE v_existing_version_count INT DEFAULT 0;
    DECLARE v_current_version_count INT DEFAULT 0;

    DECLARE v_document_version_id BIGINT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;


    START TRANSACTION;


    -- --------------------------------------------------------
    -- Validate required arguments.
    -- --------------------------------------------------------

    IF p_owner_user_id IS NULL
       OR p_document_id IS NULL
       OR p_version_number IS NULL THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Document owner, document ID, and version number are required.';
    END IF;


    IF p_version_number = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Version number must be greater than zero.';
    END IF;


    -- --------------------------------------------------------
    -- Validate document and ownership.
    -- FOR UPDATE protects ownership/document state during txn.
    -- --------------------------------------------------------

    SELECT OwnerUserID
    INTO v_owner_user_id
    FROM Document
    WHERE DocumentID = p_document_id
    FOR UPDATE;


    IF v_owner_user_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Document does not exist.';
    END IF;


    IF v_owner_user_id <> p_owner_user_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Only the document owner may create a document version.';
    END IF;


    -- --------------------------------------------------------
    -- Prevent duplicate version number.
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_existing_version_count
    FROM DocumentVersion
    WHERE DocumentID = p_document_id
      AND VersionNumber = p_version_number;


    IF v_existing_version_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Version number already exists for this document.';
    END IF;


    -- --------------------------------------------------------
    -- Resolve CURRENT status.
    -- --------------------------------------------------------

    SELECT ReferenceDataID
    INTO v_current_status_id
    FROM ReferenceData
    WHERE DomainName = 'DOCUMENT_VERSION_STATUS'
      AND Code = 'CURRENT'
      AND IsActive = TRUE
    LIMIT 1;


    IF v_current_status_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'CURRENT document version status is not configured.';
    END IF;


    -- --------------------------------------------------------
    -- Enforce at most one CURRENT version.
    -- With the current status model, a document cannot receive
    -- another CURRENT version until the existing CURRENT version
    -- has transitioned elsewhere.
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_current_version_count
    FROM DocumentVersion
    WHERE DocumentID = p_document_id
      AND CurrentVersionStatusID = v_current_status_id;


    IF v_current_version_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Document already has a CURRENT version.';
    END IF;


    -- --------------------------------------------------------
    -- Create version.
    -- --------------------------------------------------------

    INSERT INTO DocumentVersion
    (
        DocumentID,
        VersionNumber,
        EffectiveInformation,
        CreatedByUserID,
        CurrentVersionStatusID,
        LockedDateTime
    )
    VALUES
    (
        p_document_id,
        p_version_number,
        p_effective_information,
        p_owner_user_id,
        v_current_status_id,
        NULL
    );


    SET v_document_version_id = LAST_INSERT_ID();


    -- --------------------------------------------------------
    -- Audit event.
    -- --------------------------------------------------------

    INSERT INTO AuditLog
    (
        ActorUserID,
        EventType,
        AffectedRecordType,
        AffectedRecordID,
        TransactionReference,
        PriorValueContext,
        NewValueContext,
        ChangeReason
    )
    VALUES
    (
        p_owner_user_id,
        'DOCUMENT_VERSION_CREATED',
        'DocumentVersion',
        v_document_version_id,
        CONCAT('DOCVER-', v_document_version_id),
        NULL,
        CONCAT(
            'DocumentID=', p_document_id,
            '; VersionNumber=', p_version_number,
            '; Status=CURRENT'
        ),
        'Document owner created a new document version.'
    );


    COMMIT;


    SELECT
        v_document_version_id AS DocumentVersionID,
        p_document_id AS DocumentID,
        p_version_number AS VersionNumber,
        'CURRENT' AS VersionStatus;

END $$

-- ============================================================
-- 8. sp_expire_workflows
--
-- Purpose:
--   Expire ACTIVE workflows whose ExpirationDateTime has passed.
--
-- Rules:
--   - Only ACTIVE workflows are considered.
--   - ExpirationDateTime must be non-null and <= current time.
--   - Outstanding steps become CANCELLED.
--   - Outstanding participant assignments become CANCELLED.
--   - Completed/rejected/declined historical actions are preserved.
--   - One audit row is inserted per expired workflow.
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_expire_workflows $$

CREATE PROCEDURE sp_expire_workflows(
    IN p_actor_user_id BIGINT UNSIGNED
)
BEGIN
    DECLARE v_done INT DEFAULT FALSE;

    DECLARE v_workflow_id BIGINT UNSIGNED;

    DECLARE v_active_workflow_status_id BIGINT UNSIGNED;
    DECLARE v_expired_workflow_status_id BIGINT UNSIGNED;

    DECLARE v_pending_step_status_id BIGINT UNSIGNED;
    DECLARE v_active_step_status_id BIGINT UNSIGNED;
    DECLARE v_cancelled_step_status_id BIGINT UNSIGNED;

    DECLARE v_pending_participant_status_id BIGINT UNSIGNED;
    DECLARE v_active_participant_status_id BIGINT UNSIGNED;
    DECLARE v_cancelled_participant_status_id BIGINT UNSIGNED;


    DECLARE cur_expired_workflows CURSOR FOR
        SELECT WorkflowID
        FROM Workflow
        WHERE WorkflowStatusID = v_active_workflow_status_id
          AND ExpirationDateTime IS NOT NULL
          AND ExpirationDateTime <= CURRENT_TIMESTAMP
        FOR UPDATE;


    DECLARE CONTINUE HANDLER FOR NOT FOUND
        SET v_done = TRUE;


    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;


    START TRANSACTION;


    -- --------------------------------------------------------
    -- Resolve workflow statuses.
    -- --------------------------------------------------------

    SELECT ReferenceDataID
    INTO v_active_workflow_status_id
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_STATUS'
      AND Code = 'ACTIVE'
      AND IsActive = TRUE
    LIMIT 1;


    SELECT ReferenceDataID
    INTO v_expired_workflow_status_id
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_STATUS'
      AND Code = 'EXPIRED'
      AND IsActive = TRUE
    LIMIT 1;


    -- --------------------------------------------------------
    -- Resolve step statuses.
    -- --------------------------------------------------------

    SELECT ReferenceDataID
    INTO v_pending_step_status_id
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'PENDING'
      AND IsActive = TRUE
    LIMIT 1;


    SELECT ReferenceDataID
    INTO v_active_step_status_id
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'ACTIVE'
      AND IsActive = TRUE
    LIMIT 1;


    SELECT ReferenceDataID
    INTO v_cancelled_step_status_id
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'CANCELLED'
      AND IsActive = TRUE
    LIMIT 1;


    -- --------------------------------------------------------
    -- Resolve participant statuses.
    -- --------------------------------------------------------

    SELECT ReferenceDataID
    INTO v_pending_participant_status_id
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'PENDING'
      AND IsActive = TRUE
    LIMIT 1;


    SELECT ReferenceDataID
    INTO v_active_participant_status_id
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'ACTIVE'
      AND IsActive = TRUE
    LIMIT 1;


    SELECT ReferenceDataID
    INTO v_cancelled_participant_status_id
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'CANCELLED'
      AND IsActive = TRUE
    LIMIT 1;


    -- --------------------------------------------------------
    -- Validate required status configuration.
    -- --------------------------------------------------------

    IF v_active_workflow_status_id IS NULL
       OR v_expired_workflow_status_id IS NULL
       OR v_pending_step_status_id IS NULL
       OR v_active_step_status_id IS NULL
       OR v_cancelled_step_status_id IS NULL
       OR v_pending_participant_status_id IS NULL
       OR v_active_participant_status_id IS NULL
       OR v_cancelled_participant_status_id IS NULL THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Required expiration status reference data is missing.';
    END IF;


    -- --------------------------------------------------------
    -- Process expired ACTIVE workflows.
    -- --------------------------------------------------------

    OPEN cur_expired_workflows;


    expire_loop: LOOP

        FETCH cur_expired_workflows
        INTO v_workflow_id;


        IF v_done THEN
            LEAVE expire_loop;
        END IF;


        -- Cancel outstanding participant assignments first.
        UPDATE WorkflowParticipant wp
        JOIN WorkflowStep ws
          ON ws.WorkflowStepID = wp.WorkflowStepID
        SET
            wp.AssignmentStatusID = v_cancelled_participant_status_id,
            wp.CompletionDateTime = CURRENT_TIMESTAMP
        WHERE ws.WorkflowID = v_workflow_id
          AND wp.AssignmentStatusID IN
          (
              v_pending_participant_status_id,
              v_active_participant_status_id
          );


        -- Cancel outstanding steps.
        UPDATE WorkflowStep
        SET
            StepStatusID = v_cancelled_step_status_id,
            CompletionDateTime = CURRENT_TIMESTAMP
        WHERE WorkflowID = v_workflow_id
          AND StepStatusID IN
          (
              v_pending_step_status_id,
              v_active_step_status_id
          );


        -- Expire workflow.
        UPDATE Workflow
        SET
            WorkflowStatusID = v_expired_workflow_status_id,
            CompletionDateTime = CURRENT_TIMESTAMP
        WHERE WorkflowID = v_workflow_id
          AND WorkflowStatusID = v_active_workflow_status_id;


        -- Audit.
        INSERT INTO AuditLog
        (
            ActorUserID,
            EventType,
            AffectedRecordType,
            AffectedRecordID,
            TransactionReference,
            PriorValueContext,
            NewValueContext,
            ChangeReason
        )
        VALUES
        (
            p_actor_user_id,
            'WORKFLOW_EXPIRED',
            'Workflow',
            v_workflow_id,
            CONCAT('WF-EXP-', v_workflow_id),
            'WorkflowStatus=ACTIVE',
            'WorkflowStatus=EXPIRED',
            'Workflow expiration date/time reached.'
        );

    END LOOP;


    CLOSE cur_expired_workflows;


    COMMIT;


    SELECT
        'Workflow expiration scan completed.' AS Result;

END $$

DELIMITER ;