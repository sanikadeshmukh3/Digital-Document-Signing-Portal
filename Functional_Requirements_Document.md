# Document Workflow and E-signing Portal

## Functional Requirements Document

**Prepared by:** Ismael Anwar, Sanika Deshmukh  
**Course:** 01:198:437:01  
**Date:** 09/29/2026  
**Version:** 2.0  
**Repository Location:** https://github.com/sanikadeshmukh3/Digital-Document-Signing-Portal

## Business Problem & Purpose

### Business Problem

Mid-sized legal and financial services firms need to manage documents that pass through multiple reviewers, approvers, and signers. These workflows may currently rely on email, shared drives, manually edited forms, paper documents, and electronic-signature platforms.

Using disconnected processes makes it difficult to determine who is responsible for a document, which actions have been completed, what version is current, and whether a document is ready for the next workflow stage. It also makes it difficult to produce reliable reports on document volume, turnaround time, outstanding actions, and workflow bottlenecks.

Common challenges include:
- Limited visibility into who has reviewed, approved, or signed a document
- Unclear document ownership and responsibility for outstanding actions
- Difficulty determining the current document and workflow status
- Difficulty enforcing the required order of workflow actions
- Inconsistent document version and metadata management
- Limited visibility into incomplete or overdue actions
- Limited reporting on document volume, turnaround time, and workflow bottlenecks
- Increased administrative effort for document owners and staff

Our proposed project will establish a controlled digital document workflow that tracks documents from initialization through review, approval, signature, completion, and archival.

### Project Purpose

The purpose of this project is to create a relational database that allows authorized users to manage and track digital document review, approval, and electronic-signature workflows. The database will provide a structured source of truth for documents, users, participants, workflow stages, signatures, document versions, statuses, and audit history while supporting document retrieval and operational reporting.

The system will model the business rules governing document workflows, including required participants, sequential and parallel workflow stages, valid status transitions, completion of required actions, and role-based access to sensitive operations.

## Scope

| In-scope | Out-scope |
| --- | --- |
| Storage and management of documents, including metadata, versions, and categories | Real-time collaborative document editing |
| Management of users and their application roles, such as Document Owner and Participant | Authentication and identity-management infrastructure such as SSO, MFA, or password management |
| Searching and filtering documents and workflow information | Email, SMS, or push notification services |
| Recording and tracking document review and approval actions | Integration with external electronic-signature platforms |
| Management and tracking of document and workflow statuses | Legal certification or independent verification of electronic signatures |
| Recording document and workflow history for auditing | Integration with external legal, financial, or document-management systems |
| Assignment of document owners and participants | Production deployment with infrastructure management |
| Recording electronic signature and their associated statuses | External signature services or legally binding electronic-signature processing |
| Configuration and execution of sequential and parallel workflow steps | - |
| Role-based access to document and workflow information and actions | - |

## Stakeholders and User Roles

| Stakeholder or role | Responsibilities | Database needs | Typical access |
| --- | --- | --- | --- |
| Document Owner | Initiates document workflows, assigns participants, monitors progress, and manages documents they own. | Create and maintain documents; assign participants; view workflow status; monitor outstanding actions. | Create/update owned documents; view associated workflow information. |
| Reviewer | Reviews assigned documents and records review decisions or completion. | Retrieve assigned documents; record review actions and outcomes. | View assigned documents; create review records; cannot modify workflow configuration. |
| Approver | Evaluates documents requiring formal approval and records approval decisions. | Retrieve documents awaiting approval; record approval or rejection; view relevant workflow history. | View assigned documents; record approval decisions. |
| Signer | Completes required electronic-signature actions. | Retrieve documents requiring signature; record signature and statuses. | View assigned documents; record signature. |
| Workflow Manager | Oversees document workflows, monitors outstanding actions, and reviews operational performance. | Access workflow status, exception information, and operational reports. | Broad read access; manage specified workflow information. |
| System Administrator | Maintains system-level user roles and administrative information. | Manage users, roles, and administrative records; review audit information. | Administrative access. |
| Auditor | Reviews document history and system activity for audit purposes. | Retrieve audit history, status changes, workflow events, and related records. | Read-only access to audit and historical information. |

## Functional Requirements

