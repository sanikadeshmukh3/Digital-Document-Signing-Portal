-- ============================================================
-- File: database/02_programability/120_indicator_value_programmability.sql
-- Project: Document Workflow and E-signing Portal
--
-- Migration: 028
-- Schema Version: 1.4.0 - Principle 11 (Indicator Value pattern)
--
-- Purpose:
--   Everything reads coded domains from ReferenceData:
--
--   VALIDATION (is this value a member of its indicator?)
--     fn_is_indicator_member      code  -> TRUE/FALSE (active)
--     fn_is_indicator_id_member   ID    -> TRUE/FALSE (active)
--     sp_assert_indicator_id      raises 45000 on violation
--     sp_assert_indicator_code    raises 45000 on violation
--     trg_<Table>_IndicatorCheckInsert / _IndicatorCheckUpdate
--       BEFORE INSERT / BEFORE UPDATE on every table that holds
--       a coded column (20 columns, 12 tables, 21 triggers).
--       Closes the midterm gap: a direct SQL write can no longer
--       store a DOCUMENT_STATUS row as a WORKFLOW_STATUS.
--
--   LIST OF VALUES (one generic service for every combo box)
--     vw_IndicatorValue           indicator name/value/description/order
--     sp_get_indicator_values     active values of ONE indicator,
--                                 in DisplayOrder
--
--   REPORT DECODING (stored code -> current description,
--   anything not in the table surfaces as INVALID [...])
--     fn_decode_indicator         code -> DisplayName or INVALID [...]
--     vw_CodedValueIntegrity      every coded value in the database,
--                                 decoded, with VALID/INVALID status
--     vw_WorkflowDetail   (v1.1.0) + RequiredPolicyName, SignatureMethodName
--     vw_AuditHistory     (v1.1.0) + EventTypeName, AffectedRecordTypeName
--
--   OBJECT VERSION STAMPS (section 8)
--     The two replaced views are re-stamped 1.1.0 in
--     DatabaseObjectVersion, per 050_object_version_stamps.sql.
--
-- Enforcement rules (triggers):
--   INSERT  every coded column must be an ACTIVE member of its
--           indicator.
--   UPDATE  only columns whose value CHANGES are checked, so a
--           historical row that references a since-retired value
--           stays valid and maintainable. Retiring a value
--           (IsActive = FALSE) blocks only NEW use of it.
--   Unknown ReferenceDataIDs are rejected by the trigger as well
--   as by the FK, so enforcement holds even with
--   FOREIGN_KEY_CHECKS = 0.
--
-- What is still a literal in code, and why that is correct:
--   Workflow-engine procedures compare against specific state
--   codes ('ACTIVE', 'COMPLETED', ...). Those are state-machine
--   semantics, not lists of values: the engine reacts to them.
--   Adding a purely descriptive value (a classification, a
--   signature method, an audit event) needs only an INSERT.
--   Adding a value the engine must BEHAVE differently for
--   (for example a new REQUIRED_POLICY such as ANY_REQUIRED)
--   still needs engine logic, by design.
-- ============================================================

DELIMITER //


-- ============================================================
-- 1. Validation functions (generic, reusable by any caller)
-- ============================================================

DROP FUNCTION IF EXISTS fn_is_indicator_member//

CREATE FUNCTION fn_is_indicator_member (
    p_indicator_name VARCHAR(50),
    p_value VARCHAR(100)
)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM ReferenceData
        WHERE DomainName = p_indicator_name
          AND Code = p_value
          AND IsActive = TRUE
    );
END//


DROP FUNCTION IF EXISTS fn_is_indicator_id_member//

CREATE FUNCTION fn_is_indicator_id_member (
    p_reference_data_id BIGINT UNSIGNED,
    p_indicator_name VARCHAR(50)
)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    -- Used by the application to validate a submitted dropdown
    -- selection: loading options from the table does not stop a
    -- client from posting an ID from another indicator.
    RETURN EXISTS (
        SELECT 1
        FROM ReferenceData
        WHERE ReferenceDataID = p_reference_data_id
          AND DomainName = p_indicator_name
          AND IsActive = TRUE
    );
END//


-- ============================================================
-- 2. Report decoding
-- ============================================================
-- Deliberately ignores IsActive: a historical row that uses a
-- retired value still renders that value's current description.
-- A value that is not in the table renders visibly as
-- INVALID [<indicator>: <value>] instead of silently passing.
-- ============================================================

DROP FUNCTION IF EXISTS fn_decode_indicator//

CREATE FUNCTION fn_decode_indicator (
    p_indicator_name VARCHAR(50),
    p_value VARCHAR(100)
)
RETURNS VARCHAR(200)
READS SQL DATA
BEGIN
    DECLARE v_display_name VARCHAR(100) DEFAULT NULL;

    IF p_value IS NULL THEN
        RETURN NULL;
    END IF;

    SET v_display_name = (
        SELECT DisplayName
        FROM ReferenceData
        WHERE DomainName = p_indicator_name
          AND Code = p_value
    );

    RETURN COALESCE(
        v_display_name,
        CONCAT('INVALID [', p_indicator_name, ': ', p_value, ']')
    );
END//


-- ============================================================
-- 3. Assertion procedures (called by the triggers in section 6)
-- ============================================================

DROP PROCEDURE IF EXISTS sp_assert_indicator_id//

