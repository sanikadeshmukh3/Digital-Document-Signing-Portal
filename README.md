# Digital Document Workflow and E-Signing Portal

A MySQL database implementation for managing document versions, approval workflows, participant assignments, electronic-signature records, lifecycle state transitions, authorization rules, audit history, and reporting.

This project is a **database implementation project**. A production web/mobile application, external e-signature provider, email delivery, cloud storage, and external authentication are outside the current scope.

## Repository

Repository:

`sanikadeshmukh3/Digital-Document-Signing-Portal`

The final release is intended to be built from an exact Git tag, such as:

```text
v1.0.0
```

The build process resolves the requested tag to an exact Git commit SHA and records both values in the build log.

---

# 1. Project Scope

The database supports:

- User and business-role management
- Documents and document-version history
- Controlled document-version creation
- Sequential and parallel workflow steps
- Review, acknowledgement, approval, and signature actions
- Role- and assignment-based action authorization
- Workflow cancellation and expiration
- Workflow progression and completion validation
- Document-version locking
- Audit logging
- Historical reporting
- Outstanding-action reporting
- Database-level integrity and immutability controls
- Transaction rollback and exception handling
- MySQL roles and grants
- Build, seed, validation, and demonstration scripts

---

# 2. Main Database Entities

The schema contains the following primary business entities:

- `User`
- `Role`
- `UserRole`
- `Document`
- `DocumentVersion`
- `Workflow`
- `WorkflowStep`
- `WorkflowParticipant`
- `ApprovalDecision`
- `Signature`
- `ReferenceData`
- `AuditLog`

## Weak Entity

`DocumentVersion` is modeled as the project's weak entity.

Its identifying relationship is with `Document`.

Its business identity is represented by:

```text
(DocumentID, VersionNumber)
```

where `VersionNumber` acts as the partial key within a parent document.

A separate `DocumentVersionID` is retained as a unique technical identifier for references from other tables.

---

# 3. Repository Structure

```text
Digital-Document-Signing-Portal/
│
├── README.md
├── requirements.txt
│
├── build/
│   ├── build_database.py
│   ├── build_database.sh
│   ├── config.example.env
│   └── modules/
│       ├── __init__.py
│       ├── github_manager.py
│       ├── database_manager.py
│       ├── deployment_engine.py
│       └── build_logger.py
│
├── database/
│   ├── 00_create_database.sql
│   │
│   ├── 01_schema/
│   │   ├── 010_reference_tables.sql
│   │   ├── 020_core_tables.sql
│   │   ├── 030_relationship_tables.sql
│   │   └── 040_constraints_indexes.sql
│   │
│   ├── 02_programability/
│   │   ├── 010_views.sql
│   │   ├── 020_functions.sql
│   │   ├── 030_procedures.sql
│   │   └── 040_triggers.sql
│   │
│   ├── 03_security/
│   │   ├── 010_roles.sql
│   │   └── 020_grants.sql
│   │
│   ├── 04_seed/
│   │   ├── 010_reference_data.sql
│   │   └── 020_sample_data.sql
│   │
│   ├── 05_validation/
│   │   ├── 010_object_validation.sql
│   │   ├── 020_data_validation.sql
│   │   └── 030_smoke_tests.sql
│   │
│   ├── 06_demo_tests/
│   │   ├── 010_exception_transaction_tests.sql
│   │   └── 020_positive_lifecycle_tests.sql
│   │
│   └── manifest.txt
│
└── docs/
    ├── Functional Requirements Document
    ├── Technical Design Document
    ├── ERD
    └── demo_evidence/
        ├── build_logs/
        └── validation/
```

> Note: the current repository uses the directory name `02_programability`. If this directory is renamed to `02_programmability`, the manifest, README, and any build references must be updated together.

---

# 4. Prerequisites

The build requires:

- Git
- Python 3
- MySQL server
- MySQL command-line client
- Bash-compatible shell for `build_database.sh`

Verify the required tools:

```bash
git --version
python3 --version
mysql --version
```

Confirm that the MySQL server is running and reachable before starting the build.

Example:

```bash
mysql \
  --host=127.0.0.1 \
  --port=3306 \
  --user=root \
  -p
```

---

# 5. Python Environment Setup