| Id | Functional Requirements | Priority | Related Data/entities | Related Roles |
| --- | --- | --- | --- | --- |
| FR-01 | The system shall maintain a record for each document, including the title, owner, status, document type, and creation date. | High | Document, User, | Document Owner |
| FR-02 | The system shall maintain a working version history for documents that are revised before or during a workflow | High | Document, DocumentVersion | Document Owner |
| FR-03 | The system shall allow an authorized Document Owner to initiate a workflow only for a document owned by that user, using a valid document version, and shall allow the owner to assign eligible users to required review, approval, acknowledgement, or signature actions before activation. | High | Workflow, WorkflowStep, DocumentVersion | Document Owner |
| FR-04 | The system shall store one record for each user, including identifying information, organizational affiliation if applicable, and account status | High | User, AccountStatus | Administrator |
| FR-05 | The system shall maintain the business roles assigned to each user so that a user may hold one or more roles when applicable | High | User, Role, UserRole | Administrator |
| FR-06 | The system shall allow an authorized Document Owner to assign one or more eligible users to workflow steps only when each assigned user holds the business role required for that action. The system shall permit a user to be assigned to multiple workflow steps when allowed by the workflow definition. | High | WorkflowStep, User, WorkflowParticipant | Document Owner |
| FR-07 | The system shall support workflow steps that represent review, approval, acknowledgement, or signature actions | High | WorkflowStep, StepType | Document Owner |
| FR-08 | The system shall allow a workflow participant to retrieve only workflow actions assigned to that participant and shall identify each assignment as pending, active, completed, rejected, declined, cancelled, or otherwise inactive according to its lifecycle state. | High | WorkflowParticipant, WorkflowStep, Workflow | Reviewer, Approver, Signer |
| FR-09 | The system shall record completion of an assigned review or acknowledgement action, including the participant and completion date/time | High | WorkflowParticipant, ApprovalDecision, Signature | Reviewer |
| FR-10 | The system shall record an approval decision for an assigned approver, including the decision, decision date/time, and comments when provided | High | WorkflowParticipant, ApprovalDecision | Approver |
| FR-11 | The system shall record an electronic-signature for an assigned signer, including the signer, the exact document version signed, signing date/time, and the signature status or method information required by the participant | High | WorkflowParticipant, Signature, DocumentVersion | Signer |
| FR-12 | The system shall reject a workflow action unless the current user is the assigned participant, the user holds the required business role, the workflow is Active, the workflow step is Active, the participant assignment is Active, the action has not already been completed, and all required predecessor steps have been completed. | High | WorkflowParticipant, WorkflowStep, Role | Reviewer, Approver, Signer |
| FR-13 | The system shall update and preserve meaningful lifecycle status changes for documents, workflows, steps, and participant assignments | High | WorkflowStatus, StepStatus, ParticipantStatus | Document Owner, Participant |
| FR-14 | The system shall prevent workflow completion while any required workflow action remains outstanding. | High | Workflow, WorkflowStep, WorkflowParticipant | Document Owner, Manager |
| FR-15 | The system shall record auditable events for selected document, version, workflow, approval, signature, status, and administrative changes. | High | AuditLog and affected business records | Administrator, Auditor |
| FR-16 | The system shall support cancellation or expiration of an active workflow and shall prevent ordinary participants from completing new workflow actions after that workflow is no longer active. | High | Workflow, WorkflowStauts, WorkflowParticipant | Document Owner, Administrator |
| FR-17 | The system shall produce an operational list of outstanding workflow actions showing the related document, required action, responsible participant, workflow status, and relevant due or expiration information. | Medium | Document, Workflow, WorkflowStep, WorkflowParticipant | Document Owner, Manager |
| FR-18 | The system shall allow authorized auditors or managers to retrieve the history of a selected document, including versions, workflows, participant actions, approvals, signatures, and auditable status events. | Medium | Document, DocumentVersion, Workflow, WorkflowParticipant, ApprovalDecision, Signature, AuditLog | Manager, Auditor |

## State Transition Model

### Workflow State-Transition Model

| Entity | Current State | Permitted next state | Initiated By | Preconditions | Enforcements |
| --- | --- | --- | --- | --- | --- |
| Document | Draft | Active/Available | Owner | At least one valid version exists | Procedure |
| DocumentVersion | Draft | Current | Owner | Version number is unique for document | Unique constraint + procedure |
| DocumentVersion | Current | Locked | System | Version is being used by an active or completed workflow | Trigger/procedure |
| Workflow | Draft | Active | Owner | Valid document version, at least one step, required assignments, valid sequence | Single transaction/procedure |
| Workflow | Active | Completed | System | All required assignments are completed successfully | Trigger/procedure |
| Workflow | Active | Cancelled | Owner/admin | Cancellation reason supplied | Procedure + audit |
| Workflow | Active | Expired | System/admin | Expiration timestamp has reached or explicit administrative action | Scheduled process/procedure |
| WorkflowStep | Pending | Active | System | Workflow Active and all predecessor sequence numbers complete. | Procedure/trigger |
| WorkflowStep | Active | Completed | System | All required assignments complete | Procedure/Trigger |
| WorkflowStep | Pending/Active | Cancelled | System | Workflow cancelled/rejected/expired | Procedure |
| Assignment | Pending | Active | System | Step is active | Procedure |
| Assignment | Active | Completed | Assigned participant | User, role, state, and prior-state validations succeed | Transactional Procedure |
| Assignment | Active | Rejected/declined | Assigned participant | Action type permits rejection; comments required if policy requires | Transactional Procedure |
| Assignment | Active | Cancelled | System/owner/admin | Parent workflow terminated or assignment invalidated before completion. | Procedure |

