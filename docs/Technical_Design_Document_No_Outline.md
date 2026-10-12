**Document Workflow and E-signing Portal**

# Technical Design Document

Prepared by: Ismael Anwar, Sanika Deshmukh

Course: 01:198:437:01

Date: 10/03/2026

Repository Location: https://github.com/sanikadeshmukh3/Digital-Document-Signing-Portal

## Data Model, Entity Definitions, and Data Dictionary

This section defines the entities and attributes that will form the relational database implementation. It serves as the authoritative vocabulary for the Technical Design Document. Entities and attributes are included only when they are:

- Explicitly identified in the Functional Requirements Document;

- Required by an FRD business rule, workflow rule, security rule, or use case; or

- Necessary technical identifiers or foreign keys for implementing relationships already

defined in the FRD. No additional business entity should be introduced elsewhere in the TDD without first documenting its purpose and its relationship to an FRD requirement.

*(This will make the ER diagram design easier)*

### Entity List

| Entity | FRD Basis | Purpose |
| --- | --- | --- |
| User | Data Requirements / FR-04 | Represents a person recorded in the system who may own documents, hold roles, or perform workflow actions |
| Role | Data Requirements / FR-05 | Represents an authorized business role |
| UserRole | FR-05 and User ↔ Role M:N relationship | Associates user with one or more roles |
| Document | Data Requirements / FR-01 | Represents the logical business document |
| DocumentVersion | Data Requirements / FR-02 | Represents a specific historical / current version of the document |
| Workflow | Data Requirements / FR-03 | Represents a workflow for a specific document / document version |
| WorkflowStep | Data Requirements / FR-03, FR-07 | Represents an ordered or parallel step in a workflow |

| WorkflowParticipant | Data Requirements / FR-06, FR-08 | Assigns a user and a role to a WorkflowStep |
| --- | --- | --- |
| ApprovalDecision | Data Requirements / FR-10 | Stores a formal approval / rejection decision |
| Signature | Data Requirements / FR-11 | Stores the simulated electronic - signature record |
| ReferenceData | Data Requirements / BR-11 | Maintains permitted statuses, types, classifications, and decision domains |
| AuditLog | Data Requirements / FR-15 | Stores auditable changes and workflow events |

### Attribute Classification

For clarity, attributes in this TDD will be labeled as:

- FRD Explicit — directly stated in the Data Requirements or another FRD section.

- FRD Derived — required by a business, state-transition, security, or workflow rule.

- Technical Key — required to implement an FRD-defined entity or relationship.

Prevents implementation details from being mistaken for new business requirements. User:

| Attribute | Classification | Purpose / FRD Basis |
| --- | --- | --- |
| UserID | FRD Explicit | Unique identifier specified by the Data Requirements |
| FirstName | FRD Explicit | Part of identifying information |
| LastName | FRD Explicit | Part of identifying information |
| Email | FRD Explicit | Contact information |
| OrganizationalAffiliation | FRD Explicit | Organizational affiliation, if applicable |
| AccountStatus | FRD Explicit | Current user-account status |
| CreatedDateTime | FRD Explicit | Creation/maintenance information |

| UpdatedDateTime | FRD Explicit | Maintenance information |
| --- | --- | --- |

Relationships:

- One User can own multiple Documents

- One User can have one or more Roles

- One User may appear in multiple WorkflowParticipant records

- One User may be the actor associated with AuditLog entities

UserID - PK

### Role

*(Should we define as an ENUM?)*

| Attribute | Classification | Purpose |
| --- | --- | --- |
| RoleID | FRD Explicit | Unique role identifier |
| RoleName | FRD Explicit | Name such as Reviewer, Approver, Signer, Document Owner |
| Description | FRD Explicit | Description of the role |
| ActiveStatus | FRD Explicit | Whether the role is currently available |
| ResponsibilityCategory | FRD Explicit | Permitted responsibility category |

Identified Roles: Document Owner, Reviewer, Approver, Signer, Workflow Manager, System Administrator, and Auditor (more details can be found in Roles and entitlements section)

### UserRole

| Attribute | Classification | Purpose |
| --- | --- | --- |
| UserID | Technical Key / FRD Derived | References the User |

| RoleID | Technical Key / FRD Derived | References the Role |
| --- | --- | --- |

I ntegrity Rule: UserID + RoleID must be unique so that the same role cannot be assigned to the same user more than once

### Document

FRD requires title, business description, owner, classification, lifecycle status, and creation/update dates.

| Attribute | Classification | Purpose |
| --- | --- | --- |
| DocumentID | FRD Explicit | Unique document identifier |
| Title | FRD Explicit | Document title |
| BusinessDescription | FRD Explicit | Business description |
| OwnerUserID | FRD Explicit / Technical FK | Identifies the Document Owner |
| Classification | FRD Explicit | Document classification/type |
| LifecycleStatus | FRD Explicit | Current document lifecycle status |
| CreatedDateTime | FRD Explicit | Document creation date |
| UpdatedDateTime | FRD Explicit | Most recent document metadata update |

Relationships:

- Every Document belongs to exactly One User owner

- One User may own multiple Documents

- One Document may have multiple DocumentVersions

- A Document may participate in multiple Workflows over its lifecycle

### DocumentVersion

The FRD explicitly requires a version identifier/number, effective information if needed, creation information, and a current-version indication/status.

| Attribute | Classification | Purpose |
| --- | --- | --- |
| DocumentVersionID | FRD Explicit | Unique identifier for this version record |
| DocumentID | Technical FK / FRD Derived | Identifies the parent Document |
| VersionNumber | FRD Explicit | Version identifier/number within the parent Document |
| EffectiveInformation | FRD Explicit, Optional | Business-effective information where required |
| CreatedDateTime | FRD Explicit | Version creation information |
| CreatedByUserID | FRD Derived | User responsible for version creation |
| CurrentVersionStatus | FRD Explicit | Identifies whether the version is current |
| LockedDateTime | FRD Derived | Records when a workflow locks the version |

Integrity Rules:

- Each version belongs to exactly One Document

- VersionNumber is unique within a Document

Thus, UNIQUE(DocumentID, VersionNumber)

### Workflow

The FRD requires document/version context, initiator, purpose/type, status, and start/completion/cancellation/expiration information

| Attribute | Classification | Purpose |
| --- | --- | --- |
| WorkflowID | FRD Explicit | Unique workflow identifier |
| DocumentID | FRD Derived / FK | Identifies the Document |
| DocumentVersionID | FRD Explicit/Derived | Identifies the exact version used by the workflow |
| InitiatorUserID | FRD Explicit | User who initiated the workflow |

| WorkflowPurposeType | FRD Explicit | Workflow purpose/type |
| --- | --- | --- |
| WorkflowStatus | FRD Explicit | Current lifecycle status |
| StartDateTime | FRD Explicit | Workflow start/activation information |
| CompletionDateTime | FRD Explicit | Workflow completion information |
| CancellationDateTime | FRD Explicit | Cancellation information |
| CancellationReason | FRD Derived | Reason required when an Active workflow is cancelled |
| ExpirationDateTime | FRD Explicit/Derived | Expiration information |

Current allowed statuses:

- Draft

- Active

- Complete

- Rejected

- Cancelled

- Expired

### WorkflowStep

