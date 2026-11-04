-- ============================================================
-- File: database/01_schema/005_versioning_tables.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Store database build/version metadata and schema migration
--   history.
--
--   DatabaseBuild:
--     Identifies each attempted database release/build.
--
--   SchemaMigration:
--     Records each schema migration that has successfully been
--     applied so that the same migration is not applied twice.
--
-- Database: MySQL 8.x
-- ============================================================


-- ------------------------------------------------------------
-- DatabaseBuild
-- ------------------------------------------------------------
-- One row represents one database build / upgrade attempt.
--
-- ReleaseTag and CommitSHA identify the exact repository source.
-- SchemaVersion identifies the resulting database schema version.
-- ------------------------------------------------------------

CREATE TABLE DatabaseBuild (
    BuildID BIGINT AUTO_INCREMENT PRIMARY KEY,

    SchemaVersion VARCHAR(30) NOT NULL, 
    ReleaseTag VARCHAR(100) NOT NULL,
    CommitSHA VARCHAR(64) NOT NULL,

    BuildStatus VARCHAR(20) NOT NULL,

    BuildStartedDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    BuildCompletedDateTime DATETIME NULL,

    MySQLVersion VARCHAR(100) NULL,

    CONSTRAINT chk_DatabaseBuild_Status
        CHECK (
            BuildStatus IN (
                'STARTED',
                'COMPLETED',
                'FAILED'
            )
        )
);


-- ------------------------------------------------------------
-- SchemaMigration
-- ------------------------------------------------------------
-- One row represents one successfully applied schema migration.
--
-- VersionNumber is unique so that a migration cannot be recorded
-- twice.
--
-- ScriptChecksum stores the SHA-256 checksum of the migration
-- file. If a migration has already been applied but its current
-- checksum differs, the build should fail rather than silently
-- executing a modified migration.
-- ------------------------------------------------------------

CREATE TABLE SchemaMigration (
    MigrationID BIGINT AUTO_INCREMENT PRIMARY KEY,

    VersionNumber VARCHAR(30) NOT NULL,
    MigrationName VARCHAR(255) NOT NULL,
    ScriptName VARCHAR(255) NOT NULL,

    ScriptChecksum CHAR(64) NOT NULL,

    AppliedDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    BuildID BIGINT NOT NULL,

    CONSTRAINT uq_SchemaMigration_Version
        UNIQUE (VersionNumber),

    CONSTRAINT uq_SchemaMigration_Script
        UNIQUE (ScriptName),

    CONSTRAINT fk_SchemaMigration_DatabaseBuild
        FOREIGN KEY (BuildID)
        REFERENCES DatabaseBuild(BuildID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
);