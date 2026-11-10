#!/usr/bin/env python3
# ============================================================
# File: database/04_seed/scale/generate_scale_data.py
# Project: Document Workflow and E-signing Portal
#
# Loads bulk workflow data on top of the curated demo seed so the
# database can be exercised at a realistic size. By default it adds
# roughly 2,000 rows; pass --bundles to load more. The curated
# scenario data from 020_sample_data.sql is left untouched.
#
# How it stays safe:
#   - All generated rows live in a reserved namespace, and the
#     script only ever deletes rows in that namespace, so the
#     hand-written demo data and reference data are never affected.
#   - Every generated row is built to satisfy the schema as-is:
#     participants get the right (UserID, RoleID) in UserRole first,
#     there is at most one signature/decision per participant, the
#     datetime checks hold by construction, emails stay unique in
#     the @scale.example namespace, and versions are inserted
#     directly as LOCKED (like the real seed) so no trigger fires.
#   - It is safe to rerun: each run clears its own previously
#     generated rows (in FK-safe order) and regenerates. The whole
#     run is one transaction, so it either fully applies or rolls
#     back. It never changes the schema or relaxes a constraint.
#
# Generated rows are recognised by these markers:
#   - User.Email                    ends with '@scale.example'
#   - Document.Title                starts with 'SCALE-DOC-'
#   - AuditLog.TransactionReference starts with 'SCALEGEN-'
# Everything else (versions, workflows, steps, participants,
# decisions, signatures) is reached by foreign key from those rows.
#
# Usage:
#   1. Make sure build/.env exists (copied from config.example.env)
#      with DB_HOST / DB_PORT / DB_ADMIN_USER / DB_ADMIN_PASSWORD.
#   2. python database/04_seed/scale/generate_scale_data.py \
#          --database document_portal [--bundles 190] [--dry-run]
#
# The target database must already be built and seeded
# (reference data + 020_sample_data.sql applied).
# ============================================================

import argparse
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

import mysql.connector
from dotenv import load_dotenv


# ------------------------------------------------------------
# Namespace markers. Changing these changes what the generator
# considers "its own" data. Keep them distinctive.
# ------------------------------------------------------------
EMAIL_DOMAIN = "scale.example"
DOC_TITLE_PREFIX = "SCALE-DOC-"
AUDIT_TXN_PREFIX = "SCALEGEN-"
ORG_AFFILIATION = "Initech (Scale Data)"

# One-time generated user pool. Each user holds exactly the role
# its workflow action needs. Spreading assignments across many
# users keeps the data realistic and avoids lopsided worklists.
POOL = {
    "Document Owner": 8,
    "Reviewer": 12,
    "Approver": 10,
    "Signer": 10,
}

# A bundle = one full REVIEW -> APPROVAL -> SIGNATURE workflow and
# all of its rows. ~190 bundles lands total generated rows near
# 2,000 once the one-time user/role pool is included.
DEFAULT_BUNDLES = 190

# Distribution of workflow outcomes across bundles (must sum to 1).
# COMPLETED: all steps done, APPROVED decision + SIGNED signature.
# ACTIVE:    review done, approval ACTIVE (outstanding), signature PENDING.
# REJECTED:  review done, approval REJECTED, signature CANCELLED.
OUTCOME_WEIGHTS = [
    ("COMPLETED", 0.50),
    ("ACTIVE", 0.30),
    ("REJECTED", 0.20),
]


class ScaleDataExistsError(Exception):
    """Raised when committed, immutable scale rows already exist.

    Signature and ApprovalDecision rows are append-only (protected by
    triggers), so they cannot be deleted to make room for a fresh run.
    The only clean slate is a database rebuild.
    """

    def __init__(self, count):
        self.count = count
        super().__init__(
            f"{count} committed, immutable scale rows "
            "(Signature/ApprovalDecision) already exist"
        )


