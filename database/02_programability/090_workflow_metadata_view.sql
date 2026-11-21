-- ============================================================
-- File: database/02_programability/090_workflow_metadata_view.sql
-- Project: Document Workflow and E-signing Portal
--
-- Purpose:
--   Expose workflow transition metadata in a display-ready form
--   for the application service / GUI.
--
-- The view describes the workflow state machine itself.
-- It does NOT decide whether a particular user may execute an
-- action on a particular workflow instance.
-- ============================================================

CREATE OR REPLACE VIEW vw_WorkflowTransitionMetadata AS

SELECT
    wt.WorkflowStatusTransitionID,
    wt.TransitionCode,

    wt.FromStatusID,
    from_status.Code AS FromStatusCode,
    from_status.DisplayName AS FromStatusDisplayName,

    wt.ToStatusID,
    to_status.Code AS ToStatusCode,
    to_status.DisplayName AS ToStatusDisplayName,

    wt.IsActive,
    wt.SystemAllowedFlag,

    wt.Description,

    r.RoleID,
    r.RoleName,
    wtr.AllowedFlag

FROM WorkflowStatusTransition wt

JOIN ReferenceData from_status
    ON from_status.ReferenceDataID = wt.FromStatusID
   AND from_status.DomainName = 'WORKFLOW_STATUS'

JOIN ReferenceData to_status
    ON to_status.ReferenceDataID = wt.ToStatusID
   AND to_status.DomainName = 'WORKFLOW_STATUS'

LEFT JOIN WorkflowTransitionRole wtr
    ON wtr.WorkflowStatusTransitionID =
       wt.WorkflowStatusTransitionID

LEFT JOIN Role r
    ON r.RoleID = wtr.RoleID;