-- ============================================================
-- File: database/01_schema/020_core_tables.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Create the primary business entities defined in the TDD.
--
-- Core entities:
--   User
--   Role
--   Document
--   DocumentVersion
--   Workflow
--   WorkflowStep
--   AuditLog
--
-- Notes:
--   - Reference-data foreign keys are added later in
--     040_constraints_indexes.sql.
--   - Relationship/action tables are created in
--     030_relationship_tables.sql.
-- ============================================================


-- ============================================================
-- User
-- ============================================================
-- TDD attributes:
--   UserID
--   FirstName
--   LastName
--   Email
--   OrganizationalAffiliation
--   AccountStatus
--   CreatedDateTime
--   UpdatedDateTime
-- ============================================================

CREATE TABLE `User` (
    UserID BIGINT UNSIGNED AUTO_INCREMENT,

    FirstName VARCHAR(100) NOT NULL,

    LastName VARCHAR(100) NOT NULL,

    Email VARCHAR(255) NOT NULL,

    OrganizationalAffiliation VARCHAR(255) NULL,

    -- Implements TDD attribute: AccountStatus
    -- References ReferenceData domain ACCOUNT_STATUS.
    AccountStatusID BIGINT UNSIGNED NOT NULL,

    CreatedDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    UpdatedDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_User
        PRIMARY KEY (UserID),

    CONSTRAINT uq_User_Email
        UNIQUE (Email),

    CONSTRAINT chk_User_FirstName_NotBlank
        CHECK (TRIM(FirstName) <> ''),

    CONSTRAINT chk_User_LastName_NotBlank
        CHECK (TRIM(LastName) <> ''),

    CONSTRAINT chk_User_Email_NotBlank
        CHECK (TRIM(Email) <> '')
);


-- ============================================================
-- Role
-- ============================================================
-- TDD attributes:
--   RoleID
--   RoleName
--   Description
--   ActiveStatus
--   ResponsibilityCategory
--
-- Examples:
--   Document Owner
--   Reviewer
--   Approver
--   Signer
--   Workflow Manager
--   System Administrator
--   Auditor
-- ============================================================

CREATE TABLE Role (
    RoleID BIGINT UNSIGNED AUTO_INCREMENT,

    RoleName VARCHAR(100) NOT NULL,

    Description VARCHAR(255) NULL,

    ActiveStatus BOOLEAN NOT NULL DEFAULT TRUE,

    ResponsibilityCategory VARCHAR(100) NOT NULL,

    CONSTRAINT pk_Role
        PRIMARY KEY (RoleID),

    CONSTRAINT uq_Role_RoleName
        UNIQUE (RoleName),

    CONSTRAINT chk_Role_RoleName_NotBlank
        CHECK (TRIM(RoleName) <> ''),

    CONSTRAINT chk_Role_ResponsibilityCategory_NotBlank
        CHECK (TRIM(ResponsibilityCategory) <> '')
);


-- ============================================================
-- Document
-- ============================================================
-- TDD attributes:
--   DocumentID
--   Title
--   BusinessDescription
--   OwnerUserID
--   Classification
--   LifecycleStatus
--   CreatedDateTime
--   UpdatedDateTime
-- ============================================================

CREATE TABLE Document (
    DocumentID BIGINT UNSIGNED AUTO_INCREMENT,

    Title VARCHAR(255) NOT NULL,

    BusinessDescription TEXT NULL,

    OwnerUserID BIGINT UNSIGNED NOT NULL,

    -- Implements TDD attribute: Classification.
    -- References ReferenceData domain DOCUMENT_CLASSIFICATION.
    ClassificationID BIGINT UNSIGNED NOT NULL,

    -- Implements TDD attribute: LifecycleStatus.
    -- References ReferenceData domain DOCUMENT_STATUS.
    LifecycleStatusID BIGINT UNSIGNED NOT NULL,

    CreatedDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    UpdatedDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_Document
        PRIMARY KEY (DocumentID),

    CONSTRAINT chk_Document_Title_NotBlank
        CHECK (TRIM(Title) <> '')
);


-- ============================================================
-- DocumentVersion
-- ============================================================
-- TDD attributes:
--   DocumentVersionID
--   DocumentID
--   VersionNumber
--   EffectiveInformation
--   CreatedDateTime
--   CreatedByUserID
--   CurrentVersionStatus
--   LockedDateTime
--
-- Important rule:
--   VersionNumber must be unique within a Document.
-- ============================================================

// weak entity: DocumentVersion is a weak entity whose existence depends on the owning Document.
CREATE TABLE DocumentVersion (
    DocumentVersionID BIGINT UNSIGNED AUTO_INCREMENT,

    DocumentID BIGINT UNSIGNED NOT NULL,

    VersionNumber INT UNSIGNED NOT NULL,

    EffectiveInformation TEXT NULL,

    CreatedDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CreatedByUserID BIGINT UNSIGNED NOT NULL,

    CurrentVersionStatusID BIGINT UNSIGNED NOT NULL,

    LockedDateTime DATETIME NULL,

    -- DocumentVersion is modeled as a weak entity.
    -- VersionNumber is a partial key whose meaning depends on
    -- the owning Document.
    CONSTRAINT pk_DocumentVersion
        PRIMARY KEY (DocumentID, VersionNumber),

    -- Retain the TDD-defined technical identifier as an
    -- alternate unique identifier.
    CONSTRAINT uq_DocumentVersion_ID
        UNIQUE (DocumentVersionID),

    CONSTRAINT chk_DocumentVersion_VersionNumber
        CHECK (VersionNumber > 0)
);


