-- ============================================================
-- File: database/01_schema/080_indicator_value_schema.sql
-- Project: Document Workflow and E-signing Portal
--
-- Migration: 026
-- Schema Version: 1.4.0 - Principle 11 (Indicator Value pattern)
--
-- Purpose:
--   Make ReferenceData a complete Indicator Value table and
--   remove the coded domains that were hard-coded in CHECK
--   constraints.
--
--   Indicator Value concept   ReferenceData column
--   -----------------------   --------------------
--   indicator name            DomainName
--   value                     Code         (stable; code may rely on it)
--   description               DisplayName  (label; free to change)
--   display order             DisplayOrder <-- added here
--
-- Changes:
--   1. ReferenceData.DisplayOrder (list-of-values order).
--   2. DROP CHECK chk_WorkflowStep_RequiredPolicy
--        was: RequiredPolicy = 'ALL_REQUIRED'
--   3. DROP CHECK chk_DatabaseBuild_Status
--        was: BuildStatus IN ('STARTED','COMPLETED','FAILED')
--   4. DROP CHECK chk_DatabaseObjectVersion_Type
--        was: ObjectType IN ('VIEW','FUNCTION','PROCEDURE','TRIGGER')
--
--   Those domains move into ReferenceData (REQUIRED_POLICY,
--   BUILD_STATUS, DATABASE_OBJECT_TYPE) in
--   04_seed/040_indicator_value_seed.sql, and membership is
--   enforced by the triggers in
--   02_programability/120_indicator_value_programmability.sql.
--   Adding a legal value becomes one INSERT, not an ALTER TABLE.
--
-- Why a new migration instead of editing 01_schema/010..070:
--   Those scripts are already recorded (with checksums) in
--   SchemaMigration on existing databases. Editing them would
--   make ALLOW_DATABASE_UPGRADE refuse to upgrade a v1.x
--   database (see 06_demo_tests/090_v1_to_v2_*).
--
-- Each change is guarded by an information_schema check, so a
-- re-run after a partial failure is safe.
--
-- Database: MySQL 8.0.19+ (ALTER TABLE ... DROP CHECK)
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS sp__mig_026_schema//

CREATE PROCEDURE sp__mig_026_schema()
BEGIN

    -- --------------------------------------------------------
    -- 1. ReferenceData.DisplayOrder
    -- --------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'ReferenceData'
          AND COLUMN_NAME = 'DisplayOrder'
    ) THEN
        ALTER TABLE ReferenceData
            ADD COLUMN DisplayOrder INT UNSIGNED NOT NULL DEFAULT 0
                AFTER Description;
    END IF;


    -- --------------------------------------------------------
    -- 2. WorkflowStep.RequiredPolicy -> indicator REQUIRED_POLICY
    -- --------------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND TABLE_NAME = 'WorkflowStep'
          AND CONSTRAINT_TYPE = 'CHECK'
          AND CONSTRAINT_NAME = 'chk_WorkflowStep_RequiredPolicy'
    ) THEN
        ALTER TABLE WorkflowStep
            DROP CHECK chk_WorkflowStep_RequiredPolicy;
    END IF;


    -- --------------------------------------------------------
    -- 3. DatabaseBuild.BuildStatus -> indicator BUILD_STATUS
    -- --------------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND TABLE_NAME = 'DatabaseBuild'
          AND CONSTRAINT_TYPE = 'CHECK'
          AND CONSTRAINT_NAME = 'chk_DatabaseBuild_Status'
    ) THEN
        ALTER TABLE DatabaseBuild
            DROP CHECK chk_DatabaseBuild_Status;
    END IF;


    -- --------------------------------------------------------
    -- 4. DatabaseObjectVersion.ObjectType
    --    -> indicator DATABASE_OBJECT_TYPE
    -- --------------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND TABLE_NAME = 'DatabaseObjectVersion'
          AND CONSTRAINT_TYPE = 'CHECK'
          AND CONSTRAINT_NAME = 'chk_DatabaseObjectVersion_Type'
    ) THEN
        ALTER TABLE DatabaseObjectVersion
            DROP CHECK chk_DatabaseObjectVersion_Type;
    END IF;

END//

DELIMITER ;

CALL sp__mig_026_schema();

DROP PROCEDURE sp__mig_026_schema;
