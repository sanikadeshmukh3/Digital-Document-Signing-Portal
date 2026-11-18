-- ============================================================
-- File: database/02_programability/060_workflow_transition_procedure.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Provide the single database choke point for operational
--   Workflow status changes.
--
-- Principle:
--   The application does not decide whether a transition is legal.
--   The database resolves the current state, transition metadata,
--   and actor permissions before changing WorkflowStatusID.
--
-- Transaction behavior:
--   This procedure does NOT START/COMMIT/ROLLBACK a transaction.
--   It is designed to be called by the existing transactional
--   workflow procedures so their larger business operation remains
--   atomic.
--
-- Security:
--   Human authorization is derived from UserRole + Role +
--   WorkflowTransitionRole. The caller does not supply a role.
--
--   System transitions use NULL ActorUserID and are allowed only
--   where WorkflowStatusTransition.SystemAllowedFlag = TRUE.
--
-- Database: MySQL 8.x
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_transition_workflow $$

CREATE PROCEDURE sp_transition_workflow (
    IN p_WorkflowID BIGINT,
    IN p_ActorUserID BIGINT,
    IN p_ToStatusCode VARCHAR(50),
    IN p_ChangeReason VARCHAR(500),
    IN p_TransactionReference VARCHAR(255)
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_FromStatusID BIGINT;
    DECLARE v_ToStatusID BIGINT;

    DECLARE v_FromStatusCode VARCHAR(50);
    DECLARE v_TransitionCode VARCHAR(100);

    DECLARE v_TransitionID BIGINT;
    DECLARE v_SystemAllowed BOOLEAN DEFAULT FALSE;

    DECLARE v_IsAuthorized BOOLEAN DEFAULT FALSE;

    DECLARE v_DocumentID BIGINT;
    DECLARE v_OwnerUserID BIGINT;

    DECLARE v_ExpirationDateTime DATETIME;

    -- --------------------------------------------------------
    -- 1. Basic input validation
    -- --------------------------------------------------------

    IF p_WorkflowID IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow transition rejected: WorkflowID is required.';
    END IF;

    IF p_ToStatusCode IS NULL
       OR TRIM(p_ToStatusCode) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow transition rejected: target status is required.';
    END IF;


    -- --------------------------------------------------------
    -- 2. Lock and retrieve the current Workflow
    -- --------------------------------------------------------
    -- FOR UPDATE prevents two transactions from concurrently
    -- transitioning the same workflow from the same state.
    -- --------------------------------------------------------

    SELECT
        w.WorkflowStatusID,
        w.DocumentID,
        w.ExpirationDateTime
    INTO
        v_FromStatusID,
        v_DocumentID,
        v_ExpirationDateTime
    FROM Workflow w
    WHERE w.WorkflowID = p_WorkflowID
    FOR UPDATE;

    IF v_FromStatusID IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow transition rejected: workflow does not exist.';
    END IF;


    -- --------------------------------------------------------
    -- 3. Resolve current status
    -- --------------------------------------------------------

    SELECT rd.Code
    INTO v_FromStatusCode
    FROM ReferenceData rd
    WHERE rd.ReferenceDataID = v_FromStatusID
      AND rd.DomainName = 'WORKFLOW_STATUS'
      AND rd.IsActive = TRUE;

    IF v_FromStatusCode IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow transition rejected: current workflow status is invalid.';
    END IF;


    -- --------------------------------------------------------
    -- 4. Resolve requested target status
    -- --------------------------------------------------------

    SELECT rd.ReferenceDataID
    INTO v_ToStatusID
    FROM ReferenceData rd
    WHERE rd.DomainName = 'WORKFLOW_STATUS'
      AND rd.Code = p_ToStatusCode
      AND rd.IsActive = TRUE
    LIMIT 1;

    IF v_ToStatusID IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow transition rejected: target workflow status is invalid.';
    END IF;


    -- --------------------------------------------------------
    -- 5. Reject no-op transitions
    -- --------------------------------------------------------

    IF v_FromStatusID = v_ToStatusID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow transition rejected: source and target status are the same.';
    END IF;


    -- --------------------------------------------------------
    -- 6. Resolve the allowed metadata transition
    -- --------------------------------------------------------

    SET v_TransitionID = NULL;

    SELECT
        wt.WorkflowStatusTransitionID,
        wt.TransitionCode,
        wt.SystemAllowedFlag
    INTO
        v_TransitionID,
        v_TransitionCode,
        v_SystemAllowed
    FROM WorkflowStatusTransition wt
    WHERE wt.FromStatusID = v_FromStatusID
      AND wt.ToStatusID = v_ToStatusID
      AND wt.IsActive = TRUE
    LIMIT 1;

    IF v_TransitionID IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow transition rejected: requested state transition is not allowed.';
    END IF;


    -- --------------------------------------------------------
    -- 7. Authorization
    -- --------------------------------------------------------
    --
    -- NULL ActorUserID represents an internally driven transition.
    -- It is valid only when the transition metadata explicitly
    -- permits system execution.
    --
    -- Human callers are authorized through:
    --
    -- UserRole
    --   -> Role
    --   -> WorkflowTransitionRole
    --
    -- The application never supplies the role itself.
    -- --------------------------------------------------------

    IF p_ActorUserID IS NULL THEN

        IF v_SystemAllowed <> TRUE THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Workflow transition rejected: transition is not system-authorized.';
        END IF;

        SET v_IsAuthorized = TRUE;

    ELSE

        SELECT EXISTS (
            SELECT 1
            FROM UserRole ur
            JOIN WorkflowTransitionRole wtr
                ON wtr.RoleID = ur.RoleID
            WHERE ur.UserID = p_ActorUserID
              AND wtr.WorkflowStatusTransitionID =
                  v_TransitionID
              AND wtr.AllowedFlag = TRUE
        )
        INTO v_IsAuthorized;

        IF v_IsAuthorized <> TRUE THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Workflow transition rejected: actor is not authorized for this transition.';
        END IF;

    END IF;


    -- --------------------------------------------------------
    -- 8. Transition-specific contextual rules
    -- --------------------------------------------------------

    -- --------------------------------------------------------
    -- DRAFT -> ACTIVE
    -- Actor must not merely hold Document Owner role generally;
    -- the actor must own THIS workflow's Document.
    -- --------------------------------------------------------

    IF v_TransitionCode = 'ACTIVATE_WORKFLOW' THEN

        IF p_ActorUserID IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Workflow activation requires a human document owner.';
        END IF;

        SELECT d.OwnerUserID
        INTO v_OwnerUserID
        FROM Document d
        WHERE d.DocumentID = v_DocumentID;

        IF v_OwnerUserID IS NULL
           OR v_OwnerUserID <> p_ActorUserID THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Workflow transition rejected: actor does not own the workflow document.';
        END IF;

    END IF;


    -- --------------------------------------------------------
    -- ACTIVE -> COMPLETED
    -- Completion may occur only when all required workflow work
    -- is complete.
    -- --------------------------------------------------------

    IF v_TransitionCode = 'COMPLETE_WORKFLOW' THEN

        IF fn_workflow_required_work_complete(
            p_WorkflowID
        ) <> TRUE THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Workflow transition rejected: required workflow work remains incomplete.';
        END IF;

    END IF;


    -- --------------------------------------------------------
    -- ACTIVE -> EXPIRED
    -- Do not permit early expiration.
    -- --------------------------------------------------------

    IF v_TransitionCode = 'EXPIRE_WORKFLOW' THEN

        IF v_ExpirationDateTime IS NULL
           OR v_ExpirationDateTime > CURRENT_TIMESTAMP THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Workflow transition rejected: workflow has not reached its expiration time.';
        END IF;

    END IF;


    -- --------------------------------------------------------
    -- ACTIVE -> CANCELLED
    -- Cancellation requires a meaningful reason.
    -- --------------------------------------------------------

    IF v_TransitionCode = 'CANCEL_WORKFLOW' THEN

        IF p_ChangeReason IS NULL
           OR TRIM(p_ChangeReason) = '' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Workflow transition rejected: cancellation reason is required.';
        END IF;

        -- A Document Owner may only cancel a workflow belonging
        -- to that owner's own Document.

        SELECT d.OwnerUserID
        INTO v_OwnerUserID
        FROM Document d
        WHERE d.DocumentID = v_DocumentID;

        IF p_ActorUserID IS NULL
           OR v_OwnerUserID <> p_ActorUserID THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT =
                    'Workflow transition rejected: only the document owner may cancel this workflow.';
        END IF;

    END IF;


    -- --------------------------------------------------------
    -- REJECT_WORKFLOW
    -- General role authorization is validated here.
    --
    -- Assignment-specific approval eligibility remains enforced
    -- by sp_record_approval_decision, which will be the trusted
    -- caller of this transition.
    -- --------------------------------------------------------


    -- --------------------------------------------------------
    -- 9. Perform the transition
    -- --------------------------------------------------------

    UPDATE Workflow
    SET
        WorkflowStatusID = v_ToStatusID,

        CompletionDateTime =
            CASE
                WHEN p_ToStatusCode = 'COMPLETED'
                    THEN CURRENT_TIMESTAMP
                ELSE CompletionDateTime
            END,

        CancellationDateTime =
            CASE
                WHEN p_ToStatusCode = 'CANCELLED'
                    THEN CURRENT_TIMESTAMP
                ELSE CancellationDateTime
            END,

        CancellationReason =
            CASE
                WHEN p_ToStatusCode = 'CANCELLED'
                    THEN p_ChangeReason
                ELSE CancellationReason
            END

    WHERE WorkflowID = p_WorkflowID;


    -- --------------------------------------------------------
    -- 10. Audit the successful transition
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
        p_ActorUserID,
        CONCAT(
            'WORKFLOW_',
            p_ToStatusCode
        ),
        'Workflow',
        p_WorkflowID,
        COALESCE(
            p_TransactionReference,
            CONCAT(
                'WF-TRANSITION-',
                p_WorkflowID,
                '-',
                UNIX_TIMESTAMP()
            )
        ),
        v_FromStatusCode,
        p_ToStatusCode,
        p_ChangeReason
    );

END $$

DELIMITER ;