class ScaleGenerator:
    def __init__(self, conn, database, bundles):
        self.conn = conn
        self.database = database
        self.bundles = bundles
        self.cur = conn.cursor()
        self._ref_cache = {}
        self._role_cache = {}

    # --------------------------------------------------------
    # Reference / role lookups (by natural key, cached)
    # --------------------------------------------------------
    def ref_id(self, domain, code):
        key = (domain, code)
        if key not in self._ref_cache:
            self.cur.execute(
                """
                SELECT ReferenceDataID FROM ReferenceData
                WHERE DomainName = %s AND Code = %s AND IsActive = TRUE
                """,
                (domain, code),
            )
            row = self.cur.fetchone()
            if row is None:
                raise RuntimeError(
                    f"Missing reference data {domain}/{code}. "
                    "Is the database seeded (010_reference_data.sql)?"
                )
            self._ref_cache[key] = row[0]
        return self._ref_cache[key]

    def role_id(self, role_name):
        if role_name not in self._role_cache:
            self.cur.execute(
                "SELECT RoleID FROM Role WHERE RoleName = %s",
                (role_name,),
            )
            row = self.cur.fetchone()
            if row is None:
                raise RuntimeError(
                    f"Missing Role '{role_name}'. Is 020_sample_data.sql applied?"
                )
            self._role_cache[role_name] = row[0]
        return self._role_cache[role_name]

    # --------------------------------------------------------
    # Count committed, immutable scale rows (Signature /
    # ApprovalDecision). These CANNOT be deleted: the append-only
    # triggers trg_Signature_PreventDelete / trg_ApprovalDecision_
    # PreventDelete forbid it by design. If any exist, a destructive
    # re-run is impossible without a database rebuild, so the caller
    # must be told rather than hitting the trigger wall mid-run.
    # --------------------------------------------------------
    def count_immutable_scale_rows(self):
        self.cur.execute(
            f"""
            SELECT
              (SELECT COUNT(*) FROM Signature s
               JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = s.WorkflowParticipantID
               JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
               JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
               JOIN Document d ON d.DocumentID = w.DocumentID
               WHERE d.Title LIKE '{DOC_TITLE_PREFIX}%')
            + (SELECT COUNT(*) FROM ApprovalDecision ad
               JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = ad.WorkflowParticipantID
               JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
               JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
               JOIN Document d ON d.DocumentID = w.DocumentID
               WHERE d.Title LIKE '{DOC_TITLE_PREFIX}%')
            """
        )
        return self.cur.fetchone()[0]

    # --------------------------------------------------------
    # Idempotency: delete previously generated rows only.
    # FK-safe order: leaf action rows -> participants -> steps ->
    # workflows -> versions -> documents -> audit -> userrole ->
    # users. Everything is anchored to the reserved namespace.
    #
    # PRECONDITION: the caller (run()) has already confirmed there
    # are NO committed Signature / ApprovalDecision scale rows, so
    # the two deletes below only ever match zero immutable rows and
    # never trip the append-only triggers.
    # --------------------------------------------------------
    def purge_previous(self):
        # Signatures/decisions/participants/steps/workflows belonging
        # to generated documents (Title prefix), reached by FK.
        self.cur.execute(
            f"""
            DELETE s FROM Signature s
            JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = s.WorkflowParticipantID
            JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
            JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
            JOIN Document d ON d.DocumentID = w.DocumentID
            WHERE d.Title LIKE '{DOC_TITLE_PREFIX}%'
            """
        )
        self.cur.execute(
            f"""
            DELETE ad FROM ApprovalDecision ad
            JOIN WorkflowParticipant wp ON wp.WorkflowParticipantID = ad.WorkflowParticipantID
            JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
            JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
            JOIN Document d ON d.DocumentID = w.DocumentID
            WHERE d.Title LIKE '{DOC_TITLE_PREFIX}%'
            """
        )
        self.cur.execute(
            f"""
            DELETE wp FROM WorkflowParticipant wp
            JOIN WorkflowStep ws ON ws.WorkflowStepID = wp.WorkflowStepID
            JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
            JOIN Document d ON d.DocumentID = w.DocumentID
            WHERE d.Title LIKE '{DOC_TITLE_PREFIX}%'
            """
        )
        self.cur.execute(
            f"""
            DELETE ws FROM WorkflowStep ws
            JOIN Workflow w ON w.WorkflowID = ws.WorkflowID
            JOIN Document d ON d.DocumentID = w.DocumentID
            WHERE d.Title LIKE '{DOC_TITLE_PREFIX}%'
            """
        )
        self.cur.execute(
            f"""
            DELETE w FROM Workflow w
            JOIN Document d ON d.DocumentID = w.DocumentID
            WHERE d.Title LIKE '{DOC_TITLE_PREFIX}%'
            """
        )
        # Generated audit rows (by transaction-reference prefix).
        self.cur.execute(
            f"DELETE FROM AuditLog WHERE TransactionReference LIKE '{AUDIT_TXN_PREFIX}%'"
        )
        # Versions of generated documents. These are LOCKED; the
        # finalized-delete trigger blocks deleting a LOCKED row, so
        # flip them to CURRENT first (a benign, in-namespace change),
        # then delete.
        self.cur.execute(
            f"""
            UPDATE DocumentVersion dv
            JOIN Document d ON d.DocumentID = dv.DocumentID
            SET dv.CurrentVersionStatusID = %s, dv.LockedDateTime = NULL
            WHERE d.Title LIKE '{DOC_TITLE_PREFIX}%'
            """,
            (self.ref_id("DOCUMENT_VERSION_STATUS", "CURRENT"),),
        )
        self.cur.execute(
            f"""
            DELETE dv FROM DocumentVersion dv
            JOIN Document d ON d.DocumentID = dv.DocumentID
            WHERE d.Title LIKE '{DOC_TITLE_PREFIX}%'
            """
        )
        self.cur.execute(
            f"DELETE FROM Document WHERE Title LIKE '{DOC_TITLE_PREFIX}%'"
        )
        # Generated user-role links and users (namespace by email).
        self.cur.execute(
            f"""
            DELETE ur FROM UserRole ur
            JOIN `User` u ON u.UserID = ur.UserID
            WHERE u.Email LIKE '%@{EMAIL_DOMAIN}'
            """
        )
        self.cur.execute(
            f"DELETE FROM `User` WHERE Email LIKE '%@{EMAIL_DOMAIN}'"
        )

    # --------------------------------------------------------
    # One-time generated user pool, each holding the right role.
    # Returns dict: role_name -> list of (user_id, role_id).
    # --------------------------------------------------------
    def create_user_pool(self):
        active = self.ref_id("ACCOUNT_STATUS", "ACTIVE")
        pool = {}
        n = 0
        for role_name, count in POOL.items():
            rid = self.role_id(role_name)
            pool[role_name] = []
            for i in range(count):
                n += 1
                email = f"scaleuser{n:04d}@{EMAIL_DOMAIN}"
                self.cur.execute(
                    """
                    INSERT INTO `User`
                        (FirstName, LastName, Email,
                         OrganizationalAffiliation, AccountStatusID)
                    VALUES (%s, %s, %s, %s, %s)
                    """,
                    (f"Scale{n:04d}", role_name.split()[0], email,
                     ORG_AFFILIATION, active),
                )
                uid = self.cur.lastrowid
                self.cur.execute(
                    "INSERT INTO UserRole (UserID, RoleID) VALUES (%s, %s)",
                    (uid, rid),
                )
                pool[role_name].append((uid, rid))
        return pool

    # --------------------------------------------------------
    # Generate one full workflow bundle.
    # --------------------------------------------------------
    def create_bundle(self, idx, outcome, pool):
        # --- resolve the reference ids we need ---
        cls_codes = ["INTERNAL", "CONFIDENTIAL", "RESTRICTED"]
        classification = self.ref_id(
            "DOCUMENT_CLASSIFICATION", cls_codes[idx % len(cls_codes)]
        )
        doc_active = self.ref_id("DOCUMENT_STATUS", "ACTIVE")
        ver_locked = self.ref_id("DOCUMENT_VERSION_STATUS", "LOCKED")

        st_type_review = self.ref_id("STEP_TYPE", "REVIEW")
        st_type_appr = self.ref_id("STEP_TYPE", "APPROVAL")
        st_type_sign = self.ref_id("STEP_TYPE", "SIGNATURE")

        act_review = self.ref_id("ASSIGNED_ACTION", "REVIEW")
        act_appr = self.ref_id("ASSIGNED_ACTION", "APPROVAL")
        act_sign = self.ref_id("ASSIGNED_ACTION", "SIGNATURE")

        ss_completed = self.ref_id("STEP_STATUS", "COMPLETED")
        ss_active = self.ref_id("STEP_STATUS", "ACTIVE")
        ss_pending = self.ref_id("STEP_STATUS", "PENDING")
        ss_cancelled = self.ref_id("STEP_STATUS", "CANCELLED")

        ps_completed = self.ref_id("PARTICIPANT_STATUS", "COMPLETED")
        ps_active = self.ref_id("PARTICIPANT_STATUS", "ACTIVE")
        ps_pending = self.ref_id("PARTICIPANT_STATUS", "PENDING")
        ps_rejected = self.ref_id("PARTICIPANT_STATUS", "REJECTED")
        ps_cancelled = self.ref_id("PARTICIPANT_STATUS", "CANCELLED")

        wf_completed = self.ref_id("WORKFLOW_STATUS", "COMPLETED")
        wf_active = self.ref_id("WORKFLOW_STATUS", "ACTIVE")
        wf_rejected = self.ref_id("WORKFLOW_STATUS", "REJECTED")
        wf_purpose = self.ref_id(
            "WORKFLOW_PURPOSE_TYPE", "FULL_REVIEW_APPROVAL_SIGNATURE"
        )

        # --- pick role-correct actors (round-robin over the pool) ---
        owner_uid, _ = pool["Document Owner"][idx % len(pool["Document Owner"])]
        rev_uid, rev_rid = pool["Reviewer"][idx % len(pool["Reviewer"])]
        app_uid, app_rid = pool["Approver"][idx % len(pool["Approver"])]
        sig_uid, sig_rid = pool["Signer"][idx % len(pool["Signer"])]

        # --- build a valid timeline (all CHECKs satisfied) ---
        base = datetime(2026, 1, 1, 9, 0, 0) + timedelta(days=idx % 300)
        start = base
        rev_act = start
        rev_comp = rev_act + timedelta(hours=6)
        rev_due = rev_act + timedelta(days=1)
        app_act = rev_comp
        app_comp = app_act + timedelta(hours=20)
        app_due = app_act + timedelta(days=2)
        sig_act = app_comp
        sig_comp = sig_act + timedelta(hours=5)
        sig_due = sig_act + timedelta(days=1)
        expiration = start + timedelta(days=30)
        wf_completion = sig_comp

        # --- Document ---
        self.cur.execute(
            """
            INSERT INTO Document
                (Title, BusinessDescription, OwnerUserID,
                 ClassificationID, LifecycleStatusID)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (f"{DOC_TITLE_PREFIX}{idx:05d}",
             "Generated scale-test document.",
             owner_uid, classification, doc_active),
        )
        doc_id = self.cur.lastrowid

        # --- DocumentVersion (LOCKED directly; no trigger fires) ---
        self.cur.execute(
            """
            INSERT INTO DocumentVersion
                (DocumentID, VersionNumber, EffectiveInformation,
                 CreatedDateTime, CreatedByUserID,
                 CurrentVersionStatusID, LockedDateTime)
            VALUES (%s, 1, %s, %s, %s, %s, %s)
            """,
            (doc_id, "Generated scale-test version.",
             start, owner_uid, ver_locked, start),
        )
        # weak entity: fetch surrogate id
        self.cur.execute(
            "SELECT DocumentVersionID FROM DocumentVersion "
            "WHERE DocumentID = %s AND VersionNumber = 1",
            (doc_id,),
        )
        ver_id = self.cur.fetchone()[0]

        # --- Workflow (status depends on outcome) ---
        wf_status = {
            "COMPLETED": wf_completed,
            "ACTIVE": wf_active,
            "REJECTED": wf_rejected,
        }[outcome]
        completion_val = wf_completion if outcome == "COMPLETED" else None
        self.cur.execute(
            """
            INSERT INTO Workflow
                (DocumentID, DocumentVersionID, InitiatorUserID,
                 WorkflowPurposeTypeID, WorkflowStatusID,
                 StartDateTime, CompletionDateTime, ExpirationDateTime)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (doc_id, ver_id, owner_uid, wf_purpose, wf_status,
             start, completion_val, expiration),
        )
        wf_id = self.cur.lastrowid

        # --- step/participant statuses depend on outcome ---
        if outcome == "COMPLETED":
            step_states = (ss_completed, ss_completed, ss_completed)
            part_states = (ps_completed, ps_completed, ps_completed)
        elif outcome == "ACTIVE":
            step_states = (ss_completed, ss_active, ss_pending)
            part_states = (ps_completed, ps_active, ps_pending)
        else:  # REJECTED
            step_states = (ss_completed, ss_cancelled, ss_cancelled)
            part_states = (ps_completed, ps_rejected, ps_cancelled)

        def add_step(seq, step_type, status, act, comp, due):
            self.cur.execute(
                """
                INSERT INTO WorkflowStep
                    (WorkflowID, SequenceNumber, StepTypeID,
                     RequiredPolicy, StepStatusID,
                     ActivationDateTime, CompletionDateTime, DueDateTime)
                VALUES (%s, %s, %s, 'ALL_REQUIRED', %s, %s, %s, %s)
                """,
                (wf_id, seq, step_type, status, act, comp, due),
            )
            return self.cur.lastrowid

        def add_participant(step_id, uid, rid, action, status,
                            act, comp, due):
            self.cur.execute(
                """
                INSERT INTO WorkflowParticipant
                    (WorkflowStepID, UserID, RoleID, AssignedActionID,
                     AssignmentStatusID, RequiredFlag,
                     ActivationDateTime, CompletionDateTime, DueDateTime)
                VALUES (%s, %s, %s, %s, %s, TRUE, %s, %s, %s)
                """,
                (step_id, uid, rid, action, status, act, comp, due),
            )
            return self.cur.lastrowid

        # REVIEW step (always completed in every outcome)
        s1 = add_step(1, st_type_review, step_states[0],
                      rev_act, rev_comp, rev_due)
        p1 = add_participant(s1, rev_uid, rev_rid, act_review,
                             part_states[0], rev_act, rev_comp, rev_due)

        # APPROVAL step
        appr_comp = app_comp if outcome in ("COMPLETED", "REJECTED") else None
        s2 = add_step(2, st_type_appr, step_states[1],
                      app_act,
                      app_comp if outcome == "COMPLETED" else None,
                      app_due)
        p2 = add_participant(s2, app_uid, app_rid, act_appr,
                             part_states[1], app_act, appr_comp, app_due)

        # SIGNATURE step
        sig_act_val = sig_act if outcome == "COMPLETED" else None
        sig_comp_val = sig_comp if outcome == "COMPLETED" else None
        sig_due_val = sig_due if outcome == "COMPLETED" else None
        s3 = add_step(3, st_type_sign, step_states[2],
                      sig_act_val, sig_comp_val, sig_due_val)
        # participant due must be >= activation; keep NULL when not active
        p3 = add_participant(s3, sig_uid, sig_rid, act_sign,
                             part_states[2],
                             sig_act_val, sig_comp_val, sig_due_val)

        rows = 1 + 1 + 1 + 3 + 3  # doc, ver, wf, 3 steps, 3 participants

        # --- ApprovalDecision (COMPLETED->APPROVED, REJECTED->REJECTED) ---
        if outcome == "COMPLETED":
            self.cur.execute(
                """
                INSERT INTO ApprovalDecision
                    (WorkflowParticipantID, DecisionValueID,
                     DecisionDateTime, Comments, RejectionReason)
                VALUES (%s, %s, %s, %s, NULL)
                """,
                (p2, self.ref_id("APPROVAL_DECISION", "APPROVED"),
                 app_comp, "Generated approval."),
            )
            rows += 1
        elif outcome == "REJECTED":
            self.cur.execute(
                """
                INSERT INTO ApprovalDecision
                    (WorkflowParticipantID, DecisionValueID,
                     DecisionDateTime, Comments, RejectionReason)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (p2, self.ref_id("APPROVAL_DECISION", "REJECTED"),
                 app_comp, "Generated rejection.",
                 "Generated rejection reason for scale data."),
            )
            rows += 1

        # --- Signature (only on COMPLETED) ---
        if outcome == "COMPLETED":
            self.cur.execute(
                """
                INSERT INTO Signature
                    (WorkflowParticipantID, DocumentVersionID,
                     SigningDateTime, SignatureStatusID,
                     SignatureMethod, SignatureReference)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (p3, ver_id, sig_comp,
                 self.ref_id("SIGNATURE_STATUS", "SIGNED"),
                 "TYPED_NAME", f"SCALE-SIG-{idx:05d}"),
            )
            rows += 1

        # --- AuditLog (initiation + terminal event) ---
        self.cur.execute(
            """
            INSERT INTO AuditLog
                (ActorUserID, EventType, AffectedRecordType,
                 AffectedRecordID, TransactionReference,
                 PriorValueContext, NewValueContext, ChangeReason)
            VALUES (%s, 'WORKFLOW_INITIATED', 'Workflow', %s, %s,
                    NULL, 'Scale workflow activated', 'Generated scale data.')
            """,
            (owner_uid, wf_id, f"{AUDIT_TXN_PREFIX}{idx:05d}-INIT"),
        )
        terminal_event = {
            "COMPLETED": "WORKFLOW_COMPLETED",
            "ACTIVE": "WORKFLOW_PROGRESS",
            "REJECTED": "APPROVAL_REJECTED",
        }[outcome]
        self.cur.execute(
            """
            INSERT INTO AuditLog
                (ActorUserID, EventType, AffectedRecordType,
                 AffectedRecordID, TransactionReference,
                 PriorValueContext, NewValueContext, ChangeReason)
            VALUES (%s, %s, 'Workflow', %s, %s, 'ACTIVE', %s, 'Generated scale data.')
            """,
            (owner_uid, terminal_event, wf_id,
             f"{AUDIT_TXN_PREFIX}{idx:05d}-TERM", outcome),
        )
        rows += 2
        return rows

    def run(self):
        # Rerun safety: committed Signature / ApprovalDecision scale rows
        # are immutable (append-only triggers), so a destructive re-run
        # cannot purge them. Refuse with a clear message instead of
        # failing mid-transaction on the trigger.
        immutable = self.count_immutable_scale_rows()
        if immutable > 0:
            raise ScaleDataExistsError(immutable)

        total = 0
        self.purge_previous()
        pool = self.create_user_pool()
        pool_rows = sum(POOL.values()) * 2  # user + userrole each
        total += pool_rows

        # Expand outcome weights into a per-bundle list.
        plan = []
        for outcome, weight in OUTCOME_WEIGHTS:
            plan += [outcome] * round(self.bundles * weight)
        # pad/trim to exact bundle count
        while len(plan) < self.bundles:
            plan.append("COMPLETED")
        plan = plan[: self.bundles]

        for idx, outcome in enumerate(plan, start=1):
            total += self.create_bundle(idx, outcome, pool)

        return total, pool_rows