| Attribute | Classification | Purpose |
| --- | --- | --- |
| WorkflowStepID | FRD Explicit | Unique step identifier |
| WorkflowID | Technical FK / FRD Derived | Parent Workflow |
| SequenceNumber | FRD Explicit/Derived | Determines execution order and parallel grouping |
| StepType | FRD Explicit/Derived | Review, Approval, Acknowledgement, or Signature |
| RequiredPolicy | FRD Explicit | Indicates required/optional behavior at the step level if needed |
| StepStatus | FRD Explicit | Pending, Active, Completed, Cancelled, etc. |

| ActivationDateTime | FRD Explicit/Derived | When the step becomes Active |
| --- | --- | --- |
| CompletionDateTime | FRD Explicit | When the step completes |
| DueDateTime | FRD Derived, Optional | Due date when the workflow defines one |

SequenceNumber determines execution order, and multiple WorkflowSteps may share the same SequenceNumber to form a parallel group.

### WorkflowParticipant

The FRD requires assigned user/participant, assigned role/action, assignment status, required indicator, and activation/completion dates.

| Attribute | Classification | Purpose |
| --- | --- | --- |
| WorkflowParticipantID | FRD Explicit | Unique participant-assignment identifier |
| WorkflowStepID | Technical FK / FRD Derived | Step to which the user is assigned |
| UserID | FRD Explicit/Derived | Assigned user |
| RoleID | FRD Explicit/Derived | Required business role |
| AssignedAction | FRD Explicit | Review, approval, acknowledgement, or signature |
| AssignmentStatus | FRD Explicit | Current participant assignment status |
| RequiredFlag | FRD Explicit/Derived | Indicates whether this assignment is required |
| ActivationDateTime | FRD Explicit/Derived | When assignment becomes Active |
| CompletionDateTime | FRD Explicit | Completion timestamp |
| DueDateTime | FRD Derived, Optional | Participant due date if one is defined |

### ApprovalDecision

| Attribute | Classification | Purpose |
| --- | --- | --- |
| ApprovalID | FRD Explicit | Unique approval-decision identifier |
| WorkflowParticipantID | FRD Derived / FK | Identifies the eligible approval assignment |
| DecisionValue | FRD Explicit | Approved, Rejected, or other FRD-approved decision |
| DecisionDateTime | FRD Explicit | Date/time of decision |
| Comments | FRD Explicit, Optional | Decision comments |
| RejectionReason | FRD Derived | Required when the decision is Rejected |

RejectionReason is explicitly required by the workflow rules.

### Signature

The FRD models signatures as business records/events.

| Attribute | Classification | Purpose |
| --- | --- | --- |
| SignatureID | FRD Explicit | Unique signature identifier |
| WorkflowParticipantID | FRD Explicit/Derived | Signer assignment |
| DocumentVersionID | FRD Explicit | Exact version signed |
| SigningDateTime | FRD Explicit | Date/time signed |
| SignatureStatus | FRD Explicit | Signature lifecycle/status |
| SignatureMethod | FRD Explicit | Supported internal signature method |
| SignatureReference | FRD Explicit, Optional | Reference information appropriate for the simulated signature |

No additional cryptographic certificate, external provider ID, or legal-verification data will be added because those capabilities are explicitly out of scope.

### ReferenceData

Examples of controlled domains include:

- Document lifecycle status

- Document classification/type

- Workflow status

- Workflow purpose/type

- WorkflowStep status

- Step type

- WorkflowParticipant status

- Assigned action

- Approval decision value

- Signature status

- Account status

The final schema section can decide which of these justify independent lookup tables.

### AuditLog

The FRD explicitly requires actor, date/time, operation/event type, affected business record, transaction reference, and meaningful prior/new value context where required.

| Attribute | Classification | Purpose |
| --- | --- | --- |
| AuditLogID | FRD Explicit | Unique audit entry identifier |
| ActorUserID | FRD Explicit/Derived | User responsible for the event |
| EventDateTime | FRD Explicit | When the event occurred |
| EventType | FRD Explicit | Type of auditable operation |
| AffectedRecordType | FRD Explicit/Derived | Business object affected |
| AffectedRecordID | FRD Explicit/Derived | Specific affected record |
| TransactionReference | FRD Explicit | Associates audit event with business transaction |
| PriorValueContext | FRD Explicit, Conditional | Relevant prior value(s) where required |

| NewValueContext | FRD Explicit, Conditional | Relevant new value(s) where required |
| --- | --- | --- |
| ChangeReason | FRD Explicit/Derived, Conditional | Why the change occurred when required |

The FRD also requires audit history to be append-only and protected from normal modification/deletion.

## Traceability

Traceability Matrix

| FRD Requiremen t | Schema objects | Constraint / Rule | Procedure / Trigger / View | Entitlemen t View | Test Case | Demo Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| FR-01 - Maintaining Record of Document and Document metadata | Document, User, reference data | PK on DocumentID; owner required, owner must reference a valid User, controlled classificatio n/status values | INSERT / UPDATE operations; ownership validations | Document owner may only modify owned document s | TC-FR01 -P01, TC-FR01 -N01 | INSERT/SE LECT/UPDA TE output; rejection if owner is invalid |
| FR-02 - Maintain document version history | DocumentVersion, Document | FK to Document; UNIQUE(D ocumentID, VersionNumber); historical versions stored | Version-cr eation transaction / query; locked-ver sion protection | Document owner may create versions for owned document s | TC-FR02 -P01, TC-FR02 -N01 | Version-hist ory query; duplicate-ve rsion rejection |
| FR-03 - Initiate workflow | Workflow, WorkflowStep, WorkflowP articipant, DocumentVersion | Valid owner, valid version, at least one step and participant, valid status and sequencing | Workflow initiation stored procedure / transaction | Current user must own Document and be entitled to create workflow | TC-FR03 -P01, TC-FR03 -N01, TC-TX01 -E01 | Procedure output plus joined workflow / step / participant query |
| FR-04 - Maintain user records | User, reference data | PK on UserID; required user values; valid account | Administer controlled user maintenan ce operation | System administra tor only | TC-FR04 -P01, TC-FR04 -N01 | Valid user insert; invalid/null/d omain rejection |

|  |  | status |  |  |  |  |
| --- | --- | --- | --- | --- | --- | --- |
| FR-05 - Maintain user roles | User, Role, UserRole | Valid User/Role FKs; unique User/Role pairing | Role-assig nment procedure/ controlled insert | System administra tor only | TC-FR05 -P01, TC-FR05 -N01 | Role assignment query; duplicate role assignment rejected |
| FR-06 - Assign eligible participants to workflow steps | WorkflowStep, WorkflowP articipant, Role, UserRole | User must hold required role; participant/ step relationship s valid; duplicate assignment s restricted | Participant -assignme nt validation within a workflow configurati on action | Document owner constructin g a draft workflow | TC-FR06 -P01, TC-FR06 -N01 | Valid participant assignment; wrong-role assignment rejected |
| FR-07 - Support workflow action types | WorkflowStep, reference data | StepType/ assigned action restricted to approved domain (pre-confir med allowed Step types) | Reference data FK or domain validation | Document owner defines steps while workflow is in ‘Draft’ | TC-FR07 -P01, TC-FR07 -N01 | Valid step types accepted; invalid action type rejected |
| FR-08 - Retrieve participant assignments | WorkflowP articipant, WorkflowStep, Document | Returned rows limited to current participant and applicable statuses | Participant worklist view/query | Participant only sees assigned work | TC-FR08 -P01, TC-FR08 -N01 | Worklist query showing correct row-level filtering for specific participant assignment |
| FR-09 - Record review / acknowledg ement completion | WorkflowP articipant | Assigned action must be review / acknowled gement; assignment must be | Workflow-a ction completion procedure updated WorkflowP articipant | Assigned Reviewer only | TC-FR09 -P01, TC-FR09 -N01 | Before/after WorkflowPar ticipant state; duplicate/un authorized attempt |

