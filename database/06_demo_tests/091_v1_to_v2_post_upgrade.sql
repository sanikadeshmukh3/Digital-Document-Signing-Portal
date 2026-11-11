-- ============================================================
-- Demo: v1 -> v2 Upgrade
-- Phase 2: Post-upgrade verification
--
-- Run AFTER applying schema version 1.2.0.
--
-- Purpose:
--   Prove that:
--     1. v2 migrations were applied.
--     2. database object stamps exist.
--     3. pre-existing business data survived.
-- ============================================================


SELECT
    '=== V2 POST-UPGRADE VERIFICATION ==='
    AS DemoPhase;


-- ------------------------------------------------------------
-- 1. Verify current schema/build version
-- ------------------------------------------------------------

SELECT
    BuildID,
    SchemaVersion,
    ReleaseTag,
    CommitSHA,
    BuildStatus
FROM DatabaseBuild
ORDER BY BuildID DESC
LIMIT 1;


-- ------------------------------------------------------------
-- 2. Verify v2 migrations exist
-- ------------------------------------------------------------

SELECT
    VersionNumber,
    MigrationName,
    ScriptName,
    ScriptChecksum,
    BuildID
FROM SchemaMigration
WHERE VersionNumber IN (
    '014',
    '015'
)
ORDER BY VersionNumber;


-- ------------------------------------------------------------
-- 3. Verify object-version table exists
-- ------------------------------------------------------------

SELECT
    TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME =
      'DatabaseObjectVersion';


-- ------------------------------------------------------------
-- 4. Verify all object stamps
-- ------------------------------------------------------------

SELECT
    ObjectType,
    ObjectName,
    ObjectVersion,
    StampedSchemaVersion,
    StampMigrationVersion
FROM DatabaseObjectVersion
ORDER BY
    ObjectType,
    ObjectName;


-- ------------------------------------------------------------
-- 5. Object-stamp summary
-- ------------------------------------------------------------

SELECT
    ObjectType,
    COUNT(*) AS ObjectCount
FROM DatabaseObjectVersion
GROUP BY ObjectType
ORDER BY ObjectType;


-- Expected baseline:
-- VIEW       = 6
-- FUNCTION   = 4
-- PROCEDURE  = 8
-- TRIGGER    = 9
-- TOTAL      = 27


-- ------------------------------------------------------------
-- 6. Verify business-data row counts survived
-- ------------------------------------------------------------

SELECT
    'Document' AS Entity,
    COUNT(*) AS RowCount
FROM Document

UNION ALL

SELECT
    'DocumentVersion',
    COUNT(*)
FROM DocumentVersion

UNION ALL

SELECT
    'Workflow',
    COUNT(*)
FROM Workflow

UNION ALL

SELECT
    'WorkflowParticipant',
    COUNT(*)
FROM WorkflowParticipant

UNION ALL

SELECT
    'ApprovalDecision',
    COUNT(*)
FROM ApprovalDecision

UNION ALL

SELECT
    'Signature',
    COUNT(*)
FROM Signature

UNION ALL

SELECT
    'AuditLog',
    COUNT(*)
FROM AuditLog;


-- ------------------------------------------------------------
-- 7. Verify representative document/version history survived
-- ------------------------------------------------------------

SELECT
    d.DocumentID,
    d.Title,
    dv.VersionNumber,
    rd.Code AS VersionStatus
FROM Document d
JOIN DocumentVersion dv
    ON dv.DocumentID = d.DocumentID
JOIN ReferenceData rd
    ON rd.ReferenceDataID =
       dv.CurrentVersionStatusID
WHERE d.Title =
    'Master Services Agreement'
ORDER BY dv.VersionNumber;


-- ------------------------------------------------------------
-- 8. Verify approval history survived
-- ------------------------------------------------------------

SELECT
    d.Title,
    dv.VersionNumber,
    CONCAT(
    u.FirstName,
    ' ',
    u.LastName
    ) AS Approver,
    decision.Code AS Decision
FROM ApprovalDecision ad
JOIN WorkflowParticipant wp
    ON wp.WorkflowParticipantID =
       ad.WorkflowParticipantID
JOIN User u
    ON u.UserID = wp.UserID
JOIN WorkflowStep ws
    ON ws.WorkflowStepID =
       wp.WorkflowStepID
JOIN Workflow w
    ON w.WorkflowID =
       ws.WorkflowID
JOIN DocumentVersion dv
    ON dv.DocumentVersionID =
       w.DocumentVersionID
JOIN Document d
    ON d.DocumentID =
       dv.DocumentID
JOIN ReferenceData decision
    ON decision.ReferenceDataID =
       ad.DecisionVersionID
WHERE d.Title =
    'Master Services Agreement'
ORDER BY dv.VersionNumber;


-- ------------------------------------------------------------
-- 9. Verify signature history survived
-- ------------------------------------------------------------

SELECT
    d.Title,
    dv.VersionNumber,
    CONCAT(
    u.FirstName,
    ' ',
    u.LastName
    ) AS Signer,
    status.Code AS SignatureStatus,
    s.SignatureMethod
FROM Signature s
JOIN WorkflowParticipant wp
    ON wp.WorkflowParticipantID =
       s.WorkflowParticipantID
JOIN User u
    ON u.UserID = wp.UserID
JOIN DocumentVersion dv
    ON dv.DocumentVersionID =
       s.DocumentVersionID
JOIN Document d
    ON d.DocumentID =
       dv.DocumentID
JOIN ReferenceData status
    ON status.ReferenceDataID =
       s.SignatureStatusID
WHERE d.Title =
    'Master Services Agreement'
ORDER BY dv.VersionNumber;


SELECT
    'V2 UPGRADE VERIFIED: '
    'schema changed and existing business data remains.'
    AS Result;