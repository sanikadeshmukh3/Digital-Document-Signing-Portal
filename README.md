# Digital Document Workflow and E-Signing Portal

Database Implementation Project  
Course: 01:198:437:01

## Overview

The **Digital Document Workflow and E-Signing Portal** is a MySQL database implementation for managing controlled document review, approval, acknowledgement, and electronic-signature workflows.

The database provides a centralized source of truth for:

- Documents and document metadata
- Document version history
- Workflow creation and progression
- Sequential and parallel workflow steps
- Participant assignments
- Review and acknowledgement completion
- Approval decisions
- Electronic signatures
- User roles and entitlements
- Workflow cancellation and rejection
- Outstanding-action reporting
- Audit and history tracking

This project focuses on the **database layer**. A production web application, authentication system, external e-signature provider, email notification service, and document-editing interface are outside the project scope.

---

# Repository Structure

```text
Digital-Document-Signing-Portal/
│
├── README.md
├── requirements.txt
├── .gitignore
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
│   │   └── 010_exception_transaction_tests.sql
│   │
│   └── manifest.txt
│
└── docs/
    ├── Functional Requirements Document.pdf
    ├── Technical Design Document.pdf
    └── ERD.pdf
```

The `manifest.txt` file defines the authoritative database build order.

The scripts in `06_demo_tests/` are intentionally **not included in the normal manifest** because they exercise expected business-rule failures and transaction rollback behavior after a successful database build.

---

# Database Design

The implementation includes the following primary entities:

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

`DocumentVersion` is modeled as a weak entity whose existence depends on `Document`.

Its identifying key is:

```text
(DocumentID, VersionNumber)
```

`VersionNumber` is meaningful only within the parent document.

A unique surrogate `DocumentVersionID` is also maintained for technical references from other database objects.

---

# Prerequisites

The build has been tested using a local MySQL environment on macOS.

The following software is required:

- Git
- Python 3
- MySQL Server
- MySQL command-line client
- Bash-compatible shell

Verify the required tools before building:

```bash
git --version
python3 --version
mysql --version
```

Verify that the MySQL server is running and accessible:

```bash
mysql \
  --host=127.0.0.1 \
  --port=3306 \
  --user=root \
  -p
```

Then run:

```sql
SELECT VERSION();
SHOW DATABASES;
```

Exit MySQL with:

```sql
EXIT;
```

---

# Python Environment Setup

A Python virtual environment is recommended so that project-specific dependencies remain isolated from system Python packages.

From the repository root:

```bash
python3 -m venv .venv
```

Activate the environment on macOS/Linux:

```bash
source .venv/bin/activate
```

Install the required packages:

```bash
python -m pip install -r requirements.txt
```

The project currently requires:

```text
mysql-connector-python
python-dotenv
```

Optional dependency verification:

```bash
python -c "import dotenv; import mysql.connector; print('dependencies OK')"
```

Expected output:

```text
dependencies OK
```

The `.venv/` directory must not be committed to Git.

---

# Configuration

Copy the example configuration file:

```bash
cp build/config.example.env build/.env
```

Edit:

```text
build/.env
```

with the local MySQL configuration.

Example:

```text
DB_HOST=127.0.0.1
DB_PORT=3306
DB_ADMIN_USER=root
DB_ADMIN_PASSWORD=replace_with_local_password

ALLOW_DATABASE_RECREATE=NO

WORK_ROOT=.build-work
```

## Configuration Variables

### `DB_HOST`

Hostname of the MySQL server.

For a local installation:

```text
127.0.0.1
```

### `DB_PORT`

MySQL server port.

Default:

```text
3306
```

### `DB_ADMIN_USER`

MySQL account used to create the database and database objects.

Example:

```text
root
```

### `DB_ADMIN_PASSWORD`

Password for the MySQL administrative account.

The real password must be stored only in the local `.env` file and must never be committed to Git.

### `ALLOW_DATABASE_RECREATE`

Controls whether the build may replace an existing database.

Recommended default:

```text
NO
```

For an intentionally disposable development/test database:

```text
YES
```

When recreation is enabled, the build may drop the target database before rebuilding it.

### `WORK_ROOT`

Directory used for temporary tagged repository clones and build logs.

Example:

```text
.build-work
```

---

# Secret Protection

The following files/directories should remain excluded from Git:

```text
build/.env
.venv/
.build-work/
*.log
__pycache__/
*.pyc
.DS_Store
```

A real database password, API token, or other secret must never be committed to the repository.

---

# Versioned Builds

Database builds are performed from an exact Git tag rather than directly from the changing `main` branch.

This ensures that a database build can be reproduced from a specific repository state.

Development tags may use names such as:

```text
v0.1.0-test
v0.1.1-test
```

Submission/release builds should use a stable release tag such as:

```text
v1.0.0
```

The build process verifies that the resolved repository commit exactly matches the requested Git tag.

---

# Creating a Release Tag

Before creating a release tag, ensure all intended files are committed:

```bash
git status
```

Then:

```bash
git add .
git commit -m "Prepare database release"
git push
```

Create the release tag:

```bash
git tag v1.0.0
```

Push the tag:

```bash
git push origin v1.0.0
```

The release tag should be created only after the repository contents intended for submission are committed.

---

# Building and Initializing the Database

Make the Bash build script executable:

```bash
chmod +x build/build_database.sh
```

Run the build from the repository root:

```bash
./build/build_database.sh \
    sanikadeshmukh3 \
    Digital-Document-Signing-Portal \
    v1.0.0 \
    document_portal_demo
```

Arguments are:

```text
1. GitHub repository owner
2. GitHub repository name
3. Git version tag
4. Target MySQL database name
```

Example development build:

```bash
./build/build_database.sh \
    sanikadeshmukh3 \
    Digital-Document-Signing-Portal \
    v0.1.6-test \
    document_portal_test
```

---

# Build Process

The build wrapper performs the following sequence:

```text
Validate required arguments and configuration
            ↓
Connect to MySQL
            ↓
Clone the GitHub repository
            ↓
Fetch the requested Git tag
            ↓
Verify the exact tag and commit SHA
            ↓
Validate the manifest and SQL files
            ↓
Protect or recreate the target database
            ↓
Create the database
            ↓
Create schema tables
            ↓
Create foreign keys, constraints, and indexes
            ↓
Create views
            ↓
Create functions
            ↓
Create stored procedures
            ↓
Create triggers
            ↓
Create database roles
            ↓
Apply privileges
            ↓
Load reference data
            ↓
Load realistic sample data
            ↓
Validate database objects
            ↓
Validate seeded data
            ↓
Run smoke tests
            ↓
Verify build
```

The build stops immediately if a required step fails.

Dependent scripts are not executed after a failed script.

---

# Manifest Execution Order

The current manifest executes:

```text
database/00_create_database.sql

database/01_schema/010_reference_tables.sql
database/01_schema/020_core_tables.sql
database/01_schema/030_relationship_tables.sql
database/01_schema/040_constraints_indexes.sql

database/02_programability/010_views.sql
database/02_programability/020_functions.sql
database/02_programability/030_procedures.sql
database/02_programability/040_triggers.sql

database/03_security/010_roles.sql
database/03_security/020_grants.sql

database/04_seed/010_reference_data.sql
database/04_seed/020_sample_data.sql

database/05_validation/010_object_validation.sql
database/05_validation/020_data_validation.sql
database/05_validation/030_smoke_tests.sql
```

The order is intentional because later objects depend on earlier objects.

For example:

- Core tables must exist before foreign keys are added.
- Tables must exist before views, procedures, functions, and triggers reference them.
- Roles must exist before grants are assigned.
- Reference data must exist before sample transactional data is loaded.
- Validation runs only after the complete database and seed data have been created.

---

# Existing Database Protection

The build does not silently replace an existing database.

If the target database already exists while:

```text
ALLOW_DATABASE_RECREATE=NO
```

the build should stop rather than overwrite it.

For an intentionally disposable classroom/development database, set:

```text
ALLOW_DATABASE_RECREATE=YES
```

before rebuilding.

This should only be enabled when replacement of the target database is intentional.

---

# Database Initialization Data

Initialization is performed automatically by the normal manifest.

## Reference Data

The build loads controlled domain values from:

```text
database/04_seed/010_reference_data.sql
```

The validated seed currently contains:

```text
42 reference values
```

These cover controlled domains including:

- Account status
- Document status
- Document classification
- Document version status
- Workflow status
- Workflow purpose/type
- Workflow step type
- Workflow step status
- Participant assignment status
- Assigned action
- Approval decision
- Signature status

## Sample Data