### Sequential and Parallel Execution Rules

- SequenceNumber determines the execution order. Steps within the same SequenceNumber form a parallel group.
- All required participant assignments in every step of the active sequence must be completed before the next higher sequence becomes Active.
- The initial release uses the completion rule `ALL_REQUIRED` for required assignments. `ANY_ONE` and `QUROM` rules are outside the initial scope.
- Optional assignments may be completed while their step is Active but do not block the advancement of the sequence.
- A participant can be assigned to more than one step, including different action types, only when the participant holds the corresponding required role.

- An 'Approval' result of 'Rejected' terminates ordinary progression and transitions the workflow into 'Rejected'. The owner must create and start a new workflow, and if there were changes to the document, a new document version.
- Cancelling an Active workflow requires a CancellationReason.
- Rejecting an approval requires a RejectionReason
- ActivationDateTime is recorded when a step or assignment becomes Active
- DueDateTime is optional but should be present when the workflow defines a due date
- ExpirationDateTime is stored for workflows subject to expiration
- LockedDateTime is recorded when the workflow locks its document version
- An active workflow remains bound to its original locked document version if a newer version is created

## Transaction Flows / Use Cases

### UC-01: Initiate a Document Workflow

| Item | Description |
| --- | --- |
| Goal | An owner creates a valid workflow for a current document version, define required steps, assigns participant, and places the workflow into an active status |
| Primary Actor | Document owner / Initiator |
| Trigger | The owner determines that a document is ready for formal review, approval, acknowledgement, or signature |
| Precondition | The document exists. The select document is valid for the workflow, the owner is authorized, all required participants exist and are validated, and all required workflow configuration is available |
| Related Requirements | FR-02, FR-04, FR-03, FR-06, FR-07, FR-12, FR-13, FR-14, FR-15 |
| Main Success Flow | 1. The owner selects an existing document and the version that will enter the workflow 2. The system retrieves that document version and validates that the owner can initiate the workflow 3. The owner defines the workflow and the required steps 4. The owner establishes the required participants and assigns roles to the appropriate steps 5. The system validates required relationships and permitted status values 6. The system records the workflow, step, and participant information as one controlled business transaction 7. The workflow is placed in active status and the first actionable step(s) become eligible 8. The system records required audit information for workflow initiation |
| Alternate Exception Flow | If a document/document version does not exist, a required participant is invalid, or an owner is not authorized, the workflow shall not be activated. If failure occurs after a transaction (workflow) has begun, the transaction shall be rolled back. |
| Postcondition(s) | A valid workflow/steps related to participant records exists. The workflow references the intended document version and the appropriate initial actions are outstanding. The initiation is auditable. |

### UC-02: Complete an Assigned Approval or Signature Action (Workflow Actions)

| Item | Description |
| --- | --- |
| Goal | A user records a valid participant action and updates workflow progress without performing unauthorized completion. |
| Primary Actor | Approver or signer |
| Trigger | A participant has an outstanding workflow action that is eligible for completion. |
| Precondition | The workflow is active. The participant is assigned to that step and the step is eligible to be acted upon. The action has not already been completed and the referenced document version is valid for the workflow. |
| Related Requirements | FR-08. FR-10, FR-11, FR-12, FR-13, FR-14, FR-15, FR-16, FR-18 |
| Main Success Flow | 1. The system retrieves the participant's outstanding assignment and related workflow/document information 2. The system verifies the workflow is valid and active and that the participant is authorized for the assigned action 3. For approval, the participant records a permitted decision and optional/required comments. For a signature, the participant records the signature for the exact document version 4. The system records the action date/time and marks the participant assignment complete 5. The system evaluates whether the workflow step is complete and whether later steps may become active 6. If all required workflow steps are complete, the workflow may be moved to 'Complete', otherwise it remains active 7. The system records the required audit events |
| Alternate Exception Flow | The system rejects the action if the participant is not assigned that action, the workflow is cancelled/expired/complete, the step is not eligible, a required value is invalid, or if the action was already complete. |
| Postcondition(s) | A valid approval decision or signature record exists, the participant/workflow progress reflects the completed action, and the event is auditable. |

### UC-03: Create a New Document Version

