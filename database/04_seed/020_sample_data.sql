-- ============================================================
-- File: database/04_seed/020_sample_data.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Seed a complete, internally consistent demonstration dataset:
--   business roles, users, user-role assignments, documents,
--   versions, workflows, steps, participants, approval decisions,
--   signatures, and audit events.
--
-- Database: MySQL 8.x
--
-- Conventions used here:
--   - Every reference ID (status/type/action/classification) and
--     every user/role ID is resolved by natural key via subquery
--     (ReferenceData DomainName+Code, User.Email, Role.RoleName),
--     so no generated surrogate IDs are hardcoded.
--   - Rows are inserted in FK-safe dependency order.
--   - Workflow/step/participant/decision/signature rows are inserted
--     directly in their final, consistent states rather than driven
--     through the stored procedures, so the dataset deterministically
--     covers every status path and every view.
--   - DocumentVersion rows tied to active/completed workflows are
--     inserted already LOCKED, since the finalized-update trigger
--     blocks updating a LOCKED row (they are never UPDATEd to LOCKED).
--   - Every Signature.DocumentVersionID equals its workflow's
--     DocumentVersionID.
--   - Every participant (UserID, RoleID) already exists in UserRole
--     with the role matching the action
--     (REVIEW/ACKNOWLEDGEMENT -> Reviewer, APPROVAL -> Approver,
--      SIGNATURE -> Signer), and the participant action code equals
--     the parent step's StepType code.
--   - DATETIME literals satisfy every CHECK constraint:
--     completion >= activation/start, due >= activation,
--     expiration >= start.
--
-- Scenarios covered:
--   A. DRAFT document with a CURRENT version and NO workflow.
--   B. ACTIVE sequential workflow (step1 ACTIVE/participant ACTIVE,
--      step2 PENDING/participant PENDING) with an OUTSTANDING action
--      feeding vw_OutstandingActions; version LOCKED.
--   C. COMPLETED full workflow (REVIEW->APPROVAL->SIGNATURE), all
--      steps/participants COMPLETED, APPROVED decision, SIGNED
--      signature against the locked version; version LOCKED.
--   D. REJECTED workflow (APPROVAL rejected, remaining work
--      CANCELLED); version LOCKED.
--   E. CANCELLED workflow (CancellationReason set); version LOCKED.
--   F. PARALLEL workflow (two steps sharing one SequenceNumber),
--      ACTIVE; version LOCKED.
-- ============================================================

START TRANSACTION;

-- ============================================================
-- 1. Role  (seven business roles; non-blank ResponsibilityCategory)
-- ============================================================

INSERT INTO Role (RoleName, Description, ResponsibilityCategory)
VALUES
    ('Document Owner',
     'Owns documents and initiates workflows.', 'Ownership'),
    ('Reviewer',
     'Performs review and acknowledgement actions.', 'Review'),
    ('Approver',
     'Records approval or rejection decisions.', 'Approval'),
    ('Signer',
     'Applies electronic signatures.', 'Signing'),
    ('Workflow Manager',
     'Oversees workflow operations and reporting.', 'Operations'),
    ('System Administrator',
     'Administers users, roles, and reference data.', 'Administration'),
    ('Auditor',
     'Performs read-only audit and history review.', 'Audit');


-- ============================================================
-- 2. User  (realistic fictional people at a well-known
--    fictional organization; statuses from ACCOUNT_STATUS)
-- ============================================================

INSERT INTO `User`
    (FirstName, LastName, Email, OrganizationalAffiliation, AccountStatusID)
VALUES
    ('Olivia', 'Brooks', 'olivia.brooks@initech.example',
     'Initech', (SELECT ReferenceDataID FROM ReferenceData
        WHERE DomainName='ACCOUNT_STATUS' AND Code='ACTIVE')),
    ('Marcus', 'Reed', 'marcus.reed@initech.example',
     'Initech', (SELECT ReferenceDataID FROM ReferenceData
        WHERE DomainName='ACCOUNT_STATUS' AND Code='ACTIVE')),
    ('Priya', 'Nair', 'priya.nair@initech.example',
     'Initech', (SELECT ReferenceDataID FROM ReferenceData
        WHERE DomainName='ACCOUNT_STATUS' AND Code='ACTIVE')),
    ('Daniel', 'Cho', 'daniel.cho@initech.example',
     'Initech', (SELECT ReferenceDataID FROM ReferenceData
        WHERE DomainName='ACCOUNT_STATUS' AND Code='ACTIVE')),
    ('Sofia', 'Alvarez', 'sofia.alvarez@initech.example',
     'Initech', (SELECT ReferenceDataID FROM ReferenceData
        WHERE DomainName='ACCOUNT_STATUS' AND Code='ACTIVE')),
    ('James', 'Okafor', 'james.okafor@initech.example',
     'Initech', (SELECT ReferenceDataID FROM ReferenceData
        WHERE DomainName='ACCOUNT_STATUS' AND Code='ACTIVE')),
    ('Hannah', 'Lindqvist', 'hannah.lindqvist@initech.example',
     'Initech', (SELECT ReferenceDataID FROM ReferenceData
        WHERE DomainName='ACCOUNT_STATUS' AND Code='ACTIVE')),
    ('Tomas', 'Novak', 'tomas.novak@initech.example',
     'Initech', (SELECT ReferenceDataID FROM ReferenceData
        WHERE DomainName='ACCOUNT_STATUS' AND Code='ACTIVE')),
    ('Grace', 'Kim', 'grace.kim@initech.example',
     'Initech', (SELECT ReferenceDataID FROM ReferenceData
        WHERE DomainName='ACCOUNT_STATUS' AND Code='ACTIVE')),
    -- One INACTIVE account for coverage/variety (not a workflow actor).
    ('Victor', 'Pullman', 'victor.pullman@initech.example',
     'Initech', (SELECT ReferenceDataID FROM ReferenceData
        WHERE DomainName='ACCOUNT_STATUS' AND Code='INACTIVE'));


