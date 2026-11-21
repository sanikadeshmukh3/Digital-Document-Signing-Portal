-- ============================================================
-- File:
-- database/02_programability/110_fix_workflow_metadata_view.sql
--
-- Purpose:
--   Extend vw_WorkflowTransitionMetadata with the workflow
--   UI metadata columns added to WorkflowStatusTransition.
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

    wt.ActionDisplayName,
    wt.RequiresReasonFlag,
    wt.ReasonLabel,
    wt.ConfirmationRequiredFlag,
    wt.DisplayOrder,

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