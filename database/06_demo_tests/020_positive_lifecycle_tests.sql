-- ============================================================
-- POSITIVE LIFECYCLE TESTS
-- ============================================================

SELECT '============================================================'
    AS TestSection;

SELECT 'POSITIVE LIFECYCLE TESTS'
    AS TestSection;

SELECT '============================================================'
    AS TestSection;


-- ============================================================
-- TEST 8
-- Positive document-version creation.
--
-- Proves:
--   - Document owner can create a version.
--   - New version receives CURRENT status.
--   - Version is tied to the correct document/creator.
--   - Audit history is created.
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_test_08_create_document_version $$

CREATE PROCEDURE sp_test_08_create_document_version()
BEGIN
    DECLARE v_owner_id BIGINT UNSIGNED;
    DECLARE v_document_id BIGINT UNSIGNED;
    DECLARE v_document_version_id BIGINT UNSIGNED;

    DECLARE v_draft_document_status_id BIGINT UNSIGNED;
    DECLARE v_classification_id BIGINT UNSIGNED;

    DECLARE v_version_count INT DEFAULT 0;
    DECLARE v_audit_count INT DEFAULT 0;

    DECLARE v_version_number INT;
    DECLARE v_version_status VARCHAR(50);
    DECLARE v_created_by BIGINT UNSIGNED;


    -- --------------------------------------------------------
    -- Use Olivia Brooks as the document owner.
    -- --------------------------------------------------------

    SELECT UserID
    INTO v_owner_id
    FROM `User`
    WHERE Email = 'olivia.brooks@initech.example'
    LIMIT 1;


    -- --------------------------------------------------------
    -- Resolve controlled values for the test document.
    -- --------------------------------------------------------

    SELECT ReferenceDataID
    INTO v_draft_document_status_id
    FROM ReferenceData
    WHERE DomainName = 'DOCUMENT_STATUS'
      AND Code = 'DRAFT'
      AND IsActive = TRUE
    LIMIT 1;


    SELECT ReferenceDataID
    INTO v_classification_id
    FROM ReferenceData
    WHERE DomainName = 'DOCUMENT_CLASSIFICATION'
      AND Code = 'INTERNAL'
      AND IsActive = TRUE
    LIMIT 1;


    -- --------------------------------------------------------
    -- Create a dedicated test document with no versions.
    -- --------------------------------------------------------

    INSERT INTO Document
    (
        Title,
        BusinessDescription,
        OwnerUserID,
        ClassificationID,
        LifecycleStatusID
    )
    VALUES
    (
        'Demo Version Creation Document',
        'Temporary document used for positive version-creation testing.',
        v_owner_id,
        v_classification_id,
        v_draft_document_status_id
    );


    SET v_document_id = LAST_INSERT_ID();


    -- Verify there are initially no versions.
    SELECT COUNT(*)
    INTO v_version_count
    FROM DocumentVersion
    WHERE DocumentID = v_document_id;


    IF v_version_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 8 FAILED: new test document unexpectedly already has versions.';
    END IF;


    -- --------------------------------------------------------
    -- Perform the operation being tested.
    -- --------------------------------------------------------

    CALL sp_create_document_version(
        v_owner_id,
        v_document_id,
        1,
        'Initial controlled test version'
    );


    -- --------------------------------------------------------
    -- Retrieve the created version.
    -- --------------------------------------------------------

    SELECT
        dv.DocumentVersionID,
        dv.VersionNumber,
        rd.Code,
        dv.CreatedByUserID
    INTO
        v_document_version_id,
        v_version_number,
        v_version_status,
        v_created_by
    FROM DocumentVersion dv
    JOIN ReferenceData rd
      ON rd.ReferenceDataID = dv.CurrentVersionStatusID
    WHERE dv.DocumentID = v_document_id
    LIMIT 1;


    -- --------------------------------------------------------
    -- Verify exactly one version exists.
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_version_count
    FROM DocumentVersion
    WHERE DocumentID = v_document_id;


    IF v_version_count <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 8 FAILED: expected exactly one DocumentVersion.';
    END IF;


    IF v_version_number <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 8 FAILED: incorrect VersionNumber.';
    END IF;


    IF v_version_status <> 'CURRENT' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 8 FAILED: new version is not CURRENT.';
    END IF;


    IF v_created_by <> v_owner_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 8 FAILED: CreatedByUserID does not match document owner.';
    END IF;


    -- --------------------------------------------------------
    -- Verify corresponding audit event.
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_audit_count
    FROM AuditLog
    WHERE EventType = 'DOCUMENT_VERSION_CREATED'
      AND AffectedRecordType = 'DocumentVersion'
      AND AffectedRecordID = v_document_version_id;


    IF v_audit_count <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 8 FAILED: document-version audit event was not created.';
    END IF;


    SELECT
        'PASS' AS Result,
        'TEST 8 - Document owner successfully created CURRENT document version'
            AS TestName,
        v_document_id AS DocumentID,
        v_document_version_id AS DocumentVersionID,
        v_version_number AS VersionNumber,
        v_version_status AS VersionStatus,
        v_audit_count AS AuditRows;

