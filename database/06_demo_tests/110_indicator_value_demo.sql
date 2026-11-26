-- ============================================================================
-- File:     database/06_demo_tests/110_indicator_value_demo.sql
-- Project:  Document Workflow and E-signing Portal
-- Database: MySQL 8.x  (schema 1.4.0 or later)
-- ============================================================================
--
-- PURPOSE
--   Demonstrate Principle 11 - "Never hard-code a domain of values" - using
--   the Indicator Value pattern (ReferenceData + trg_<Table>_IndicatorCheck*
--   triggers + sp_get_indicator_values + fn_decode_indicator).
--
-- WHAT THIS FILE PROVES
--   Part 1  List of values      Combo-box options come from ONE generic
--                               service: sp_get_indicator_values(<indicator>).
--   Part 2  The classroom moment
--                               ONE INSERT adds a legal value (classification
--                               PUBLIC). The next service call returns it and
--                               the database accepts it. Zero code changes.
--   Part 3  Wrong indicator     Direct SQL (no stored procedure) can no longer
--                               store a DOCUMENT_STATUS row as a Workflow
--                               status, on INSERT or on UPDATE. This is the
--                               midterm A2 live test, which now FAILS as it
--                               should.
--   Part 4  Unknown value       A ReferenceDataID that does not exist is
--                               rejected.
--   Part 5  Code-valued columns Former CHECK / literal domains
--                               (RequiredPolicy, EventType) are validated
--                               against the table too.
--   Part 6  Retiring a value    IsActive = FALSE removes the value from the
--                               list of values and blocks NEW use, while
--                               historical rows stay valid and still decode.
--   Part 7  Report decoding     A code that is not in the table renders
--                               visibly as INVALID [...], never silently.
--   Part 8  Cleanup             Demo rows removed; script is re-runnable.
--
-- HOW TO RUN
--   mysql -u <user> -p <database> < database/06_demo_tests/110_indicator_value_demo.sql
--   Every check writes PASS/FAIL to the scoreboard printed at the end.
--
-- IMPORTANT
--   - Requires the seeded database (users/documents from 020_sample_data.sql).
--   - Negative tests run inside START TRANSACTION ... ROLLBACK, so even if a
--     check FAILS (a bad write is accepted) nothing invalid is left behind.
--   - Demo rows are tagged with the marker 'IND-DEMO' and removed in Part 8.
--   - If the business has really added a PUBLIC classification already, the
--     Part 2 INSERT fails with a duplicate key; that row is never touched.
--   - This file is NOT part of the normal build manifest.
-- ============================================================================


-- ============================================================================
-- SESSION SETUP
-- ============================================================================

SET @ind_saved_sql_mode = @@SESSION.sql_mode;
SET SESSION sql_mode = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

DROP TEMPORARY TABLE IF EXISTS ind_results;
CREATE TEMPORARY TABLE ind_results (
    seq        INT AUTO_INCREMENT PRIMARY KEY,
    area       VARCHAR(20),
    test_name  VARCHAR(200),
    result     VARCHAR(4),
    detail     TEXT
);


-- ============================================================================
-- HELPER PROCEDURES  (test plumbing; dropped at the end)
-- ============================================================================

DELIMITER $$

-- sp__ind_check: records one PASS/FAIL row and prints it.
DROP PROCEDURE IF EXISTS sp__ind_check $$
CREATE PROCEDURE sp__ind_check(IN p_area VARCHAR(20), IN p_name VARCHAR(200),
                               IN p_pass BOOLEAN, IN p_detail TEXT)
BEGIN
    INSERT INTO ind_results(area, test_name, result, detail)
    VALUES (p_area, p_name, IF(COALESCE(p_pass, 0), 'PASS', 'FAIL'), p_detail);
    SELECT IF(COALESCE(p_pass, 0), 'PASS', 'FAIL') AS Result,
           p_area AS Area, p_name AS Test, p_detail AS Detail;
END $$

