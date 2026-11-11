-- ============================================================
-- Demo: v1 -> v2 Upgrade
-- Phase 1: Pre-upgrade baseline
--
-- Run against schema version 1.1.0 BEFORE applying v1.2.0.
--
-- Purpose:
--   Capture representative business data that must survive
--   the upgrade.
-- ============================================================


SELECT
    '=== V1 PRE-UPGRADE BASELINE ==='
    AS DemoPhase;


-- ------------------------------------------------------------
-- 1. Current build/schema version
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
-- 2. Business-data row counts
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
-- 3. Representative document/version history
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
-- 4. Representative approval history
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
       ad.DecisionValueID
WHERE d.Title =
    'Master Services Agreement'
ORDER BY dv.VersionNumber;


-- ------------------------------------------------------------
-- 5. Representative signature history
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
    'V1 PRE-UPGRADE BASELINE COMPLETE'
    AS Result;