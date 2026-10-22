-- ============================================================
-- File: database/01_schema/010_reference_tables.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Create controlled reference data structures used to restrict
--   statuses, types, classifications, decision values, and other
--   predefined domains throughout the database.
--
-- TDD Basis:
--   ReferenceData
--
-- Notes:
--   - Actual reference values are loaded later in:
--       database/04_seed/010_reference_data.sql
--   - Foreign keys from business tables to ReferenceData are
--       added later in:
--       database/01_schema/040_constraints_indexes.sql
-- ============================================================


-- ------------------------------------------------------------
-- ReferenceData
-- ------------------------------------------------------------
-- Stores controlled values for domains including:
--
--   ACCOUNT_STATUS
--   DOCUMENT_STATUS
--   DOCUMENT_CLASSIFICATION
--   WORKFLOW_STATUS
--   WORKFLOW_PURPOSE_TYPE
--   STEP_TYPE
--   STEP_STATUS
--   PARTICIPANT_STATUS
--   ASSIGNED_ACTION
--   APPROVAL_DECISION
--   SIGNATURE_STATUS
--
-- A generalized table is used instead of creating a separate
-- lookup table for every domain.
-- ------------------------------------------------------------

CREATE TABLE ReferenceData (
    ReferenceDataID BIGINT UNSIGNED AUTO_INCREMENT,

    DomainName VARCHAR(50) NOT NULL,

    Code VARCHAR(50) NOT NULL,

    DisplayName VARCHAR(100) NOT NULL,

    Description VARCHAR(255) NULL,

    IsActive BOOLEAN NOT NULL DEFAULT TRUE,

    CreatedDateTime DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UpdatedDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_ReferenceData
        PRIMARY KEY (ReferenceDataID),

    CONSTRAINT uq_ReferenceData_Domain_Code
        UNIQUE (DomainName, Code),

    CONSTRAINT chk_ReferenceData_DomainName_NotBlank
        CHECK (TRIM(DomainName) <> ''),

    CONSTRAINT chk_ReferenceData_Code_NotBlank
        CHECK (TRIM(Code) <> ''),

    CONSTRAINT chk_ReferenceData_DisplayName_NotBlank
        CHECK (TRIM(DisplayName) <> '')
);