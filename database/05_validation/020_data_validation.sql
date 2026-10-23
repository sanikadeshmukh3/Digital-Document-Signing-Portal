-- ============================================================
-- File: database/05_validation/020_data_validation.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Validate the seeded CONTENT: reference-data completeness,
--   non-empty core tables, foreign-key / uniqueness consistency,
--   role-assignment correctness, and workflow-status invariants.
--
-- Behavior:
--   A temporary stored procedure performs each check. Any violation
--   raises SQLSTATE '45000', aborting the build (fail-closed).
--   A per-table row-count result set is emitted for the demo.
--
-- Database: MySQL 8.x
-- ============================================================


-- ------------------------------------------------------------
-- Per-table row counts (for the demo).
-- ------------------------------------------------------------

SELECT 'ReferenceData' AS TableName, COUNT(*) AS RowCountValue FROM ReferenceData
UNION ALL SELECT 'Role', COUNT(*) FROM Role
UNION ALL SELECT 'User', COUNT(*) FROM `User`
UNION ALL SELECT 'UserRole', COUNT(*) FROM UserRole
UNION ALL SELECT 'Document', COUNT(*) FROM Document
UNION ALL SELECT 'DocumentVersion', COUNT(*) FROM DocumentVersion
UNION ALL SELECT 'Workflow', COUNT(*) FROM Workflow
UNION ALL SELECT 'WorkflowStep', COUNT(*) FROM WorkflowStep
UNION ALL SELECT 'WorkflowParticipant', COUNT(*) FROM WorkflowParticipant
UNION ALL SELECT 'ApprovalDecision', COUNT(*) FROM ApprovalDecision
UNION ALL SELECT 'Signature', COUNT(*) FROM Signature
UNION ALL SELECT 'AuditLog', COUNT(*) FROM AuditLog;


DELIMITER $$

DROP PROCEDURE IF EXISTS sp__validate_data $$

