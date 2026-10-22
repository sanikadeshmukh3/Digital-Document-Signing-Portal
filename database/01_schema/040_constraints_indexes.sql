-- ============================================================
-- File: database/01_schema/040_constraints_indexes.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Add foreign-key constraints and operational indexes after
--   all schema tables have been created.
--
-- TDD / FRD goals supported:
--   - Referential integrity
--   - Valid document ownership
--   - Valid user-role assignments
--   - Valid workflow relationships
--   - Controlled reference values
--   - Preservation of historical records
--   - Efficient participant worklists and workflow queries
--
-- Notes:
--   - Business-state transitions are enforced later through
--     procedures/triggers.
--   - RESTRICT is used for historical/business records so that
--     referenced data cannot be silently deleted.
-- ============================================================


-- ============================================================
-- 1. User -> ReferenceData
-- ============================================================

ALTER TABLE `User`
    ADD CONSTRAINT fk_User_AccountStatus
        FOREIGN KEY (AccountStatusID)
        REFERENCES ReferenceData (ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;


-- ============================================================
-- 2. Document relationships
-- ============================================================

ALTER TABLE Document
    ADD CONSTRAINT fk_Document_Owner
        FOREIGN KEY (OwnerUserID)
        REFERENCES `User` (UserID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_Document_Classification
        FOREIGN KEY (ClassificationID)
        REFERENCES ReferenceData (ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_Document_LifecycleStatus
        FOREIGN KEY (LifecycleStatusID)
        REFERENCES ReferenceData (ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;


-- ============================================================
-- 3. DocumentVersion relationships
-- ============================================================

ALTER TABLE DocumentVersion
    ADD CONSTRAINT fk_DocumentVersion_Document
        FOREIGN KEY (DocumentID)
        REFERENCES Document (DocumentID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_DocumentVersion_CreatedBy
        FOREIGN KEY (CreatedByUserID)
        REFERENCES `User` (UserID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_DocumentVersion_CurrentStatus
        FOREIGN KEY (CurrentVersionStatusID)
        REFERENCES ReferenceData (ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;


-- ------------------------------------------------------------
-- Allows Workflow to enforce that its DocumentID and
-- DocumentVersionID refer to the same DocumentVersion record.
-- ------------------------------------------------------------

ALTER TABLE DocumentVersion
    ADD CONSTRAINT uq_DocumentVersion_ID_Document
        UNIQUE (DocumentVersionID, DocumentID);


-- ============================================================
-- 4. Workflow relationships
-- ============================================================

ALTER TABLE Workflow
    ADD CONSTRAINT fk_Workflow_Document
        FOREIGN KEY (DocumentID)
        REFERENCES Document (DocumentID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_Workflow_DocumentVersionContext
        FOREIGN KEY (DocumentVersionID, DocumentID)
        REFERENCES DocumentVersion (DocumentVersionID, DocumentID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_Workflow_Initiator
        FOREIGN KEY (InitiatorUserID)
        REFERENCES `User` (UserID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_Workflow_PurposeType
        FOREIGN KEY (WorkflowPurposeTypeID)
        REFERENCES ReferenceData (ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_Workflow_Status
        FOREIGN KEY (WorkflowStatusID)
        REFERENCES ReferenceData (ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;


-- ============================================================
-- 5. WorkflowStep relationships
-- ============================================================

ALTER TABLE WorkflowStep
    ADD CONSTRAINT fk_WorkflowStep_Workflow
        FOREIGN KEY (WorkflowID)
        REFERENCES Workflow (WorkflowID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_WorkflowStep_StepType
        FOREIGN KEY (StepTypeID)
        REFERENCES ReferenceData (ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_WorkflowStep_Status
        FOREIGN KEY (StepStatusID)
        REFERENCES ReferenceData (ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;


-- ============================================================
-- 6. UserRole relationships
-- ============================================================

ALTER TABLE UserRole
    ADD CONSTRAINT fk_UserRole_User
        FOREIGN KEY (UserID)
        REFERENCES `User` (UserID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_UserRole_Role
        FOREIGN KEY (RoleID)
        REFERENCES Role (RoleID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;


-- ============================================================
-- 7. WorkflowParticipant relationships
-- ============================================================

ALTER TABLE WorkflowParticipant
    ADD CONSTRAINT fk_WorkflowParticipant_WorkflowStep
        FOREIGN KEY (WorkflowStepID)
        REFERENCES WorkflowStep (WorkflowStepID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    -- This composite FK is important:
    -- it guarantees that the assigned User actually holds
    -- the Role stored on the participant assignment.
    ADD CONSTRAINT fk_WorkflowParticipant_UserRole
        FOREIGN KEY (UserID, RoleID)
        REFERENCES UserRole (UserID, RoleID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_WorkflowParticipant_AssignedAction
        FOREIGN KEY (AssignedActionID)
        REFERENCES ReferenceData (ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_WorkflowParticipant_Status
        FOREIGN KEY (AssignmentStatusID)
        REFERENCES ReferenceData (ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;


-- ============================================================
-- 8. ApprovalDecision relationships
-- ============================================================

ALTER TABLE ApprovalDecision
    ADD CONSTRAINT fk_ApprovalDecision_WorkflowParticipant
        FOREIGN KEY (WorkflowParticipantID)
        REFERENCES WorkflowParticipant (WorkflowParticipantID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_ApprovalDecision_DecisionValue
        FOREIGN KEY (DecisionValueID)
        REFERENCES ReferenceData (ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;


-- ============================================================
-- 9. Signature relationships
-- ============================================================

ALTER TABLE Signature
    ADD CONSTRAINT fk_Signature_WorkflowParticipant
        FOREIGN KEY (WorkflowParticipantID)
        REFERENCES WorkflowParticipant (WorkflowParticipantID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_Signature_DocumentVersion
        FOREIGN KEY (DocumentVersionID)
        REFERENCES DocumentVersion (DocumentVersionID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    ADD CONSTRAINT fk_Signature_Status
        FOREIGN KEY (SignatureStatusID)
        REFERENCES ReferenceData (ReferenceDataID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;


-- ============================================================
-- 10. AuditLog relationships
-- ============================================================

ALTER TABLE AuditLog
    ADD CONSTRAINT fk_AuditLog_Actor
        FOREIGN KEY (ActorUserID)
        REFERENCES `User` (UserID)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;


-- ============================================================
-- INDEXES
-- ============================================================
-- Indexes below are based on the operational access paths
-- described in the FRD/TDD.
--
-- Primary keys and UNIQUE constraints already create indexes,
-- so they are not duplicated here.
-- ============================================================


-- ------------------------------------------------------------
-- Document Owner queries
--
-- Supports:
--   "Show documents owned by User X"
-- ------------------------------------------------------------

CREATE INDEX idx_Document_Owner
    ON Document (OwnerUserID);


-- ------------------------------------------------------------
-- Document filtering by lifecycle status
-- ------------------------------------------------------------

CREATE INDEX idx_Document_LifecycleStatus
    ON Document (LifecycleStatusID);


-- ------------------------------------------------------------
-- Document version-history query
--
-- Note:
-- UNIQUE(DocumentID, VersionNumber) already provides the
-- primary access path for ordered version history.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- Workflow lookup by document/version
-- ------------------------------------------------------------

CREATE INDEX idx_Workflow_Document
    ON Workflow (DocumentID);

CREATE INDEX idx_Workflow_DocumentVersion
    ON Workflow (DocumentVersionID);


-- ------------------------------------------------------------
-- Active/status-based workflow searches
-- ------------------------------------------------------------

CREATE INDEX idx_Workflow_Status
    ON Workflow (WorkflowStatusID);


-- ------------------------------------------------------------
-- Expiration processing/reporting
--
-- Supports:
--   finding workflows by status and expiration date
-- ------------------------------------------------------------

CREATE INDEX idx_Workflow_Status_Expiration
    ON Workflow (
        WorkflowStatusID,
        ExpirationDateTime
    );


-- ------------------------------------------------------------
-- WorkflowStep sequencing
--
-- Supports:
--   retrieving steps in sequence order and identifying
--   parallel groups sharing the same SequenceNumber.
--
-- This is deliberately NOT UNIQUE because multiple steps may
-- share a SequenceNumber.
-- ------------------------------------------------------------

CREATE INDEX idx_WorkflowStep_Workflow_Sequence
    ON WorkflowStep (
        WorkflowID,
        SequenceNumber
    );


-- ------------------------------------------------------------
-- Step status lookup
-- ------------------------------------------------------------

CREATE INDEX idx_WorkflowStep_Status
    ON WorkflowStep (StepStatusID);


-- ------------------------------------------------------------
-- Participant worklist index
--
-- Supports FR-08 / FR-17:
--   retrieve assignments for a participant by status and
--   order/filter using DueDateTime.
-- ------------------------------------------------------------

CREATE INDEX idx_WorkflowParticipant_User_Status_DueDate
    ON WorkflowParticipant (
        UserID,
        AssignmentStatusID,
        DueDateTime
    );


-- ------------------------------------------------------------
-- Step participant lookup
--
-- Supports:
--   evaluating whether all required assignments for a step
--   have completed.
-- ------------------------------------------------------------

CREATE INDEX idx_WorkflowParticipant_Step_Status_Required
    ON WorkflowParticipant (
        WorkflowStepID,
        AssignmentStatusID,
        RequiredFlag
    );


-- ------------------------------------------------------------
-- Role-based participant searches
-- ------------------------------------------------------------

CREATE INDEX idx_WorkflowParticipant_Role
    ON WorkflowParticipant (RoleID);


-- ------------------------------------------------------------
-- Audit history
--
-- Supports retrieving actions performed by a user over time.
-- ------------------------------------------------------------

CREATE INDEX idx_AuditLog_Actor_EventDate
    ON AuditLog (
        ActorUserID,
        EventDateTime
    );


-- ------------------------------------------------------------
-- Audit history for a specific affected business record.
--
-- Since AuditLog may reference multiple business entity types,
-- the type + identifier pair is indexed together.
-- ------------------------------------------------------------

CREATE INDEX idx_AuditLog_AffectedRecord
    ON AuditLog (
        AffectedRecordType,
        AffectedRecordID,
        EventDateTime
    );


-- ------------------------------------------------------------
-- Transaction-level audit reconstruction
--
-- Supports reconstructing all events belonging to one
-- transaction/business operation.
-- ------------------------------------------------------------

CREATE INDEX idx_AuditLog_TransactionReference
    ON AuditLog (TransactionReference);