|  |  | Active; completion cannot occur twice |  |  |  | rejected |
| --- | --- | --- | --- | --- | --- | --- |
| FR-10 - Record approval decision | ApprovalDecision, WorkflowP articipant | Valid active approval assignment ; valid decision value; one completed action per assignment | Approved stored procedure / transaction | Assigned Approver only | TC-FR10 -P01, TC-FR10 -N01, TC-DUP-01 | Approval row plus participant/w orkflow status query |
| FR-11 - Record signature event | Signature,, WorkflowP articipant, DocumentVersion | Signer must be assigned, exact locked DocumentV ersion required; duplicate completion prohibited | Signature stored procedure / transaction | Assigned signer only | TC-FR11 -P01, TC-FR11 -N01, TC-DUP-02 | Signature row joined to participant/v ersion; invalid signer/versi on rejected |
| FR-12 - Prevent unauthorize d actions | Workflow, WorkflowSt p, WorkflowP articipant, UserRole | Current user equals assigned user; required role held; workflow, step, and participant Active; not already complete; predecesso rs in workflow complete | All actions procedures perform authorizati on / state validation | Assignme nt-specific authority | TC-FR12 -N01, TC-FR12 -N02 | Error plus unchanged before/after database state |
| FR-13 - Maintain lifecycle statuses | Document, DocumentVersion, Workflow, WorkflowStep, | Statuses restricted to valid domain; only permitted | State-trans ition procedures /triggers and audit procedures | Actor depends on transition | TC-FR13 -P01, TC-FR13 -N01 | Valid transition succeeds; invalid transition rejected; |

|  | WorkflowP articipant, AuditLog, reference data | transaction s allowed |  |  |  | audit row |
| --- | --- | --- | --- | --- | --- | --- |
| FR-14 - Prevent early workflow completion | Workflow, WorkflowStep, WorkflowP articipant | All current work must be complete before a workflow completes | Workflow-p rogression procedure checks outstandin g required work | Completio n-system controlled, not an arbitrary user update | TC-FR14 -N01 | Workflow remains Active while required assignment remains incomplete |
| FR-15 - Record audit events | AuditLog and affected business records | Audit rows append only; all required actor/date/ event context | Trigger and/or central transaction al procedure | Auditor read-only; operationa l users cannot alter audit history | TC-FR15 -P01, TC-AUD-N01 | Source operation plus correspondi ng AuditLog row; update/delet e rejection |
| FR-16 - Cancellation and expiration | Workflow, WorkflowP articipant, AuditLog, reference data | Only valid transition from Active; cancellatio n reason required; terminal state blocks current and future actions | Workflow-c ancellation procedure; expiration procedure; action-stat e checks | Owner for cancellatio ns; System/Ad min for expiration | TC-FR16 -P01, TC-FR16 -N01 | Workflow status change, audit record, blocked participant action |
| FR-17 - Outstanding actions report | Document, Workflow, WorkflowStep, WorkflowP articipant | Only applicable incomplete/ active work; status/date filters | vw_Outsta ndingActio ns or equivalent SELECT/J OIN query | Owner within an authorized scope; participant can view own work | TC-FR17 -P01 | Query result with document, participant, action, status, due/expirati on data |
| FR-18 - Retrieve document history | Document, DocumentVersion, Workflow, | Historical records read-only where | ww_Docu mentHistor y or joined history | Workflow auditor within an authorized | TC-FR18 -P01, TC-FR18 -N01 | Joined history query; unauthorize |

|  | WorkflowP articipant, ApprovalDecision, Signature, AuditLog | finalized | query | scope |  | d history retrieval rejected |
| --- | --- | --- | --- | --- | --- | --- |

## Business Rule Traceability - if necessary - not included in the outline provided

## Testing and Test Evidence

### Constraint Validation Testing

- Enforcement of primary-key, foreign-key, unique, NOT NULL, CHECK, and

status/domain rules

| Test ID | Require ment (mapped to business roles) | Type | Initial State | SQL Procedu re | Expected Result | Actual Result | Verifica tion Query | Query evidenc e | Pass / Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-PK-01 | BR-01 | Negati ve | A Docum ent alread y exists with the given Docum entID | Attempti ng to insert another Docume nt with the same Docume ntID | Insert is rejected by primary-k ey constraint | Populate after executio n | Query Docum ent for the tested Docum entID | Exactly one Docume nt record exists | Populate |
| TC-FK-01 | BR-03 | Negati ve | No Docum ent exists for the supplie d Docum entID | Attempti ng to insert a Docume ntVersio n referenc ing the non-exis tent Docume ntID | Insert is rejected by foreign-k ey constraint | Populate after executio n | Query Docum entVers ion for the attempt ed record | No invalid Docume ntVersio n exists | Populate |
| TC-FK-02 | FR-06 / BR-04 | Negati ve | No matchi ng User or Workfl owSte p exists | Attempti ng to create a Workflo wPartici pant referenc ing the invalid | Insert is rejected | Populate after exection | Query Workflo wPartic ipant | No orphan Workflo wPartici pant exists | Populate |

|  |  |  |  | parent record |  |  |  |  |  |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-NN-01 | BR-02 | Negati ve | No owner is supplie d, but valid Docum ent data | Attempt to create a Docume nt with NULL owner | Insert is rejected by NOT NULL validation | Populate after executio n | Query Docum ent | No ownerle ss Docume nt exists | Populate |
| TC-UQ-01 | BR-03 | Negati ve | Docum ent 10 alread y contai ns Versio nNum ber 2 | Insert another Docume ntVersio n for Docume nt 10 with Version 2 | Duplicate version is rejected | Populate after exection | Query Docum entVers ion by Docum entID and Version Numbe r | Exactly one version 2 exists for Docume nt 10 | Populate |
| TC-UQ-02 | FR-05 | Negati ve | A User alread y holds a specifi c Role | Attempt to insert the same UserRol e associat ion again | Duplicate role assignme nt is rejected | Populate after executio n | Query UserRole for one UserID/ RoleID pair | Exactly one associat ion exists | Populate |
| TC-CHEC K-01 | Workflow Participa nt indicated rule | Bound ary / Negati ve | Valid Workfl owPart icipant but the Requir edFlag is outsid e the require d domai n | Attempt to INSERT or UPDAT E | Operation is rejected | Populate after executio n | Query Workflo wPartic ipant | No invalid Require dFlag is stored | Populate |
| TC-DOMA | BR-11 | Negati | Valid | Attempt | Operation | Populate | Query | Original | Populate |