-- ============================================================
-- 3. UserRole  (every workflow participant holds the role its
--    action requires; a user may hold multiple roles)
-- ============================================================
-- Role map:
--   Olivia Brooks   -> Document Owner, Workflow Manager
--   Marcus Reed     -> Reviewer
--   Priya Nair      -> Reviewer, Approver
--   Daniel Cho      -> Approver
--   Sofia Alvarez   -> Signer
--   James Okafor    -> Signer, Reviewer
--   Hannah Lindqvist-> System Administrator, Document Owner
--   Tomas Novak     -> Auditor
--   Grace Kim       -> Approver, Reviewer
--   (Victor Pullman -> inactive; no workflow role needed)
-- ============================================================

INSERT INTO UserRole (UserID, RoleID)
SELECT u.UserID, r.RoleID
FROM `User` u
JOIN Role r
WHERE (u.Email = 'olivia.brooks@initech.example'    AND r.RoleName = 'Document Owner')
   OR (u.Email = 'olivia.brooks@initech.example'    AND r.RoleName = 'Workflow Manager')
   OR (u.Email = 'marcus.reed@initech.example'      AND r.RoleName = 'Reviewer')
   OR (u.Email = 'priya.nair@initech.example'       AND r.RoleName = 'Reviewer')
   OR (u.Email = 'priya.nair@initech.example'       AND r.RoleName = 'Approver')
   OR (u.Email = 'daniel.cho@initech.example'       AND r.RoleName = 'Approver')
   OR (u.Email = 'sofia.alvarez@initech.example'    AND r.RoleName = 'Signer')
   OR (u.Email = 'james.okafor@initech.example'     AND r.RoleName = 'Signer')
   OR (u.Email = 'james.okafor@initech.example'     AND r.RoleName = 'Reviewer')
   OR (u.Email = 'hannah.lindqvist@initech.example' AND r.RoleName = 'System Administrator')
   OR (u.Email = 'hannah.lindqvist@initech.example' AND r.RoleName = 'Document Owner')
   OR (u.Email = 'tomas.novak@initech.example'      AND r.RoleName = 'Auditor')
   OR (u.Email = 'grace.kim@initech.example'        AND r.RoleName = 'Approver')
   OR (u.Email = 'grace.kim@initech.example'        AND r.RoleName = 'Reviewer');


-- ============================================================
-- 4. Document  (varied classification and lifecycle status;
--    owners hold 'Document Owner')
-- ============================================================
-- Doc 1: DRAFT  / INTERNAL      owner Olivia      (Scenario A)
-- Doc 2: ACTIVE / CONFIDENTIAL  owner Olivia      (Scenario B + C)
-- Doc 3: ACTIVE / RESTRICTED    owner Hannah      (Scenario D + E)
-- Doc 4: ARCHIVED / INTERNAL    owner Olivia      (Scenario F)
-- ============================================================

INSERT INTO Document
    (Title, BusinessDescription, OwnerUserID, ClassificationID, LifecycleStatusID)