-- sp__ind_expect_reject (NEGATIVE test)
--   Runs p_stmt inside a transaction that is ALWAYS rolled back.
--   PASS only if the statement raised an error. The error text is the
--   evidence of WHICH rule rejected it.
DROP PROCEDURE IF EXISTS sp__ind_expect_reject $$
CREATE PROCEDURE sp__ind_expect_reject(IN p_area VARCHAR(20), IN p_name VARCHAR(200),
                                       IN p_stmt TEXT)
BEGIN
    DECLARE v_rejected BOOLEAN DEFAULT FALSE;
    DECLARE v_msg TEXT DEFAULT NULL;

    START TRANSACTION;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_rejected = TRUE;
        END;

        SET @ind_stmt = p_stmt;
        PREPARE ind_s FROM @ind_stmt;
        EXECUTE ind_s;
        DEALLOCATE PREPARE ind_s;
    END;
    ROLLBACK;

    CALL sp__ind_check(p_area, p_name, v_rejected,
        IF(v_rejected, CONCAT('Rejected: ', v_msg),
                       'NOT rejected - the write was accepted (rolled back).'));
END $$

-- sp__ind_expect_ok (POSITIVE test)
--   Runs p_stmt (autocommit). PASS if it succeeds.
DROP PROCEDURE IF EXISTS sp__ind_expect_ok $$
CREATE PROCEDURE sp__ind_expect_ok(IN p_area VARCHAR(20), IN p_name VARCHAR(200),
                                   IN p_stmt TEXT)
BEGIN
    DECLARE v_failed BOOLEAN DEFAULT FALSE;
    DECLARE v_msg TEXT DEFAULT NULL;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_failed = TRUE;
        END;

        SET @ind_stmt = p_stmt;
        PREPARE ind_s FROM @ind_stmt;
        EXECUTE ind_s;
        DEALLOCATE PREPARE ind_s;
    END;

    CALL sp__ind_check(p_area, p_name, NOT v_failed,
        IF(v_failed, CONCAT('Unexpected error: ', v_msg), 'Accepted.'));
END $$

-- sp__ind_cleanup: removes everything tagged IND-DEMO (children first).
DROP PROCEDURE IF EXISTS sp__ind_cleanup $$
CREATE PROCEDURE sp__ind_cleanup()
BEGIN
    DELETE ws
    FROM WorkflowStep ws
    JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
    WHERE w.CancellationReason = 'IND-DEMO';

    DELETE FROM Workflow
    WHERE CancellationReason = 'IND-DEMO';

    DELETE FROM Document
    WHERE BusinessDescription = 'IND-DEMO';

    DELETE FROM ReferenceData
    WHERE DomainName = 'DOCUMENT_CLASSIFICATION'
      AND Code = 'PUBLIC'
      AND Description = 'IND-DEMO';
END $$

DELIMITER ;

-- Remove leftovers if a previous run was interrupted.
CALL sp__ind_cleanup();


-- ============================================================================
-- RESOLVE IDS (by indicator + value, never by hard-coded number)
-- ============================================================================

SET @u_owner = (SELECT UserID FROM `User` WHERE Email = 'olivia.brooks@initech.example');

SET @doc_msa = (SELECT DocumentID FROM Document WHERE Title = 'Master Services Agreement' LIMIT 1);
SET @ver_msa = (SELECT DocumentVersionID FROM DocumentVersion
                WHERE DocumentID = @doc_msa ORDER BY VersionNumber LIMIT 1);

SET @doc_status_active  = (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName = 'DOCUMENT_STATUS'         AND Code = 'ACTIVE');
SET @doc_status_draft   = (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName = 'DOCUMENT_STATUS'         AND Code = 'DRAFT');
SET @classif_internal   = (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName = 'DOCUMENT_CLASSIFICATION' AND Code = 'INTERNAL');
SET @wf_status_draft    = (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName = 'WORKFLOW_STATUS'         AND Code = 'DRAFT');
SET @wf_purpose_review  = (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName = 'WORKFLOW_PURPOSE_TYPE'   AND Code = 'REVIEW');
SET @step_type_review   = (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName = 'STEP_TYPE'               AND Code = 'REVIEW');
SET @step_status_pend   = (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName = 'STEP_STATUS'             AND Code = 'PENDING');