| IN-01 |  | ve | workflo w record | to assign an unsuppo rted workflo w status, step type, or participa nt status | is rejected by CHECK or reference -data validation | after executio n | affecte d record | valid domain value exists |  |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Positive Functional Tests

| Test ID | Require ment (mapped to business roles) | Type | Initial State | SQL Procedu re | Expected Result | Actual Result | Verifica tion Query | Query evidenc e | Pass / Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-FR03-P01 | FR-03, FR-06, FR-07, TX-01 | Positiv e | Valid Docum ent and Docum entVer sion exist; initiatin g user owns Docum ent; valid Workfl owSte ps and Workfl owPart icipant s exist; require d roles | Execute workflo w-initiati on procedu re | Workflow becomes Active; initial eligible steps and participan ts become Active; workflow reference s correct Documen tVersion; audit event is recorded | Populate | Joined query across Workflo w, Workflo wStep, Workflo wPartic ipant, Docum entVers ion, AuditLog | Correct workflo w hierarch y, active initial sequen ce, and audit entry are returned | Populate |

|  |  |  | are valid |  |  |  |  |  |  |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Valid Approval

| Test ID | Require ment (mapped to business roles) | Type | Initial State | SQL Procedu re | Expecte d Result | Actual Result | Verifica tion Query | Query evidenc e | Pass / Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-FR10-P01 | FR-10 | Positiv e | Workflo w Active; approval Workflo wStep Active; Workflo wPartici pant assigned to current user with Approve r role | Execute valid approva l decision | Approva lDecisio n is stored; particip ant completi on is recorde d; workflo w progres sion is reevalu ated | Populate | Query Approv alDecis ion, Workflo wPartic ipant, Workflo wStep, Workflo w | Correct approva l and resultin g workflo w state are returned | Populate |

### Valid Signature

| Test ID | Require ment (mapped to business roles) | Type | Initial State | SQL Procedu re | Expected Result | Actual Result | Verifica tion Query | Query evidenc e | Pass / Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-FR11-P01 | FR-11 | Positiv e | Workfl ow Active; signat ure | Execute Signatur e procedu re | Signature is stored against the assigned | Populate | Query Signatu re joined to | Signatur e referenc es correct | Populate |

|  |  |  | step Active; signer assign ed; correct Docum entVer sion associ ated with workflo w |  | Workflow Participa nt and exact Documen tVersion; assignme nt completio n is recorded |  | Workflo wPartic ipant and Docum entVers ion | Particip ant |  |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Authorization and Security Tests

| Test ID | Require ment (mapped to business roles) | Type | Initial State | SQL Procedu re | Expected Result | Actual Result | Verifica tion Query | Query evidenc e | Pass / Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-FR12-N01 | FR-12 / SEC-08 | Negati ve | Workfl ow Active; Workfl owSte p Active; Workfl owPart icipant assign ed to User A | User B execute s the action-c ompletio n procedu re for User A's assignm ent | Operation is rejected; no action record is created; Workflow Participa nt remains Active; workflow does not advance | Populate after exection | Query Workflo wPartic ipant, Approv alDecis ion/Sig nature, Workflo wStep, Workflo w | No new action exists and state remains unchan ged | Populate |
| TC-FR06-N01 | FR-06 / BR-05 | Negati ve | User exists but does not hold the | Attempt to assign user as Workflo wPartici pant | Assignme nt is rejected | Populate | Query Workflo wPartic ipant and UserRole | No invalid assignm ent exists | Populate |

|  |  |  | role require d by the Workfl owSte p |  |  |  |  |  |  |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Workflow Transition Tests

| Test ID | Require ment (mapped to business roles) | Type | Initial State | SQL Procedu re | Expected Result | Actual Result | Verifica tion Query | Query evidenc e | Pass / Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-FR13-P01 | FR-13 | Positiv e | Workfl ow is Draft and all activati on precon ditions are satisfie d | Execute workflo w activatio n procedu re | Workflow changes to Active; first eligible steps activate; transition is audited | Populate | Query Workflo w, Workflo wStep, AuditLog | Active status and expecte d audit event appear | Populate |
| TC-FR13-N01 | FR-13 / BR-11 | Negati ve | Workfl ow status = compl eted | Attempt to reactivat e complet ed workflo w | Transition is rejected; workflow remains Complete d | Populate | Query Workflo w | Workflo w remains Complet ed and no invalid transitio n occurs | Populate |

### Sequential and Parallel Workflow Tests

| Test ID | Require ment (mapped to business roles) | Type | Initial State | SQL Procedu re | Expected Result | Actual Result | Verifica tion Query | Query evidenc e | Pass / Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-SEQ-N01 | BR-08 / SEC-07 | Negati ve | Requir ed work in Seque nce 1 remain s incom plete; Seque nce 2 is Pendin g | Sequen ce-2 Particip ant attempts action to complet e | Action is rejected; Sequenc e 2 remains Pending; no completio n is stored | Populate | Query Workflo wStep and Workflo wPartic ipant for both sequen ces | Sequen ce 1 remains incompl ete and Sequen ce 2 remains Pending | Populate |
| TC-PAR-P 01 | Sequenti al / Parallel Rule | Positiv e / Bound ary | Steps A and B share Seque nceNu mber2; Step C has Seque nceNu mber 3; A and B are require d | Complet e Step A only | Step A complete s; Step B remains Active; Step C remains Pending | Populate | Query Workflo wStep ordere d by Seque nceNu mber | Step C has not been activate d prematu rely | Populate |
| TC-PAR-P 02 | Sequenti al / Parallel Rule | Positiv e | Step A in Seque nce 2 is compl ete; Step B in Seque | Complet e Step B | All required Sequenc e-2 work complete s and Sequenc e 3 becomes Active | Populate | Query Workflo wStep and Workflo wPartic ipant | Sequen ce 3 records are Active | Populate |

|  |  |  | nce 2 remain s Active |  |  |  |  |  |  |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Duplicate and Concurrency Tests

| Test ID | Require ment (mapped to business roles) | Type | Initial State | SQL Procedu re | Expected Result | Actual Result | Verifica tion Query | Query evidenc e | Pass / Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-DUP-0 1 | BR-10 / RES-02 | Negati ve | Workfl owPart icipant has alread y compl eted an approv al action | Submit the same approval again | Second request is rejected; only one complete d Approval Decision remains; workflow does not advance twice | Populate | Count Approv alDecis ion records for assign ment and query workflo w state | Count remains 1; state remains valid | Populate |
| TC-DUP-0 2 | BR-10 / RES-02 | Negati ve | Workfl owPart icipant has alread y compl eted signat ure action | Submit same Signatur e again | Second request rejected; exactly one Signature exists | Populate | Count Signatu re rows for assign ment | Count remains 1 | Populate |
| TC-CONC -01 | BR-13 | Except ion | One Active Workfl owPart icipant assign | Two transacti ons attempt to complet | Exactly one transactio n succeeds ; | Populate | Count action rows and query final | One completi on record; one final | Populate |

|  |  |  | ment exists | e the same assignm ent concurr ently | duplicate completio n is prevente d |  | assign ment status | Complet ed assignm ent |  |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Boundary Tests

