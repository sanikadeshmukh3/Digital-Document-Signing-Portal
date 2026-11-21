-- ============================================================
-- File:
-- database/06_demo_tests/100_workflow_metadata_enforcement.sql
--
-- Purpose:
--   Demonstrate database-enforced workflow transition rules.
-- ============================================================


-- ------------------------------------------------------------
-- Resolve useful users.
-- ------------------------------------------------------------

SET @olivia_id = (
    SELECT UserID
    FROM `User`
    WHERE Email = 'olivia.brooks@initech.example'
);

SET @marcus_id = (
    SELECT UserID
    FROM `User`
    WHERE Email = 'marcus.reed@initech.example'
);


-- ------------------------------------------------------------
-- Find an ACTIVE workflow owned by Olivia.
-- ------------------------------------------------------------

SET @workflow_id = (
    SELECT w.WorkflowID
    FROM Workflow w

    JOIN Document d
        ON d.DocumentID = w.DocumentID

    JOIN ReferenceData ws
        ON ws.ReferenceDataID = w.WorkflowStatusID

    WHERE d.OwnerUserID = @olivia_id
      AND ws.DomainName = 'WORKFLOW_STATUS'
      AND ws.Code = 'ACTIVE'

    ORDER BY w.WorkflowID
    LIMIT 1
);


SELECT
    @workflow_id AS TestWorkflowID,
    @olivia_id AS OwnerUserID,
    @marcus_id AS UnauthorizedUserID;