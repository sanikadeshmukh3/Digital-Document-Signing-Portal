-- ============================================================
-- File: database/01_schema/060_workflow_transition_metadata.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Define metadata describing valid Workflow status transitions
--   and the business roles authorized to request them.
--
-- Database: MySQL 8.x
-- ============================================================


CREATE TABLE WorkflowStatusTransition (
    WorkflowStatusTransitionID BIGINT UNSIGNED
        AUTO_INCREMENT PRIMARY KEY,

    TransitionCode VARCHAR(100) NOT NULL,

    FromStatusID BIGINT UNSIGNED NOT NULL,

    ToStatusID BIGINT UNSIGNED NOT NULL,

    IsActive BOOLEAN NOT NULL DEFAULT TRUE,

    SystemAllowedFlag BOOLEAN NOT NULL DEFAULT FALSE,

    Description VARCHAR(500) NULL,


    CONSTRAINT uq_WorkflowStatusTransition_Code
        UNIQUE (TransitionCode),

    CONSTRAINT uq_WorkflowStatusTransition_StatePair
        UNIQUE (FromStatusID, ToStatusID),

    CONSTRAINT chk_WorkflowStatusTransition_DifferentStates
        CHECK (FromStatusID <> ToStatusID),


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


CREATE TABLE WorkflowTransitionRole (
    WorkflowStatusTransitionID BIGINT UNSIGNED NOT NULL,

    RoleID BIGINT UNSIGNED NOT NULL,

    AllowedFlag BOOLEAN NOT NULL DEFAULT TRUE,


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