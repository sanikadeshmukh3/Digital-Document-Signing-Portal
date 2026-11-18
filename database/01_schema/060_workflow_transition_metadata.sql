-- ============================================================
-- File: database/01_schema/060_workflow_transition_metadata.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Introduce metadata-driven workflow lifecycle enforcement.
--
-- Tables:
--   WorkflowStatusTransition
--   WorkflowTransitionRole
--
-- Principle:
--   Valid workflow state changes and the roles authorized to
--   request them are represented as data rather than being
--   defined only inside application or stored-procedure code.
--
-- Database: MySQL 8.x
-- ============================================================


-- ============================================================
-- 1. WorkflowStatusTransition
-- ============================================================
-- Defines each valid transition between workflow states.
--
-- Example:
--   DRAFT -> ACTIVE
--   ACTIVE -> COMPLETED
--
-- FromStatusID and ToStatusID reference ReferenceData rows in
-- the WORKFLOW_STATUS domain.
--
-- SystemAllowedFlag identifies transitions that may be performed
-- internally by trusted database workflow logic rather than by
-- an end-user role.
-- ============================================================

CREATE TABLE WorkflowStatusTransition (
    WorkflowStatusTransitionID BIGINT AUTO_INCREMENT PRIMARY KEY,

    TransitionCode VARCHAR(100) NOT NULL,

    FromStatusID BIGINT NOT NULL,
    ToStatusID BIGINT NOT NULL,

    IsActive BOOLEAN NOT NULL
        DEFAULT TRUE,

    SystemAllowedFlag BOOLEAN NOT NULL
        DEFAULT FALSE,

    Description VARCHAR(500) NULL,

    CONSTRAINT uq_WorkflowStatusTransition_Code
        UNIQUE (TransitionCode),

    CONSTRAINT uq_WorkflowStatusTransition_StatePair
        UNIQUE (
            FromStatusID,
            ToStatusID
        ),

    CONSTRAINT chk_WorkflowStatusTransition_DifferentStates
        CHECK (
            FromStatusID <> ToStatusID
        ),

    CONSTRAINT fk_WorkflowStatusTransition_FromStatus
        FOREIGN KEY (FromStatusID)
        REFERENCES ReferenceData(ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_WorkflowStatusTransition_ToStatus
        FOREIGN KEY (ToStatusID)
        REFERENCES ReferenceData(ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
);


-- ============================================================
-- 2. WorkflowTransitionRole
-- ============================================================
-- Maps a workflow transition to the business roles allowed to
-- request that transition.
--
-- Example:
--
--   ACTIVATE_WORKFLOW
--       -> Document Owner
--
--   CANCEL_WORKFLOW
--       -> Document Owner
--
-- This table does not store user authorization directly.
-- A user's current permissions will later be resolved through:
--
--   User
--      -> UserRole
--      -> Role
--      -> WorkflowTransitionRole
--
-- This prevents the application from supplying its own claimed
-- role when requesting a state transition.
-- ============================================================

CREATE TABLE WorkflowTransitionRole (
    WorkflowStatusTransitionID BIGINT NOT NULL,
    RoleID BIGINT NOT NULL,

    AllowedFlag BOOLEAN NOT NULL
        DEFAULT TRUE,

    PRIMARY KEY (
        WorkflowStatusTransitionID,
        RoleID
    ),

    CONSTRAINT fk_WorkflowTransitionRole_Transition
        FOREIGN KEY (WorkflowStatusTransitionID)
        REFERENCES WorkflowStatusTransition(
            WorkflowStatusTransitionID
        )
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_WorkflowTransitionRole_Role
        FOREIGN KEY (RoleID)
        REFERENCES Role(RoleID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
);