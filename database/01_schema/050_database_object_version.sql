-- ============================================================
-- File: database/01_schema/050_database_object_version.sql
-- Project: Document Workflow and E-signing Portal
--
-- Migration: 014
-- Schema Version: 1.2.0
--
-- Purpose:
--   Add database-object version stamps so individual views,
--   functions, procedures, and triggers can report their
--   current implementation version independently from the
--   overall schema version.
--
--   This migration is intentionally additive so that existing
--   business data survives the v1 -> v2 upgrade.
-- ============================================================

CREATE TABLE DatabaseObjectVersion (
    DatabaseObjectVersionID BIGINT AUTO_INCREMENT PRIMARY KEY,

    ObjectType VARCHAR(20) NOT NULL,
    ObjectName VARCHAR(128) NOT NULL,

    ObjectVersion VARCHAR(30) NOT NULL,

    StampedSchemaVersion VARCHAR(30) NOT NULL,
    StampMigrationVersion VARCHAR(30) NOT NULL,

    LastStampedDateTime DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_DatabaseObjectVersion_Object
        UNIQUE (
            ObjectType,
            ObjectName
        ),

    CONSTRAINT chk_DatabaseObjectVersion_Type
        CHECK (
            ObjectType IN (
                'VIEW',
                'FUNCTION',
                'PROCEDURE',
                'TRIGGER'
            )
        )
);