-- ============================================================
-- File:
--   database/06_demo_tests/040_common_queries_performance_demo.sql
--
-- Project:
--   Document Workflow and E-signing Portal
--
-- Purpose:
--   Demonstrate representative operational and reporting queries
--   from the FRD/TDD and show MySQL execution-plan evidence.
--
-- Demonstrates:
--   - Filtering
--   - Joins
--   - Ordering
--   - Aggregation
--   - Exception / outstanding-work reporting
--   - EXPLAIN execution plans
--   - Index-supported access paths
--
-- Database:
--   MySQL 8.x
-- ============================================================


SELECT '============================================================'
    AS DemoSection;

SELECT 'COMMON QUERIES AND PERFORMANCE EVIDENCE'
    AS DemoSection;

SELECT '============================================================'
    AS DemoSection;



-- ============================================================
-- QUERY 1
-- Participant operational worklist
--
-- TDD Q-02:
-- Retrieve active assignments for a user.
--
-- Tables:
--   WorkflowParticipant
--   WorkflowStep
--   Workflow
--   Document
--   User
--   ReferenceData
--
-- Access pattern:
--   Filter by UserID
--   Filter by AssignmentStatusID
--   Order by DueDateTime
--
-- Important index:
--   idx_WorkflowParticipant_User_Status_DueDate
--       (UserID, AssignmentStatusID, DueDateTime)
--
-- Why the column order matters:
--   UserID and AssignmentStatusID are equality predicates.
--   DueDateTime is then available in index order.
-- ============================================================

SELECT
    'QUERY 1 - ACTIVE ASSIGNMENTS FOR ONE USER'
    AS DemoSection;


SET @demo_user_id = (
    SELECT UserID
    FROM `User`
    WHERE Email = 'daniel.cho@initech.example'
    LIMIT 1
);


SET @demo_active_participant_status_id = (
    SELECT ReferenceDataID
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'ACTIVE'
    LIMIT 1
);


SELECT
    wp.WorkflowParticipantID,
    d.Title,
    w.WorkflowID,
    ws.SequenceNumber,
    step_type.Code AS StepType,
    action_type.Code AS AssignedAction,
    participant_status.Code AS AssignmentStatus,
    wp.DueDateTime

FROM WorkflowParticipant wp

JOIN WorkflowStep ws
  ON ws.WorkflowStepID = wp.WorkflowStepID

JOIN Workflow w
  ON w.WorkflowID = ws.WorkflowID

JOIN Document d
  ON d.DocumentID = w.DocumentID

JOIN ReferenceData step_type
  ON step_type.ReferenceDataID = ws.StepTypeID

JOIN ReferenceData action_type
  ON action_type.ReferenceDataID = wp.AssignedActionID

JOIN ReferenceData participant_status
  ON participant_status.ReferenceDataID = wp.AssignmentStatusID

WHERE wp.UserID = @demo_user_id
  AND wp.AssignmentStatusID =
      @demo_active_participant_status_id

ORDER BY wp.DueDateTime;


SELECT
    'EXPLAIN QUERY 1 - EXPECT INDEX LOOKUP ON WORKFLOWPARTICIPANT'
    AS DemoSection;


EXPLAIN
SELECT
    wp.WorkflowParticipantID,
    wp.WorkflowStepID,
    wp.UserID,
    wp.AssignmentStatusID,
    wp.DueDateTime

FROM WorkflowParticipant wp

WHERE wp.UserID = @demo_user_id
  AND wp.AssignmentStatusID =
      @demo_active_participant_status_id

ORDER BY wp.DueDateTime;



-- ============================================================
-- QUERY 2
-- Workflow steps in execution order
--
-- TDD Q-03:
-- Retrieve steps for a workflow ordered by SequenceNumber.
--
-- Access pattern:
--   Filter by WorkflowID
--   Order by SequenceNumber
--
-- Relevant index:
--   WorkflowStep(WorkflowID, SequenceNumber)
--
-- Expected behavior:
--   MySQL can use the composite index to find rows belonging to
--   one workflow and return them in sequence order.
-- ============================================================

SELECT
    'QUERY 2 - WORKFLOW STEPS IN EXECUTION ORDER'
    AS DemoSection;


SET @demo_workflow_id = (
    SELECT WorkflowID
    FROM Workflow w
    JOIN Document d
      ON d.DocumentID = w.DocumentID
    WHERE d.Title = 'Master Services Agreement'
    ORDER BY w.WorkflowID
    LIMIT 1
);


SELECT
    ws.WorkflowStepID,
    ws.WorkflowID,
    ws.SequenceNumber,
    step_type.Code AS StepType,
    step_status.Code AS StepStatus,
    ws.ActivationDateTime,
    ws.CompletionDateTime,
    ws.DueDateTime

FROM WorkflowStep ws