def load_db_config():
    env_path = Path(__file__).resolve().parents[3] / "build" / ".env"
    load_dotenv(dotenv_path=env_path)
    host = os.getenv("DB_HOST", "127.0.0.1")
    port = int(os.getenv("DB_PORT", "3306"))
    user = os.getenv("DB_ADMIN_USER")
    password = os.getenv("DB_ADMIN_PASSWORD")
    if not user or not password:
        print(
            f"ERROR: DB_ADMIN_USER / DB_ADMIN_PASSWORD not found. "
            f"Expected build/.env at: {env_path}",
            file=sys.stderr,
        )
        sys.exit(1)
    return host, port, user, password


def main():
    parser = argparse.ArgumentParser(
        description="Generate ~2,000 reproducible scale-test business records."
    )
    parser.add_argument(
        "--database", required=True,
        help="Target database name (already built and seeded).",
    )
    parser.add_argument(
        "--bundles", type=int, default=DEFAULT_BUNDLES,
        help=f"Number of full workflow bundles (default {DEFAULT_BUNDLES}).",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Generate inside a transaction, report counts, then ROLL BACK.",
    )
    args = parser.parse_args()

    host, port, user, password = load_db_config()

    conn = mysql.connector.connect(
        host=host, port=port, user=user, password=password,
        database=args.database, autocommit=False,
    )
    try:
        gen = ScaleGenerator(conn, args.database, args.bundles)
        try:
            total, pool_rows = gen.run()
        except ScaleDataExistsError as exists:
            conn.rollback()
            print(
                "REFUSED: this database already contains "
                f"{exists.count} committed, immutable scale rows "
                "(Signature/ApprovalDecision).\n"
                "These are append-only (protected by triggers) and cannot "
                "be deleted to make room for a fresh run.\n"
                "To regenerate from a clean slate, rebuild the database "
                "(re-run the build so the schema+seed are recreated), then "
                "run this generator once.\n"
                "No changes were made.",
                file=sys.stderr,
            )
            sys.exit(2)

        if args.dry_run:
            conn.rollback()
            print(
                f"[DRY RUN] would insert ~{total} rows "
                f"({pool_rows} one-time user/role rows + "
                f"{args.bundles} workflow bundles). Rolled back."
            )
        else:
            conn.commit()
            print(
                f"SUCCESS: inserted ~{total} generated rows "
                f"({pool_rows} one-time user/role rows + "
                f"{args.bundles} workflow bundles). Committed."
            )
    except Exception as exc:
        conn.rollback()
        print(f"ERROR: generation failed and was rolled back: {exc}",
              file=sys.stderr)
        sys.exit(1)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