| Test ID | Require ment (mapped to business roles) | Type | Initial State | SQL Procedu re | Expected Result | Actual Result | Verifica tion Query | Query evidenc e | Pass / Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-SEQ-BOUND-0 1 | Workflow sequenci ng rule | Bound ary | Valid Workfl ow exists | Attempt to create Workflo wStep with Sequen ceNumb er 0 or negative value | Invalid sequence is rejected if design requires positive sequence numbers | Populate | Query Workflo wStep | No invalid Sequen ceNumb er is stored | Populate |
| TC-DATE-BOUND-0 1 | Workflow Date validation | Bound ary | Workfl owSte p has a define d activati on Date | Set DueDat eTime equal to permitte d lower boundar y | Value is accepted if equal boundary is valid | Populate | Query Workflo wStep | Expecte d DueDat eTime is stored | Populate |
| TC-DATE-N01 | Workflow Date validation | Negati ve / Bound ary | Workfl ow has start / activati on timest amp | Set DueDat eTime or Expirati onDateT ime earlier | Operation is rejected | Populate | Query Workflo w/Work flowSte p | Invalid Date is not stored | Populate |

|  |  |  |  | than permitte d start time |  |  |  |  |  |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Immutability and Audit Tests

| Test ID | Require ment (mapped to business roles) | Type | Initial State | SQL Procedu re | Expected Result | Actual Result | Verifica tion Query | Query evidenc e | Pass / Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-IMM-0 1 | BR-12 / RES-03 | Negati ve | Docum entVer sion was used in compl eted approv al/sign ature workflo w | Attempt UPDAT E or DELET E on protecte d version data | Operation is rejected; historical version remains unchange d | Populate | Query Docum entVers ion before and after | Values remain unchan ged | Populate |
| TC-AUD-N01 | FR-15 / RES-06 | Negati ve | AuditL og row exists | Attempt UPDAT E on AuditLog | Update is rejected | Populate | Query AuditLog row | Original row unchan ged | Populate |
| TC-AUD-N02 | FR-15 / RES-06 | Negati ve | AuditL og row exists | Attempt DELET E on AuditLog | Delete is rejected | Populate | Query AuditLog row | Original row still exists | Populate |

### Workflow Completion Tests

| Test ID | Require | Type | Initial | SQL | Expected | Actual | Verifica | Query | Pass / |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

|  | ment (mapped to business roles) |  | State | Procedu re | Result | Result | tion Query | evidenc e | Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-FR14-N01 | FR-14 / BR-09 | Negati ve | Workfl ow Active; at least one require d Workfl owPart icipant remain s incom plete | Attempt to complet e/finaliz e Workflo w | Completi on is rejected; Workflow remains Active | Populate | Query Workflo w and outstan ding Workflo wPartic ipants | Workflo w = Active and incompl ete required assignm ent remains | Populate |

### Cancellation / Terminal State Tests

| Test ID | Require ment (mapped to business roles) | Type | Initial State | SQL Procedu re | Expected Result | Actual Result | Verifica tion Query | Query evidenc e | Pass / Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-FR16-P01 | FR-16 | Positiv e | Workfl ow Active; authori zed Owner /Admin ; Cancel lationR eason supplie d | Execute cancella tion procedu re | Workflow becomes Cancelle d; appropria te participan t work becomes non-actio nable; audit event created | Populate | Query Workflo w, Workflo wPartic ipant, AuditLog | Cancell ed status and expecte d audit/st ate updates appear | Populate |

| TC-FR16-N01 | FR-16 / SEC-09 | Negati ve | Workfl ow is cancell ed | Particip ant attempts outstand ing workflo w action | Action is rejected; no action/co mpletion record created | Populate | Query Workflo wPartic ipant and action records | No new completi on exists | Populate |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Transaction Rollback and Exception Tests

| Test ID | Require ment (mapped to business roles) | Type | Initial State | SQL Procedu re | Expected Result | Actual Result | Verifica tion Query | Query evidenc e | Pass / Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-TX01-E01 | TX-01 / RES-01 / RES-05 | Except ion | Valid Docum ent and Docum entVer sion; workflo w transa ction begins | Execute workflo w-initiati on procedu re with an induced failure after partial work begins | Entire transactio n rolls back | Populate | Query Workflo w, Workflo wStep, Workflo wPartic ipant, Docum entVers ion, AuditLog | No partial Active workflo w, orphan steps/p articipa nts, incorrec t version lock, or success audit record remains | Populate |
| TC-TX02-E01 | TX-02 / RES-05 | Except ion | Eligibl e Active Workfl owPart icipant exists | Execute action transacti on with induced failure after action processi ng begins | Entire action transactio n rolls back | Populate | Query Approv alDecis ion/Sig nature, Workflo wPartic ipant, Workflo wStep, Workflo | No partial action, particip ant completi on, step transitio n, later activatio n, or | Populate |

|  |  |  |  | but before final commit |  |  | w, AuditLog | success audit record remains |  |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Roles and Entitlements

## Purpose

Authorization will be implemented using a combination of:

- stored procedures for protected state-changing operations;

- filtered views and queries for read access;

- ownership and assignment checks inside procedures;

- role validation through User, Role, and UserRole;

- database constraints and protected tables for historical records;

- application-layer identity context where the current user must be passed to database

procedures. The FRD already defines the main business roles as Document Owner, Reviewer, Approver, Signer, Workflow Manager, System Administrator, and Auditor

## Business Roles

Document Owner: Manages Documents they own and initiates and configures workflows for those documents Permitted responsibilities:

- Create Documents

- Viewed owned Documents

- Update permitted Document metadata

- Create new DocumentVersions

- Initiate Workflows

- Configure WorkflowSteps while Workflow is in Draft

- Assign eligible users as WorkflowParticipants

- Cancel eligible Active Workflows

- Monitor Workflow progress and outstanding work

The owner may only modify, delete, create work associated with Documents they own. Reviewer: Performs assigned review or acknowledgement work Permitted responsibilities:

- View Documents for an assigned review

- View assigned WorkflowStep and WorkflowParticipant record

- Complete an eligible review or acknowledgement action

The Reviewer may only act when (constraints):

- The WorkflowParticipant is assigned to the current user

- The Workflow is Active

- The WorkflowStep is Active

- The WorkflowParticipant is Active

- Required predecessor work is complete

- The action has not already been completed

Reviewers may not modify document ownership, workflow configuration, sequencing, or participant assignments unless they separately hold another authorized role. Approver: Evaluates assigned approval steps and records Approval Decisions Permitted responsibilities:

- View the relevant assigned Document/DocumentVersion

- View the assigned approval step

- Record an approval or rejection decision

- Provide comments where applicable

An Approver may act only on a WorkflowParticipant assignment belonging to that current user and only when the assignment is eligible and Active. They cannot alter Workflow configuration. Signer: Completes assigned simulated electronic-signature actions Permitted responsibilities:

- View the Document/DocumentVersion associated with the Signature step

- Record a Signature

- Record a permitted Signature status or method information

The Signer may only act when:

- The current user is the assigned WorkflowParticipant

- The assignment and the step are Active

- The Workflow is Active

- The signature references the exact locked DocumentVersion

The Signer only has access to the assigned Documents and signature actions only

Workflow Manager: Oversees Workflow operations and exception conditions Permitted responsibilities:

- View Workflows within authorized scope

- Monitor outstanding and overdue work

- View operational reports

- Review Workflow exceptions

- Access Document/Workflow history as permitted