| Item | Description |
| --- | --- |
| Goal | The owner preserves document history while creating a newer version that can be used in a later or restored workflow. |
| Primary Actor | Document owner, initiator |
| Trigger | The business document is revised and the revised content needs to be tracked as a new version. |
| Precondition | The business document exists, the owner is authorized to create a new document version, the proposed version is not a duplicate of the existing version identifier/number for the same document. |
| Related Requirements | FR-01, FR-02, FR-13, FR-15 |
| Main Success Flow | 1. The owner identifies the document being revised 2. The system retrieves the existing version history 3. The owner provides the business information required for the new version 4. The system validates version uniqueness and relationship to the original document 5. The system records the new version and updates which version is considered current according to project policy 6. Prior versions and their approvals/signatures remain unchanged 7. The version creation/change is recorded for audit purposes |
| Alternate Exception Flow | The system rejects the new version if the document does not exist, the user is unauthorized, or the proposed version duplicates an existing version for the same document. Existing historical records shall not be overwritten |
| Postcondition(s) | The document has an additional history version, one version is identified as the current version and prior workflow, approval, and signature history remains associated with the versions of which those actions occurred |

## Data Requirements

| Data Subject | Information to Store | Example Identifier | Likely relationship(s) |
| --- | --- | --- | --- |
| User | Identify/contact information, organizational affiliation is applicable, account status, creation/maintenance information | UserID | Can own documents, hold roles, participate in workflow steps, or perform applicable actions |
| Role / entitlement | Role name, description, active status, and permitted responsibility category | RoleID | May be assigned to multiple users, and users may hold multiple roles |
| Document | Title, business description, owner, classification, lifecycle status, created/updated dates | DocumentID | Owned by a user, may have multiple versions, may have multiple workflows over a lifecycle |
| Document version | Version identifier/number, business effective information if necessary, creation information, current version indication/status | DocumentVersionID | Belongs to one document, may be the basis of more than one workflow, may have approved/signatures associated through workflow activity, a document may have multiple versions |
| Workflow | Document/version context, initiator, workflow purpose/type, status, start/completion/canc ellation/expiration information | WorkflowID | Belongs to one document/version context, contains workflow steps |
| Workflow Step | Step order or grouping (multiple steps at once), required/optional policy, status, activation/completion information | WorkflowStepID | Belongs to one workflow, may have one more more participant assignments |
| Workflow participant / assignment | Assigned user/participant, assigned role/action, assignment status, required indicator, activation/completion dates | WorkflowParticipantI D | Connects a user/participant to a workflow step, may own an approval, signature, review, or acknowledgement action |
| Approval Decision | Decision value, decision date/time, comments where applicable | ApprovalID | Belongs to an eligible approver action and indirectly related to document version/workflow |
| Signature | Signer assignment, document version, signing date/time, signature status/method/refere nce information appropriate for document | SignatureID | Belongs to an eligible assignment and one document version |
| Status / reference data | Allowed lifecycle values and classifications for documents, workflows, steps, and participants, decisions, and other domains | StatusID / TypeID | Referenced by operation entities to restrict allowed values |
| Audit Record | Actor, date/time, operation/event type, affected business record, transaction reference, and meaningful prior/new value context where required (what is updated and why) | AuditLogID | Links user/actor to action and affected document/version context/workflow/tran saction context |

## Business Rules and Validation Rules

| ID | Business rule | Why it matters | Possible enforcement approach |
| --- | --- | --- | --- |
| BR-01 | Each document shall have a unique document identifier | Prevents duplicate records and record ambiguity across system transactions. | Primary key constraint |
| BR-02 | Every document must belong to exactly one document owner, and a document owner may own multiple documents. | Establishes explicit document accountability and ownership scope. | Foreign Key constraint + NOT NULL |
| BR-03 | Each document version must belong to exactly one document, and version numbers must be unique within a document. | Maintains strict versioning history while preventing duplicate version tagging. | Foreign Key + NOT NULL, UNIQUE(DocumentID, VersionNumber) |
| BR-04 | A document may have multiple participants, and a user may participate in multiple documents. | Resolves the many-to-many relationship between participants and workflows. | Associative entity (DocumentParticipant) with composite keys |
| BR-05 | Each document participant must have a defined, authorized workflow role (Reviewer, Approver, Signer). | Prevents unauthorized action types and ensures clear operational boundaries. | reference table constraint or foreign key to Role table |
| BR-06 | Every document workflow must belong to exactly one document. | Ensures workflow state and approval chains remain strictly bounded to a single asset. | Foreign Key constraint + NOT NULL |
| BR-07 | Each workflow stage must have a defined sequence position, unique within a given workflow. | Establishes a predictable, ordered processing pipeline (e.g., Stage 1 → Stage 2). | UNIQUE(WorkflowID, SequenceNumber) |
| BR-08 | A workflow stage may be completed only after all required preceding stages have been completed. | Prevents out-of-order processing and unauthorized early sign-offs. | Stored procedure, transactional triggers, or application-level state machine logic |
| BR-09 | A workflow shall not be marked complete until all required review, approval, and signature actions have been completed. | Prevents incomplete or non-compliant document workflows from being finalized. | Multi-table validation routine / database view check prior to state transition |
| BR-10 | A participant assignment shall result in at most one completed action for a given workflow step and action type. | Prevents duplicate completion of the same assigned action. | Unique constraint + transaction/concurrency control |
| BR-11 | Document, workflow, and action statuses must be restricted to defined, valid system states. | Protects system integrity by preventing invalid or corrupt state entries. | CHECK constraints or controlled Foreign Key lookup tables |
| BR-12 | A finalized document version shall not be modified after it has been used in a completed approval or signature workflow. | Prevents covert content modification after approval or signature execution (Immutability). | Database trigger blocking UPDATE/DELETE operations on locked version records |
| BR-13 | Completion of a participant action shall be atomic and concurrency-safe; simultaneous attempts shall not result in multiple completed actions. | Prevents race conditions and duplicate submissions. | Transaction + row locking/optimistic concurrency + unique constraint |