CALL sp__ind_check('SETUP', 'Seeded users, documents and reference values found',
    @u_owner IS NOT NULL AND @doc_msa IS NOT NULL AND @ver_msa IS NOT NULL
    AND @doc_status_active IS NOT NULL AND @wf_status_draft IS NOT NULL,
    CONCAT('owner=', COALESCE(@u_owner, 'NULL'), ' doc=', COALESCE(@doc_msa, 'NULL'),
           ' version=', COALESCE(@ver_msa, 'NULL')));


-- ============================================================================
-- PART 1 - LIST OF VALUES COMES FROM ONE GENERIC SERVICE
-- ============================================================================
-- WHAT   The classification combo box calls the generic endpoint.
-- EXPECT Internal / Confidential / Restricted, in DisplayOrder.
-- ============================================================================

SELECT '=== PART 1: Classification dropdown BEFORE (generic service) ===' AS Demo;

CALL sp_get_indicator_values('DOCUMENT_CLASSIFICATION');

SET @lov_before = (SELECT COUNT(*) FROM vw_IndicatorValue
                   WHERE IndicatorName = 'DOCUMENT_CLASSIFICATION' AND IsActive = TRUE);

-- The same endpoint serves every other indicator: nothing is per-page.
CALL sp_get_indicator_values('WORKFLOW_STATUS');

CALL sp__ind_check('LOV', 'PUBLIC is not yet a legal classification',
    fn_is_indicator_member('DOCUMENT_CLASSIFICATION', 'PUBLIC') = FALSE,
    CONCAT(@lov_before, ' active classification values'));


-- ============================================================================
-- PART 2 - THE CLASSROOM MOMENT: ONE INSERT, NO CODE CHANGE
-- ============================================================================
-- WHAT   The business adds a "Public" classification.
--        Indicator name, value, description, display order:
--          ('DOCUMENT_CLASSIFICATION', 'PUBLIC', 'Public', 40)
--        (Description is only used here as the demo cleanup marker.)
-- EXPECT The next call to the same service returns it, and the database
--        accepts it on a Document. No ALTER, no procedure, no redeploy.
-- ============================================================================

SELECT '=== PART 2: One INSERT adds a legal value ===' AS Demo;

INSERT INTO ReferenceData (DomainName, Code, DisplayName, DisplayOrder, Description)
VALUES ('DOCUMENT_CLASSIFICATION', 'PUBLIC', 'Public', 40, 'IND-DEMO');

SELECT '--- Classification dropdown AFTER (same call, refreshed) ---' AS Demo;

CALL sp_get_indicator_values('DOCUMENT_CLASSIFICATION');

SET @classif_public = (SELECT ReferenceDataID FROM ReferenceData
                       WHERE DomainName = 'DOCUMENT_CLASSIFICATION' AND Code = 'PUBLIC');

CALL sp__ind_check('LOV', 'New value appears in the list of values',
    (SELECT COUNT(*) FROM vw_IndicatorValue
     WHERE IndicatorName = 'DOCUMENT_CLASSIFICATION' AND IsActive = TRUE) = @lov_before + 1
    AND EXISTS (SELECT 1 FROM vw_IndicatorValue
                WHERE IndicatorName = 'DOCUMENT_CLASSIFICATION'
                  AND IndicatorValue = 'PUBLIC' AND IsActive = TRUE),
    'Returned by sp_get_indicator_values without any code change');

CALL sp__ind_check('VALIDATE', 'Validation now accepts PUBLIC as a classification',
    fn_is_indicator_member('DOCUMENT_CLASSIFICATION', 'PUBLIC')
    AND fn_is_indicator_id_member(@classif_public, 'DOCUMENT_CLASSIFICATION'),
    'fn_is_indicator_member / fn_is_indicator_id_member read the table');