CREATE PROCEDURE sp__validate_data()
BEGIN
    DECLARE v_count INT;

    -- ========================================================
    -- 1. Core seeded tables must not be empty.
    -- ========================================================
    IF (SELECT COUNT(*) FROM ReferenceData) = 0
       OR (SELECT COUNT(*) FROM Role) = 0
       OR (SELECT COUNT(*) FROM `User`) = 0
       OR (SELECT COUNT(*) FROM UserRole) = 0
       OR (SELECT COUNT(*) FROM Document) = 0
       OR (SELECT COUNT(*) FROM DocumentVersion) = 0
       OR (SELECT COUNT(*) FROM Workflow) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a core seeded table is empty.';
    END IF;

    -- ========================================================
    -- 2. Required reference domains/codes present AND active.
    --    Expected total of enumerated codes = 40.
    -- ========================================================
    SELECT COUNT(*) INTO v_count
    FROM ReferenceData
    WHERE IsActive = TRUE
      AND (
          (DomainName='ACCOUNT_STATUS' AND Code IN ('ACTIVE','INACTIVE'))
       OR (DomainName='DOCUMENT_STATUS' AND Code IN ('DRAFT','ACTIVE','ARCHIVED'))
       OR (DomainName='DOCUMENT_CLASSIFICATION' AND Code IN ('INTERNAL','CONFIDENTIAL','RESTRICTED'))
       OR (DomainName='DOCUMENT_VERSION_STATUS' AND Code IN ('DRAFT','CURRENT','LOCKED'))
       OR (DomainName='WORKFLOW_STATUS' AND Code IN ('DRAFT','ACTIVE','COMPLETED','REJECTED','CANCELLED','EXPIRED'))
       OR (DomainName='WORKFLOW_PURPOSE_TYPE' AND Code IN ('REVIEW','APPROVAL','SIGNATURE','FULL_REVIEW_APPROVAL_SIGNATURE'))
       OR (DomainName='STEP_TYPE' AND Code IN ('REVIEW','APPROVAL','ACKNOWLEDGEMENT','SIGNATURE'))
       OR (DomainName='STEP_STATUS' AND Code IN ('PENDING','ACTIVE','COMPLETED','CANCELLED'))
       OR (DomainName='PARTICIPANT_STATUS' AND Code IN ('PENDING','ACTIVE','COMPLETED','REJECTED','CANCELLED', 'DECLINED'))
       OR (DomainName='ASSIGNED_ACTION' AND Code IN ('REVIEW','APPROVAL','ACKNOWLEDGEMENT','SIGNATURE'))
       OR (DomainName='APPROVAL_DECISION' AND Code IN ('APPROVED','REJECTED'))
       OR (DomainName='SIGNATURE_STATUS' AND Code IN ('SIGNED'))
      );
    IF v_count <> 42 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: one or more required reference codes are missing or inactive.';
    END IF;

    -- ========================================================
    -- 3. Role completeness (all 7 business roles).
    -- ========================================================
    SELECT COUNT(*) INTO v_count
    FROM Role
    WHERE RoleName IN (
        'Document Owner','Reviewer','Approver','Signer',
        'Workflow Manager','System Administrator','Auditor');
    IF v_count <> 7 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: not all 7 business roles are seeded.';
    END IF;

    -- Every Role must have a non-blank ResponsibilityCategory.
    SELECT COUNT(*) INTO v_count
    FROM Role WHERE TRIM(COALESCE(ResponsibilityCategory,'')) = '';
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a Role has a blank ResponsibilityCategory.';
    END IF;

    -- ========================================================
    -- 4. Scenario coverage: each workflow status present.
    -- ========================================================
    SELECT COUNT(DISTINCT rd.Code) INTO v_count
    FROM Workflow w
    JOIN ReferenceData rd ON rd.ReferenceDataID = w.WorkflowStatusID
    WHERE rd.Code IN ('ACTIVE','COMPLETED','REJECTED','CANCELLED');
    IF v_count <> 4 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: workflow scenarios (ACTIVE/COMPLETED/REJECTED/CANCELLED) not all present.';
    END IF;

    -- ========================================================
    -- 5. FK / consistency sanity (each must return zero rows).
    -- ========================================================

    -- 5a. Documents with a missing owner.
    SELECT COUNT(*) INTO v_count
    FROM Document d
    LEFT JOIN `User` u ON u.UserID = d.OwnerUserID
    WHERE u.UserID IS NULL;
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a Document references a missing owner.';
    END IF;

    -- 5b. Versions with no matching document.
    SELECT COUNT(*) INTO v_count
    FROM DocumentVersion dv
    LEFT JOIN Document d ON d.DocumentID = dv.DocumentID
    WHERE d.DocumentID IS NULL;
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a DocumentVersion has no matching Document.';
    END IF;

    -- 5c. Participants whose (UserID, RoleID) is not in UserRole.
    SELECT COUNT(*) INTO v_count
    FROM WorkflowParticipant wp
    LEFT JOIN UserRole ur
        ON ur.UserID = wp.UserID AND ur.RoleID = wp.RoleID
    WHERE ur.UserID IS NULL;
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a WorkflowParticipant (UserID, RoleID) is not present in UserRole.';
    END IF;

    -- 5d. Role must match the assigned action.
    SELECT COUNT(*) INTO v_count
    FROM WorkflowParticipant wp
    JOIN Role r ON r.RoleID = wp.RoleID
    JOIN ReferenceData action_ref ON action_ref.ReferenceDataID = wp.AssignedActionID
    WHERE NOT (
          (action_ref.Code IN ('REVIEW','ACKNOWLEDGEMENT') AND r.RoleName = 'Reviewer')
       OR (action_ref.Code = 'APPROVAL' AND r.RoleName = 'Approver')
       OR (action_ref.Code = 'SIGNATURE' AND r.RoleName = 'Signer')
    );
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a participant role does not match its assigned action.';
    END IF;

    -- 5e. Participant action code must equal its step StepType code.
    SELECT COUNT(*) INTO v_count
    FROM WorkflowParticipant wp
    JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN ReferenceData action_ref ON action_ref.ReferenceDataID = wp.AssignedActionID
    JOIN ReferenceData step_type ON step_type.ReferenceDataID = ws.StepTypeID
    WHERE action_ref.Code <> step_type.Code;
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a participant action does not match its WorkflowStep type.';
    END IF;

    -- 5f. Workflow.DocumentID must match the parent Document of Workflow.DocumentVersionID.
    SELECT COUNT(*) INTO v_count
    FROM Workflow w
    JOIN DocumentVersion dv
        ON dv.DocumentVersionID = w.DocumentVersionID
    WHERE w.DocumentID <> dv.DocumentID;

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: Workflow.DocumentID does not match the parent Document of its DocumentVersion.';
    END IF;


    -- ========================================================
    -- 6. ReferenceData domain correctness
    -- ========================================================
    -- Each foreign key into ReferenceData must point to the
    -- expected reference-data domain, not merely to an existing
    -- ReferenceData row.
    -- ========================================================


    -- --------------------------------------------------------
    -- 6a. User.AccountStatusID -> ACCOUNT_STATUS
    -- --------------------------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM `User` u
    JOIN ReferenceData rd
        ON rd.ReferenceDataID = u.AccountStatusID
    WHERE rd.DomainName <> 'ACCOUNT_STATUS';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: User.AccountStatusID references the wrong ReferenceData domain.';
    END IF;


    -- --------------------------------------------------------
    -- 6b. Document.ClassificationID -> DOCUMENT_CLASSIFICATION
    -- --------------------------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM Document d
    JOIN ReferenceData rd
        ON rd.ReferenceDataID = d.ClassificationID
    WHERE rd.DomainName <> 'DOCUMENT_CLASSIFICATION';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: Document.ClassificationID references the wrong ReferenceData domain.';
    END IF;


    -- --------------------------------------------------------
    -- 6c. Document.LifecycleStatusID -> DOCUMENT_STATUS
    -- --------------------------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM Document d
    JOIN ReferenceData rd
        ON rd.ReferenceDataID = d.LifecycleStatusID
    WHERE rd.DomainName <> 'DOCUMENT_STATUS';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: Document.LifecycleStatusID references the wrong ReferenceData domain.';
    END IF;


    -- --------------------------------------------------------
    -- 6d. DocumentVersion.CurrentVersionStatusID
    --     -> DOCUMENT_VERSION_STATUS
    -- --------------------------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM DocumentVersion dv
    JOIN ReferenceData rd
        ON rd.ReferenceDataID = dv.CurrentVersionStatusID
    WHERE rd.DomainName <> 'DOCUMENT_VERSION_STATUS';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: DocumentVersion.CurrentVersionStatusID references the wrong ReferenceData domain.';
    END IF;


    -- --------------------------------------------------------
    -- 6e. Workflow.WorkflowPurposeTypeID
    --     -> WORKFLOW_PURPOSE_TYPE
    -- --------------------------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM Workflow w
    JOIN ReferenceData rd
        ON rd.ReferenceDataID = w.WorkflowPurposeTypeID
    WHERE rd.DomainName <> 'WORKFLOW_PURPOSE_TYPE';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: Workflow.WorkflowPurposeTypeID references the wrong ReferenceData domain.';
    END IF;


    -- --------------------------------------------------------
    -- 6f. Workflow.WorkflowStatusID -> WORKFLOW_STATUS
    -- --------------------------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM Workflow w
    JOIN ReferenceData rd
        ON rd.ReferenceDataID = w.WorkflowStatusID
    WHERE rd.DomainName <> 'WORKFLOW_STATUS';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: Workflow.WorkflowStatusID references the wrong ReferenceData domain.';
    END IF;


    -- --------------------------------------------------------
    -- 6g. WorkflowStep.StepTypeID -> STEP_TYPE
    -- --------------------------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM WorkflowStep ws
    JOIN ReferenceData rd
        ON rd.ReferenceDataID = ws.StepTypeID
    WHERE rd.DomainName <> 'STEP_TYPE';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: WorkflowStep.StepTypeID references the wrong ReferenceData domain.';
    END IF;


    -- --------------------------------------------------------
    -- 6h. WorkflowStep.StepStatusID -> STEP_STATUS
    -- --------------------------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM WorkflowStep ws
    JOIN ReferenceData rd
        ON rd.ReferenceDataID = ws.StepStatusID
    WHERE rd.DomainName <> 'STEP_STATUS';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: WorkflowStep.StepStatusID references the wrong ReferenceData domain.';
    END IF;


    -- --------------------------------------------------------
    -- 6i. WorkflowParticipant.AssignedActionID
    --     -> ASSIGNED_ACTION
    -- --------------------------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM WorkflowParticipant wp
    JOIN ReferenceData rd
        ON rd.ReferenceDataID = wp.AssignedActionID
    WHERE rd.DomainName <> 'ASSIGNED_ACTION';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: WorkflowParticipant.AssignedActionID references the wrong ReferenceData domain.';
    END IF;


    -- --------------------------------------------------------
    -- 6j. WorkflowParticipant.AssignmentStatusID
    --     -> PARTICIPANT_STATUS
    -- --------------------------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM WorkflowParticipant wp
    JOIN ReferenceData rd
        ON rd.ReferenceDataID = wp.AssignmentStatusID
    WHERE rd.DomainName <> 'PARTICIPANT_STATUS';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: WorkflowParticipant.AssignmentStatusID references the wrong ReferenceData domain.';
    END IF;


    -- --------------------------------------------------------
    -- 6k. ApprovalDecision.DecisionValueID
    --     -> APPROVAL_DECISION
    -- --------------------------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM ApprovalDecision ad
    JOIN ReferenceData rd
        ON rd.ReferenceDataID = ad.DecisionValueID
    WHERE rd.DomainName <> 'APPROVAL_DECISION';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: ApprovalDecision.DecisionValueID references the wrong ReferenceData domain.';
    END IF;


    -- --------------------------------------------------------
    -- 6l. Signature.SignatureStatusID
    --     -> SIGNATURE_STATUS
    -- --------------------------------------------------------

    SELECT COUNT(*) INTO v_count
    FROM Signature s
    JOIN ReferenceData rd
        ON rd.ReferenceDataID = s.SignatureStatusID
    WHERE rd.DomainName <> 'SIGNATURE_STATUS';

    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Data validation failed: Signature.SignatureStatusID references the wrong ReferenceData domain.';
    END IF;

    -- ========================================================
    -- 7. Version uniqueness / positivity.
    -- ========================================================

    -- 7a. Duplicate (DocumentID, VersionNumber).
    SELECT COUNT(*) INTO v_count FROM (
        SELECT DocumentID, VersionNumber
        FROM DocumentVersion
        GROUP BY DocumentID, VersionNumber
        HAVING COUNT(*) > 1
    ) dup;
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: duplicate (DocumentID, VersionNumber) exists.';
    END IF;

    -- 7b. Non-positive version numbers.
    SELECT COUNT(*) INTO v_count FROM DocumentVersion WHERE VersionNumber <= 0;
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a DocumentVersion has a non-positive VersionNumber.';
    END IF;

    -- 7c. Duplicate (WorkflowStepID, UserID, AssignedActionID).
    SELECT COUNT(*) INTO v_count FROM (
        SELECT WorkflowStepID, UserID, AssignedActionID
        FROM WorkflowParticipant
        GROUP BY WorkflowStepID, UserID, AssignedActionID
        HAVING COUNT(*) > 1
    ) dup;
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: duplicate participant assignment (WorkflowStepID, UserID, AssignedActionID).';
    END IF;

    -- ========================================================
    -- 8. Workflow-status invariants.
    -- ========================================================

    -- 8a. A COMPLETED workflow has no participant in (PENDING, ACTIVE).
    SELECT COUNT(*) INTO v_count
    FROM Workflow w
    JOIN ReferenceData wf_status ON wf_status.ReferenceDataID = w.WorkflowStatusID
    JOIN WorkflowStep ws ON ws.WorkflowID = w.WorkflowID
    JOIN WorkflowParticipant wp ON wp.WorkflowStepID = ws.WorkflowStepID
    JOIN ReferenceData p_status ON p_status.ReferenceDataID = wp.AssignmentStatusID
    WHERE wf_status.Code = 'COMPLETED'
      AND p_status.Code IN ('PENDING','ACTIVE');
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a COMPLETED workflow still has PENDING/ACTIVE participants.';
    END IF;

    -- 8b. A COMPLETED step has all RequiredFlag participants COMPLETED.
    SELECT COUNT(*) INTO v_count
    FROM WorkflowStep ws
    JOIN ReferenceData s_status ON s_status.ReferenceDataID = ws.StepStatusID
    JOIN WorkflowParticipant wp ON wp.WorkflowStepID = ws.WorkflowStepID
    JOIN ReferenceData p_status ON p_status.ReferenceDataID = wp.AssignmentStatusID
    WHERE s_status.Code = 'COMPLETED'
      AND wp.RequiredFlag = TRUE
      AND p_status.Code <> 'COMPLETED';
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a COMPLETED step has a required participant that is not COMPLETED.';
    END IF;

    -- 8c. A REJECTED ApprovalDecision has a non-null, non-blank RejectionReason.
    SELECT COUNT(*) INTO v_count
    FROM ApprovalDecision ad
    JOIN ReferenceData dv ON dv.ReferenceDataID = ad.DecisionValueID
    WHERE dv.Code = 'REJECTED'
      AND (ad.RejectionReason IS NULL OR TRIM(ad.RejectionReason) = '');
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a REJECTED ApprovalDecision lacks a RejectionReason.';
    END IF;

    -- 8d. A CANCELLED workflow has a non-null CancellationReason.
    SELECT COUNT(*) INTO v_count
    FROM Workflow w
    JOIN ReferenceData wf_status ON wf_status.ReferenceDataID = w.WorkflowStatusID
    WHERE wf_status.Code = 'CANCELLED'
      AND (w.CancellationReason IS NULL OR TRIM(w.CancellationReason) = '');
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a CANCELLED workflow lacks a CancellationReason.';
    END IF;

    -- 8e. Every Signature's DocumentVersionID equals its workflow's DocumentVersionID.
    SELECT COUNT(*) INTO v_count
    FROM Signature s
    JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = s.WorkflowParticipantID
    JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
    JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
    WHERE s.DocumentVersionID <> w.DocumentVersionID;
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: a Signature references a DocumentVersion different from its workflow version.';
    END IF;

    -- 8f. At most one ApprovalDecision / Signature per participant.
    SELECT COUNT(*) INTO v_count FROM (
        SELECT WorkflowParticipantID FROM ApprovalDecision
        GROUP BY WorkflowParticipantID HAVING COUNT(*) > 1
    ) d;
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: more than one ApprovalDecision for a participant.';
    END IF;

    SELECT COUNT(*) INTO v_count FROM (
        SELECT WorkflowParticipantID FROM Signature
        GROUP BY WorkflowParticipantID HAVING COUNT(*) > 1
    ) d;
    IF v_count <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data validation failed: more than one Signature for a participant.';
    END IF;

    SELECT 'DATA VALIDATION PASSED: seeded content satisfies all invariants.' AS Result;
END $$

DELIMITER ;

CALL sp__validate_data();

DROP PROCEDURE sp__validate_data;