## Transaction Requirements and Data Enforcement

### Transaction Requirements

#### TX-01: Initiate Workflow

The following operations shall be performed as one atomic transaction:

1. Validate owner authorization and document ownership.
2. Validate the selected document version.
3. Create the workflow record.
4. Create workflow steps.
5. Create participant assignments.
6. Validate required roles, assignments, sequencing, and dates.
7. Set the workflow to Active.
8. Activate the initial eligible steps or assignments.
9. Create the required audit event.
10. Commit all changes.

#### TX-02: Complete Workflow Action

1. Retrieve/lock the current participant assignment.
2. Verify current user, assignment, role, workflow status, step eligibility, and document version.
3. Record approval/signature/review action.
4. Mark participant assignment complete.
5. Reevaluate step completion.
6. Activate eligible subsequent steps.
7. Determine whether the workflow can be completed.
8. Mark workflow complete if all required work is finished.
9. Record audit event.
10. Commit.

If any validation or database operation fails, all changes made during the transaction shall be rolled back.

### Data Enforcement Matrix

| Rule | Enforcement Mechanism | Enforcement purpose |
| --- | --- | --- |
| BR-01 | Primary key | Prevent duplicate document IDs |
| BR-02 | NOT NULL + foreign key | Require valid document owner |
| BR-03 | Foreign key + UNIQUE(DocumentID, VersionNumber) | Require valid document and prevent duplicate version numbers |
| BR-04 | WorkflowParticipant associative entity + foreign keys | Support many-to-many participation |
| BR-05 | Foreign key + transaction validation | Ensure assigned role is valid for the action |
| BR-06 | NOT NULL + foreign key | Require workflow to belong to a document |
| BR-07 | UNIQUE(WorkflowID, SequenceNumber) | Prevent ambiguous step ordering |
| BR-08 | Transaction/procedure or trigger | Prevent completion before predecessors |
| BR-09 | Transaction/procedure or trigger | Prevent premature workflow completion |
| BR-10 | Unique constraint + transaction | Prevent duplicate participant actions |
| BR-11 | CHECK constraints / lookup-table FKs | Restrict lifecycle states |
| BR-12 | Trigger/restricted update procedure | Prevent modification of finalized versions |
| BR-13 | Transaction + row locking/concurrency mechanism + unique constraint | Prevent duplicate completion under simultaneous requests |

## Resiliency, Recovery, and Data Integrity Requirements

| ID | Requirement | Design implication | Test evidence |
| --- | --- | --- | --- |
| RES-01 | Multi-record workflow creation shall be atomic. Workflow, steps, assignments, activation, and associated audit records shall either all be committed or none shall be committed. | Use a database transaction with rollback. | Induce a failure after a partial insert and verify that no partial workflow remains. |
| RES-02 | Action completion shall be idempotent or shall safely reject duplicate submissions. | Use a unique action key, status validation, and appropriate concurrency controls. | Submit the same action twice and verify that only one completion is recorded. |
| RES-03 | Historical document versions used by completed workflows shall remain retrievable and immutable. | Lock versions referenced by completed workflows and restrict modification or deletion. | Retrieve a signed document version after subsequent versions have been created and verify that it is unchanged. |
| RES-04 | The system shall preserve referential integrity when documents, users, or workflows are deactivated. | Prefer soft deletion or inactive-status transitions; restrict deletion of referenced records. | Attempt to delete a referenced user or document and verify that the configured policy is enforced. |
| RES-05 | Interrupted transactions shall not leave a workflow partially activated or an action partially completed. | Use transactional boundaries and rollback mechanisms around state-changing operations. | Simulate failure during workflow initiation or action completion and verify the resulting state. |
| RES=06 | Audit records shall be append-only and retained for the project-defined retention period. | Prevent modification and deletion of audit records through normal application operations. | Attempt to modify or delete an audit record and verify rejection. |
| RES-07 | The system shall distinguish business expiration from technical failure. | Maintain distinct states such as Expired, Cancelled, Failed, and Pending, with defined transition rules. | Demonstrate that each state has a distinct meaning and permitted transition behavior. |
| RES-08 | Invalid workflow configurations shall be recovered through cancellation, correction, and new activation rather than destructive modification of historical records. | Provide a controlled corrective workflow and record the correction as an audit event. | Cancel an invalid workflow, create the corrected configuration, and verify that the original story remains intact. |
| RES-09 | Required reference data, including roles, statuses, decision values, and action types, shall be protected from uncontrolled deletion or modification. | Use foreign keys, effective dates or status controls where appropriate, and restricted administrative access. | Attempt an invalid reference-data deletion or modification and verify that it is rejected. |
| RES-10 | The system shall retain sufficient event context to reconstruct workflow progression following an incident. | Record an audit transaction ID, actor, timestamp, event type, and prior/new state where applicable. | Reconstruct a sample workflow's progression using only its audit records. |

