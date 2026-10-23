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

A unique surrogate `DocumentVersionID` is also maintained for