CALL sp__ind_expect_ok('VALIDATE', 'Document can be classified PUBLIC (direct SQL)',
    CONCAT('INSERT INTO Document (Title, BusinessDescription, OwnerUserID, ClassificationID, LifecycleStatusID) ',
           'VALUES (''Public Product Brochure'', ''IND-DEMO'', ', @u_owner, ', ', @classif_public, ', ', @doc_status_draft, ')'));

SET @doc_public = (SELECT DocumentID FROM Document WHERE BusinessDescription = 'IND-DEMO' LIMIT 1);


-- ============================================================================
-- PART 3 - WRONG INDICATOR IS REJECTED (closes the midterm A1/A2 gap)
-- ============================================================================
-- WHAT   The midterm live test: direct SQL, no stored procedure, store a
--        DOCUMENT_STATUS row as Workflow.WorkflowStatusID.
-- BEFORE 1.4.0 the INSERT succeeded (FK only proves the ID exists).
-- EXPECT Rejected by trg_Workflow_IndicatorCheckInsert / ...Update.
-- ============================================================================

SELECT '=== PART 3: Cross-indicator values are rejected ===' AS Demo;

SET @wf_count_before = (SELECT COUNT(*) FROM Workflow);

CALL sp__ind_expect_reject('DOMAIN', '3a INSERT Workflow with a DOCUMENT_STATUS id as WorkflowStatusID',
    CONCAT('INSERT INTO Workflow (DocumentID, DocumentVersionID, InitiatorUserID, ',
           'WorkflowPurposeTypeID, WorkflowStatusID, CancellationReason) VALUES (',
           @doc_msa, ', ', @ver_msa, ', ', @u_owner, ', ',
           @wf_purpose_review, ', ', @doc_status_active, ', ''IND-DEMO'')'));

CALL sp__ind_check('DOMAIN', '3a No invalid workflow was created',
    (SELECT COUNT(*) FROM Workflow) = @wf_count_before,
    CONCAT('Workflow rows before=', @wf_count_before, ' after=', (SELECT COUNT(*) FROM Workflow)));

-- A valid DRAFT workflow (direct SQL) to attempt the UPDATE against.
CALL sp__ind_expect_ok('DOMAIN', '3b Setup: valid DRAFT workflow (correct indicators) is accepted',
    CONCAT('INSERT INTO Workflow (DocumentID, DocumentVersionID, InitiatorUserID, ',
           'WorkflowPurposeTypeID, WorkflowStatusID, CancellationReason) VALUES (',
           @doc_msa, ', ', @ver_msa, ', ', @u_owner, ', ',
           @wf_purpose_review, ', ', @wf_status_draft, ', ''IND-DEMO'')'));

SET @wf_test = (SELECT MAX(WorkflowID) FROM Workflow WHERE CancellationReason = 'IND-DEMO');

CALL sp__ind_expect_reject('DOMAIN', '3b UPDATE Workflow.WorkflowStatusID to a DOCUMENT_STATUS id',
    CONCAT('UPDATE Workflow SET WorkflowStatusID = ', @doc_status_active,
           ' WHERE WorkflowID = ', @wf_test));

CALL sp__ind_check('DOMAIN', '3b Workflow status is unchanged (still DRAFT)',
    (SELECT WorkflowStatusID FROM Workflow WHERE WorkflowID = @wf_test) = @wf_status_draft,
    (SELECT fn_decode_indicator('WORKFLOW_STATUS', rd.Code)
     FROM Workflow w JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID
     WHERE w.WorkflowID = @wf_test));

CALL sp__ind_expect_reject('DOMAIN', '3c INSERT Document whose ClassificationID is a DOCUMENT_STATUS id',
    CONCAT('INSERT INTO Document (Title, BusinessDescription, OwnerUserID, ClassificationID, LifecycleStatusID) ',
           'VALUES (''Bad Classification'', ''IND-DEMO'', ', @u_owner, ', ', @doc_status_active, ', ', @doc_status_draft, ')'));


-- ============================================================================
-- PART 4 - UNKNOWN VALUE IS REJECTED
-- ============================================================================
-- EXPECT Rejected (by the trigger first; the FK is a second line of defence).
-- ============================================================================