JOIN ReferenceData step_type
  ON step_type.ReferenceDataID = ws.StepTypeID

JOIN ReferenceData step_status
  ON step_status.ReferenceDataID = ws.StepStatusID

WHERE ws.WorkflowID = @demo_workflow_id

ORDER BY ws.SequenceNumber;


SELECT
    'EXPLAIN QUERY 2 - WORKFLOWID + SEQUENCENUMBER ACCESS PATH'
    AS DemoSection;


EXPLAIN
SELECT
    WorkflowStepID,
    WorkflowID,
    SequenceNumber,
    StepStatusID

FROM WorkflowStep

WHERE WorkflowID = @demo_workflow_id

ORDER BY SequenceNumber;



-- ============================================================
-- QUERY 3
-- Document version history
--
-- TDD Q-04:
-- Retrieve all versions for one document.
--
-- Access pattern:
--   Filter by DocumentID
--   Order by VersionNumber
--
-- Important structure:
--   UNIQUE(DocumentID, VersionNumber)
--
-- This serves two purposes:
--   1. Integrity:
--      prevents duplicate version numbers within a document.
--
--   2. Retrieval:
--      supports filtering by DocumentID and ordered VersionNumber.
-- ============================================================

SELECT
    'QUERY 3 - DOCUMENT VERSION HISTORY'
    AS DemoSection;


SET @demo_document_id = (
    SELECT DocumentID
    FROM Document
    WHERE Title = 'Master Services Agreement'
    LIMIT 1
);


SELECT
    dv.DocumentVersionID,
    dv.DocumentID,
    dv.VersionNumber,
    version_status.Code AS VersionStatus,
    dv.CreatedDateTime,
    dv.LockedDateTime

FROM DocumentVersion dv

JOIN ReferenceData version_status
  ON version_status.ReferenceDataID =
     dv.CurrentVersionStatusID

WHERE dv.DocumentID = @demo_document_id

ORDER BY dv.VersionNumber;


SELECT
    'EXPLAIN QUERY 3 - DOCUMENT VERSION UNIQUE INDEX'
    AS DemoSection;


EXPLAIN
SELECT
    DocumentVersionID,
    DocumentID,
    VersionNumber

FROM DocumentVersion

WHERE DocumentID = @demo_document_id

ORDER BY VersionNumber;



-- ============================================================
-- QUERY 4
-- Audit history for a business record
--
-- TDD Q-05:
-- Retrieve history by affected entity/record and time.
--
-- Access pattern:
--   Filter by AffectedRecordType
--   Filter by AffectedRecordID
--   Order by EventDateTime
--
-- Relevant index:
--   AuditLog(
--       AffectedRecordType,
--       AffectedRecordID,
--       EventDateTime
--   )
--
-- This allows the database to narrow to one business object's
-- audit history and retrieve it chronologically.
-- ============================================================

SELECT
    'QUERY 4 - AUDIT HISTORY FOR A WORKFLOW'
    AS DemoSection;


SET @demo_audit_workflow_id = (
    SELECT WorkflowID
    FROM Workflow
    ORDER BY WorkflowID
    LIMIT 1
);


SELECT
    al.AuditLogID,
    al.EventDateTime,
    al.EventType,
    al.AffectedRecordType,
    al.AffectedRecordID,
    al.TransactionReference,
    al.ChangeReason

FROM AuditLog al

WHERE al.AffectedRecordType = 'Workflow'
  AND al.AffectedRecordID =
      @demo_audit_workflow_id

ORDER BY
    al.EventDateTime,
    al.AuditLogID;


SELECT
    'EXPLAIN QUERY 4 - AUDIT ENTITY/TIME ACCESS PATH'
    AS DemoSection;


EXPLAIN
SELECT
    AuditLogID,
    EventDateTime,
    EventType

FROM AuditLog

WHERE AffectedRecordType = 'Workflow'
  AND AffectedRecordID =
      @demo_audit_workflow_id

ORDER BY EventDateTime;



-- ============================================================
-- QUERY 5
-- Outstanding / exception-style reporting
--
-- FR-17:
-- Retrieve outstanding assigned actions.
--
-- This is a joined operational report using the implemented view.
--
-- Demonstrates:
--   joins
--   filtering
--   ordering
--   incomplete / exception-style reporting
-- ============================================================

SELECT
    'QUERY 5 - OUTSTANDING ACTIONS REPORT'
    AS DemoSection;


SELECT
    WorkflowParticipantID,
    DocumentID,
    Title,
    WorkflowID,
    ParticipantName,
    AssignedAction,
    AssignmentStatus,
    DueDateTime,
    ExpirationDateTime

FROM vw_OutstandingActions

ORDER BY
    DueDateTime,
    WorkflowParticipantID;



-- ============================================================
-- QUERY 6
-- Aggregated reporting
--
-- Demonstrates:
--   joins
--   grouping
--   aggregation
--   status reporting
--
-- Business question:
--   How many workflows currently exist in each lifecycle status?
-- ============================================================