Access is restricted to manager’s authorized organizational scope System administrator: Maintains User, Role, and administrative information Permitted responsibilities:

- Create and update User records

- Deactivate Users

- Assign or revoke UserRole records

- Maintain permitted administrative/reference information

- Review audit information

System Administrators do not have permission to alter completed approvals, signatures, finalized historical workflow records, or existing AuditLog records merely because they are administrators. Auditor: Read-only access to historical and audit information within authorized scope. Permitted responsibilities:

- View AuditLog

- View Document and version history

- View Workflow lifecycle events

- View ApprovalDecision and Signature history

- Review protected status changes

Auditors may not modify operational or historical records.

## Entitlement Matrix

| Role | Protected Data Area | View | Crea te | Upd ate | Delete / Cancel | Approve / Act | Admi nister | Audit | Row-Le vel Conditio n | Enforcement |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Doc ume nt Own er | Documen t | Yes | Yes | Yes, whe re stat e per mits | No hard delete; cancel workflo w only where permitt ed | No | No | Limit ed own-histo ry view | OwnerU serID = Current UserID | Ownership check + stored procedures / filtered queries |
| Doc ume nt Own er | Documen tVersion | Yes | Yes | Onl y whil e mut able | No delete when referen ced/fin alized | No | No | View own histo ry | Parent Docume nt owned by current user | Stored procedures + immutability checks |
| Doc ume nt Own er | Workflow | Yes | Yes | Draf t conf igur atio n only | Cancel Active workflo w with require d reason | No | No | View own work flow histo ry | Workflo w belongs to owned Docume nt | Stored procedures + ownership/st ate checks |
| Doc ume nt Own er | Workflow Step | Yes | Yes while Draft | Yes whil e Draf t | No after activati on | No | No | Limit ed | Parent Workflo w belongs to owned Docume nt | Stored procedure + workflow-stat us check |

| Doc ume nt Own er | Workflow Participa nt | Yes | Yes while Draft | Yes whil e Draf t | No direct delete after activati on | No | No | Limit ed | Parent Workflo w belongs to owned Docume nt | Stored procedure + role eligibility validation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Revi ewer | Assigned documen t/workflo w data | Yes | No | No | No | Complete review/ac knowledg ement only | No | No | Workflo wPartici pant.Us erID = Current UserID and assignm ent Active | Filtered view + action procedure |
| Appr over | Assigned documen t/workflo w data | Yes | Appr oval Deci sion only throu gh proc edur e | No dire ct upd ate afte r com pleti on | No | Approve/ reject assigned action | No | No | Assign ment belongs to current user and is Active/el igible | Transactional stored procedure |
| Sign er | Assigned documen t/workflo w data | Yes | Sign ature only throu gh proc edur e | No dire ct upd ate afte r com pleti on | No | Sign assigned action | No | No | Assign ment belongs to current user; correct locked version | Transactional stored procedure |

| Work flow Man ager | Workflow /operatio nal data | Yes | Nor mall y No | Limi ted exc epti on man age men t if per mitt ed | Limite d per policy | No participa nt action unless separatel y assigned | No | View histo ry | Authoriz ed organiz ational scope | Reporting views + authorization logic |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Syst em Admi nistr ator | User, Role, UserRole , admin/ref erence data | Yes | Yes | Yes | Deacti vate, not destru ctive delete where referen ced | No | Yes | View audit infor mati on | Adminis trative role required | Restricted administrativ e procedures / grants |
| Syst em Admi nistr ator | Complete d approvals /signatur es/audit | Yes wher e auth orize d | No | No | No | No | No | Rea d only | No override of immuta ble history | Table restrictions + no update/delete procedures |
| Audit or | Historical records / AuditLog | Yes | No | No | No | No | No | Yes | Authoriz ed audit scope | Read-only views / SELECT grants |

## Row-level Access Rules

Document Owner:

- A DocumentOwner may only manage a Document when Document.OwnerID =

CurrentUserID

- An owner must not gain access to another owner’s Document merely because the user

has the DocumentOwner role

Reviewer / Approver / Signer

- Participant access is controlled through WorkflowParticipant

- A participant may only act when WorkflowParticipant.UserID = CurrentUserID

- WorkflowParticipant status is Active

- WorkflowStep status is Active

- Workflow status is Active

- The participant holds the required Role

- Required predecessors are complete

- The action has not already been completed

- A participant may only act on an assignment specifically assigned to the participant

Workflow Manager

- May view Workflow and reporting data only within the the manager’s authorized scope

- No unrestricted global access unless explicitly required

Auditor

- An Auditor may only retrieve historical records within an authorized audit-scope

- Access is read-only

## Authorization Enforcement Strategy

Using multiple enforcement layers instead of relying solely on application logic Stored Procedures: Stored procedures should be the primary mechanism for sensitive state-changing operations, including:

- Workflow creation/activation

- Workflow cancellation

- WorkflowParticipant assignment

- ApprovalDecision completion

- Signature completion

- Review/acknowledgement completion

- user/role administration

Each procedure should receive or derive the current UserID and validate:

- User identity

- Required Role

- Ownership or assignment

- Lifecycle state

- Predecessor completion

- Duplicate action status

Views: Views should be used for scoped retrieval such as:

- Participant worklists

- Outstanding actions

- Workflow detail

- Document history

- Audit history

Database Roles and Grants Limit direct access to underlying tables Practical Approach:

- Application / service accounts receive EXECUTE on approved procedures

- Reporting / auditing accounts receive SELECT on approved views

- Direct UPDATE / DELETE privileges on protected historical tables are withheld

This is important for

- ApprovalDecision

- Signature

- AuditLog

- DocumentVersion

Application Logic Can determine the current authenticated user and pass CurrentUserID into protected database operations Application checks should not be the only control for critical business rules. There should be sensitive authorization and Workflow-state validation that should occur inside stored procedures or database enforcement logic

## Protection of Completed and Historical Records

ApprovalDecision: Once an ApprovalDecision has been completed, the original ApprovalDecision must not be directly updated or deleted, any correction should preserve the original historical record, and rejection/approval history must remain traceable. The FRD explicitly prohibits direct modification or deletion of completed approval records. Signature: Once a Signature is recorded for eligible action, the record must not be modified or deleted through ordinary operations, it must remain tied to the exact DocumentVersion signed, and subsequent document versions must not overwrite the historical signature relationship. FinalizedDocumentVersion: A DocumentVersion used in a complete approval/signature Workflow must be protected from unauthorized modification or deletion. AuditLog: AuditLog is append-only. No ordinary user, owner, participant, administrator, manager, or auditor may directly update or delete an existing AuditLog record through normal operations.

### Summary

| Protected Area | Primary Authorized Role(s) | Key Restriction |
| --- | --- | --- |
| Document | Document Owner | Own records only |
| DocumentVersion | Document Owner | Own document; finalized versions immutable |
| Workflow configuration | Document Owner | Draft workflow only |
| WorkflowParticipants | Document Owner | Draft configuration only; assigned user must hold required role |