SELECT '=== PART 4: Non-existent ReferenceDataID is rejected ===' AS Demo;

CALL sp__ind_expect_reject('UNKNOWN', 'INSERT Workflow with WorkflowStatusID that does not exist',
    CONCAT('INSERT INTO Workflow (DocumentID, DocumentVersionID, InitiatorUserID, ',
           'WorkflowPurposeTypeID, WorkflowStatusID, CancellationReason) VALUES (',
           @doc_msa, ', ', @ver_msa, ', ', @u_owner, ', ',
           @wf_purpose_review, ', 999999999, ''IND-DEMO'')'));


-- ============================================================================
-- PART 5 - FORMERLY HARD-CODED DOMAINS ARE TABLE-DRIVEN TOO
-- ============================================================================
-- RequiredPolicy used CHECK (RequiredPolicy = 'ALL_REQUIRED').
-- AuditLog.EventType accepted any non-blank string.
-- Both are now validated against ReferenceData (REQUIRED_POLICY,
-- AUDIT_EVENT_TYPE).
-- ============================================================================

SELECT '=== PART 5: Code-valued columns validated against the table ===' AS Demo;

CALL sp__ind_expect_ok('CODE', 'WorkflowStep with RequiredPolicy ALL_REQUIRED is accepted',
    CONCAT('INSERT INTO WorkflowStep (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID) ',
           'VALUES (', @wf_test, ', 1, ', @step_type_review, ', ''ALL_REQUIRED'', ', @step_status_pend, ')'));

CALL sp__ind_expect_reject('CODE', 'WorkflowStep with RequiredPolicy ANY_REQUIRED (not a REQUIRED_POLICY value)',
    CONCAT('INSERT INTO WorkflowStep (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID) ',
           'VALUES (', @wf_test, ', 2, ', @step_type_review, ', ''ANY_REQUIRED'', ', @step_status_pend, ')'));

CALL sp__ind_expect_reject('CODE', 'AuditLog with EventType BOGUS_EVENT (not an AUDIT_EVENT_TYPE value)',
    'INSERT INTO AuditLog (ActorUserID, EventType, AffectedRecordType) VALUES (NULL, ''BOGUS_EVENT'', ''Workflow'')');

CALL sp__ind_expect_reject('CODE', 'AuditLog with AffectedRecordType Spreadsheet (not an AUDIT_RECORD_TYPE value)',
    'INSERT INTO AuditLog (ActorUserID, EventType, AffectedRecordType) VALUES (NULL, ''WORKFLOW_INITIATED'', ''Spreadsheet'')');


-- ============================================================================
-- PART 6 - RETIRING A VALUE (IsActive = FALSE)
-- ============================================================================
-- WHAT   The business retires PUBLIC.
-- EXPECT - it disappears from the list of values;
--        - new use is rejected;
--        - the historical Document that uses it stays valid, still decodes
--          to "Public", and its other columns can still be maintained.
-- ============================================================================

SELECT '=== PART 6: Retire PUBLIC (IsActive = FALSE) ===' AS Demo;

UPDATE ReferenceData
SET IsActive = FALSE
WHERE ReferenceDataID = @classif_public;

CALL sp_get_indicator_values('DOCUMENT_CLASSIFICATION');

CALL sp__ind_check('RETIRE', 'Retired value no longer offered in the list of values',
    NOT EXISTS (SELECT 1 FROM vw_IndicatorValue
                WHERE IndicatorName = 'DOCUMENT_CLASSIFICATION'
                  AND IndicatorValue = 'PUBLIC' AND IsActive = TRUE),
    'sp_get_indicator_values returns active values only');

CALL sp__ind_expect_reject('RETIRE', 'New Document using the retired PUBLIC value is rejected',
    CONCAT('INSERT INTO Document (Title, BusinessDescription, OwnerUserID, ClassificationID, LifecycleStatusID) ',
           'VALUES (''Another Brochure'', ''IND-DEMO'', ', @u_owner, ', ', @classif_public, ', ', @doc_status_draft, ')'));

