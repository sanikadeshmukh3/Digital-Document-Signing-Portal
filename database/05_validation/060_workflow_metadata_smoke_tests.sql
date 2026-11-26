-- ============================================================
-- File:
-- database/05_validation/060_workflow_metadata_smoke_tests.sql
--
-- Purpose:
--   Read-only smoke tests for metadata-driven workflow actions.
-- ============================================================


SELECT
    '=== Workflow Metadata Smoke Test 1: transition catalogue ==='
    AS SmokeTest;


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
    SystemAllowedFlag
FROM vw_WorkflowTransitionMetadata
ORDER BY
    DisplayOrder,
    TransitionCode,
    RoleName;


-- ============================================================
-- Resolve a seeded ACTIVE workflow owned by Olivia.
-- ============================================================

SET @workflow_metadata_smoke_owner = (
    SELECT UserID
    FROM `User`
    WHERE Email = 'olivia.brooks@initech.example'
);

SET @workflow_metadata_smoke_workflow = (
    SELECT w.WorkflowID

    FROM Workflow w

    JOIN Document d
        ON d.DocumentID = w.DocumentID

    JOIN ReferenceData status_ref
        ON status_ref.ReferenceDataID = w.WorkflowStatusID

    WHERE d.OwnerUserID = @workflow_metadata_smoke_owner
      AND status_ref.DomainName = 'WORKFLOW_STATUS'
      AND status_ref.Code = 'ACTIVE'

    ORDER BY w.WorkflowID
    LIMIT 1
);


SELECT
    '=== Workflow Metadata Smoke Test 2: selected workflow ==='
    AS SmokeTest;

SELECT
    @workflow_metadata_smoke_workflow AS WorkflowID,
    @workflow_metadata_smoke_owner AS OwnerUserID;


-- ============================================================
-- Fail if a suitable seeded workflow was not found.
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp__smoke_assert_workflow_metadata $$

CREATE PROCEDURE sp__smoke_assert_workflow_metadata()
BEGIN

    IF @workflow_metadata_smoke_owner IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata smoke test failed: seeded Olivia user was not found.';
    END IF;

    IF @workflow_metadata_smoke_workflow IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Workflow metadata smoke test failed: no ACTIVE Olivia-owned workflow was found.';
    END IF;

END $$

DELIMITER ;


CALL sp__smoke_assert_workflow_metadata();

DROP PROCEDURE sp__smoke_assert_workflow_metadata;


-- ============================================================
-- Owner allowed actions.
--
-- Expected:
-- CANCEL_WORKFLOW appears.
-- ============================================================

SELECT
    '=== Workflow Metadata Smoke Test 3: owner allowed actions ==='
    AS SmokeTest;

CALL sp_get_allowed_workflow_transitions(
    @workflow_metadata_smoke_workflow,
    @workflow_metadata_smoke_owner
);


-- ============================================================
-- Reviewer allowed actions against same workflow.
--
-- CANCEL_WORKFLOW must NOT appear.
-- ============================================================

SET @workflow_metadata_smoke_reviewer = (
    SELECT UserID
    FROM `User`
    WHERE Email = 'marcus.reed@initech.example'
);


SELECT
    '=== Workflow Metadata Smoke Test 4: reviewer allowed actions ==='
    AS SmokeTest;

CALL sp_get_allowed_workflow_transitions(
    @workflow_metadata_smoke_workflow,
    @workflow_metadata_smoke_reviewer
);


SELECT
    'WORKFLOW METADATA SMOKE TESTS COMPLETED.'
    AS Result;