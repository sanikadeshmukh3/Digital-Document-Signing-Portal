-- ============================================================
-- File: database/04_seed/030_workflow_transition_metadata.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Seed valid workflow status transitions and the business-role
--   permissions associated with human-requested transitions.
--
-- Principle:
--   Workflow lifecycle behavior is represented as metadata so
--   runtime clients ask the database which transitions are allowed
--   rather than hard-coding lifecycle rules in application code.
--
-- Notes:
--   - Workflow states come from ReferenceData / WORKFLOW_STATUS.
--   - Business roles come from Role.
--   - SystemAllowedFlag is used for internally driven transitions
--     such as completion and expiration.
--   - This file seeds metadata only; it does not modify business
--     workflow instances.
--
-- Database: MySQL 8.x
-- ============================================================

START TRANSACTION;


-- ============================================================
-- 1. Valid workflow lifecycle transitions
-- ============================================================

INSERT INTO WorkflowStatusTransition (
    TransitionCode,
    FromStatusID,
    ToStatusID,
    IsActive,
    SystemAllowedFlag,
    Description
)

-- DRAFT -> ACTIVE
SELECT
    'ACTIVATE_WORKFLOW',
    from_status.ReferenceDataID,
    to_status.ReferenceDataID,
    TRUE,
    FALSE,
    'Activate a configured draft workflow.'
FROM ReferenceData from_status
JOIN ReferenceData to_status
WHERE from_status.DomainName = 'WORKFLOW_STATUS'
  AND from_status.Code = 'DRAFT'
  AND to_status.DomainName = 'WORKFLOW_STATUS'
  AND to_status.Code = 'ACTIVE'

UNION ALL

-- ACTIVE -> COMPLETED
SELECT
    'COMPLETE_WORKFLOW',
    from_status.ReferenceDataID,
    to_status.ReferenceDataID,
    TRUE,
    TRUE,
    'Complete an active workflow after all required work has finished.'
FROM ReferenceData from_status
JOIN ReferenceData to_status
WHERE from_status.DomainName = 'WORKFLOW_STATUS'
  AND from_status.Code = 'ACTIVE'
  AND to_status.DomainName = 'WORKFLOW_STATUS'
  AND to_status.Code = 'COMPLETED'

UNION ALL

-- ACTIVE -> REJECTED
SELECT
    'REJECT_WORKFLOW',
    from_status.ReferenceDataID,
    to_status.ReferenceDataID,
    TRUE,
    FALSE,
    'Terminate an active workflow because an approval was rejected.'
FROM ReferenceData from_status
JOIN ReferenceData to_status
WHERE from_status.DomainName = 'WORKFLOW_STATUS'
  AND from_status.Code = 'ACTIVE'
  AND to_status.DomainName = 'WORKFLOW_STATUS'
  AND to_status.Code = 'REJECTED'

UNION ALL

-- ACTIVE -> CANCELLED
SELECT
    'CANCEL_WORKFLOW',
    from_status.ReferenceDataID,
    to_status.ReferenceDataID,
    TRUE,
    FALSE,
    'Cancel an active workflow before normal completion.'
FROM ReferenceData from_status
JOIN ReferenceData to_status
WHERE from_status.DomainName = 'WORKFLOW_STATUS'
  AND from_status.Code = 'ACTIVE'
  AND to_status.DomainName = 'WORKFLOW_STATUS'
  AND to_status.Code = 'CANCELLED'

UNION ALL

-- ACTIVE -> EXPIRED
SELECT
    'EXPIRE_WORKFLOW',
    from_status.ReferenceDataID,
    to_status.ReferenceDataID,
    TRUE,
    TRUE,
    'Expire an active workflow after its configured expiration time.'
FROM ReferenceData from_status
JOIN ReferenceData to_status
WHERE from_status.DomainName = 'WORKFLOW_STATUS'
  AND from_status.Code = 'ACTIVE'
  AND to_status.DomainName = 'WORKFLOW_STATUS'
  AND to_status.Code = 'EXPIRED';


-- ============================================================
-- 2. Human role permissions
-- ============================================================

-- ------------------------------------------------------------
-- ACTIVATE_WORKFLOW -> Document Owner
-- ------------------------------------------------------------

INSERT INTO WorkflowTransitionRole (
    WorkflowStatusTransitionID,
    RoleID,
    AllowedFlag
)
SELECT
    wt.WorkflowStatusTransitionID,
    r.RoleID,
    TRUE
FROM WorkflowStatusTransition wt
JOIN Role r
    ON r.RoleName = 'Document Owner'
WHERE wt.TransitionCode = 'ACTIVATE_WORKFLOW';


-- ------------------------------------------------------------
-- REJECT_WORKFLOW -> Approver
-- ------------------------------------------------------------

INSERT INTO WorkflowTransitionRole (
    WorkflowStatusTransitionID,
    RoleID,
    AllowedFlag
)
SELECT
    wt.WorkflowStatusTransitionID,
    r.RoleID,
    TRUE
FROM WorkflowStatusTransition wt
JOIN Role r
    ON r.RoleName = 'Approver'
WHERE wt.TransitionCode = 'REJECT_WORKFLOW';


-- ------------------------------------------------------------
-- CANCEL_WORKFLOW -> Document Owner
-- ------------------------------------------------------------

INSERT INTO WorkflowTransitionRole (
    WorkflowStatusTransitionID,
    RoleID,
    AllowedFlag
)
SELECT
    wt.WorkflowStatusTransitionID,
    r.RoleID,
    TRUE
FROM WorkflowStatusTransition wt
JOIN Role r
    ON r.RoleName = 'Document Owner'
WHERE wt.TransitionCode = 'CANCEL_WORKFLOW';

-- ------------------------------------------------------------
-- CANCEL_WORKFLOW -> System Administrator
-- ------------------------------------------------------------

INSERT INTO WorkflowTransitionRole (
    WorkflowStatusTransitionID,
    RoleID,
    AllowedFlag
)
SELECT
    wt.WorkflowStatusTransitionID,
    r.RoleID,
    TRUE
FROM WorkflowStatusTransition wt
JOIN Role r
    ON r.RoleName = 'System Administrator'
WHERE wt.TransitionCode = 'CANCEL_WORKFLOW';

-- ------------------------------------------------------------
-- EXPIRE_WORKFLOW -> System Administrator
-- ------------------------------------------------------------

INSERT INTO WorkflowTransitionRole (
    WorkflowStatusTransitionID,
    RoleID,
    AllowedFlag
)
SELECT
    wt.WorkflowStatusTransitionID,
    r.RoleID,
    TRUE
FROM WorkflowStatusTransition wt
JOIN Role r
    ON r.RoleName = 'System Administrator'
WHERE wt.TransitionCode = 'EXPIRE_WORKFLOW';

COMMIT;