CALL sp__ind_check('RETIRE', 'Historical Document still decodes to the current description',
    (SELECT DecodedDescription FROM vw_CodedValueIntegrity
     WHERE TableName = 'Document' AND ColumnName = 'ClassificationID'
       AND RecordKey = CAST(@doc_public AS CHAR)) = 'Public'
    AND (SELECT IntegrityStatus FROM vw_CodedValueIntegrity
         WHERE TableName = 'Document' AND ColumnName = 'ClassificationID'
           AND RecordKey = CAST(@doc_public AS CHAR)) = 'VALID',
    'Reports join by ID without filtering IsActive');

CALL sp__ind_expect_ok('RETIRE', 'Historical Document can still be maintained (Title update)',
    CONCAT('UPDATE Document SET Title = ''Public Product Brochure (2026)'' WHERE DocumentID = ', @doc_public));


-- ============================================================================
-- PART 7 - REPORT DECODING SURFACES INVALID CODES
-- ============================================================================

SELECT '=== PART 7: Report decoding ===' AS Demo;

SELECT
    fn_decode_indicator('SIGNATURE_METHOD', 'TYPED_NAME')       AS KnownCode,
    fn_decode_indicator('DOCUMENT_CLASSIFICATION', 'TOP_SECRET') AS UnknownCode;

CALL sp__ind_check('DECODE', 'A code not in the table renders visibly as INVALID',
    fn_decode_indicator('DOCUMENT_CLASSIFICATION', 'TOP_SECRET') LIKE 'INVALID [%',
    fn_decode_indicator('DOCUMENT_CLASSIFICATION', 'TOP_SECRET'));

SELECT '--- Integrity report: any coded value anywhere that is not VALID (expect none) ---' AS Demo;

SELECT TableName, ColumnName, RecordKey, StoredValue, DecodedDescription, IntegrityStatus
FROM vw_CodedValueIntegrity
WHERE IntegrityStatus <> 'VALID';

CALL sp__ind_check('DECODE', 'Every coded value in the database is a member of its indicator',
    NOT EXISTS (SELECT 1 FROM vw_CodedValueIntegrity WHERE IntegrityStatus <> 'VALID'),
    CONCAT((SELECT COUNT(*) FROM vw_CodedValueIntegrity), ' coded values checked across 20 columns'));


-- ============================================================================
-- PART 8 - CLEANUP
-- ============================================================================

SELECT '=== PART 8: Cleanup ===' AS Demo;

CALL sp__ind_cleanup();

CALL sp__ind_check('CLEANUP', 'All IND-DEMO rows removed',
    NOT EXISTS (SELECT 1 FROM Workflow WHERE CancellationReason = 'IND-DEMO')
    AND NOT EXISTS (SELECT 1 FROM Document WHERE BusinessDescription = 'IND-DEMO')
    AND NOT EXISTS (SELECT 1 FROM ReferenceData WHERE Description = 'IND-DEMO'),
    'Workflow, WorkflowStep, Document and ReferenceData demo rows deleted');


-- ============================================================================
-- SCOREBOARD
-- ============================================================================

SELECT '=== SCOREBOARD ===' AS Demo;

SELECT seq, area, test_name, result, detail
FROM ind_results
ORDER BY seq;

SELECT
    SUM(result = 'PASS') AS Passed,
    SUM(result = 'FAIL') AS Failed,
    IF(SUM(result = 'FAIL') = 0, 'ALL INDICATOR VALUE CHECKS PASSED',
                                 'SOME CHECKS FAILED') AS Summary
FROM ind_results;


-- ============================================================================
-- TEARDOWN
-- ============================================================================

DROP PROCEDURE IF EXISTS sp__ind_check;
DROP PROCEDURE IF EXISTS sp__ind_expect_reject;
DROP PROCEDURE IF EXISTS sp__ind_expect_ok;
DROP PROCEDURE IF EXISTS sp__ind_cleanup;
DROP TEMPORARY TABLE IF EXISTS ind_results;

SET SESSION sql_mode = @ind_saved_sql_mode;