| Review / acknowledgement actions | Reviewer | Assigned Active WorkflowParticipant only |
| --- | --- | --- |
| ApprovalDecision | Approver | Assigned Active approval only; immutable after completion |
| Signature | Signer | Assigned Active signature only; exact DocumentVersion |
| Workflow operational reporting | Workflow Manager | Authorized organizational scope |
| User / Role / UserRole | System Administrator | Administrative role only |
| Historical workflow data | Workflow Manager / Auditor | Read-only where finalized |
| AuditLog | Auditor / permitted Administrator | Read-only; append-only history |

## Performance & Index Design

## 1. Operational query inventory

This section identifies frequent operational queries expected to be supported by the document and workflow management database. These query patterns will guide index selection and later performance evaluation.

| Query ID | Operational query | Tables involved | Access pattern |
| --- | --- | --- | --- |
| Q-01 | Find a document's current version | DocumentVersion | Filter by DocumentID and current-version status |
| Q-02 | Retrieve active assignments for a user | WorkflowParticipant, WorkflowStep | Filter by UserID and AssignmentStatus; join by WorkflowStepID |
| Q-03 | Retrieve steps for a workflow in execution order | WorkflowStep | Filter by WorkflowID; sort by SequenceNumber |
| Q-04 | Find document version history | DocumentVersion | Filter by DocumentID; sort by VersionNumber |
| Q-05 | Retrieve a workflow's audit history | AuditLog | Filter by affected record type and ID; sort by event timestamp |
| Q-06 | Find workflows by status and creation date | Workflow | Filter by WorkflowStatus and StartDateTime; sort by date |

## 2. Index design matrix

The following indexes are proposed based on expected query patterns and data-integrity requirements. The final selection will be reconciled with the relational schema and existing primary-key, foreign-key, and unique-constraint indexes.

| Proposed index / Constraint | Query Supported | Expected benefit |
| --- | --- | --- |
| UNIQUE(DocumentID, VersionNumber) | Q-04 | Prevents duplicate version numbers within a document and supports version-history retrieval |
| WorkflowStep(WorkflowID, SequenceNumber) | Q-03 | Supports workflow filtering and ordered step retrieval |
| WorkflowParticipant(UserID, AssignmentStatus) | Q-02 | Supports retrieval of a user's assignments by status |
| AuditLog(AffectedRecordType, AffectedRecordID, EventDateTime) | Q-05 | Supports filtering audit events by affected record and retrieving them chronologically |
| Workflow(WorkflowStatus, CreatedDateTime) | Q-06 | Supports status-based filtering and date-based retrieval |

## 3. Index implementation and evidence

### 3.1 Implementation Plan

After the relational schema is finalized, the selected indexes will be implemented in MySQL. Existing indexes will be inspected to prevent redundant definitions. Representative SQL for the proposed workflow-step index: CREATE INDEX idx_step_workflow_sequence ON WorkflowStep (WorkflowID, SequenceNumber); Representative SQL for the proposed user-assignment index: CREATE INDEX idx_participant_user_status ON WorkflowParticipant (UserID, AssignmentStatus); Representative SQL for the proposed audit-history index: CREATE INDEX idx_audit_entity_time ON AuditLog ( AffectedRecordType, AffectedRecordID, EventDateTime ); The exact column names and data types will be verified against the final schema before execution.

### 3.2 Query-Plan Evaluation

MySQL EXPLAIN will be used to inspect the execution plans for representative operational queries. Where useful, query plans will be compared before and after index creation using the same test dataset. The evaluation will record:

- Access method selected by the optimizer.

- Available and selected indexes.

- Estimated rows examined.

- Additional sorting or filtering operations.

- Execution time where a meaningful measurement is available.

### 3.3 Evidence Plan

| Evidence ID | Evaluation | Evidence to Capture |
| --- | --- | --- |
| PERF-E01 | Workflow-step retrieval | EXPLAIN output for Q-03 |
| PERF-E02 | Version-history retrieval | EXPLAIN output for Q-04 |
| PERF-E03 | Audit-history retrieval | PERF-E03 |
| PERF-E04 | Index Integrity | Demonstration that duplicate document-version numbers are rejected |

Actual execution plans and results will be added after implementation. No performance improvement will be claimed solely because an index exists.

## 4. Index Trade-offs

Indexes can reduce the amount of data examined for frequently executed queries, but they consume storage and add overhead to inserts, updates, and deletes. Composite index column order will reflect the filtering and sorting requirements of each query. Unique constraints will be used where they enforce business rules as well as support retrieval. The final index set will prioritize demonstrated query needs and avoid redundant indexes. Performance testing will use representative synthetic data where appropriate. Index effectiveness will be evaluated using execution plans and, when useful, measured query execution time.

## Resiliency, Recovery & Data Integrity

## 1. Critical Transaction Inventory

This section identifies multi-step operations that must either complete successfully as a unit or leave no partial business changes behind.

| Transaction ID | Operation | Operations That Must Be Atomic | Expected Failure Behavior |
| --- | --- | --- | --- |
| TX-01 | Initiate workflow | Create workflow, workflow steps, participant assignments, activation changes, and success audit event | Roll back all changes |
| TX-02 | Record approval or rejection | Validate assignment and workflow state, insert decision, update assignment and applicable workflow state, insert audit event | Roll back all changes |
| TX-03 | Record signature | Validate signer and document version, insert signature, update applicable workflow state, insert audit event | Roll back all changes |
| TX-04 | Cancel workflow | Validate cancellation rules, update workflow and pending assignments, insert audit event | Roll back all changes |
| TX-05 | Create document version | Insert version, update current-version designation, insert audit event | Roll back all changes |

These transaction boundaries are proposed designs. The final implementation will reflect the operations supported by the approved requirements and application workflow.

## 2. Critical Implementation Strategy

Critical multi-step operations will use MySQL transactions with transactional storage engines such as InnoDB. Each transaction will: 1. Validate the current business state and applicable authorization rules. 2. Acquire necessary row locks when concurrent operations could conflict. 3. Perform the required inserts and updates.

4. Record the corresponding success audit event. 5. Commit only after all required operations succeed. 6. Roll back and propagate the error if a required operation fails. For example, workflow approval will validate that the workflow and assignment remain eligible for action before recording the decision. Concurrent requests will be serialized or rejected using a defined locking or optimistic-concurrency strategy. Detailed stored-procedure or application-transaction implementations will be finalized after the relational schema is established.

## 3. Integrity and Concurrency Control Matrix

| Risk | Proposed Control | Verification Method |
| --- | --- | --- |
| Duplicate document version | UNIQUE(DocumentID, VersionNumber) | Attempt to insert a duplicate version number |
| Duplicate user-role assignment | Composite primary key or unique constraint on UserRole(UserID, RoleID) | Attempt duplicate assignment |
| Orphaned workflow step | Foreign key from WorkflowStep to Workflow | Insert a step referencing a nonexistent workflow |
| Invalid status value | CHECK constraint or reference-table foreign key | Attempt to insert an unsupported status |
| Duplicate approval decision | Unique constraint on ApprovalDecision(WorkflowParticipantID), if only one final decision is permitted | Attempt a second final decision |
| Duplicate request submission | Idempotency key or appropriate unique business constraint | Submit the same request more than once |
| Concurrent workflow actions | Row locking or optimistic-concurrency check | Simulate conflicting actions |

| Invalid state transition | Controlled operation validates current and permitted next states | Attempt an action on a cancelled or completed workflow |
| --- | --- | --- |
| Unauthorized modification | Restricted database privileges and controlled operations | Attempt modification using an unauthorized database account |
| Partial transaction failure | Transaction rollback | Cause a required operation to fail and inspect resulting records |