SELECT
    'QUERY 6 - WORKFLOW STATUS SUMMARY'
    AS DemoSection;


SELECT
    workflow_status.Code
        AS WorkflowStatus,

    COUNT(*)
        AS WorkflowCount

FROM Workflow w

JOIN ReferenceData workflow_status
  ON workflow_status.ReferenceDataID =
     w.WorkflowStatusID

GROUP BY
    workflow_status.Code

ORDER BY
    workflow_status.Code;



-- ============================================================
-- QUERY 7
-- Aggregation with business context
--
-- Business question:
--   How many participant assignments are outstanding for each
--   document?
--
-- Demonstrates:
--   multiple joins
--   filtering
--   GROUP BY
--   COUNT
--   ordering
-- ============================================================

SELECT
    'QUERY 7 - OUTSTANDING ASSIGNMENTS BY DOCUMENT'
    AS DemoSection;


SELECT
    d.DocumentID,
    d.Title,

    COUNT(*)
        AS OutstandingAssignments

FROM Document d

JOIN Workflow w
  ON w.DocumentID = d.DocumentID

JOIN WorkflowStep ws
  ON ws.WorkflowID = w.WorkflowID

JOIN WorkflowParticipant wp
  ON wp.WorkflowStepID = ws.WorkflowStepID

JOIN ReferenceData workflow_status
  ON workflow_status.ReferenceDataID =
     w.WorkflowStatusID

JOIN ReferenceData participant_status
  ON participant_status.ReferenceDataID =
     wp.AssignmentStatusID

WHERE workflow_status.Code = 'ACTIVE'

  AND participant_status.Code IN (
      'ACTIVE',
      'PENDING'
  )

GROUP BY
    d.DocumentID,
    d.Title

ORDER BY
    OutstandingAssignments DESC,
    d.Title;



-- ============================================================
-- INDEX INVENTORY
--
-- Show the actual installed indexes that support the queries.
--
-- This is useful during the live demo because it connects:
--
--     Query requirement
--          ↓
--     Physical index
--          ↓
--     EXPLAIN plan
-- ============================================================

SELECT
    'INDEX INVENTORY - IMPORTANT PERFORMANCE INDEXES'
    AS DemoSection;


SELECT
    TABLE_NAME,
    INDEX_NAME,
    NON_UNIQUE,
    SEQ_IN_INDEX,
    COLUMN_NAME

FROM information_schema.STATISTICS

WHERE TABLE_SCHEMA = DATABASE()

  AND TABLE_NAME IN (
      'WorkflowParticipant',
      'WorkflowStep',
      'DocumentVersion',
      'AuditLog',
      'Workflow'
  )

ORDER BY
    TABLE_NAME,
    INDEX_NAME,
    SEQ_IN_INDEX;



-- ============================================================
-- EXPLAIN ANALYZE
--
-- MySQL 8 allows EXPLAIN ANALYZE, which executes the query and
-- reports actual timing and row counts.
--
-- This is especially useful for the participant worklist because
-- the TDD asks for estimated/actual rows where available.
--
-- NOTE:
-- On a very small seed dataset, the optimizer may choose a table
-- scan for some queries because scanning a few rows can be cheaper
-- than using an index. That is NOT automatically a design flaw.
--
-- We demonstrate the worklist query because this index was already
-- observed being selected during the build smoke test.
-- ============================================================

SELECT
    'EXPLAIN ANALYZE - PARTICIPANT WORKLIST'
    AS DemoSection;


EXPLAIN ANALYZE
SELECT
    wp.WorkflowParticipantID,
    wp.UserID,
    wp.AssignmentStatusID,
    wp.DueDateTime

FROM WorkflowParticipant wp

WHERE wp.UserID = @demo_user_id
  AND wp.AssignmentStatusID =
      @demo_active_participant_status_id

ORDER BY wp.DueDateTime;



-- ============================================================
-- FINAL DEMO NOTES
-- ============================================================

SELECT
    '============================================================'
    AS DemoSection;

SELECT
    'COMMON QUERIES AND PERFORMANCE DEMO COMPLETED'
    AS DemoSection;

SELECT
    'Query 1: participant worklist - filtering + ordering + index lookup'
    AS Evidence;

SELECT
    'Query 2: workflow-step retrieval - filter by workflow + sequence ordering'
    AS Evidence;

SELECT
    'Query 3: version history - unique composite key supports integrity and retrieval'
    AS Evidence;

SELECT
    'Query 4: audit history - entity/id/time access path'
    AS Evidence;

SELECT
    'Query 5: outstanding-action exception report using view'
    AS Evidence;

SELECT
    'Queries 6-7: aggregation and grouped operational reporting'
    AS Evidence;

SELECT
    '============================================================'
    AS DemoSection;