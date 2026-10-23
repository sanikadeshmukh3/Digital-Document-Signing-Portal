# Document Workflow and E-Signing Portal

## Overview

The Document Workflow and E-Signing Portal is a relational database project for managing digital document review, approval, acknowledgement, and electronic-signature workflows.

The database serves as the system of record for:

- users and business roles
- documents and document versions
- workflow definitions and workflow steps
- workflow participants
- approval decisions
- simulated electronic signatures
- document and workflow lifecycle states
- audit history
- operational and historical reporting

The project is implemented using **MySQL 8.x**. Python is used to provide a reproducible database build process.

---

## Technology

- **Database:** MySQL 8.x
- **Build language:** Python 3
- **Database client:** MySQL command-line client
- **Version control:** Git / GitHub
- **Supported development environments:** macOS, Linux, Windows, Git Bash, or WSL, provided Python, Git, and MySQL are available

---

## Repository Structure

```text
Digital-Document-Signing-Portal/
│
├── README.md
│
├── build/
│   ├── build_database.py
│   └── config.example.env
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
│   ├── 02_programmability/
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
│   └── manifest.txt
│
└── docs/
    ├── Functional_Requirements_Document.md
    ├── Technical_Design_Document.md
    └── ERD.pdf
```

The database build order is defined exclusively by `database/manifest.txt`.

---

## Database Design

The primary schema entities are:

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

### Weak Entity

`DocumentVersion` is intentionally modeled as a weak entity.

Its identifying key is:

```text
(DocumentID, VersionNumber)
```

`VersionNumber` is a partial key that is meaningful only within its owning `Document`.

`DocumentVersionID` is retained as an alternate unique technical identifier for references from other database objects.

---

## Prerequisites

Before running the database build, install:

- Python 3
- Git
- MySQL Server 8.x
- MySQL command-line client

Verify the required tools:

```bash
python3 --version
git --version
mysql --version
```

The MySQL server must be running and reachable before starting the build.

---

## Configuration

Copy the example configuration:

```bash
cp build/config.example.env build/.env
```

Edit `build/.env` with local database credentials.

Example:

```text
DB_HOST=127.0.0.1
DB_PORT=3306
DB_ADMIN_USER=root
DB_ADMIN_PASSWORD=replace_with_local_secret

GITHUB_TOKEN=

ALLOW_DATABASE_RECREATE=NO
```

Do **not** commit `build/.env`.

The repository should include the following in `.gitignore`:

```text
build/.env
.build-work/
*.log
```

Passwords, GitHub tokens, and other credentials must never be committed to the repository.

---

## Release Tags

Database builds must use a Git release tag rather than an unpinned branch such as `main`.

Example:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The Python build script verifies that the checked-out commit exactly matches the requested tag before modifying the database.

---

## Building the Database

The build script is run as:

```bash
python3 build/build_database.py \
    sanikadeshmukh3 \
    Digital-Document-Signing-Portal \
    v1.0.0 \
    document_portal_demo
```

Arguments:

```text
owner        GitHub repository owner
repository   GitHub repository name
tag          Exact Git release tag
database     Target MySQL database name
```

The build process:

1. validates required configuration;
2. verifies that Python, Git, and MySQL prerequisites are available;
3. verifies database connectivity;
4. retrieves the requested Git tag;
5. verifies the exact release tag and commit SHA;
6. validates the database manifest and required SQL scripts;
7. checks whether the target database already exists;
8. refuses destructive replacement unless explicitly permitted;
9. executes SQL scripts in manifest order;
10. stops immediately if a required script fails;
11. records build status and errors;
12. runs database validation and smoke-test scripts;
13. reports the final build result.

---

## Existing Database Protection

The build does not silently overwrite an existing database.

If the requested database already exists, the build fails unless:

```text
ALLOW_DATABASE_RECREATE=YES
```

is explicitly configured.

This option should only be enabled for intentional classroom/demo rebuilds.

---

## Build Manifest

`database/manifest.txt` defines the authoritative SQL execution order.

Example:

```text
database/00_create_database.sql
database/01_schema/010_reference_tables.sql
database/01_schema/020_core_tables.sql
database/01_schema/030_relationship_tables.sql
database/01_schema/040_constraints_indexes.sql
database/02_programmability/010_views.sql
database/02_programmability/020_functions.sql
database/02_programmability/030_procedures.sql
database/02_programmability/040_triggers.sql
database/03_security/010_roles.sql
database/03_security/020_grants.sql
database/04_seed/010_reference_data.sql
database/04_seed/020_sample_data.sql
database/05_validation/010_object_validation.sql
database/05_validation/020_data_validation.sql
database/05_validation/030_smoke_tests.sql
```

Comments and blank lines may be included in the manifest and are ignored by the build script.

---

## Build Failure Behavior

The build stops immediately when a required SQL script fails.

The build does not continue to dependent scripts after a failure.

Business-level procedures also use MySQL transactions so that multi-table operations such as workflow initiation, approvals, signatures, and cancellations do not leave partially completed state.

---

## Logging

Each build records:

- requested release tag
- resolved Git commit SHA
- target database
- SQL script path
- execution start time
- execution result
- failure information when applicable

Local logs are written under:

```text
.build-work/
```

The database build also maintains build execution information where permitted.

---

## Security

The implementation separates:

### Business roles

Stored in the project's `Role` and `UserRole` tables:

- Document Owner
- Reviewer
- Approver
- Signer
- Workflow Manager
- System Administrator
- Auditor

### Database roles

Used to control technical database privileges:

- `document_portal_app`
- `document_portal_reporter`
- `document_portal_auditor`
- `document_portal_admin`

Protected state-changing operations are executed through stored procedures rather than unrestricted direct table updates.

Completed approvals, signatures, locked document versions, and audit history are protected from unauthorized modification.

---

## Documentation

Project documentation is maintained under `docs/`.

- Functional Requirements Document
- Technical Design Document
- Entity Relationship Diagram

The database implementation is designed to remain traceable to the approved functional requirements and technical design.