Create a local virtual environment:

```bash
python3 -m venv .venv
```

Activate it:

```bash
source .venv/bin/activate
```

Install dependencies:

```bash
python -m pip install -r requirements.txt
```

`requirements.txt` contains:

```text
mysql-connector-python
python-dotenv
```

The `.venv/` directory should not be committed to Git.

---

# 6. Build Configuration

Copy the example configuration:

```bash
cp build/config.example.env build/.env
```

Edit:

```text
build/.env
```

Example:

```text
DB_HOST=127.0.0.1
DB_PORT=3306

DB_ADMIN_USER=root
DB_ADMIN_PASSWORD=replace_with_local_secret

ALLOW_DATABASE_RECREATE=NO

WORK_ROOT=.build-work
```

## Environment Variables

### `DB_HOST`

MySQL server hostname.

### `DB_PORT`

MySQL server port.

Default MySQL port:

```text
3306
```

### `DB_ADMIN_USER`

Administrative MySQL account used to create the database and database objects.

### `DB_ADMIN_PASSWORD`

Password for the administrative MySQL account.

Do not commit this password.

### `ALLOW_DATABASE_RECREATE`

Controls protection against accidentally replacing an existing database.

Recommended value for final/release builds:

```text
NO
```

During deliberate local development rebuilds:

```text
YES
```

may be used when replacement of the target database is intentional.

### `WORK_ROOT`

Temporary location used by the build system for tagged repository retrieval, logs, and intermediate build artifacts.

Default:

```text
.build-work
```

---

# 7. Secret Protection

The following should remain excluded from Git:

```text
build/.env
.venv/
.build-work/
*.log
__pycache__/
*.pyc
.DS_Store
```

The repository contains `config.example.env`, but must not contain real database credentials.

---

# 8. Tagged Builds

The build system retrieves and builds an exact tagged version of the repository rather than the changing working branch.

A release tag should identify one immutable project state.

Example:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The build process:

1. Retrieves the repository.
2. Checks out the requested tag.
3. Confirms that the checked-out commit exactly matches that tag.
4. Resolves and records the Git commit SHA.
5. Validates the database manifest.
6. Executes SQL files in manifest order.
7. Runs object validation.
8. Runs data validation.
9. Runs smoke tests.
10. Records the final build result.

---

# 9. Build Command

Run the build from the project repository:

```bash
./build/build_database.sh \
    sanikadeshmukh3 \
    Digital-Document-Signing-Portal \
    v1.0.0 \
    document_portal_demo
```

Arguments:

```text
1. GitHub owner
2. Repository name
3. Exact release tag
4. Target database name
```

Example target database:

```text
document_portal_demo
```

For a release build, using a new database name with:

```text
ALLOW_DATABASE_RECREATE=NO
```

is recommended.

---

# 10. Build Order

`database/manifest.txt` is the authoritative SQL execution order.

The build runs the database scripts in dependency order:

```text
00_create_database.sql

01_schema/
    reference tables
    core tables
    relationship tables
    constraints and indexes

02_programability/
    views
    functions
    procedures
    triggers

03_security/
    roles
    grants

04_seed/
    reference data
    sample data

05_validation/
    object validation
    data validation
    smoke tests
```

The build stops immediately if a required SQL script fails.

The `06_demo_tests` directory is intentionally not part of the manifest because those files exercise failure scenarios and modify demonstration data after the validated database build.

---

# 11. Existing Database Protection

The build process checks whether the target database already exists.

With:

```text
ALLOW_DATABASE_RECREATE=NO
```

the build must stop rather than silently replace an existing database.

Database recreation should only occur when:

```text
ALLOW_DATABASE_RECREATE=YES
```

has been deliberately configured for a local/test build.

---

# 12. Initial Data

The build loads:

- controlled reference values
- business roles
- sample users
- user-role assignments
- documents
- document versions
- workflows
- workflow steps
- workflow participants
- approval decisions
- signatures
- representative audit records

The reference-data seed currently contains **42 required controlled values**.

Sample data demonstrates:

- completed workflow history
- an active sequential workflow
- rejected workflow behavior
- cancelled workflow behavior
- parallel workflow steps
- approval history
- signature history
- outstanding work
- system and user audit events

---

# 13. Database Programmability