## Security & Audit

### Role and Entitlement Requirements + Auditing

| ID | Security/Entitlement Requirement | Role(s) Affected | Protected Action or Data |
| --- | --- | --- | --- |
| SEC-01 | The system shall allow a Document Owner to view and manage only documents owned by that user and their associated versions and workflow records, subject to the document and workflow lifecycle state. The owner shall not be permitted to modify immutable historical approval, signature, or audit records. | Document Owner | Owned documents, document versions, and active workflow information |
| SEC-02 | The system shall allow Reviewers, Approvers, and Signers to view only documents and workflow assignments for which they have an active assignment and shall limit visible workflow information to the information required to perform that assignment, unless broader access is explicitly granted by role. | Reviewer, Approver, Signer | Assigned documents, WorkflowSteps, and WorkflowParticipantAssignments |
| SEC-03 | The system shall allow an authorized Document Owner to create and modify WorkflowSteps, sequencing, and participant assignments only while the workflow is in Draft status. Once the workflow becomes Active, workflow configuration shall be immutable; corrections shall require cancellation of the workflow and creation of a revised workflow or document version as defined by business policy. | Document Owner, Administrator | WorkflowSteps,se quencing, and WorkflowParticipantAssignments |
| SEC-04 | The system shall prevent Reviewers, Approvers, Signers, Document Owners, and Administrators from directly modifying or deleting completed review actions, ApprovalDecisions, SignatureEvents, or audit records. Corrections shall be represented through an append-only correction, reversal, or replacement transaction that preserves the original historical record. | All operational and administrative roles | Completed review decisions, ApprovalDecision, SignatureEvent, AuditLog |
| SEC-05 | The system shall prevent Reviewers, Approvers, and Signers from modifying document ownership, workflow configuration, step sequencing, or participant assignments unless the user has separately been granted an authorized ownership or administrative entitlement for that action. | Reviewer, Approver, Signer | Document ownership, workflow configuration, and participant assignments |
| SEC-06 | The system shall restrict creation, modification, deactivation, and role assignment of user accounts to authorized System Administrators. Non-administrative roles shall not be permitted to modify user-account, role-assignment, or entitlement information. | System administrator, Non-Administrat or Roles | User accounts, UserRole assignments, and entitlement data |
| SEC-07 | The system shall reject completion of a workflow action unless all required predecessor WorkflowSteps have completed and the current WorkflowStep and WorkflowParticipantAssignment are Active. | Reviewer, Approver, Signer | WorkflowStep Status, assignment status, step completion |
| SEC-08 | The system shall permit a participant to complete a workflow action only when the current user matches the assigned user, the user holds the required business role, the workflow is Active, the assigned step is Active, the assignment is Active, and the action has not already been completed. | Reviewer, Approver, Signer | WorkflowParticipantAssignment, WorkflowStep, Role, Workflow |
| SEC-09 | The system shall prevent ordinary participants from completing new workflow actions after the associated workflow has entered Completed, Cancelled, Expired, or Rejected status. | Reviewer, Approver, Signer | Workflow status, participant actions |
| SEC-10 | The system shall allow Workflow Managers and Auditors to view document and workflow history only within their authorized organizational or audit scope and shall provide read-only access to completed approvals, signatures, lifecycle transitions, and audit records. | WorkflowManag er, Auditor | Historical document, workflow, approval, signature, and audit data |
| SEC-11 | The system shall preserve AuditLog records as append-only history. No ordinary or administrative role shall be permitted to update or delete an existing audit record through normal system operations. | Administrator, Auditor, All other roles | AuditLog |
| SEC-12 | The system shall record the acting user, timestamp, operation, affected business record, and relevant prior and new values when a protected document, workflow, approval, signature, assignment, status, or administrative record is created, modified, cancelled, or otherwise changed. | All roles performing auditable actions | Audit events and protected business records |

