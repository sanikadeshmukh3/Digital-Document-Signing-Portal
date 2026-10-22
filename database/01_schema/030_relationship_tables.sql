-- ============================================================
-- File: database/01_schema/030_relationship_tables.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Create relationship and workflow-action tables defined in
--   the TDD.
--
-- Entities:
--   UserRole
--   WorkflowParticipant
--   ApprovalDecision
--   Signature
--
-- Notes:
--   - Foreign-key constraints are added later in:
--       database/01_schema/040_constraints_indexes.sql
--   - Reference-data values are loaded later in:
--       database/04_seed/010_reference_data.sql
-- ============================================================


-- ============================================================
-- UserRole
-- ============================================================
-- Resolves the many-to-many relationship between User and Role.
--
-- TDD attributes:
--   UserID
--   RoleID
--
-- Integrity rule:
--   The same User/Role combination may not appear more than once.
-- ============================================================

CREATE TABLE UserRole (
    UserID BIGINT UNSIGNED NOT NULL,

    RoleID BIGINT UNSIGNED NOT NULL,

    AssignedDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_UserRole
        PRIMARY KEY (UserID, RoleID)
);


-- ============================================================
-- WorkflowParticipant
-- ============================================================
-- Represents the assignment of a User to a specific
-- WorkflowStep.
--
-- TDD attributes:
--   WorkflowParticipantID
--   WorkflowStepID
--   UserID
--   RoleID
--   AssignedAction
--   AssignmentStatus
--   RequiredFlag
--   ActivationDateTime
--   CompletionDateTime
--   DueDateTime
--
-- Review and acknowledgement completion are represented through
-- this entity rather than through a separate action table.
-- ============================================================

CREATE TABLE WorkflowParticipant (
    WorkflowParticipantID BIGINT UNSIGNED AUTO_INCREMENT,

    WorkflowStepID BIGINT UNSIGNED NOT NULL,

    UserID BIGINT UNSIGNED NOT NULL,

    RoleID BIGINT UNSIGNED NOT NULL,

    -- Implements TDD attribute: AssignedAction.
    -- References ASSIGNED_ACTION reference data.
    AssignedActionID BIGINT UNSIGNED NOT NULL,

    -- Implements TDD attribute: AssignmentStatus.
    -- References PARTICIPANT_STATUS reference data.
    AssignmentStatusID BIGINT UNSIGNED NOT NULL,

    RequiredFlag BOOLEAN NOT NULL DEFAULT TRUE,

    ActivationDateTime DATETIME NULL,

    CompletionDateTime DATETIME NULL,

    DueDateTime DATETIME NULL,

    CONSTRAINT pk_WorkflowParticipant
        PRIMARY KEY (WorkflowParticipantID),

    CONSTRAINT uq_WorkflowParticipant_Assignment
        UNIQUE (
            WorkflowStepID,
            UserID,
            AssignedActionID
        ),

    CONSTRAINT chk_WorkflowParticipant_Completion
        CHECK (
            CompletionDateTime IS NULL
            OR ActivationDateTime IS NULL
            OR CompletionDateTime >= ActivationDateTime
        ),

    CONSTRAINT chk_WorkflowParticipant_DueDate
        CHECK (
            DueDateTime IS NULL
            OR ActivationDateTime IS NULL
            OR DueDateTime >= ActivationDateTime
        )
);


-- ============================================================
-- ApprovalDecision
-- ============================================================
-- Stores a formal approval/rejection decision made by an
-- eligible WorkflowParticipant.
--
-- TDD attributes:
--   ApprovalID
--   WorkflowParticipantID
--   DecisionValue
--   DecisionDateTime
--   Comments
--   RejectionReason
--
-- Each approval assignment may result in at most one
-- ApprovalDecision.
-- ============================================================

CREATE TABLE ApprovalDecision (
    ApprovalID BIGINT UNSIGNED AUTO_INCREMENT,

    WorkflowParticipantID BIGINT UNSIGNED NOT NULL,

    -- Implements TDD attribute: DecisionValue.
    -- References APPROVAL_DECISION reference data.
    DecisionValueID BIGINT UNSIGNED NOT NULL,

    DecisionDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    Comments TEXT NULL,

    RejectionReason VARCHAR(500) NULL,

    CONSTRAINT pk_ApprovalDecision
        PRIMARY KEY (ApprovalID),

    CONSTRAINT uq_ApprovalDecision_WorkflowParticipant
        UNIQUE (WorkflowParticipantID)
);


-- ============================================================
-- Signature
-- ============================================================
-- Stores the simulated electronic-signature record.
--
-- TDD attributes:
--   SignatureID
--   WorkflowParticipantID
--   DocumentVersionID
--   SigningDateTime
--   SignatureStatus
--   SignatureMethod
--   SignatureReference
--
-- Each signature assignment may result in at most one Signature.
-- ============================================================

CREATE TABLE Signature (
    SignatureID BIGINT UNSIGNED AUTO_INCREMENT,

    WorkflowParticipantID BIGINT UNSIGNED NOT NULL,

    DocumentVersionID BIGINT UNSIGNED NOT NULL,

    SigningDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    -- Implements TDD attribute: SignatureStatus.
    -- References SIGNATURE_STATUS reference data.
    SignatureStatusID BIGINT UNSIGNED NOT NULL,

    SignatureMethod VARCHAR(100) NOT NULL,

    SignatureReference VARCHAR(255) NULL,

    CONSTRAINT pk_Signature
        PRIMARY KEY (SignatureID),

    CONSTRAINT uq_Signature_WorkflowParticipant
        UNIQUE (WorkflowParticipantID),

    CONSTRAINT chk_Signature_Method_NotBlank
        CHECK (TRIM(SignatureMethod) <> '')
);