-- ============================================================
-- Workflow
-- ============================================================
-- TDD attributes:
--   WorkflowID
--   DocumentID
--   DocumentVersionID
--   InitiatorUserID
--   WorkflowPurposeType
--   WorkflowStatus
--   StartDateTime
--   CompletionDateTime
--   CancellationDateTime
--   CancellationReason
--   ExpirationDateTime
-- ============================================================

CREATE TABLE Workflow (
    WorkflowID BIGINT UNSIGNED AUTO_INCREMENT,

    DocumentID BIGINT UNSIGNED NOT NULL,

    DocumentVersionID BIGINT UNSIGNED NOT NULL,

    InitiatorUserID BIGINT UNSIGNED NOT NULL,

    -- Implements TDD attribute: WorkflowPurposeType.
    -- References WORKFLOW_PURPOSE_TYPE reference data.
    WorkflowPurposeTypeID BIGINT UNSIGNED NOT NULL,

    -- Implements TDD attribute: WorkflowStatus.
    -- References WORKFLOW_STATUS reference data.
    WorkflowStatusID BIGINT UNSIGNED NOT NULL,

    StartDateTime DATETIME NULL,

    CompletionDateTime DATETIME NULL,

    CancellationDateTime DATETIME NULL,

    CancellationReason VARCHAR(500) NULL,

    ExpirationDateTime DATETIME NULL,

    CONSTRAINT pk_Workflow
        PRIMARY KEY (WorkflowID),

    CONSTRAINT chk_Workflow_Expiration
        CHECK (
            ExpirationDateTime IS NULL
            OR StartDateTime IS NULL
            OR ExpirationDateTime >= StartDateTime
        ),

    CONSTRAINT chk_Workflow_Completion
        CHECK (
            CompletionDateTime IS NULL
            OR StartDateTime IS NULL
            OR CompletionDateTime >= StartDateTime
        )
);


-- ============================================================
-- WorkflowStep
-- ============================================================
-- TDD attributes:
--   WorkflowStepID
--   WorkflowID
--   SequenceNumber
--   StepType
--   RequiredPolicy
--   StepStatus
--   ActivationDateTime
--   CompletionDateTime
--   DueDateTime
--
-- Multiple steps MAY share a SequenceNumber.
-- This is necessary for parallel workflow execution.
-- ============================================================

CREATE TABLE WorkflowStep (
    WorkflowStepID BIGINT UNSIGNED AUTO_INCREMENT,

    WorkflowID BIGINT UNSIGNED NOT NULL,

    SequenceNumber INT UNSIGNED NOT NULL,

    -- Implements TDD attribute: StepType.
    -- References STEP_TYPE reference data.
    StepTypeID BIGINT UNSIGNED NOT NULL,

    -- Initial release uses ALL_REQUIRED.
    RequiredPolicy VARCHAR(30) NOT NULL
        DEFAULT 'ALL_REQUIRED',

    -- Implements TDD attribute: StepStatus.
    -- References STEP_STATUS reference data.
    StepStatusID BIGINT UNSIGNED NOT NULL,

    ActivationDateTime DATETIME NULL,

    CompletionDateTime DATETIME NULL,

    DueDateTime DATETIME NULL,

    CONSTRAINT pk_WorkflowStep
        PRIMARY KEY (WorkflowStepID),

    CONSTRAINT chk_WorkflowStep_SequenceNumber
        CHECK (SequenceNumber > 0),

    CONSTRAINT chk_WorkflowStep_RequiredPolicy
        CHECK (RequiredPolicy = 'ALL_REQUIRED'),

    CONSTRAINT chk_WorkflowStep_Completion
        CHECK (
            CompletionDateTime IS NULL
            OR ActivationDateTime IS NULL
            OR CompletionDateTime >= ActivationDateTime
        ),

    CONSTRAINT chk_WorkflowStep_DueDate
        CHECK (
            DueDateTime IS NULL
            OR ActivationDateTime IS NULL
            OR DueDateTime >= ActivationDateTime
        )
);


-- ============================================================
-- AuditLog
-- ============================================================
-- TDD attributes:
--   AuditLogID
--   ActorUserID
--   EventDateTime
--   EventType
--   AffectedRecordType
--   AffectedRecordID
--   TransactionReference
--   PriorValueContext
--   NewValueContext
--   ChangeReason
--
-- AuditLog will later be protected from UPDATE and DELETE.
-- ============================================================

CREATE TABLE AuditLog (
    AuditLogID BIGINT UNSIGNED AUTO_INCREMENT,

    ActorUserID BIGINT UNSIGNED NULL,

    EventDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    EventType VARCHAR(100) NOT NULL,

    AffectedRecordType VARCHAR(100) NOT NULL,

    AffectedRecordID BIGINT UNSIGNED NULL,

    TransactionReference VARCHAR(100) NULL,

    PriorValueContext TEXT NULL,

    NewValueContext TEXT NULL,

    ChangeReason VARCHAR(500) NULL,

    CONSTRAINT pk_AuditLog
        PRIMARY KEY (AuditLogID),

    CONSTRAINT chk_AuditLog_EventType_NotBlank
        CHECK (TRIM(EventType) <> ''),

    CONSTRAINT chk_AuditLog_AffectedRecordType_NotBlank
        CHECK (TRIM(AffectedRecordType) <> '')
);