VALUES
    ('Employee Handbook',
     'Company-wide employee handbook, still in drafting.',
     (SELECT UserID FROM `User` WHERE Email='olivia.brooks@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_CLASSIFICATION' AND Code='INTERNAL'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_STATUS' AND Code='DRAFT')),

    ('Master Services Agreement',
     'Standard MSA used for client engagements.',
     (SELECT UserID FROM `User` WHERE Email='olivia.brooks@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_CLASSIFICATION' AND Code='CONFIDENTIAL'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_STATUS' AND Code='ACTIVE')),

    ('Data Processing Addendum',
     'Restricted addendum covering data-processing terms.',
     (SELECT UserID FROM `User` WHERE Email='hannah.lindqvist@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_CLASSIFICATION' AND Code='RESTRICTED'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_STATUS' AND Code='ACTIVE')),

    ('Legacy Travel Policy',
     'Superseded travel policy retained for history.',
     (SELECT UserID FROM `User` WHERE Email='olivia.brooks@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_CLASSIFICATION' AND Code='INTERNAL'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_STATUS' AND Code='ACTIVE'));


-- ============================================================
-- 5. DocumentVersion
-- ============================================================
-- Doc 1 "Employee Handbook":      v1 CURRENT (no workflow)      -> Scenario A
-- Doc 2 "Master Services Agreement": v1 LOCKED (completed WF C),
--                                    v2 LOCKED (active WF B)
-- Doc 3 "Data Processing Addendum":  v1 LOCKED (rejected WF D),
--                                    v2 LOCKED (cancelled WF E)
-- Doc 4 "Legacy Travel Policy":      v1 LOCKED (parallel WF F)
-- LOCKED rows are inserted directly as LOCKED with LockedDateTime set.
-- ============================================================

-- Doc 1 v1 - CURRENT, no workflow (Scenario A)
INSERT INTO DocumentVersion
    (DocumentID, VersionNumber, EffectiveInformation, CreatedDateTime,
     CreatedByUserID, CurrentVersionStatusID, LockedDateTime)
VALUES
    ((SELECT DocumentID FROM Document WHERE Title='Employee Handbook'),
     1, 'Initial draft of the handbook.', '2026-01-05 09:00:00',
     (SELECT UserID FROM `User` WHERE Email='olivia.brooks@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_VERSION_STATUS' AND Code='CURRENT'),
     NULL);

-- Doc 2 v1 - LOCKED (completed workflow C)
INSERT INTO DocumentVersion
    (DocumentID, VersionNumber, EffectiveInformation, CreatedDateTime,
     CreatedByUserID, CurrentVersionStatusID, LockedDateTime)
VALUES
    ((SELECT DocumentID FROM Document WHERE Title='Master Services Agreement'),
     1, 'MSA version finalized through full workflow.', '2026-01-10 08:00:00',
     (SELECT UserID FROM `User` WHERE Email='olivia.brooks@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_VERSION_STATUS' AND Code='LOCKED'),
     '2026-01-10 09:00:00');

-- Doc 2 v2 - LOCKED (active workflow B)
INSERT INTO DocumentVersion
    (DocumentID, VersionNumber, EffectiveInformation, CreatedDateTime,
     CreatedByUserID, CurrentVersionStatusID, LockedDateTime)
VALUES
    ((SELECT DocumentID FROM Document WHERE Title='Master Services Agreement'),
     2, 'MSA revision currently moving through an active workflow.', '2026-02-01 08:00:00',
     (SELECT UserID FROM `User` WHERE Email='olivia.brooks@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_VERSION_STATUS' AND Code='LOCKED'),
     '2026-02-02 09:00:00');

-- Doc 3 v1 - LOCKED (rejected workflow D)
INSERT INTO DocumentVersion
    (DocumentID, VersionNumber, EffectiveInformation, CreatedDateTime,
     CreatedByUserID, CurrentVersionStatusID, LockedDateTime)
VALUES
    ((SELECT DocumentID FROM Document WHERE Title='Data Processing Addendum'),
     1, 'DPA version that was rejected during approval.', '2026-01-15 08:00:00',
     (SELECT UserID FROM `User` WHERE Email='hannah.lindqvist@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_VERSION_STATUS' AND Code='LOCKED'),
     '2026-01-15 09:00:00');

-- Doc 3 v2 - LOCKED (cancelled workflow E)
INSERT INTO DocumentVersion
    (DocumentID, VersionNumber, EffectiveInformation, CreatedDateTime,
     CreatedByUserID, CurrentVersionStatusID, LockedDateTime)
VALUES
    ((SELECT DocumentID FROM Document WHERE Title='Data Processing Addendum'),
     2, 'DPA version whose workflow was cancelled.', '2026-02-05 08:00:00',
     (SELECT UserID FROM `User` WHERE Email='hannah.lindqvist@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_VERSION_STATUS' AND Code='LOCKED'),
     '2026-02-05 09:00:00');

-- Doc 4 v1 - LOCKED (parallel workflow F)
INSERT INTO DocumentVersion
    (DocumentID, VersionNumber, EffectiveInformation, CreatedDateTime,
     CreatedByUserID, CurrentVersionStatusID, LockedDateTime)
VALUES
    ((SELECT DocumentID FROM Document WHERE Title='Legacy Travel Policy'),
     1, 'Travel policy routed through a parallel review workflow.', '2026-01-20 08:00:00',
     (SELECT UserID FROM `User` WHERE Email='olivia.brooks@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='DOCUMENT_VERSION_STATUS' AND Code='LOCKED'),
     '2026-01-20 09:00:00');


-- ============================================================
-- Helpful reusable lookups are inlined as subqueries below.
-- For readability, workflow inserts capture generated IDs via
-- natural-key SELECTs immediately after each insert.
-- ============================================================


-- ============================================================
-- 6a. Scenario C - COMPLETED full workflow (Doc 2 v1)
--     REVIEW(seq1) -> APPROVAL(seq2) -> SIGNATURE(seq3)
-- ============================================================

INSERT INTO Workflow
    (DocumentID, DocumentVersionID, InitiatorUserID,
     WorkflowPurposeTypeID, WorkflowStatusID,
     StartDateTime, CompletionDateTime, ExpirationDateTime)
VALUES
    ((SELECT DocumentID FROM Document WHERE Title='Master Services Agreement'),
     (SELECT DocumentVersionID FROM DocumentVersion
        WHERE DocumentID=(SELECT DocumentID FROM Document WHERE Title='Master Services Agreement')
          AND VersionNumber=1),
     (SELECT UserID FROM `User` WHERE Email='olivia.brooks@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='WORKFLOW_PURPOSE_TYPE' AND Code='FULL_REVIEW_APPROVAL_SIGNATURE'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='WORKFLOW_STATUS' AND Code='COMPLETED'),
     '2026-01-11 09:00:00', '2026-01-13 16:00:00', '2026-02-11 09:00:00');

SET @wf_c = LAST_INSERT_ID();

-- Step C1: REVIEW, COMPLETED
INSERT INTO WorkflowStep
    (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID,
     ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@wf_c, 1,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_TYPE' AND Code='REVIEW'),
     'ALL_REQUIRED',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_STATUS' AND Code='COMPLETED'),
     '2026-01-11 09:00:00', '2026-01-11 15:00:00', '2026-01-12 17:00:00');
SET @step_c1 = LAST_INSERT_ID();

-- Step C2: APPROVAL, COMPLETED
INSERT INTO WorkflowStep
    (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID,
     ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@wf_c, 2,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_TYPE' AND Code='APPROVAL'),
     'ALL_REQUIRED',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_STATUS' AND Code='COMPLETED'),
     '2026-01-11 15:00:00', '2026-01-12 11:00:00', '2026-01-13 17:00:00');
SET @step_c2 = LAST_INSERT_ID();

-- Step C3: SIGNATURE, COMPLETED
INSERT INTO WorkflowStep
    (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID,
     ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@wf_c, 3,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_TYPE' AND Code='SIGNATURE'),
     'ALL_REQUIRED',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_STATUS' AND Code='COMPLETED'),
     '2026-01-12 11:00:00', '2026-01-13 16:00:00', '2026-01-14 17:00:00');
SET @step_c3 = LAST_INSERT_ID();

-- Participant C1: Marcus Reed (Reviewer), REVIEW, COMPLETED
INSERT INTO WorkflowParticipant
    (WorkflowStepID, UserID, RoleID, AssignedActionID, AssignmentStatusID,
     RequiredFlag, ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@step_c1,
     (SELECT UserID FROM `User` WHERE Email='marcus.reed@initech.example'),
     (SELECT RoleID FROM Role WHERE RoleName='Reviewer'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='ASSIGNED_ACTION' AND Code='REVIEW'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='PARTICIPANT_STATUS' AND Code='COMPLETED'),
     TRUE, '2026-01-11 09:00:00', '2026-01-11 15:00:00', '2026-01-12 17:00:00');
SET @part_c1 = LAST_INSERT_ID();

-- Participant C2: Daniel Cho (Approver), APPROVAL, COMPLETED
INSERT INTO WorkflowParticipant
    (WorkflowStepID, UserID, RoleID, AssignedActionID, AssignmentStatusID,
     RequiredFlag, ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@step_c2,
     (SELECT UserID FROM `User` WHERE Email='daniel.cho@initech.example'),
     (SELECT RoleID FROM Role WHERE RoleName='Approver'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='ASSIGNED_ACTION' AND Code='APPROVAL'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='PARTICIPANT_STATUS' AND Code='COMPLETED'),
     TRUE, '2026-01-11 15:00:00', '2026-01-12 11:00:00', '2026-01-13 17:00:00');
SET @part_c2 = LAST_INSERT_ID();

-- Participant C3: Sofia Alvarez (Signer), SIGNATURE, COMPLETED
INSERT INTO WorkflowParticipant
    (WorkflowStepID, UserID, RoleID, AssignedActionID, AssignmentStatusID,
     RequiredFlag, ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@step_c3,
     (SELECT UserID FROM `User` WHERE Email='sofia.alvarez@initech.example'),
     (SELECT RoleID FROM Role WHERE RoleName='Signer'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='ASSIGNED_ACTION' AND Code='SIGNATURE'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='PARTICIPANT_STATUS' AND Code='COMPLETED'),
     TRUE, '2026-01-12 11:00:00', '2026-01-13 16:00:00', '2026-01-14 17:00:00');
SET @part_c3 = LAST_INSERT_ID();

-- Approval decision C2: APPROVED
INSERT INTO ApprovalDecision
    (WorkflowParticipantID, DecisionValueID, DecisionDateTime, Comments, RejectionReason)
VALUES
    (@part_c2,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='APPROVAL_DECISION' AND Code='APPROVED'),
     '2026-01-12 11:00:00', 'Terms acceptable; approved.', NULL);

SET @approval_c2 = LAST_INSERT_ID();

-- Signature C3: SIGNED against the workflow's version (Doc 2 v1)
INSERT INTO Signature
    (WorkflowParticipantID, DocumentVersionID, SigningDateTime,
     SignatureStatusID, SignatureMethod, SignatureReference)
VALUES
    (@part_c3,
     (SELECT DocumentVersionID FROM DocumentVersion
        WHERE DocumentID=(SELECT DocumentID FROM Document WHERE Title='Master Services Agreement')
          AND VersionNumber=1),
     '2026-01-13 16:00:00',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='SIGNATURE_STATUS' AND Code='SIGNED'),
     'TYPED_NAME', 'SIG-MSA-V1-0001');

SET @signature_c3 = LAST_INSERT_ID();


-- ============================================================
-- 6b. Scenario B - ACTIVE sequential workflow (Doc 2 v2)
--     REVIEW(seq1) COMPLETED -> APPROVAL(seq2) ACTIVE (outstanding)
--     plus a trailing PENDING step to show seq2 is not last.
-- ============================================================

INSERT INTO Workflow
    (DocumentID, DocumentVersionID, InitiatorUserID,
     WorkflowPurposeTypeID, WorkflowStatusID,
     StartDateTime, ExpirationDateTime)
VALUES
    ((SELECT DocumentID FROM Document WHERE Title='Master Services Agreement'),
     (SELECT DocumentVersionID FROM DocumentVersion
        WHERE DocumentID=(SELECT DocumentID FROM Document WHERE Title='Master Services Agreement')
          AND VersionNumber=2),
     (SELECT UserID FROM `User` WHERE Email='olivia.brooks@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='WORKFLOW_PURPOSE_TYPE' AND Code='FULL_REVIEW_APPROVAL_SIGNATURE'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='WORKFLOW_STATUS' AND Code='ACTIVE'),
     '2026-02-02 09:00:00', '2026-03-02 09:00:00');
SET @wf_b = LAST_INSERT_ID();

-- Step B1: REVIEW, COMPLETED
INSERT INTO WorkflowStep
    (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID,
     ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@wf_b, 1,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_TYPE' AND Code='REVIEW'),
     'ALL_REQUIRED',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_STATUS' AND Code='COMPLETED'),
     '2026-02-02 09:00:00', '2026-02-02 14:00:00', '2026-02-03 17:00:00');
SET @step_b1 = LAST_INSERT_ID();

-- Step B2: APPROVAL, ACTIVE (outstanding)
INSERT INTO WorkflowStep
    (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID,
     ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@wf_b, 2,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_TYPE' AND Code='APPROVAL'),
     'ALL_REQUIRED',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_STATUS' AND Code='ACTIVE'),
     '2026-02-02 14:00:00', NULL, '2026-02-28 17:00:00');
SET @step_b2 = LAST_INSERT_ID();

-- Step B3: SIGNATURE, PENDING
INSERT INTO WorkflowStep
    (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID,
     ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@wf_b, 3,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_TYPE' AND Code='SIGNATURE'),
     'ALL_REQUIRED',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_STATUS' AND Code='PENDING'),
     NULL, NULL, NULL);
SET @step_b3 = LAST_INSERT_ID();

-- Participant B1: Priya Nair (Reviewer), REVIEW, COMPLETED
INSERT INTO WorkflowParticipant
    (WorkflowStepID, UserID, RoleID, AssignedActionID, AssignmentStatusID,
     RequiredFlag, ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@step_b1,
     (SELECT UserID FROM `User` WHERE Email='priya.nair@initech.example'),
     (SELECT RoleID FROM Role WHERE RoleName='Reviewer'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='ASSIGNED_ACTION' AND Code='REVIEW'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='PARTICIPANT_STATUS' AND Code='COMPLETED'),
     TRUE, '2026-02-02 09:00:00', '2026-02-02 14:00:00', '2026-02-03 17:00:00');

-- Participant B2: Daniel Cho (Approver), APPROVAL, ACTIVE  (OUTSTANDING)
INSERT INTO WorkflowParticipant
    (WorkflowStepID, UserID, RoleID, AssignedActionID, AssignmentStatusID,
     RequiredFlag, ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@step_b2,
     (SELECT UserID FROM `User` WHERE Email='daniel.cho@initech.example'),
     (SELECT RoleID FROM Role WHERE RoleName='Approver'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='ASSIGNED_ACTION' AND Code='APPROVAL'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='PARTICIPANT_STATUS' AND Code='ACTIVE'),
     TRUE, '2026-02-02 14:00:00', NULL, '2026-02-28 17:00:00');

-- Participant B3: Sofia Alvarez (Signer), SIGNATURE, PENDING
INSERT INTO WorkflowParticipant
    (WorkflowStepID, UserID, RoleID, AssignedActionID, AssignmentStatusID,
     RequiredFlag, ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@step_b3,
     (SELECT UserID FROM `User` WHERE Email='sofia.alvarez@initech.example'),
     (SELECT RoleID FROM Role WHERE RoleName='Signer'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='ASSIGNED_ACTION' AND Code='SIGNATURE'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='PARTICIPANT_STATUS' AND Code='PENDING'),
     TRUE, NULL, NULL, NULL);


-- ============================================================
-- 6c. Scenario D - REJECTED workflow (Doc 3 v1)
--     REVIEW(seq1) COMPLETED -> APPROVAL(seq2) REJECTED,
--     trailing SIGNATURE(seq3) CANCELLED.
-- ============================================================

INSERT INTO Workflow
    (DocumentID, DocumentVersionID, InitiatorUserID,
     WorkflowPurposeTypeID, WorkflowStatusID,
     StartDateTime, ExpirationDateTime)
VALUES
    ((SELECT DocumentID FROM Document WHERE Title='Data Processing Addendum'),
     (SELECT DocumentVersionID FROM DocumentVersion
        WHERE DocumentID=(SELECT DocumentID FROM Document WHERE Title='Data Processing Addendum')
          AND VersionNumber=1),
     (SELECT UserID FROM `User` WHERE Email='hannah.lindqvist@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='WORKFLOW_PURPOSE_TYPE' AND Code='APPROVAL'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='WORKFLOW_STATUS' AND Code='REJECTED'),
     '2026-01-16 09:00:00', '2026-02-16 09:00:00');
SET @wf_d = LAST_INSERT_ID();

-- Step D1: REVIEW, COMPLETED
INSERT INTO WorkflowStep
    (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID,
     ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@wf_d, 1,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_TYPE' AND Code='REVIEW'),
     'ALL_REQUIRED',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_STATUS' AND Code='COMPLETED'),
     '2026-01-16 09:00:00', '2026-01-16 15:00:00', '2026-01-17 17:00:00');
SET @step_d1 = LAST_INSERT_ID();

-- Step D2: APPROVAL, CANCELLED. A rejection decision terminates the
-- workflow, so the step that was ACTIVE at rejection time is cancelled
-- (only COMPLETED steps carry all-required-participants-COMPLETED
-- semantics).
INSERT INTO WorkflowStep
    (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID,
     ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@wf_d, 2,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_TYPE' AND Code='APPROVAL'),
     'ALL_REQUIRED',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_STATUS' AND Code='CANCELLED'),
     '2026-01-16 15:00:00', NULL, '2026-01-18 17:00:00');
SET @step_d2 = LAST_INSERT_ID();

-- Step D3: SIGNATURE, CANCELLED
INSERT INTO WorkflowStep
    (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID,
     ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@wf_d, 3,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_TYPE' AND Code='SIGNATURE'),
     'ALL_REQUIRED',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_STATUS' AND Code='CANCELLED'),
     NULL, NULL, NULL);
SET @step_d3 = LAST_INSERT_ID();

-- Participant D1: James Okafor (Reviewer), REVIEW, COMPLETED
INSERT INTO WorkflowParticipant
    (WorkflowStepID, UserID, RoleID, AssignedActionID, AssignmentStatusID,
     RequiredFlag, ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@step_d1,
     (SELECT UserID FROM `User` WHERE Email='james.okafor@initech.example'),
     (SELECT RoleID FROM Role WHERE RoleName='Reviewer'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='ASSIGNED_ACTION' AND Code='REVIEW'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='PARTICIPANT_STATUS' AND Code='COMPLETED'),
     TRUE, '2026-01-16 09:00:00', '2026-01-16 15:00:00', '2026-01-17 17:00:00');

-- Participant D2: Grace Kim (Approver), APPROVAL, REJECTED
INSERT INTO WorkflowParticipant
    (WorkflowStepID, UserID, RoleID, AssignedActionID, AssignmentStatusID,
     RequiredFlag, ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@step_d2,
     (SELECT UserID FROM `User` WHERE Email='grace.kim@initech.example'),
     (SELECT RoleID FROM Role WHERE RoleName='Approver'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='ASSIGNED_ACTION' AND Code='APPROVAL'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='PARTICIPANT_STATUS' AND Code='REJECTED'),
     TRUE, '2026-01-16 15:00:00', '2026-01-17 10:00:00', '2026-01-18 17:00:00');
SET @part_d2 = LAST_INSERT_ID();

-- Participant D3: Sofia Alvarez (Signer), SIGNATURE, CANCELLED
INSERT INTO WorkflowParticipant
    (WorkflowStepID, UserID, RoleID, AssignedActionID, AssignmentStatusID,
     RequiredFlag, ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@step_d3,
     (SELECT UserID FROM `User` WHERE Email='sofia.alvarez@initech.example'),
     (SELECT RoleID FROM Role WHERE RoleName='Signer'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='ASSIGNED_ACTION' AND Code='SIGNATURE'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='PARTICIPANT_STATUS' AND Code='CANCELLED'),
     TRUE, NULL, NULL, NULL);

-- Approval decision D2: REJECTED with reason
INSERT INTO ApprovalDecision
    (WorkflowParticipantID, DecisionValueID, DecisionDateTime, Comments, RejectionReason)
VALUES
    (@part_d2,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='APPROVAL_DECISION' AND Code='REJECTED'),
     '2026-01-17 10:00:00', 'Liability terms are unacceptable.',
     'Section 7 liability cap conflicts with policy and must be renegotiated.');


-- ============================================================
-- 6d. Scenario E - CANCELLED workflow (Doc 3 v2)
--     REVIEW(seq1) CANCELLED after cancellation.
-- ============================================================

INSERT INTO Workflow
    (DocumentID, DocumentVersionID, InitiatorUserID,
     WorkflowPurposeTypeID, WorkflowStatusID,
     StartDateTime, CancellationDateTime, CancellationReason, ExpirationDateTime)
VALUES
    ((SELECT DocumentID FROM Document WHERE Title='Data Processing Addendum'),
     (SELECT DocumentVersionID FROM DocumentVersion
        WHERE DocumentID=(SELECT DocumentID FROM Document WHERE Title='Data Processing Addendum')
          AND VersionNumber=2),
     (SELECT UserID FROM `User` WHERE Email='hannah.lindqvist@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='WORKFLOW_PURPOSE_TYPE' AND Code='REVIEW'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='WORKFLOW_STATUS' AND Code='CANCELLED'),
     '2026-02-06 09:00:00', '2026-02-07 09:00:00',
     'Superseded by a newer addendum; workflow no longer needed.', '2026-03-06 09:00:00');
SET @wf_e = LAST_INSERT_ID();

-- Step E1: REVIEW, CANCELLED
INSERT INTO WorkflowStep
    (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID,
     ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@wf_e, 1,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_TYPE' AND Code='REVIEW'),
     'ALL_REQUIRED',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_STATUS' AND Code='CANCELLED'),
     '2026-02-06 09:00:00', NULL, '2026-02-10 17:00:00');
SET @step_e1 = LAST_INSERT_ID();

-- Participant E1: Marcus Reed (Reviewer), REVIEW, CANCELLED
INSERT INTO WorkflowParticipant
    (WorkflowStepID, UserID, RoleID, AssignedActionID, AssignmentStatusID,
     RequiredFlag, ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@step_e1,
     (SELECT UserID FROM `User` WHERE Email='marcus.reed@initech.example'),
     (SELECT RoleID FROM Role WHERE RoleName='Reviewer'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='ASSIGNED_ACTION' AND Code='REVIEW'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='PARTICIPANT_STATUS' AND Code='CANCELLED'),
     TRUE, '2026-02-06 09:00:00', NULL, '2026-02-10 17:00:00');


-- ============================================================
-- 6e. Scenario F - PARALLEL ACTIVE workflow (Doc 4 v1)
--     Two REVIEW steps share SequenceNumber 1 (parallel group),
--     both ACTIVE with ACTIVE participants (also outstanding).
-- ============================================================

INSERT INTO Workflow
    (DocumentID, DocumentVersionID, InitiatorUserID,
     WorkflowPurposeTypeID, WorkflowStatusID,
     StartDateTime, ExpirationDateTime)
VALUES
    ((SELECT DocumentID FROM Document WHERE Title='Legacy Travel Policy'),
     (SELECT DocumentVersionID FROM DocumentVersion
        WHERE DocumentID=(SELECT DocumentID FROM Document WHERE Title='Legacy Travel Policy')
          AND VersionNumber=1),
     (SELECT UserID FROM `User` WHERE Email='olivia.brooks@initech.example'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='WORKFLOW_PURPOSE_TYPE' AND Code='REVIEW'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='WORKFLOW_STATUS' AND Code='ACTIVE'),
     '2026-01-21 09:00:00', '2026-02-21 09:00:00');
SET @wf_f = LAST_INSERT_ID();

-- Step F1a: REVIEW, seq 1, ACTIVE (parallel)
INSERT INTO WorkflowStep
    (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID,
     ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@wf_f, 1,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_TYPE' AND Code='REVIEW'),
     'ALL_REQUIRED',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_STATUS' AND Code='ACTIVE'),
     '2026-01-21 09:00:00', NULL, '2026-02-15 17:00:00');
SET @step_f1a = LAST_INSERT_ID();

-- Step F1b: REVIEW, seq 1 (SAME sequence number -> parallel), ACTIVE
INSERT INTO WorkflowStep
    (WorkflowID, SequenceNumber, StepTypeID, RequiredPolicy, StepStatusID,
     ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@wf_f, 1,
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_TYPE' AND Code='REVIEW'),
     'ALL_REQUIRED',
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='STEP_STATUS' AND Code='ACTIVE'),
     '2026-01-21 09:00:00', NULL, '2026-02-15 17:00:00');
SET @step_f1b = LAST_INSERT_ID();

-- Participant F1a: Marcus Reed (Reviewer), REVIEW, ACTIVE (outstanding)
INSERT INTO WorkflowParticipant
    (WorkflowStepID, UserID, RoleID, AssignedActionID, AssignmentStatusID,
     RequiredFlag, ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@step_f1a,
     (SELECT UserID FROM `User` WHERE Email='marcus.reed@initech.example'),
     (SELECT RoleID FROM Role WHERE RoleName='Reviewer'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='ASSIGNED_ACTION' AND Code='REVIEW'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='PARTICIPANT_STATUS' AND Code='ACTIVE'),
     TRUE, '2026-01-21 09:00:00', NULL, '2026-02-15 17:00:00');

-- Participant F1b: James Okafor (Reviewer), REVIEW, ACTIVE (outstanding)
INSERT INTO WorkflowParticipant
    (WorkflowStepID, UserID, RoleID, AssignedActionID, AssignmentStatusID,
     RequiredFlag, ActivationDateTime, CompletionDateTime, DueDateTime)
VALUES
    (@step_f1b,
     (SELECT UserID FROM `User` WHERE Email='james.okafor@initech.example'),
     (SELECT RoleID FROM Role WHERE RoleName='Reviewer'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='ASSIGNED_ACTION' AND Code='REVIEW'),
     (SELECT ReferenceDataID FROM ReferenceData WHERE DomainName='PARTICIPANT_STATUS' AND Code='ACTIVE'),
     TRUE, '2026-01-21 09:00:00', NULL, '2026-02-15 17:00:00');


-- ============================================================
-- 7. AuditLog  (representative events, incl. a NULL-actor SYSTEM row)
-- ============================================================

INSERT INTO AuditLog
    (ActorUserID, EventType, AffectedRecordType, AffectedRecordID,
     TransactionReference, PriorValueContext, NewValueContext, ChangeReason)
VALUES
    -- Workflow C initiated
    ((SELECT UserID FROM `User` WHERE Email='olivia.brooks@initech.example'),
     'WORKFLOW_INITIATED', 'Workflow', @wf_c,
     'TXN-C-0001', NULL, 'Workflow activated for MSA v1',
     'Document Owner initiated full workflow.'),

    -- Approval recorded (Scenario C)
    ((SELECT UserID FROM `User` WHERE Email='daniel.cho@initech.example'),
     'APPROVAL_RECORDED', 'ApprovalDecision', @approval_c2,
     'TXN-C-0002', NULL, 'APPROVED', 'Approver approved MSA v1.'),

    -- Signature recorded (Scenario C)
    ((SELECT UserID FROM `User` WHERE Email='sofia.alvarez@initech.example'),
     'SIGNATURE_RECORDED', 'Signature', @signature_c3,
     'TXN-C-0003', NULL, 'DocumentVersion signed (MSA v1)',
     'Signer executed signature.'),

    -- Approval rejected (Scenario D)
    ((SELECT UserID FROM `User` WHERE Email='grace.kim@initech.example'),
     'APPROVAL_REJECTED', 'Workflow', @wf_d,
     'TXN-D-0001', 'ACTIVE', 'REJECTED',
     'Approval rejected; workflow terminated.'),

    -- Workflow cancelled (Scenario E)
    ((SELECT UserID FROM `User` WHERE Email='hannah.lindqvist@initech.example'),
     'WORKFLOW_CANCELLED', 'Workflow', @wf_e,
     'TXN-E-0001', 'ACTIVE', 'CANCELLED',
     'Workflow cancelled by document owner.'),

    -- System-generated event (NULL actor -> vw_AuditHistory 'SYSTEM')
    (NULL, 'WORKFLOW_EXPIRY_SCAN', 'Workflow', @wf_b,
     'TXN-SYS-0001', NULL, 'Expiration scan executed; no action taken.',
     'Scheduled system maintenance scan.');

COMMIT;
