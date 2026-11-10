# Scale Data Generator

Reproducible bulk-data generator that adds roughly **2,000 additional
business records** on top of the curated demonstration dataset. It exists to
address the scalability critique without touching the hand-written scenario
data (Scenarios A–F) in `../020_sample_data.sql`.

This folder is **not** part of the ordered build manifest. The build
(`010_reference_data.sql` → `020_sample_data.sql`) still produces the clean,
deterministic demo dataset. You run this generator *afterward*, only when you
want bulk volume for scale/performance work.

## What it creates

A one-time pool of generated users (each holding exactly the role its workflow
action requires), then ~190 complete workflow **bundles**. Each bundle is a
full REVIEW → APPROVAL → SIGNATURE lifecycle:

| Table | Approx rows |
| --- | --- |
| User + UserRole (one-time pool) | ~80 |
| Document | ~190 |
| DocumentVersion | ~190 |
| Workflow | ~190 |
| WorkflowStep | ~570 |
| WorkflowParticipant | ~570 |
| ApprovalDecision | ~130 |
| Signature | ~95 |
| AuditLog | ~380 |

Workflow outcomes are mixed (≈50% COMPLETED, 30% ACTIVE, 20% REJECTED) so the
generated data exercises every status path, not just the happy path.

## Safety / integrity guarantees

- **Preserves curated data.** Everything created lives in a reserved
  namespace (`@scale.example` emails, `SCALE-DOC-` titles, `SCALEGEN-` audit
  references). The generator only ever deletes rows in that namespace.
- **Respects all constraints**: role↔action match + the composite
  `WorkflowParticipant → UserRole` FK, the per-step participant uniqueness,
  one-signature / one-decision-per-participant, and every DATETIME CHECK
  (completion ≥ activation, due ≥ activation, expiration ≥ start) — all
  satisfied by construction.
- **No schema changes, no weakened constraints.** Generated versions are
  inserted directly as `LOCKED` (exactly as the curated seed does), so the
  immutability triggers are never violated.
- **Idempotent.** Re-running first removes the previously generated rows
  (FK-safe order) and regenerates. The whole run is one transaction: it either
  fully applies or rolls back.

## Usage

Requires `build/.env` (copied from `build/config.example.env`) with the MySQL
connection settings, and a database that has already been built and seeded.

```bash
# from the repo root
pip install -r requirements.txt

# preview only (generates in a transaction, prints counts, rolls back)
python database/04_seed/scale/generate_scale_data.py --database document_portal --dry-run

# apply
python database/04_seed/scale/generate_scale_data.py --database document_portal

# custom volume
python database/04_seed/scale/generate_scale_data.py --database document_portal --bundles 250
```

Replace `document_portal` with your actual target database name.