CREATE PROCEDURE sp_assert_indicator_id (
    IN p_reference_data_id BIGINT UNSIGNED,
    IN p_indicator_name VARCHAR(50),
    IN p_column_label VARCHAR(64)
)
BEGIN
    DECLARE v_domain VARCHAR(50) DEFAULT NULL;
    DECLARE v_code VARCHAR(50) DEFAULT NULL;
    DECLARE v_is_active BOOLEAN DEFAULT NULL;
    DECLARE v_msg VARCHAR(255);

    -- No matching row simply leaves the variables NULL.
    DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

    -- NULL is left to the column's NOT NULL constraint.
    IF p_reference_data_id IS NOT NULL THEN

        SELECT DomainName, Code, IsActive
        INTO v_domain, v_code, v_is_active
        FROM ReferenceData
        WHERE ReferenceDataID = p_reference_data_id
        LIMIT 1;

        IF v_domain IS NULL THEN
            SET v_msg = CONCAT(
                'Unknown value: ', p_column_label,
                ' ReferenceDataID ', p_reference_data_id,
                ' does not exist.'
            );
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = v_msg;

        ELSEIF v_domain <> p_indicator_name THEN
            SET v_msg = LEFT(CONCAT(
                'Indicator violation: ', p_column_label,
                ' must be ', p_indicator_name,
                '; ID ', p_reference_data_id,
                ' is ', v_domain, '.', v_code
            ), 128);
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = v_msg;

        ELSEIF v_is_active = FALSE THEN
            SET v_msg = LEFT(CONCAT(
                'Inactive value: ', p_column_label,
                ' may not use retired ', v_domain, '.', v_code
            ), 128);
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = v_msg;
        END IF;

    END IF;
END//


DROP PROCEDURE IF EXISTS sp_assert_indicator_code//