### Audit Requirements

- Document creation and changes to ownership, classification, or lifecycle state
- Document version creation, current version designation, and locking
- Workflow activation, completion, rejection, cancellation, expiration, and corrective replacement
- Creation of participant assignments while Draft and attempted/authorized exceptional correctness
- Review, acknowledgement, approval, rejection, signature, and assignment-completion events
- Administrative user-status, role-assignment, and protected reference-data changes
- Append-only correction/reversal events that reference historical record being corrected
- Each event must retain enough context to reconstruct who did what, to which record, when, in which transaction/workflow context, and what state changed

### Entitlement Matrix

| Entitlement ID | Role | Resource | Allowed Action | Row-level condition | Enforcement target |
| --- | --- | --- | --- | --- | --- |
| ENT-01 | Document Owner | Document | Create, view, update metadata | User owns document; document state permits owner modification | Procedure/ap plication authorization |
| ENT-02 | Document Owner | Workflow | Create, configure, cancel | Workflow belongs to document owned by user, workflow is Draft or Active as applicable | Stored procedure + ownership check |
| ENT-03 | Reviewer | Workflow Assignment | View, complete review | Assignment is active and assigned to the current user | Procedure/vi ew filter |
| ENT-04 | Approver | Approval Action | View, approve, reject, request changes | Assignment is active, eligible, and assigned to the current user | Transactional procedure |
| ENT-05 | Signer | Signer Action | View, sign | Assignment is active, eligible, and references the locked document version | Transactional procedure |
| ENT-06 | Workflow Manager | Workflow | View, exception management | Within authorized organizational scope | Reporting view or authorization logic |
| ENT-07 | Auditor | Audit/history | Read only | Authorized audit scope | Read-only view/role |
| ENT-08 | System Administrator | User/role administratio n | Create, update, disable users and role assignments | Administrative role only | Restricted procedures |

## Reports and Queries

| ID | Report / query name | Business Question | Required Result | Primary Filters / Sort | Likely SQL Features |
| --- | --- | --- | --- | --- | --- |
| RQ-01 | Required action worklist | What workflow actions currently require attention? | For a selected participant, owner, manager : document/titleID, workflow, action type, responsible participant, step/status, assigned/activated date, expiration information, urgency | Participant, status, activation date | SELECT, JOIN, WHERE, ORDER BY |
| RQ-02 | Document Workflow Detail | How are the document, version, workflow, steps, participants, decisions, and signatures connected for a selected workflow? | One joined detail view showing the document / version context, ordered workflow steps, assigned participants, role/action, participant status, decision/signature outcome, and completion date/time | Workflow, DocumentVersion | Multi-table JOIN, ORDER BY |
| RQ-03 | Document Version History | What versions exist for a selected document, and which version is current? | Document identifier/title plus all versions, version number, created date/by, current status, and related workflow count or status | Document, version number | SELECT, JOIN, ORDER BY, optional aggregate |
| RQ-04 | Overdue / Exception Report | Which active workflows or participant actions require intervention because they are overdue, expired, missing a required completion, or otherwise outside expected state? | Records requiring action with document, owner, participant, required action, relevant date, and exception reason | Status, due date, expiration date | JOIN, WHERE, NOT EXISTS |
| RQ-05 | Signature History Report | Which users signed which document versions and when? | Signer identity, document, exact version, workflow, signing date/time, signature status/method, optional filters for signer, document type, etc. | Document, signer, date range | JOIN, WHERE, ORDER BY |
| RQ-07 | Audit History Workflow | What meaningful changes and lifecycle events occurred for a selected document or workflow? | Chronological list of event type, actor, timestamp, affected record/context, and change details (update details, prior to new value) | Document, workflow, event date | JOIN, WHERE, ORDER BY |
| RQ-08 | Owner Portfolio / Status Report | What documents does a selected owner currently control and what is their workflow state? | For each document in a selected period, initiated count, completed count, completion rate, and average completion duration | Owner, reporting period, status | JOIN, aggregate, GROUP BY |

## Assumptions and Constraints

### Assumptions

- Each document has one owner at a given point in time.
- A document may have multiple historical versions and one version may be designated as the current version according.
- A workflow is created for a known document/version context such that later approvals and signatures can be traced to the content version.
- A workflow contains at least one actionable step and one participant assignment before it becomes active.
- A participant may appear in more than one workflow and may perform different roles in different workflows.
- Completed approvals and signatures are historical business records and are not overwritten when a later document version or workflow is created.
- Electronic signatures are modeled as business events/records.
- Controlled status/type values will be maintained through lookup/reference data or other controlled mechanism chosen during design.