Realistic fictional workflow data is loaded from:

```text
database/04_seed/020_sample_data.sql
```

The sample data includes examples of:

- A document with a current version
- An active sequential workflow
- A completed workflow
- A rejected workflow
- A cancelled workflow
- An active parallel workflow
- Approval decisions
- Signature records
- Audit-history records

All project data is fictional and intended only for testing and demonstration.

---

# Validation

The normal build automatically runs three validation stages.

## Object Validation

```text
database/05_validation/010_object_validation.sql
```

Validates the presence of required:

- Tables
- Views
- Functions
- Stored procedures
- Triggers
- Keys and constraints
- Important indexes
- Database roles

A successful validation reports:

```text
OBJECT VALIDATION PASSED: all required objects are present.
```

The tested build currently verifies:

```text
12 tables
10 routines
8 triggers
```

---

## Data Validation

```text
database/05_validation/020_data_validation.sql
```

Checks seeded data and relational/business invariants including:

- Required reference-domain values
- Foreign-key/domain consistency
- Document/version relationships
- Workflow/document-version consistency
- Valid workflow statuses
- Participant roles
- Approval/signature consistency
- Seed row counts

A successful validation reports:

```text
DATA VALIDATION PASSED: seeded content satisfies all invariants.
```

---

## Smoke Tests

```text
database/05_validation/030_smoke_tests.sql
```

Exercises representative queries including:

- Outstanding participant actions
- Per-participant worklists
- Document history
- Workflow detail
- Document-version history
- Approval-decision history
- Signature/version consistency
- Audit history
- Query execution-plan/index verification

A successful run reports:

```text
SMOKE TESTS COMPLETED.
```

The tested participant-worklist query uses:

```text
idx_WorkflowParticipant_User_Status_DueDate
```

for its indexed lookup.

---

# Successful Build

A fully successful build ends with output similar to:

```text
Build verification: tables=12, routines=10, triggers=8

BUILD SUCCEEDED
```

The final line from the Bash wrapper should indicate that the database build completed successfully.

---

# Manual Verification

After a successful build, connect to MySQL:

```bash
mysql \
  --host=127.0.0.1 \
  --port=3306 \
  --user=root \
  -p
```

Select the database:

```sql
USE document_portal_demo;
```

Inspect tables and views:

```sql
SHOW FULL TABLES;
```

Inspect procedures:

```sql
SHOW PROCEDURE STATUS
WHERE Db = 'document_portal_demo';
```

Inspect functions:

```sql
SHOW FUNCTION STATUS
WHERE Db = 'document_portal_demo';
```

Inspect triggers:

```sql
SHOW TRIGGERS;
```

Inspect selected row counts:

```sql
SELECT COUNT(*) FROM ReferenceData;
SELECT COUNT(*) FROM `User`;
SELECT COUNT(*) FROM Role;
SELECT COUNT(*) FROM UserRole;
SELECT COUNT(*) FROM Document;
SELECT COUNT(*) FROM DocumentVersion;
SELECT COUNT(*) FROM Workflow;
SELECT COUNT(*) FROM WorkflowStep;
SELECT COUNT(*) FROM WorkflowParticipant;
SELECT COUNT(*) FROM ApprovalDecision;
SELECT COUNT(*) FROM Signature;
SELECT COUNT(*) FROM AuditLog;
```

---

# Exception and Transaction Tests

Exception and rollback tests are stored separately from the normal build:

```text
database/06_demo_tests/010_exception_transaction_tests.sql
```

These tests are not included in `manifest.txt` because they intentionally attempt operations that should fail.

Run them only after the standard build succeeds:

```bash
mysql \
  --host=127.0.0.1 \
  --port=3306 \
  --user=root \
  -p \
  document_portal_demo \
  < database/06_demo_tests/010_exception_transaction_tests.sql
```

The test script currently verifies:

### Test 1 — Unauthorized Approval

An unassigned user attempts to complete another participant's approval.

Expected result:

```text
REJECTED
```

The approval record, assignment status, and workflow status must remain unchanged.

### Test 2 — Action on Cancelled Workflow

A participant attempts an ordinary workflow action after the workflow has been cancelled.

Expected result:

```text
REJECTED
```

The workflow and participant assignment must remain cancelled.

### Test 3 — Rejection Without Required Reason

An approver attempts to reject an approval without supplying the required rejection reason.