## Views

The implementation includes:

```text
vw_ParticipantWorklist
vw_OutstandingActions
vw_WorkflowDetail
vw_DocumentVersionHistory
vw_DocumentHistory
vw_AuditHistory
```

## Functions

The implementation includes:

```text
fn_user_has_role
fn_all_predecessors_complete
fn_step_required_work_complete
fn_workflow_required_work_complete
```

## Procedures

The implementation includes:

```text
sp_advance_workflow
sp_initiate_workflow
sp_complete_review_acknowledgement
sp_record_approval_decision
sp_record_signature
sp_cancel_workflow
sp_create_document_version
sp_expire_workflows
```

### Controlled Document-Version Creation

`sp_create_document_version` validates ownership and version uniqueness, creates the version transactionally, and records the corresponding audit event.

### Workflow Expiration

`sp_expire_workflows` identifies eligible expired active workflows, transitions them to `EXPIRED`, cancels outstanding steps and participant assignments, and records expiration audit events.

## Triggers

The current implementation contains triggers that protect finalized and append-only records from prohibited update/delete operations, including:

- finalized `DocumentVersion` records
- `ApprovalDecision`
- `Signature`
- `AuditLog`

---

# 14. Object Validation

The object-validation script confirms the presence and structure of the required database objects.

Expected implementation totals include:

```text
12 tables
4 functions
8 procedures
12 routines total
9 triggers
4 database roles
```

It also validates required:

- primary keys
- composite keys
- unique constraints
- foreign keys
- indexes
- views
- procedures
- functions
- triggers
- roles

---

# 15. Data Validation

The data-validation script verifies:

- required `ReferenceData` values
- valid foreign-key domains
- required seed-data counts
- workflow/document consistency
- workflow/document-version consistency
- participant-role consistency
- other project invariants

A successful run reports:

```text
DATA VALIDATION PASSED
```

---

# 16. Smoke Tests

The normal build executes smoke tests after initialization.

Representative tests include:

- outstanding-action worklist
- participant worklist
- workflow detail
- document history
- version history
- approval history
- signature history
- audit history
- query execution-plan verification

A successful run reports:

```text
SMOKE TESTS COMPLETED
```

The worklist performance test uses `EXPLAIN` and verifies use of the participant worklist index where appropriate.

---

# 17. Demo and Exception Tests

Demonstration tests are stored separately from the normal build manifest.

## Exception / Transaction Tests

Run:

```bash
mysql \
  --host=127.0.0.1 \
  --port=3306 \
  --user=root \
  -p \
  document_portal_demo \
  < database/06_demo_tests/010_exception_transaction_tests.sql
```

These tests demonstrate:

1. Unauthorized approval rejection
2. Action rejection against a cancelled workflow
3. Required rejection-reason validation
4. Forced mid-transaction rollback
5. Direct UNIQUE constraint enforcement
6. `AuditLog` update/delete protection
7. Locked `DocumentVersion` update/delete protection

A successful run ends with:

```text
ALL EXCEPTION / TRANSACTION / CONSTRAINT / IMMUTABILITY TESTS PASSED
```

## Positive Lifecycle Tests

Run:

```bash
mysql \
  --host=127.0.0.1 \
  --port=3306 \
  --user=root \
  -p \
  document_portal_demo \
  < database/06_demo_tests/020_positive_lifecycle_tests.sql
```

These tests demonstrate:

1. Controlled positive document-version creation
2. Workflow expiration
3. Cancellation of outstanding workflow steps
4. Cancellation of outstanding participant assignments
5. Associated audit-event creation

A successful run ends with:

```text
ALL POSITIVE LIFECYCLE TESTS PASSED
```

Because workflow expiration is a batch operation, positive lifecycle tests should be run after the pristine build/smoke-test evidence has been captured.

---

# 18. Transaction and Rollback Behavior

Important multi-table operations execute transactionally.

Stored procedures use:

```text
START TRANSACTION
COMMIT
ROLLBACK
EXIT HANDLER FOR SQLEXCEPTION
RESIGNAL
```

where appropriate.

The demo suite contains a forced mid-transaction failure that proves a partially started workflow operation does not leave:

- a partial `Workflow`
- partial `WorkflowStep` rows
- partial `WorkflowParticipant` rows
- incorrect audit rows
- an incorrectly locked `DocumentVersion`

after rollback.

---

# 19. Security and Roles

The implementation defines the following MySQL roles:

```text
document_portal_app
document_portal_reporter
document_portal_auditor
document_portal_admin
```

Authorization is enforced through a combination of:

- database roles and grants
- controlled stored procedures
- participant/role relationships
- workflow-state checks
- assignment-state checks
- immutable-history controls

Business authorization requires more than the existence of a database account. Controlled procedures validate applicable owner, participant, role, workflow, step, and assignment conditions.

---

# 20. Audit and Historical Protection

`AuditLog` records representative business events using:

- actor
- event timestamp
- event type
- affected record type
- affected record identifier
- transaction reference
- prior-value context where appropriate
- new-value context where appropriate
- change reason where appropriate

Audit records are append-only within the supported application design.

Database triggers prevent ordinary update and deletion of existing audit records.

Additional triggers prevent modification/deletion of protected finalized records such as locked document versions, completed approvals, and signatures.

Audit-history views support chronological reconstruction of business activity.

---

# 21. Performance and Indexing

Indexes are defined for common operational access paths, including:

- documents by owner
- documents by lifecycle status
- workflows by document/version/status
- workflows by expiration
- workflow steps by workflow and sequence
- workflow participants by user/status/due date
- workflow participants by step/status/required flag
- participant roles
- audit events by actor/time
- audit events by affected record/time
- transaction references

The smoke tests include `EXPLAIN` evidence for the participant worklist query.

---

# 22. Build Logs and Demo Evidence

The build system creates timestamped logs under the temporary build workspace.

Final release evidence should be copied into the repository's demo-evidence area rather than relying only on the temporary `.build-work` directory.

Example:

```text
docs/demo_evidence/
├── build_logs/
│   └── build_v1.0.0_<timestamp>.log
└── validation/
    ├── exception_tests_v1.0.0.txt
    └── lifecycle_tests_v1.0.0.txt
```

The final build log should contain:

- build timestamp
- requested version/tag
- resolved Git commit SHA
- target database name
- manifest/script execution order
- per-script execution result
- object-validation output
- data-validation output
- smoke-test output
- final object counts
- build success/failure status
- error details for any failed build

The final successful build evidence should be retained for the release submitted to the course.

Do not include database passwords or other secrets in evidence files.

---

# 23. Failure Handling

The build stops when it encounters:

- missing configuration
- unavailable required tooling
- repository/tag retrieval failure
- exact-tag verification failure
- missing manifest
- missing SQL file
- invalid build contents
- unavailable database server
- protected existing target database
- schema-build failure
- seed-data failure
- object-validation failure
- data-validation failure
- smoke-test failure

Database procedures independently use transactional error handling to prevent partial business transactions.

---

# 24. Manual Verification

After a successful build:

```bash
mysql \
  --host=127.0.0.1 \
  --port=3306 \
  --user=root \
  -p \
  document_portal_demo
```

Example checks:

```sql
SHOW TABLES;
```

```sql
SHOW PROCEDURE STATUS
WHERE Db = 'document_portal_demo';
```

```sql
SHOW FUNCTION STATUS
WHERE Db = 'document_portal_demo';
```

```sql
SHOW TRIGGERS;
```

```sql
SELECT *
FROM vw_OutstandingActions;
```

```sql
SELECT *
FROM vw_DocumentVersionHistory;
```

```sql
SELECT *
FROM vw_AuditHistory
ORDER BY EventDateTime, AuditLogID;
```

---

# 25. Clean Reproduction Procedure

A new evaluator should be able to reproduce the database with the following process:

```bash
git clone <repository-url>
cd Digital-Document-Signing-Portal
```

Create and activate the Python environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

Create local configuration:

```bash
cp build/config.example.env build/.env
```

Configure the local MySQL credentials in:

```text
build/.env
```

Then execute the tagged build:

```bash
./build/build_database.sh \
    sanikadeshmukh3 \
    Digital-Document-Signing-Portal \
    v1.0.0 \
    document_portal_demo
```

The expected result is a successfully initialized and validated database containing the required schema, programmable objects, security objects, reference data, sample data, and validation evidence.

---

