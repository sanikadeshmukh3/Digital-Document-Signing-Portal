-- ============================================================
-- File: database/02_programability/070_refactor_workflow_procedures.sql
--
-- Purpose:
--   Route all operational Workflow lifecycle changes through
--   sp_transition_workflow.
-- ============================================================

DELIMITER $$


DROP PROCEDURE IF EXISTS sp_advance_workflow $$

CREATE PROCEDURE sp_advance_workflow (...)
BEGIN
    -- copied from 030
    -- direct completion UPDATE replaced with CALL
END $$


DROP PROCEDURE IF EXISTS sp_initiate_workflow $$

CREATE PROCEDURE sp_initiate_workflow (...)
BEGIN
    -- copied from 030
    -- DRAFT -> ACTIVE UPDATE replaced with CALL
    -- duplicate transition audit removed
END $$


DROP PROCEDURE IF EXISTS sp_record_approval_decision $$

CREATE PROCEDURE sp_record_approval_decision (...)
BEGIN
    -- copied from 030
    -- rejection status UPDATE replaced with CALL
    -- decision audit separated from transition audit
END $$


DROP PROCEDURE IF EXISTS sp_cancel_workflow $$

CREATE PROCEDURE sp_cancel_workflow (...)
BEGIN
    -- copied from 030
    -- status UPDATE replaced with CALL
    -- duplicate child cleanup removed
    -- duplicate transition audit removed


    
END $$


DROP PROCEDURE IF EXISTS sp_expire_workflows $$

CREATE PROCEDURE sp_expire_workflows (...)
BEGIN
    -- copied from 030
    -- terminal UPDATE replaced with CALL
    -- duplicate child cleanup removed
    -- duplicate transition audit removed
END $$


DELIMITER ;