Expected result:

```text
REJECTED
```

No approval decision should be created and workflow state must remain unchanged.

### Test 4 — Transaction Rollback

Workflow initiation intentionally fails because of invalid participant/role data.

Expected result:

```text
ROLLBACK
```

The failed operation must leave no partial:

- Workflow
- WorkflowStep
- WorkflowParticipant
- AuditLog state change
- DocumentVersion lock state change

A successful exception-test run ends with:

```text
ALL EXCEPTION / TRANSACTION TESTS PASSED
```

---

# Security and Entitlements

The build creates the following MySQL database roles:

```text
document_portal_app
document_portal_reporter
document_portal_auditor
document_portal_admin
```

These roles are distinct from the target database name.

The target schema is selected dynamically at build time, while MySQL role names remain fixed.

Security responsibilities are divided among database grants, controlled stored procedures, views, constraints, and business-rule validation.

Protected historical records include:

- Completed approval decisions
- Signature records
- Locked document versions
- Audit records

Triggers prevent prohibited updates or deletions to protected historical data.

---

# Audit History

`AuditLog` stores business-event history including:

- Actor
- Event timestamp
- Event type
- Affected record type
- Affected record identifier
- Transaction reference
- Prior/new value context where applicable
- Change reason where applicable

Audit records are protected from normal update and deletion.

Audit/history views support reconstruction of significant document and workflow activity.

---

# Build Failure Handling

The build is designed to stop on failures rather than continuing with an incomplete database.

Failure conditions include:

- Missing command-line arguments
- Missing environment configuration
- Missing Python dependencies
- MySQL connection failure
- Git repository retrieval failure
- Missing or incorrect Git tag
- Missing manifest
- Missing SQL script
- Existing database without explicit recreation permission
- SQL/schema failure
- Validation failure
- Smoke-test failure

The failed SQL file and error context are reported in the build output.

---

# Build Logs

Build execution records the selected:

- Version tag
- Git commit SHA
- Timestamp
- SQL script path
- Execution status
- Failure context where applicable

Temporary build working files and logs are stored under the configured:

```text
WORK_ROOT
```

directory.

These temporary build artifacts should not be committed unless intentionally retained as demonstration evidence.

---

# Reproducing the Project From Scratch

A new evaluator can reproduce the database using the following sequence.

## 1. Clone the repository

```bash
git clone https://github.com/sanikadeshmukh3/Digital-Document-Signing-Portal.git
cd Digital-Document-Signing-Portal
```

## 2. Create and activate a Python environment

```bash
python3 -m venv .venv
source .venv/bin/activate
```

## 3. Install Python dependencies

```bash
python -m pip install -r requirements.txt
```

## 4. Create local configuration

```bash
cp build/config.example.env build/.env
```

Update the local MySQL username and password in:

```text
build/.env
```

## 5. Verify MySQL

```bash
mysql \
  --host=127.0.0.1 \
  --port=3306 \
  --user=root \
  -p
```

## 6. Make the build wrapper executable

```bash
chmod +x build/build_database.sh
```

## 7. Run the tagged release build

```bash
./build/build_database.sh \
    sanikadeshmukh3 \
    Digital-Document-Signing-Portal \
    v1.0.0 \
    document_portal_demo
```

## 8. Confirm successful validation

Verify that the output contains:

```text
OBJECT VALIDATION PASSED
DATA VALIDATION PASSED
SMOKE TESTS COMPLETED
BUILD SUCCEEDED
```

## 9. Optionally run exception/rollback tests

```bash
mysql \
  --host=127.0.0.1 \
  --port=3306 \
  --user=root \
  -p \
  document_portal_demo \
  < database/06_demo_tests/010_exception_transaction_tests.sql
```

Expected final result:

```text
ALL EXCEPTION / TRANSACTION TESTS PASSED
```

At this point the database is fully initialized and ready for project demonstration.

---

# Project Documentation

Project documentation is maintained in:

```text
docs/
```

and includes:

- Functional Requirements Document (FRD)
- Technical Design Document (TDD)
- Entity Relationship Diagram (ERD)

The implementation is intended to remain traceable across:

```text
FRD requirement
    ↓
TDD design
    ↓
ERD entity/relationship
    ↓
SQL implementation
    ↓
constraint/procedure/trigger/view
    ↓
test case
    ↓
demonstration evidence
```