CREATE PROCEDURE sp_assert_indicator_code (
    IN p_value VARCHAR(100),
    IN p_indicator_name VARCHAR(50),
    IN p_column_label VARCHAR(64)
)
BEGIN
    DECLARE v_is_active BOOLEAN DEFAULT NULL;
    DECLARE v_msg VARCHAR(255);

    DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

    IF p_value IS NOT NULL THEN

        SELECT IsActive
        INTO v_is_active
        FROM ReferenceData
        WHERE DomainName = p_indicator_name
          AND Code = p_value
        LIMIT 1;

        IF v_is_active IS NULL THEN
            SET v_msg = LEFT(CONCAT(
                'Indicator violation: ', p_column_label,
                ' value ''', p_value,
                ''' is not a ', p_indicator_name, ' value'
            ), 128);
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = v_msg;

        ELSEIF v_is_active = FALSE THEN
            SET v_msg = LEFT(CONCAT(
                'Inactive value: ', p_column_label,
                ' may not use retired ', p_indicator_name, '.', p_value
            ), 128);
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = v_msg;
        END IF;

    END IF;
END//


DELIMITER ;


-- ============================================================
-- 4. Views
-- ============================================================

-- ------------------------------------------------------------
-- 4a. vw_IndicatorValue
--     ReferenceData presented in Indicator Value terms.
--     Includes retired values (IsActive = FALSE) for admin and
--     reporting use; list-of-values consumers go through
--     sp_get_indicator_values, which filters to active values.
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW vw_IndicatorValue AS
SELECT
    ReferenceDataID,
    DomainName AS IndicatorName,
    Code AS IndicatorValue,
    DisplayName,
    Description,
    DisplayOrder,
    IsActive
FROM ReferenceData;


-- ------------------------------------------------------------
-- 4b. vw_CodedValueIntegrity
--     One row per coded value stored anywhere in the database
--     (20 coded columns), decoded through ReferenceData.
--     IntegrityStatus is VALID, or INVALID: <reason> for a
--     value that is unknown or belongs to another indicator.
--     05_validation/020_data_validation.sql fails the build if any row here
--     is not VALID.
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW vw_CodedValueIntegrity AS
SELECT
    'User' AS TableName,
    'AccountStatusID' AS ColumnName,
    'ACCOUNT_STATUS' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.UserID AS CHAR(40)) AS RecordKey,
    CAST(t.AccountStatusID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.AccountStatusID, ']')
        WHEN rd.DomainName <> 'ACCOUNT_STATUS'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'ACCOUNT_STATUS' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM `User` t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.AccountStatusID

UNION ALL

SELECT
    'Document' AS TableName,
    'ClassificationID' AS ColumnName,
    'DOCUMENT_CLASSIFICATION' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.DocumentID AS CHAR(40)) AS RecordKey,
    CAST(t.ClassificationID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.ClassificationID, ']')
        WHEN rd.DomainName <> 'DOCUMENT_CLASSIFICATION'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'DOCUMENT_CLASSIFICATION' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM Document t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.ClassificationID

UNION ALL

SELECT
    'Document' AS TableName,
    'LifecycleStatusID' AS ColumnName,
    'DOCUMENT_STATUS' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.DocumentID AS CHAR(40)) AS RecordKey,
    CAST(t.LifecycleStatusID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.LifecycleStatusID, ']')
        WHEN rd.DomainName <> 'DOCUMENT_STATUS'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'DOCUMENT_STATUS' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM Document t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.LifecycleStatusID

UNION ALL

SELECT
    'DocumentVersion' AS TableName,
    'CurrentVersionStatusID' AS ColumnName,
    'DOCUMENT_VERSION_STATUS' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.DocumentVersionID AS CHAR(40)) AS RecordKey,
    CAST(t.CurrentVersionStatusID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.CurrentVersionStatusID, ']')
        WHEN rd.DomainName <> 'DOCUMENT_VERSION_STATUS'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'DOCUMENT_VERSION_STATUS' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM DocumentVersion t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.CurrentVersionStatusID

UNION ALL

SELECT
    'Workflow' AS TableName,
    'WorkflowPurposeTypeID' AS ColumnName,
    'WORKFLOW_PURPOSE_TYPE' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.WorkflowID AS CHAR(40)) AS RecordKey,
    CAST(t.WorkflowPurposeTypeID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.WorkflowPurposeTypeID, ']')
        WHEN rd.DomainName <> 'WORKFLOW_PURPOSE_TYPE'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'WORKFLOW_PURPOSE_TYPE' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM Workflow t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.WorkflowPurposeTypeID

UNION ALL

SELECT
    'Workflow' AS TableName,
    'WorkflowStatusID' AS ColumnName,
    'WORKFLOW_STATUS' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.WorkflowID AS CHAR(40)) AS RecordKey,
    CAST(t.WorkflowStatusID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.WorkflowStatusID, ']')
        WHEN rd.DomainName <> 'WORKFLOW_STATUS'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'WORKFLOW_STATUS' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM Workflow t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.WorkflowStatusID

UNION ALL

SELECT
    'WorkflowStep' AS TableName,
    'StepTypeID' AS ColumnName,
    'STEP_TYPE' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.WorkflowStepID AS CHAR(40)) AS RecordKey,
    CAST(t.StepTypeID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.StepTypeID, ']')
        WHEN rd.DomainName <> 'STEP_TYPE'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'STEP_TYPE' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM WorkflowStep t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.StepTypeID

UNION ALL

SELECT
    'WorkflowStep' AS TableName,
    'StepStatusID' AS ColumnName,
    'STEP_STATUS' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.WorkflowStepID AS CHAR(40)) AS RecordKey,
    CAST(t.StepStatusID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.StepStatusID, ']')
        WHEN rd.DomainName <> 'STEP_STATUS'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'STEP_STATUS' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM WorkflowStep t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.StepStatusID

UNION ALL

SELECT
    'WorkflowStep' AS TableName,
    'RequiredPolicy' AS ColumnName,
    'REQUIRED_POLICY' AS ExpectedIndicator,
    'CODE' AS StorageKind,
    CAST(t.WorkflowStepID AS CHAR(40)) AS RecordKey,
    CAST(t.RequiredPolicy AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL
            THEN CONCAT('INVALID [REQUIRED_POLICY: ', t.RequiredPolicy, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: NOT IN INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM WorkflowStep t
LEFT JOIN ReferenceData rd
    ON rd.DomainName = 'REQUIRED_POLICY'
   AND rd.Code = t.RequiredPolicy

UNION ALL

SELECT
    'WorkflowParticipant' AS TableName,
    'AssignedActionID' AS ColumnName,
    'ASSIGNED_ACTION' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.WorkflowParticipantID AS CHAR(40)) AS RecordKey,
    CAST(t.AssignedActionID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.AssignedActionID, ']')
        WHEN rd.DomainName <> 'ASSIGNED_ACTION'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'ASSIGNED_ACTION' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM WorkflowParticipant t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.AssignedActionID

UNION ALL

SELECT
    'WorkflowParticipant' AS TableName,
    'AssignmentStatusID' AS ColumnName,
    'PARTICIPANT_STATUS' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.WorkflowParticipantID AS CHAR(40)) AS RecordKey,
    CAST(t.AssignmentStatusID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.AssignmentStatusID, ']')
        WHEN rd.DomainName <> 'PARTICIPANT_STATUS'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'PARTICIPANT_STATUS' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM WorkflowParticipant t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.AssignmentStatusID

UNION ALL

SELECT
    'ApprovalDecision' AS TableName,
    'DecisionValueID' AS ColumnName,
    'APPROVAL_DECISION' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.ApprovalID AS CHAR(40)) AS RecordKey,
    CAST(t.DecisionValueID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.DecisionValueID, ']')
        WHEN rd.DomainName <> 'APPROVAL_DECISION'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'APPROVAL_DECISION' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM ApprovalDecision t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.DecisionValueID

UNION ALL

SELECT
    'Signature' AS TableName,
    'SignatureStatusID' AS ColumnName,
    'SIGNATURE_STATUS' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.SignatureID AS CHAR(40)) AS RecordKey,
    CAST(t.SignatureStatusID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.SignatureStatusID, ']')
        WHEN rd.DomainName <> 'SIGNATURE_STATUS'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'SIGNATURE_STATUS' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM Signature t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.SignatureStatusID

UNION ALL

SELECT
    'Signature' AS TableName,
    'SignatureMethod' AS ColumnName,
    'SIGNATURE_METHOD' AS ExpectedIndicator,
    'CODE' AS StorageKind,
    CAST(t.SignatureID AS CHAR(40)) AS RecordKey,
    CAST(t.SignatureMethod AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL
            THEN CONCAT('INVALID [SIGNATURE_METHOD: ', t.SignatureMethod, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: NOT IN INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM Signature t
LEFT JOIN ReferenceData rd
    ON rd.DomainName = 'SIGNATURE_METHOD'
   AND rd.Code = t.SignatureMethod

UNION ALL

SELECT
    'AuditLog' AS TableName,
    'EventType' AS ColumnName,
    'AUDIT_EVENT_TYPE' AS ExpectedIndicator,
    'CODE' AS StorageKind,
    CAST(t.AuditLogID AS CHAR(40)) AS RecordKey,
    CAST(t.EventType AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL
            THEN CONCAT('INVALID [AUDIT_EVENT_TYPE: ', t.EventType, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: NOT IN INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM AuditLog t
LEFT JOIN ReferenceData rd
    ON rd.DomainName = 'AUDIT_EVENT_TYPE'
   AND rd.Code = t.EventType

UNION ALL

SELECT
    'AuditLog' AS TableName,
    'AffectedRecordType' AS ColumnName,
    'AUDIT_RECORD_TYPE' AS ExpectedIndicator,
    'CODE' AS StorageKind,
    CAST(t.AuditLogID AS CHAR(40)) AS RecordKey,
    CAST(t.AffectedRecordType AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL
            THEN CONCAT('INVALID [AUDIT_RECORD_TYPE: ', t.AffectedRecordType, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: NOT IN INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM AuditLog t
LEFT JOIN ReferenceData rd
    ON rd.DomainName = 'AUDIT_RECORD_TYPE'
   AND rd.Code = t.AffectedRecordType

UNION ALL

SELECT
    'DatabaseBuild' AS TableName,
    'BuildStatus' AS ColumnName,
    'BUILD_STATUS' AS ExpectedIndicator,
    'CODE' AS StorageKind,
    CAST(t.BuildID AS CHAR(40)) AS RecordKey,
    CAST(t.BuildStatus AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL
            THEN CONCAT('INVALID [BUILD_STATUS: ', t.BuildStatus, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: NOT IN INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM DatabaseBuild t
LEFT JOIN ReferenceData rd
    ON rd.DomainName = 'BUILD_STATUS'
   AND rd.Code = t.BuildStatus

UNION ALL

SELECT
    'DatabaseObjectVersion' AS TableName,
    'ObjectType' AS ColumnName,
    'DATABASE_OBJECT_TYPE' AS ExpectedIndicator,
    'CODE' AS StorageKind,
    CAST(t.DatabaseObjectVersionID AS CHAR(40)) AS RecordKey,
    CAST(t.ObjectType AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL
            THEN CONCAT('INVALID [DATABASE_OBJECT_TYPE: ', t.ObjectType, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: NOT IN INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM DatabaseObjectVersion t
LEFT JOIN ReferenceData rd
    ON rd.DomainName = 'DATABASE_OBJECT_TYPE'
   AND rd.Code = t.ObjectType

UNION ALL

SELECT
    'WorkflowStatusTransition' AS TableName,
    'FromStatusID' AS ColumnName,
    'WORKFLOW_STATUS' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.WorkflowStatusTransitionID AS CHAR(40)) AS RecordKey,
    CAST(t.FromStatusID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.FromStatusID, ']')
        WHEN rd.DomainName <> 'WORKFLOW_STATUS'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'WORKFLOW_STATUS' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM WorkflowStatusTransition t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.FromStatusID

UNION ALL

SELECT
    'WorkflowStatusTransition' AS TableName,
    'ToStatusID' AS ColumnName,
    'WORKFLOW_STATUS' AS ExpectedIndicator,
    'ID' AS StorageKind,
    CAST(t.WorkflowStatusTransitionID AS CHAR(40)) AS RecordKey,
    CAST(t.ToStatusID AS CHAR(100)) AS StoredValue,
    CAST(rd.DomainName AS CHAR(50)) AS ActualIndicator,
    CAST(rd.Code AS CHAR(50)) AS DecodedCode,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN CONCAT('INVALID [unknown ReferenceDataID ', t.ToStatusID, ']')
        WHEN rd.DomainName <> 'WORKFLOW_STATUS'
            THEN CONCAT('INVALID [', rd.DomainName, '.', rd.Code, ']')
        ELSE rd.DisplayName
    END AS CHAR(200)) AS DecodedDescription,
    rd.IsActive AS ValueIsActive,
    CAST(CASE
        WHEN rd.ReferenceDataID IS NULL THEN 'INVALID: UNKNOWN VALUE'
        WHEN rd.DomainName <> 'WORKFLOW_STATUS' THEN 'INVALID: WRONG INDICATOR'
        ELSE 'VALID'
    END AS CHAR(30)) AS IntegrityStatus
FROM WorkflowStatusTransition t
LEFT JOIN ReferenceData rd
    ON rd.ReferenceDataID = t.ToStatusID;


-- ------------------------------------------------------------
-- 4c. vw_WorkflowDetail (object version 1.1.0; replaces 1.0.0)
--     Columns unchanged from 1.0.0, plus two decoded columns
--     APPENDED at the end so positional consumers are unaffected:
--       RequiredPolicyName, SignatureMethodName
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW vw_WorkflowDetail AS
SELECT
    w.WorkflowID,

    d.DocumentID,
    d.Title,

    dv.DocumentVersionID,
    dv.VersionNumber,

    workflow_status.Code
        AS WorkflowStatus,

    w.InitiatorUserID,
    w.StartDateTime,
    w.CompletionDateTime,
    w.CancellationDateTime,
    w.CancellationReason,
    w.ExpirationDateTime,

    ws.WorkflowStepID,
    ws.SequenceNumber,

    step_type.Code
        AS StepType,

    step_status.Code
        AS StepStatus,

    ws.RequiredPolicy,
    ws.ActivationDateTime
        AS StepActivationDateTime,
    ws.CompletionDateTime
        AS StepCompletionDateTime,
    ws.DueDateTime
        AS StepDueDateTime,

    wp.WorkflowParticipantID,
    wp.UserID,

    CONCAT(
        participant_user.FirstName,
        ' ',
        participant_user.LastName
    ) AS ParticipantName,

    r.RoleName,

    assigned_action.Code
        AS AssignedAction,

    participant_status.Code
        AS AssignmentStatus,

    wp.RequiredFlag,

    wp.ActivationDateTime
        AS ParticipantActivationDateTime,

    wp.CompletionDateTime
        AS ParticipantCompletionDateTime,

    ad.ApprovalID,

    approval_value.Code
        AS ApprovalDecision,

    ad.DecisionDateTime,

    ad.Comments
        AS ApprovalComments,

    ad.RejectionReason,

    s.SignatureID,
    s.SigningDateTime,

    signature_status.Code
        AS SignatureStatus,

    s.SignatureMethod,
    s.SignatureReference,

    -- 1.2.0: decoded through the indicator table.
    CASE
        WHEN ws.WorkflowStepID IS NULL THEN NULL
        ELSE COALESCE(
            required_policy.DisplayName,
            CONCAT('INVALID [REQUIRED_POLICY: ', ws.RequiredPolicy, ']')
        )
    END AS RequiredPolicyName,

    CASE
        WHEN s.SignatureID IS NULL THEN NULL
        ELSE COALESCE(
            signature_method.DisplayName,
            CONCAT('INVALID [SIGNATURE_METHOD: ', s.SignatureMethod, ']')
        )
    END AS SignatureMethodName

FROM Workflow w

JOIN Document d
    ON d.DocumentID = w.DocumentID

JOIN DocumentVersion dv
    ON dv.DocumentVersionID = w.DocumentVersionID

JOIN ReferenceData workflow_status
    ON workflow_status.ReferenceDataID = w.WorkflowStatusID

LEFT JOIN WorkflowStep ws
    ON ws.WorkflowID = w.WorkflowID

LEFT JOIN ReferenceData step_type
    ON step_type.ReferenceDataID = ws.StepTypeID

LEFT JOIN ReferenceData step_status
    ON step_status.ReferenceDataID = ws.StepStatusID

LEFT JOIN ReferenceData required_policy
    ON required_policy.DomainName = 'REQUIRED_POLICY'
   AND required_policy.Code = ws.RequiredPolicy

LEFT JOIN WorkflowParticipant wp
    ON wp.WorkflowStepID = ws.WorkflowStepID

LEFT JOIN `User` participant_user
    ON participant_user.UserID = wp.UserID

LEFT JOIN Role r
    ON r.RoleID = wp.RoleID

LEFT JOIN ReferenceData assigned_action
    ON assigned_action.ReferenceDataID = wp.AssignedActionID

LEFT JOIN ReferenceData participant_status
    ON participant_status.ReferenceDataID =
       wp.AssignmentStatusID

LEFT JOIN ApprovalDecision ad
    ON ad.WorkflowParticipantID =
       wp.WorkflowParticipantID

LEFT JOIN ReferenceData approval_value
    ON approval_value.ReferenceDataID =
       ad.DecisionValueID

LEFT JOIN Signature s
    ON s.WorkflowParticipantID =
       wp.WorkflowParticipantID

LEFT JOIN ReferenceData signature_status
    ON signature_status.ReferenceDataID =
       s.SignatureStatusID

LEFT JOIN ReferenceData signature_method
    ON signature_method.DomainName = 'SIGNATURE_METHOD'
   AND signature_method.Code = s.SignatureMethod;


-- ------------------------------------------------------------
-- 4d. vw_AuditHistory (object version 1.1.0; replaces 1.0.0)
--     Columns unchanged from 1.0.0, plus two decoded columns APPENDED:
--       EventTypeName, AffectedRecordTypeName
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW vw_AuditHistory AS
SELECT
    a.AuditLogID,

    a.EventDateTime,

    a.ActorUserID,

    CASE
        WHEN a.ActorUserID IS NULL
            THEN 'SYSTEM'
        ELSE CONCAT(
            u.FirstName,
            ' ',
            u.LastName
        )
    END AS ActorName,

    a.EventType,

    a.AffectedRecordType,

    a.AffectedRecordID,

    a.TransactionReference,

    a.PriorValueContext,

    a.NewValueContext,

    a.ChangeReason,

    -- 1.2.0: decoded through the indicator table.
    COALESCE(
        event_type.DisplayName,
        CONCAT('INVALID [AUDIT_EVENT_TYPE: ', a.EventType, ']')
    ) AS EventTypeName,

    COALESCE(
        record_type.DisplayName,
        CONCAT('INVALID [AUDIT_RECORD_TYPE: ', a.AffectedRecordType, ']')
    ) AS AffectedRecordTypeName

FROM AuditLog a

LEFT JOIN `User` u
    ON u.UserID = a.ActorUserID

LEFT JOIN ReferenceData event_type
    ON event_type.DomainName = 'AUDIT_EVENT_TYPE'
   AND event_type.Code = a.EventType

LEFT JOIN ReferenceData record_type
    ON record_type.DomainName = 'AUDIT_RECORD_TYPE'
   AND record_type.Code = a.AffectedRecordType;


-- ============================================================
-- 5. Generic list-of-values service
-- ============================================================
-- The ONE endpoint every combo box calls, for example:
--
--   CALL sp_get_indicator_values('WORKFLOW_STATUS')
--   CALL sp_get_indicator_values('DOCUMENT_CLASSIFICATION')
--
-- Returns the indicator's ACTIVE values in DisplayOrder. A page
-- builds its options from (ReferenceDataID, DisplayName) and
-- contains no hard-coded options. Inserting a row into
-- ReferenceData makes it appear on the next call: no code
-- change, no redeploy.
--
-- An unknown indicator name raises an error rather than
-- returning an empty list, so a typo surfaces immediately.
-- ============================================================

DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_indicator_values//

CREATE PROCEDURE sp_get_indicator_values (
    IN p_indicator_name VARCHAR(50)
)
READS SQL DATA
BEGIN
    DECLARE v_msg VARCHAR(255);

    IF NOT EXISTS (
        SELECT 1
        FROM ReferenceData
        WHERE DomainName = p_indicator_name
    ) THEN
        SET v_msg = LEFT(CONCAT(
            'Unknown indicator: ', COALESCE(p_indicator_name, 'NULL')
        ), 128);
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_msg;
    END IF;

    SELECT
        ReferenceDataID,
        IndicatorName,
        IndicatorValue,
        DisplayName,
        Description,
        DisplayOrder
    FROM vw_IndicatorValue
    WHERE IndicatorName = p_indicator_name
      AND IsActive = TRUE
    ORDER BY DisplayOrder, DisplayName;
END//


-- ============================================================
-- 6. Indicator-membership triggers
-- ============================================================
-- One BEFORE INSERT and (where rows are mutable) one
-- BEFORE UPDATE trigger per table. Each column is checked
-- against the indicator it belongs to.
-- ============================================================

-- ------------------------------------------------------------
-- User: AccountStatusID
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_User_IndicatorCheckInsert//

CREATE TRIGGER trg_User_IndicatorCheckInsert
BEFORE INSERT ON `User`
FOR EACH ROW
BEGIN
    CALL sp_assert_indicator_id(NEW.AccountStatusID, 'ACCOUNT_STATUS', 'User.AccountStatusID');
END//


DROP TRIGGER IF EXISTS trg_User_IndicatorCheckUpdate//

CREATE TRIGGER trg_User_IndicatorCheckUpdate
BEFORE UPDATE ON `User`
FOR EACH ROW
BEGIN
    IF NOT (NEW.AccountStatusID <=> OLD.AccountStatusID) THEN
        CALL sp_assert_indicator_id(NEW.AccountStatusID, 'ACCOUNT_STATUS', 'User.AccountStatusID');
    END IF;
END//


-- ------------------------------------------------------------
-- Document: ClassificationID, LifecycleStatusID
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_Document_IndicatorCheckInsert//

CREATE TRIGGER trg_Document_IndicatorCheckInsert
BEFORE INSERT ON Document
FOR EACH ROW
BEGIN
    CALL sp_assert_indicator_id(NEW.ClassificationID, 'DOCUMENT_CLASSIFICATION', 'Document.ClassificationID');
    CALL sp_assert_indicator_id(NEW.LifecycleStatusID, 'DOCUMENT_STATUS', 'Document.LifecycleStatusID');
END//


DROP TRIGGER IF EXISTS trg_Document_IndicatorCheckUpdate//

CREATE TRIGGER trg_Document_IndicatorCheckUpdate
BEFORE UPDATE ON Document
FOR EACH ROW
BEGIN
    IF NOT (NEW.ClassificationID <=> OLD.ClassificationID) THEN
        CALL sp_assert_indicator_id(NEW.ClassificationID, 'DOCUMENT_CLASSIFICATION', 'Document.ClassificationID');
    END IF;
    IF NOT (NEW.LifecycleStatusID <=> OLD.LifecycleStatusID) THEN
        CALL sp_assert_indicator_id(NEW.LifecycleStatusID, 'DOCUMENT_STATUS', 'Document.LifecycleStatusID');
    END IF;
END//


-- ------------------------------------------------------------
-- DocumentVersion: CurrentVersionStatusID
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_DocumentVersion_IndicatorCheckInsert//

CREATE TRIGGER trg_DocumentVersion_IndicatorCheckInsert
BEFORE INSERT ON DocumentVersion
FOR EACH ROW
BEGIN
    CALL sp_assert_indicator_id(NEW.CurrentVersionStatusID, 'DOCUMENT_VERSION_STATUS', 'DocumentVersion.CurrentVersionStatusID');
END//


DROP TRIGGER IF EXISTS trg_DocumentVersion_IndicatorCheckUpdate//

CREATE TRIGGER trg_DocumentVersion_IndicatorCheckUpdate
BEFORE UPDATE ON DocumentVersion
FOR EACH ROW
FOLLOWS trg_DocumentVersion_PreventFinalizedUpdate
BEGIN
    IF NOT (NEW.CurrentVersionStatusID <=> OLD.CurrentVersionStatusID) THEN
        CALL sp_assert_indicator_id(NEW.CurrentVersionStatusID, 'DOCUMENT_VERSION_STATUS', 'DocumentVersion.CurrentVersionStatusID');
    END IF;
END//


-- ------------------------------------------------------------
-- Workflow: WorkflowPurposeTypeID, WorkflowStatusID
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_Workflow_IndicatorCheckInsert//

CREATE TRIGGER trg_Workflow_IndicatorCheckInsert
BEFORE INSERT ON Workflow
FOR EACH ROW
BEGIN
    CALL sp_assert_indicator_id(NEW.WorkflowPurposeTypeID, 'WORKFLOW_PURPOSE_TYPE', 'Workflow.WorkflowPurposeTypeID');
    CALL sp_assert_indicator_id(NEW.WorkflowStatusID, 'WORKFLOW_STATUS', 'Workflow.WorkflowStatusID');
END//


DROP TRIGGER IF EXISTS trg_Workflow_IndicatorCheckUpdate//

CREATE TRIGGER trg_Workflow_IndicatorCheckUpdate
BEFORE UPDATE ON Workflow
FOR EACH ROW
PRECEDES trg_Workflow_ProtectStatusTransition
BEGIN
    IF NOT (NEW.WorkflowPurposeTypeID <=> OLD.WorkflowPurposeTypeID) THEN
        CALL sp_assert_indicator_id(NEW.WorkflowPurposeTypeID, 'WORKFLOW_PURPOSE_TYPE', 'Workflow.WorkflowPurposeTypeID');
    END IF;
    IF NOT (NEW.WorkflowStatusID <=> OLD.WorkflowStatusID) THEN
        CALL sp_assert_indicator_id(NEW.WorkflowStatusID, 'WORKFLOW_STATUS', 'Workflow.WorkflowStatusID');
    END IF;
END//


-- ------------------------------------------------------------
-- WorkflowStep: StepTypeID, StepStatusID, RequiredPolicy
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_WorkflowStep_IndicatorCheckInsert//

CREATE TRIGGER trg_WorkflowStep_IndicatorCheckInsert
BEFORE INSERT ON WorkflowStep
FOR EACH ROW
BEGIN
    CALL sp_assert_indicator_id(NEW.StepTypeID, 'STEP_TYPE', 'WorkflowStep.StepTypeID');
    CALL sp_assert_indicator_id(NEW.StepStatusID, 'STEP_STATUS', 'WorkflowStep.StepStatusID');
    CALL sp_assert_indicator_code(NEW.RequiredPolicy, 'REQUIRED_POLICY', 'WorkflowStep.RequiredPolicy');
END//


DROP TRIGGER IF EXISTS trg_WorkflowStep_IndicatorCheckUpdate//

CREATE TRIGGER trg_WorkflowStep_IndicatorCheckUpdate
BEFORE UPDATE ON WorkflowStep
FOR EACH ROW
BEGIN
    IF NOT (NEW.StepTypeID <=> OLD.StepTypeID) THEN
        CALL sp_assert_indicator_id(NEW.StepTypeID, 'STEP_TYPE', 'WorkflowStep.StepTypeID');
    END IF;
    IF NOT (NEW.StepStatusID <=> OLD.StepStatusID) THEN
        CALL sp_assert_indicator_id(NEW.StepStatusID, 'STEP_STATUS', 'WorkflowStep.StepStatusID');
    END IF;
    IF NOT (NEW.RequiredPolicy <=> OLD.RequiredPolicy) THEN
        CALL sp_assert_indicator_code(NEW.RequiredPolicy, 'REQUIRED_POLICY', 'WorkflowStep.RequiredPolicy');
    END IF;
END//


-- ------------------------------------------------------------
-- WorkflowParticipant: AssignedActionID, AssignmentStatusID
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_WorkflowParticipant_IndicatorCheckInsert//

CREATE TRIGGER trg_WorkflowParticipant_IndicatorCheckInsert
BEFORE INSERT ON WorkflowParticipant
FOR EACH ROW
BEGIN
    CALL sp_assert_indicator_id(NEW.AssignedActionID, 'ASSIGNED_ACTION', 'WorkflowParticipant.AssignedActionID');
    CALL sp_assert_indicator_id(NEW.AssignmentStatusID, 'PARTICIPANT_STATUS', 'WorkflowParticipant.AssignmentStatusID');
END//


DROP TRIGGER IF EXISTS trg_WorkflowParticipant_IndicatorCheckUpdate//

CREATE TRIGGER trg_WorkflowParticipant_IndicatorCheckUpdate
BEFORE UPDATE ON WorkflowParticipant
FOR EACH ROW
BEGIN
    IF NOT (NEW.AssignedActionID <=> OLD.AssignedActionID) THEN
        CALL sp_assert_indicator_id(NEW.AssignedActionID, 'ASSIGNED_ACTION', 'WorkflowParticipant.AssignedActionID');
    END IF;
    IF NOT (NEW.AssignmentStatusID <=> OLD.AssignmentStatusID) THEN
        CALL sp_assert_indicator_id(NEW.AssignmentStatusID, 'PARTICIPANT_STATUS', 'WorkflowParticipant.AssignmentStatusID');
    END IF;
END//


-- ------------------------------------------------------------
-- ApprovalDecision: DecisionValueID
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_ApprovalDecision_IndicatorCheckInsert//

CREATE TRIGGER trg_ApprovalDecision_IndicatorCheckInsert
BEFORE INSERT ON ApprovalDecision
FOR EACH ROW
BEGIN
    CALL sp_assert_indicator_id(NEW.DecisionValueID, 'APPROVAL_DECISION', 'ApprovalDecision.DecisionValueID');
END//


-- ApprovalDecision: no UPDATE trigger needed; existing
-- trg_ApprovalDecision_PreventUpdate rejects every UPDATE.


-- ------------------------------------------------------------
-- Signature: SignatureStatusID, SignatureMethod
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_Signature_IndicatorCheckInsert//

CREATE TRIGGER trg_Signature_IndicatorCheckInsert
BEFORE INSERT ON Signature
FOR EACH ROW
BEGIN
    CALL sp_assert_indicator_id(NEW.SignatureStatusID, 'SIGNATURE_STATUS', 'Signature.SignatureStatusID');
    CALL sp_assert_indicator_code(NEW.SignatureMethod, 'SIGNATURE_METHOD', 'Signature.SignatureMethod');
END//


-- Signature: no UPDATE trigger needed; existing
-- trg_Signature_PreventUpdate rejects every UPDATE.


-- ------------------------------------------------------------
-- AuditLog: EventType, AffectedRecordType
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_AuditLog_IndicatorCheckInsert//

CREATE TRIGGER trg_AuditLog_IndicatorCheckInsert
BEFORE INSERT ON AuditLog
FOR EACH ROW
BEGIN
    CALL sp_assert_indicator_code(NEW.EventType, 'AUDIT_EVENT_TYPE', 'AuditLog.EventType');
    CALL sp_assert_indicator_code(NEW.AffectedRecordType, 'AUDIT_RECORD_TYPE', 'AuditLog.AffectedRecordType');
END//


-- AuditLog: no UPDATE trigger needed; existing
-- trg_AuditLog_PreventUpdate rejects every UPDATE.


-- ------------------------------------------------------------
-- DatabaseBuild: BuildStatus
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_DatabaseBuild_IndicatorCheckInsert//

CREATE TRIGGER trg_DatabaseBuild_IndicatorCheckInsert
BEFORE INSERT ON DatabaseBuild
FOR EACH ROW
BEGIN
    CALL sp_assert_indicator_code(NEW.BuildStatus, 'BUILD_STATUS', 'DatabaseBuild.BuildStatus');
END//


DROP TRIGGER IF EXISTS trg_DatabaseBuild_IndicatorCheckUpdate//

CREATE TRIGGER trg_DatabaseBuild_IndicatorCheckUpdate
BEFORE UPDATE ON DatabaseBuild
FOR EACH ROW
BEGIN
    IF NOT (NEW.BuildStatus <=> OLD.BuildStatus) THEN
        CALL sp_assert_indicator_code(NEW.BuildStatus, 'BUILD_STATUS', 'DatabaseBuild.BuildStatus');
    END IF;
END//


-- ------------------------------------------------------------
-- DatabaseObjectVersion: ObjectType
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_DatabaseObjectVersion_IndicatorCheckInsert//

CREATE TRIGGER trg_DatabaseObjectVersion_IndicatorCheckInsert
BEFORE INSERT ON DatabaseObjectVersion
FOR EACH ROW
BEGIN
    CALL sp_assert_indicator_code(NEW.ObjectType, 'DATABASE_OBJECT_TYPE', 'DatabaseObjectVersion.ObjectType');
END//


DROP TRIGGER IF EXISTS trg_DatabaseObjectVersion_IndicatorCheckUpdate//

CREATE TRIGGER trg_DatabaseObjectVersion_IndicatorCheckUpdate
BEFORE UPDATE ON DatabaseObjectVersion
FOR EACH ROW
BEGIN
    IF NOT (NEW.ObjectType <=> OLD.ObjectType) THEN
        CALL sp_assert_indicator_code(NEW.ObjectType, 'DATABASE_OBJECT_TYPE', 'DatabaseObjectVersion.ObjectType');
    END IF;
END//


-- ------------------------------------------------------------
-- WorkflowStatusTransition: FromStatusID, ToStatusID
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_WorkflowStatusTransition_IndicatorCheckInsert//

CREATE TRIGGER trg_WorkflowStatusTransition_IndicatorCheckInsert
BEFORE INSERT ON WorkflowStatusTransition
FOR EACH ROW
BEGIN
    CALL sp_assert_indicator_id(NEW.FromStatusID, 'WORKFLOW_STATUS', 'WorkflowStatusTransition.FromStatusID');
    CALL sp_assert_indicator_id(NEW.ToStatusID, 'WORKFLOW_STATUS', 'WorkflowStatusTransition.ToStatusID');
END//


DROP TRIGGER IF EXISTS trg_WorkflowStatusTransition_IndicatorCheckUpdate//

CREATE TRIGGER trg_WorkflowStatusTransition_IndicatorCheckUpdate
BEFORE UPDATE ON WorkflowStatusTransition
FOR EACH ROW
BEGIN
    IF NOT (NEW.FromStatusID <=> OLD.FromStatusID) THEN
        CALL sp_assert_indicator_id(NEW.FromStatusID, 'WORKFLOW_STATUS', 'WorkflowStatusTransition.FromStatusID');
    END IF;
    IF NOT (NEW.ToStatusID <=> OLD.ToStatusID) THEN
        CALL sp_assert_indicator_id(NEW.ToStatusID, 'WORKFLOW_STATUS', 'WorkflowStatusTransition.ToStatusID');
    END IF;
END//

DELIMITER ;


-- ============================================================
-- 7. Pre-existing data report
-- ============================================================
-- The triggers stop NEW invalid values. Rows written before
-- this release are reported here (expected: zero rows) and
-- 05_validation/020_data_validation.sql fails the build if any exist.
-- ============================================================

SELECT
    TableName,
    ColumnName,
    ExpectedIndicator,
    RecordKey,
    StoredValue,
    DecodedDescription,
    IntegrityStatus
FROM vw_CodedValueIntegrity
WHERE IntegrityStatus <> 'VALID'
ORDER BY TableName, ColumnName, RecordKey;


-- ============================================================
-- 8. Object version stamps for the replaced views
-- ============================================================
-- 050_object_version_stamps.sql: "Future changes to an
-- individual object should be made through a new migration that
-- also updates that object's version stamp." New objects in this
-- migration are not stamped, matching schema 1.3.0, so the
-- 27-stamp check in 010_object_validation.sql still holds.
-- ============================================================

UPDATE DatabaseObjectVersion
SET
    ObjectVersion = '1.1.0',
    StampedSchemaVersion = '1.4.0',
    StampMigrationVersion = '028',
    LastStampedDateTime = CURRENT_TIMESTAMP
WHERE ObjectType = 'VIEW'
  AND ObjectName IN ('vw_WorkflowDetail', 'vw_AuditHistory');