### Constraints

- The database design will be normalized to at least third-normal form.
- External e-signature, cloud storage, CRM/ERP, payment, and identity-verification document integration is outside the scope of this project.
- The implementation must demonstrate meaningful primary keys, foreign keys, uniqueness rules, validation constraints, transactions/rollbacks, role or entitlement concepts, audit logging, and SQL reporting support as required.
- The project will use fictional/sample data and will not store real-life confidentiality agreements, production data, or legally binding signatures.
- Final physical design choices such as exact table names, data types, indexes, trigger syntax, and stored-procedure implementation will be documented in the technical design rather than treated as FRD requirements.

## Acceptance Criteria and Traceability

### Acceptance Criteria

| Requirement | Acceptance Criteria | Evidence to Show |
| --- | --- | --- |
| FR-01 | Given valid document data, when a document is inserted, retrieved, and updated, then the stored values match the submitted values. | INSERT, UPDATE, and SELECT results |
| FR-02 | Given a document with multiple versions, when version history is retrieved, then all versions appear in version order and the current version is correctly identified. | Version history query |
| FR-03, FR-06 | Given an existing document version, when a workflow with multiple steps and assignments is created, then all steps and assignments reference valid records and are associated with the correct document version. | Transaction and joined query |
| FR-08 | Given a participant has both completed and outstanding assignments, when their worklist is queried, then only their outstanding assignments are returned. | Query and output |
| FR-10 | Given an eligible participant is assigned to an approval step, when they record an approval, then the approval is stored with the correct participant, workflow, and document context. | Transaction and query |
| FR-11 | Given an assigned signer and active workflow, when the signer records a signature, then the signature is stored against the correct document version. | Transaction and query |
| FR-12 | Given a participant is not eligible for an action, when they attempt the action, then the action is rejected and no invalid record is created. | Error plus before/after queries |
| FR-14 | Given a required action remains incomplete, when workflow completion is attempted, then completion is rejected and the workflow remains incomplete. | Error plus state query |
| FR-15, SEC-08 | Given a tracked business record exists, when it is changed, then an audit entry records the actor, event, timestamp, and affected context. | Transaction and AuditLog query |
| FR-16 | Given a workflow is cancelled or expired, when a participant attempts a new action, then the action is rejected and no invalid state change occurs. | Error plus before/after queries |
| RQ-01, FR-17 | Given sample data contains completed and incomplete assignments, when the worklist is run, then only outstanding assignments are returned. | Query and output |
| RQ-04 | Given sample data contains overdue, expired, and valid records, when the exception report is run, then only records requiring attention are returned. | Query and output |
| SEC-03, SEC-04 | Given one eligible and one ineligible user, when both attempt the protected operation, then the eligible user succeeds and the ineligible user is rejected. | Procedure or permission results |

### Traceability Matrix

| Requirement | Related entity | Rule / relationship implied | Planned implementation evidence | Evidence |
| --- | --- | --- | --- | --- |
| FR-01 | Document | Document data must be stored and retrieved accurately | Document table + CRUD operations | Insert, update, retrieve test |
| FR-02 | DocumentVersion / RQ-03 | Versions must be ordered and current version identifiable | FK + version uniqueness + history query | Multiple-versio n test + query output |
| FR-03, FR-06 | Workflow, WorkflowStep, Assignment / RQ-02 | Workflows, steps, and assignments must reference the correct document/version and participant | FK constraints + transaction | Multi-step workflow creation test + joined query |
| FR-08, FR-17 | Assignment / RQ-01 | Participants must see only outstanding work; urgent/overdue work must be identifiable | Worklist and status/date filtering | Completed + incomplete + overdue sample data; verify results |
| FR-10, FR-11 | Approval, Signature / RQ-02, RQ-05 | Approvals/signatures must be tied to the correct participant, workflow, and document version | FK + validation rules | Valid approval/signat ure test + query |
| FR-12, FR-16 | User, Workflow, Assignment | Unauthorized or invalid actions must not change workflow state | Authorization + state validation | Eligible/ineligib le and active/cancelle d/expired action tests |
| FR-14 | Workflow, Assignment / RQ-04 | Workflow cannot complete while required actions remain incomplete | Completion validation | Attempt completion with incomplete action; verify rejection and unchanged state |
| FR-15, SEC-08 | AuditLog / RQ-07 | Meaningful business changes must be attributable and auditable | Audit trigger/procedure + AuditLog | Perform tracked change; verify actor, timestamp, context, and change details |
| SEC-03, SEC-04 | User / authorization | Protected operations require appropriate permissions | Roles/permissions + protected procedures | Authorized vs. unauthorized operation test |