END $$

DELIMITER ;


CALL sp_test_08_create_document_version();

DROP PROCEDURE sp_test_08_create_document_version;

-- ============================================================
-- TEST 9
-- Positive workflow expiration.
--
-- Proves:
--   - Expired ACTIVE workflow transitions to EXPIRED.
--   - Outstanding steps become CANCELLED.
--   - Outstanding participant assignments become CANCELLED.
--   - WORKFLOW_EXPIRED audit event is created.
--
-- NOTE:
--   sp_expire_workflows is a batch procedure. It may also expire
--   other seeded ACTIVE workflows whose ExpirationDateTime has
--   already passed.
-- ============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_test_09_expire_workflow $$

CREATE PROCEDURE sp_test_09_expire_workflow()
BEGIN
    DECLARE v_document_id BIGINT UNSIGNED;
    DECLARE v_version_id BIGINT UNSIGNED;
    DECLARE v_owner_id BIGINT UNSIGNED;

    DECLARE v_workflow_id BIGINT UNSIGNED;
    DECLARE v_step_id BIGINT UNSIGNED;
    DECLARE v_participant_id BIGINT UNSIGNED;

    DECLARE v_reviewer_id BIGINT UNSIGNED;
    DECLARE v_reviewer_role_id BIGINT UNSIGNED;

    DECLARE v_purpose_id BIGINT UNSIGNED;
    DECLARE v_workflow_active_id BIGINT UNSIGNED;
    DECLARE v_step_active_id BIGINT UNSIGNED;
    DECLARE v_participant_active_id BIGINT UNSIGNED;

    DECLARE v_step_type_id BIGINT UNSIGNED;
    DECLARE v_action_id BIGINT UNSIGNED;

    DECLARE v_workflow_status VARCHAR(50);
    DECLARE v_step_status VARCHAR(50);
    DECLARE v_participant_status VARCHAR(50);

    DECLARE v_audit_count INT DEFAULT 0;


    -- --------------------------------------------------------
    -- Locate the dedicated document/version created by Test 8.
    -- --------------------------------------------------------

    SELECT
        d.DocumentID,
        dv.DocumentVersionID,
        d.OwnerUserID
    INTO
        v_document_id,
        v_version_id,
        v_owner_id
    FROM Document d
    JOIN DocumentVersion dv
      ON dv.DocumentID = d.DocumentID
    WHERE d.Title = 'Demo Version Creation Document'
      AND dv.VersionNumber = 1
    ORDER BY d.DocumentID DESC
    LIMIT 1;


    -- --------------------------------------------------------
    -- Resolve reviewer and role.
    -- --------------------------------------------------------

    SELECT
        u.UserID,
        r.RoleID
    INTO
        v_reviewer_id,
        v_reviewer_role_id
    FROM `User` u
    JOIN UserRole ur
      ON ur.UserID = u.UserID
    JOIN Role r
      ON r.RoleID = ur.RoleID
    WHERE u.Email = 'marcus.reed@initech.example'
      AND r.RoleName = 'Reviewer'
    LIMIT 1;


    -- --------------------------------------------------------
    -- Resolve controlled reference values.
    -- --------------------------------------------------------

    SELECT ReferenceDataID
    INTO v_purpose_id
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_PURPOSE_TYPE'
      AND Code = 'REVIEW'
      AND IsActive = TRUE
    LIMIT 1;


    SELECT ReferenceDataID
    INTO v_workflow_active_id
    FROM ReferenceData
    WHERE DomainName = 'WORKFLOW_STATUS'
      AND Code = 'ACTIVE'
      AND IsActive = TRUE
    LIMIT 1;


    SELECT ReferenceDataID
    INTO v_step_type_id
    FROM ReferenceData
    WHERE DomainName = 'STEP_TYPE'
      AND Code = 'REVIEW'
      AND IsActive = TRUE
    LIMIT 1;


    SELECT ReferenceDataID
    INTO v_step_active_id
    FROM ReferenceData
    WHERE DomainName = 'STEP_STATUS'
      AND Code = 'ACTIVE'
      AND IsActive = TRUE
    LIMIT 1;


    SELECT ReferenceDataID
    INTO v_action_id
    FROM ReferenceData
    WHERE DomainName = 'ASSIGNED_ACTION'
      AND Code = 'REVIEW'
      AND IsActive = TRUE
    LIMIT 1;


    SELECT ReferenceDataID
    INTO v_participant_active_id
    FROM ReferenceData
    WHERE DomainName = 'PARTICIPANT_STATUS'
      AND Code = 'ACTIVE'
      AND IsActive = TRUE
    LIMIT 1;


    -- --------------------------------------------------------
    -- Create a dedicated ACTIVE workflow whose expiration time
    -- has already passed.
    --
    -- This is test setup; the behavior being tested is the
    -- expiration procedure.
    -- --------------------------------------------------------

    INSERT INTO Workflow
    (
        DocumentID,
        DocumentVersionID,
        InitiatorUserID,
        WorkflowPurposeTypeID,
        WorkflowStatusID,
        StartDateTime,
        ExpirationDateTime
    )
    VALUES
    (
        v_document_id,
        v_version_id,
        v_owner_id,
        v_purpose_id,
        v_workflow_active_id,
        DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 2 DAY),
        DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 DAY)
    );


    SET v_workflow_id = LAST_INSERT_ID();


    -- --------------------------------------------------------
    -- Create one ACTIVE workflow step.
    -- --------------------------------------------------------

    INSERT INTO WorkflowStep
    (
        WorkflowID,
        SequenceNumber,
        StepTypeID,
        RequiredPolicy,
        StepStatusID,
        ActivationDateTime,
        CompletionDateTime,
        DueDateTime
    )
    VALUES
    (
        v_workflow_id,
        1,
        v_step_type_id,
        'ALL_REQUIRED',
        v_step_active_id,
        DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 2 DAY),
        NULL,
        DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 DAY)
    );


    SET v_step_id = LAST_INSERT_ID();


    -- --------------------------------------------------------
    -- Create one ACTIVE participant assignment.
    -- --------------------------------------------------------

    INSERT INTO WorkflowParticipant
    (
        WorkflowStepID,
        UserID,
        RoleID,
        AssignedActionID,
        AssignmentStatusID,
        RequiredFlag,
        ActivationDateTime,
        CompletionDateTime,
        DueDateTime
    )
    VALUES
    (
        v_step_id,
        v_reviewer_id,
        v_reviewer_role_id,
        v_action_id,
        v_participant_active_id,
        TRUE,
        DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 2 DAY),
        NULL,
        DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 DAY)
    );


    SET v_participant_id = LAST_INSERT_ID();


    -- --------------------------------------------------------
    -- Perform expiration scan.
    --
    -- NULL indicates a SYSTEM actor if your AuditLog permits a
    -- nullable ActorUserID, as your current sample data does.
    -- --------------------------------------------------------

    CALL sp_expire_workflows(NULL);


    -- --------------------------------------------------------
    -- Read resulting workflow status.
    -- --------------------------------------------------------

    SELECT rd.Code
    INTO v_workflow_status
    FROM Workflow w
    JOIN ReferenceData rd
      ON rd.ReferenceDataID = w.WorkflowStatusID
    WHERE w.WorkflowID = v_workflow_id;


    SELECT rd.Code
    INTO v_step_status
    FROM WorkflowStep ws
    JOIN ReferenceData rd
      ON rd.ReferenceDataID = ws.StepStatusID
    WHERE ws.WorkflowStepID = v_step_id;


    SELECT rd.Code
    INTO v_participant_status
    FROM WorkflowParticipant wp
    JOIN ReferenceData rd
      ON rd.ReferenceDataID = wp.AssignmentStatusID
    WHERE wp.WorkflowParticipantID = v_participant_id;


    -- --------------------------------------------------------
    -- Verify audit event.
    -- --------------------------------------------------------

    SELECT COUNT(*)
    INTO v_audit_count
    FROM AuditLog
    WHERE EventType = 'WORKFLOW_EXPIRED'
      AND AffectedRecordType = 'Workflow'
      AND AffectedRecordID = v_workflow_id;


    -- --------------------------------------------------------
    -- Assertions.
    -- --------------------------------------------------------

    IF v_workflow_status <> 'EXPIRED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 9 FAILED: workflow did not transition to EXPIRED.';
    END IF;


    IF v_step_status <> 'CANCELLED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 9 FAILED: outstanding step was not CANCELLED.';
    END IF;


    IF v_participant_status <> 'CANCELLED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 9 FAILED: outstanding participant was not CANCELLED.';
    END IF;


    IF v_audit_count <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'TEST 9 FAILED: WORKFLOW_EXPIRED audit event not found.';
    END IF;


    SELECT
        'PASS' AS Result,
        'TEST 9 - Expired workflow and outstanding work transitioned correctly'
            AS TestName,
        v_workflow_id AS WorkflowID,
        v_workflow_status AS WorkflowStatus,
        v_step_status AS StepStatus,
        v_participant_status AS ParticipantStatus,
        v_audit_count AS AuditRows;

END $$

DELIMITER ;


CALL sp_test_09_expire_workflow();

DROP PROCEDURE sp_test_09_expire_workflow;