A uniqueness constraint prevents duplicate keys but does not, by itself, guarantee safe retries or prevent concurrent overwrites. Those cases require explicit transaction and concurrency handling.

## 4. Workflow Lifecycle and Recovery

The database will enforce the workflow lifecycle defined by the functional requirements.

| Current State | Attempted Operation | Expected Behavior |
| --- | --- | --- |
| Draft | Activate workflow | Allow if required setup and validation succeed |
| Active | Record an eligible approval decision | Allow if authorization and assignment checks succeed |
| Active | Cancel workflow | Allow if cancellation rules are satisfied |
| Cancelled | Record a new approval decision | Reject |
| Complete | Modify a finalized decision | Reject or use a controlled correction process |
| Expired | Perform an ordinary workflow action | Reject |

The final transition matrix will be reconciled with the approved workflow rules. Completed approvals, signatures, and historical workflow actions will be retained when a workflow is cancelled or expires.

Failed transactions will roll back uncommitted changes. Retried operations will be checked for duplicate effects. Database backup and restoration assumptions will be documented in accordance with the project's scope.

## 5. Historical Record Protection

Records representing finalized business actions should not be silently overwritten or deleted. This includes completed approval decisions, signatures tied to a specific document version, finalized document versions, completed workflow history, and audit events. The design will distinguish between mutable current state and historical records. For example, a workflow may transition from Active to Cancelled while retaining the approvals and actions that occurred before cancellation. Proposed controls include foreign-key deletion policies, restricted database privileges, controlled update procedures, and triggers where appropriate. The specific controls will be selected based on the finalized schema and required database behavior.

## 6. Failure and Recovery Test Plan

| Test ID | Test Scenario | Expected Result |
| --- | --- | --- |
| RES-T 01 | Force audit-event insertion to fail during workflow initiation | Workflow creation and associated changes are rolled back |
| RES-T 02 | Insert the same document version number twice | Duplicate insert is rejected |
| RES-T 03 | Attempt approval after workflow cancellation | Operation is rejected without recording a successful decision |
| RES-T 04 | Submit two conflicting approval actions concurrently | No more than one incompatible final action succeeds |
| RES-T 05 | Insert a workflow step with an invalid WorkflowID | Foreign-key constraint rejects the insert |
| RES-T 06 | Attempt to modify a finalized historical record | Modification is rejected or routed through the defined correction process |

Actual results and supporting SQL output will be recorded after implementation and testing.

## Audit and Traceability Design

## 1. Audit Event Catalogue

The audit system will record significant document-management, workflow, approval, signature, and administrative events. Successful business changes will generate audit events within the same transaction as the associated changes.

| Event ID | Event | Trigger | Important Context |
| --- | --- | --- | --- |
| AE-01 | Document created | Document creation succeeds | Actor, document ID |
| AE-02 | Document version created | New version is committed | Actor, document ID, version number |
| AE-03 | Workflow initiated | Workflow initiation succeeds | Initiator, workflow ID, document version |
| AE-04 | Participant assigned or changed | Assignment operation succeeds | Actor, assignment ID, relevant changes |
| AE-05 | Approval or rejection recorded | Decision is committed | Actor, assignment ID, decision outcome |
| AE-06 | Signature recorded | Signature record is committed | Signer, signature ID, document version |
| AE-07 | Workflow cancelled or expired | State transition succeeds | Actor, previous status, new status, reason where required |
| AE-08 | Role or permission changed | Administrative change succeeds | Actor, affected user or role |
| AE-09 | Security-sensitive failure | Defined authorization or validation failure occurs | Actor if known, attempted operation, timestamp |

The implemented event catalogue will include only events supported by the approved requirements and final database operations. Failed business transactions will not retain success events from rolled-back operations. Security-failure logging will use a separately defined mechanism if those events must survive business-transaction rollback.

## 2. Audit Record Specification

The AuditLog entity defined in the data dictionary will provide the common record structure for audit events.

| Attribute | Purpose / Design Decision |
| --- | --- |
| AuditLogID | Unique identifier and primary key |
| ActorUserID | Identifies the user responsible for the event, where applicable |
| EventDateTime | Records when the event occurred |
| EventType | Identifies the type of auditable operation |
| AffectedRecordType | Identifies the affected entity type |
| AffectedRecordID | Identifies the affected business record |
| TransactionReferenc e | Correlates events belonging to the same logical transaction |
| PriorValueContext | Records relevant previous values where required |
| NewValueContext | Records relevant resulting values where required |
| ChangeReason | Records the reason for a change when required |

The final schema will specify data types, nullability, timestamp conventions, and the representation of prior/new value context. Generic affected-record references will be validated by the application or controlled database operations because a single conventional foreign key cannot reference multiple target tables. Audit records will avoid storing secrets or unnecessary sensitive information.

## 3. Audit Protection Strategy

| Requirement | Proposed Control | Verification |
| --- | --- | --- |
| Prevent routine modification of audit history | Restrict UPDATE and DELETE privileges for ordinary application roles | Attempt modification using the application database account |
| Associate events with successful operations | Insert audit records within the business transaction | Inspect committed records after a successful operation |
| Prevent false success events | Roll back audit inserts with failed business transactions | Perform a failure-injection test |
| Identify the responsible actor | Populate and validate ActorUserID where applicable | Inspect audit records for representative actions |
| Correlate related events | Populate TransactionReference consistently | Retrieve events belonging to one operation |
| Preserve historical records | Restrict deletion and use controlled correction procedures | Attempt unauthorized deletion or modification |

The append-only guarantee applies to the defined application roles and database permissions. Privileged administrators may retain the technical ability to modify database contents; this limitation will be documented rather than claiming absolute immutability.

## 4. Audit History Reconstruction

The audit design will support chronological reconstruction of document and workflow activity. The following representative query retrieves events for a workflow, assuming the final schema retains the proposed generic affected-record fields: SELECT AuditLogID, ActorUserID, EventType, AffectedRecordType, AffectedRecordID, EventDateTime, TransactionReference, PriorValueContext, NewValueContext FROM AuditLog

WHERE AffectedRecordType = 'Workflow' AND AffectedRecordID = 100 ORDER BY EventDateTime, AuditLogID; A second query will join the relevant workflow, step, participant, approval, and signature records to reconstruct the workflow's progression. The implementation will use the finalized foreign keys and avoid misleading row multiplication from one-to-many joins.

## 5. Audit Verification Plan

| Test ID | Test Scenario | Expected Result |
| --- | --- | --- |
| AUD-T0 1 | Create a document | Expected creation event is recorded |
| AUD-T0 2 | Record an approval or rejection | Event contains the correct actor and outcome |
| AUD-T0 3 | Cancel a workflow | Cancellation is recorded and earlier history remains |
| AUD-T0 4 | Attempt unauthorized audit UPDATE or DELETE | Database rejects the operation for the tested role |
| AUD-T0 5 | Force a business transaction to fail after business writes begin | No corresponding success event remains committed |
| AUD-T0 6 | Retrieve a workflow's audit history | Relevant events are returned in chronological order |

Actual results, SQL output, and screenshots will be added after the database implementation is available.