-- ============================================================
-- File: database/02_programmability/040_triggers.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Enforce database-level protection for immutable and
--   append-only historical records.
--
-- Triggers:
--   trg_DocumentVersion_PreventFinalizedUpdate
--   trg_DocumentVersion_PreventFinalizedDelete
--   trg_ApprovalDecision_PreventUpdate
--   trg_ApprovalDecision_PreventDelete
--   trg_Signature_PreventUpdate
--   trg_Signature_PreventDelete
--   trg_AuditLog_PreventUpdate
--   trg_AuditLog_PreventDelete
--
-- Notes:
--   Workflow progression and authorization logic belongs in
--   stored procedures rather than triggers.
-- ============================================================

DELIMITER //


-- ============================================================
-- 1. Prevent modification of finalized/locked DocumentVersion
-- ============================================================
-- Supports:
--   BR-12
--   RES-03
--
-- A DocumentVersion in LOCKED status is historical and may not
-- be modified through ordinary operations.
-- ============================================================

CREATE TRIGGER trg_DocumentVersion_PreventFinalizedUpdate
BEFORE UPDATE ON DocumentVersion
FOR EACH ROW
BEGIN
    DECLARE v_old_status_code VARCHAR(50);

    SELECT Code
    INTO v_old_status_code
    FROM ReferenceData
    WHERE ReferenceDataID = OLD.CurrentVersionStatusID
      AND DomainName = 'DOCUMENT_VERSION_STATUS';

    IF v_old_status_code = 'LOCKED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Locked DocumentVersion records may not be modified.';
    END IF;
END//


-- ============================================================
-- 2. Prevent deletion of finalized/locked DocumentVersion
-- ============================================================

CREATE TRIGGER trg_DocumentVersion_PreventFinalizedDelete
BEFORE DELETE ON DocumentVersion
FOR EACH ROW
BEGIN
    DECLARE v_status_code VARCHAR(50);

    SELECT Code
    INTO v_status_code
    FROM ReferenceData
    WHERE ReferenceDataID = OLD.CurrentVersionStatusID
      AND DomainName = 'DOCUMENT_VERSION_STATUS';

    IF v_status_code = 'LOCKED' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Locked DocumentVersion records may not be deleted.';
    END IF;
END//


-- ============================================================
-- 3. Protect ApprovalDecision from UPDATE
-- ============================================================
-- Supports:
--   SEC-04
--   historical approval integrity
--
-- Approval decisions are append-only historical records.
-- Corrections must be represented through a separate controlled
-- correction/replacement process rather than editing the
-- original row.
-- ============================================================

CREATE TRIGGER trg_ApprovalDecision_PreventUpdate
BEFORE UPDATE ON ApprovalDecision
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'ApprovalDecision records are immutable and may not be updated.';
END//


-- ============================================================
-- 4. Protect ApprovalDecision from DELETE
-- ============================================================

CREATE TRIGGER trg_ApprovalDecision_PreventDelete
BEFORE DELETE ON ApprovalDecision
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'ApprovalDecision records are historical and may not be deleted.';
END//


-- ============================================================
-- 5. Protect Signature from UPDATE
-- ============================================================
-- Supports:
--   SEC-04
--   historical signature integrity
--
-- A recorded signature must remain tied to the exact
-- DocumentVersion originally signed.
-- ============================================================

CREATE TRIGGER trg_Signature_PreventUpdate
BEFORE UPDATE ON Signature
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Signature records are immutable and may not be updated.';
END//


-- ============================================================
-- 6. Protect Signature from DELETE
-- ============================================================

CREATE TRIGGER trg_Signature_PreventDelete
BEFORE DELETE ON Signature
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'Signature records are historical and may not be deleted.';
END//


-- ============================================================
-- 7. Make AuditLog append-only
-- ============================================================
-- Supports:
--   FR-15
--   SEC-11
--   RES-06
--
-- Audit records may be inserted but may not be modified after
-- creation.
-- ============================================================

CREATE TRIGGER trg_AuditLog_PreventUpdate
BEFORE UPDATE ON AuditLog
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'AuditLog is append-only; existing audit records may not be updated.';
END//


-- ============================================================
-- 8. Prevent AuditLog deletion
-- ============================================================

CREATE TRIGGER trg_AuditLog_PreventDelete
BEFORE DELETE ON AuditLog
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
            'AuditLog records may not be deleted.';
END//


DELIMITER ;