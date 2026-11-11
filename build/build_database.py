#!/usr/bin/env python3

import argparse
from asyncio.log import logger
import os
import re
import shutil
import sys
import hashlib
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv

from modules.build_logger import BuildLogger
from modules.github_manager import GitHubManager
from modules.database_manager import DatabaseManager
from modules.deployment_engine import DeploymentEngine


def parse_arguments():
    parser = argparse.ArgumentParser(
        description=(
            "Build the Document Workflow and "
            "E-Signing Portal database."
        )
    )

    parser.add_argument(
        "owner",
        help="GitHub repository owner"
    )

    parser.add_argument(
        "repository",
        help="GitHub repository name"
    )

    parser.add_argument(
        "version_tag",
        help="Exact Git tag such as v1.2.0"
    )

    parser.add_argument(
        "target_database",
        help="Target MySQL database name"
    )

    return parser.parse_args()


def require_environment(name):
    value = os.getenv(name)

    if not value:
        raise RuntimeError(
            f"Missing environment variable: {name}"
        )

    return value


def require_command(name):
    if shutil.which(name) is None:
        raise RuntimeError(
            f"Required command not found: {name}"
        )


def validate_database_name(name):
    if not re.fullmatch(
        r"[A-Za-z][A-Za-z0-9_]{0,63}",
        name
    ):
        raise RuntimeError(
            "Database name must start with a letter "
            "and contain only letters, numbers, "
            "and underscores."
        )


def record_database_build(db, target_database, schema_version, release_tag, commit_sha, mysql_version):
    db.connect(
        target_database
    )

    cursor = db.connection.cursor()

    cursor.execute(
        """
        INSERT INTO DatabaseBuild (
            SchemaVersion,
            ReleaseTag,
            CommitSHA,
            BuildStatus,
            BuildStartedDateTime,
            BuildCompletedDateTime,
            MySQLVersion
        )
        VALUES (
            %s,
            %s,
            %s,
            'COMPLETED',
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP,
            %s
        )
        """,
        (
            schema_version,
            release_tag,
            commit_sha,
            mysql_version
        )
    )

    build_id = cursor.lastrowid

    db.connection.commit()

    cursor.close()

    return build_id

def calculate_file_checksum(file_path):
    """
    Calculate the SHA-256 checksum of a SQL script.

    This lets us prove that an applied migration file has not
    been modified after it was recorded in SchemaMigration.
    """
    sha256 = hashlib.sha256()

    with open(file_path, "rb") as file:
        while True:
            chunk = file.read(8192)

            if not chunk:
                break

            sha256.update(chunk)

    return sha256.hexdigest()


def record_schema_migrations(db, repo_dir, scripts,build_id):
    cursor = db.connection.cursor()

    migration_number = 1

    for script_entry in scripts:

        if isinstance(
            script_entry,
            (tuple, list)
        ):
            relative_script = (
                script_entry[0]
            )
        else:
            relative_script = (
                script_entry
            )

        relative_script = str(
            relative_script
        )

        # Database creation and validation
        # are not schema migrations.
        if (
            relative_script
            == "database/00_create_database.sql"
            or relative_script.startswith(
                "database/05_validation/"
            )
        ):
            continue

        script_path = (
            repo_dir
            / relative_script
        )

        checksum = (
            calculate_file_checksum(
                script_path
            )
        )

        version_number = (
            f"{migration_number:03d}"
        )

        migration_name = (
            Path(
                relative_script
            ).stem
        )

        # --------------------------------------------
        # Check whether migration already exists
        # --------------------------------------------

        cursor.execute(
            """
            SELECT
                VersionNumber,
                ScriptChecksum
            FROM SchemaMigration
            WHERE ScriptName = %s
            """,
            (
                relative_script,
            )
        )

        existing = cursor.fetchone()

        if existing is not None:

            existing_version = (
                existing[0]
            )

            existing_checksum = (
                existing[1]
            )

            # Existing migration must remain unchanged.
            if (
                existing_checksum
                != checksum
            ):
                cursor.close()

                raise RuntimeError(
                    "Previously applied migration "
                    "has been modified | "
                    f"script={relative_script} | "
                    f"recorded_checksum="
                    f"{existing_checksum} | "
                    f"current_checksum="
                    f"{checksum}"
                )

            # Already applied and unchanged.
            # No new SchemaMigration row needed.
            migration_number += 1
            continue

        # --------------------------------------------
        # New migration
        # --------------------------------------------

        cursor.execute(
            """
            INSERT INTO SchemaMigration (
                VersionNumber,
                MigrationName,
                ScriptName,
                ScriptChecksum,
                BuildID
            )
            VALUES (%s, %s, %s, %s, %s)
            """,
            (
                version_number,
                migration_name,
                relative_script,
                checksum,
                build_id
            )
        )

        migration_number += 1

    db.connection.commit()

    cursor.close()

def main():
    args = parse_arguments()

    build_dir = Path(__file__).resolve().parent

    load_dotenv(
        build_dir / ".env"
    )

    timestamp = datetime.now(
        timezone.utc
    ).strftime("%Y%m%dT%H%M%SZ")

    run_id = (
        f"{timestamp}-{args.version_tag}"
    )

    work_root = Path(
        os.getenv(
            "WORK_ROOT",
            ".build-work"
        )
    ).resolve()

    work_dir = (
        work_root
        / f"{args.repository}-{run_id}"
    )

    repo_dir = work_dir / "repo"
    log_dir = work_dir / "logs"

    logger = BuildLogger(log_dir)

    try:
        logger.info(
            "Starting database build"
        )

        validate_database_name(
            args.target_database
        )

        # ----------------------------------------------------
        # Validate prerequisites
        # ----------------------------------------------------

        require_command("git")

        db_host = require_environment(
            "DB_HOST"
        )

        db_port = int(
            os.getenv(
                "DB_PORT",
                "3306"
            )
        )

        db_user = require_environment(
            "DB_ADMIN_USER"
        )

        db_password = require_environment(
            "DB_ADMIN_PASSWORD"
        )

        allow_recreate = (
            os.getenv(
                "ALLOW_DATABASE_RECREATE",
                "NO"
            ).upper()
            == "YES"
        )

        allow_upgrade = (
            os.getenv(
                "ALLOW_DATABASE_UPGRADE",
                "NO"
            ).upper()
            == "YES"
        )

        # ----------------------------------------------------
        # Test MySQL connection
        # ----------------------------------------------------

        db = DatabaseManager(
            host=db_host,
            port=db_port,
            user=db_user,
            password=db_password
        )

        mysql_version = (
            db.test_connection()
        )

        logger.info(
            f"Connected to MySQL "
            f"version={mysql_version}"
        )

        # ----------------------------------------------------
        # Retrieve exact Git release
        # ----------------------------------------------------

        github = GitHubManager(
            owner=args.owner,
            repository=args.repository,
            version_tag=args.version_tag,
            logger=logger
        )

        commit_sha = (
            github.clone_release(
                repo_dir
            )
            
        )

        schema_version_file = (
            repo_dir
            / "database"
            / "schema_version.txt"
        )

        if not schema_version_file.exists():
            raise RuntimeError(
                "Missing database/schema_version.txt"
            )

        schema_version = (
            schema_version_file
            .read_text(encoding="utf-8")
            .strip()
        )

        logger.info(
            f"Resolved schema version="
            f"{schema_version}"
        )

        # ----------------------------------------------------
        # Validate manifest BEFORE modifying database
        # ----------------------------------------------------

        deployment = DeploymentEngine(
            database_manager=db,
            target_database=(
                args.target_database
            ),
            logger=logger
        )

        scripts = deployment.load_manifest(
            repo_dir
        )

        logger.info(
            f"Manifest contains "
            f"{len(scripts)} SQL scripts"
        )

        # ----------------------------------------------------
        # Existing DB protection / upgrade mode
        # ----------------------------------------------------

        database_already_exists = db.database_exists(
            args.target_database
        )

        if database_already_exists:

            if allow_recreate:
                logger.info(
                    "Existing database found. "
                    "Recreation explicitly authorized."
                )

                db.drop_database(
                    args.target_database
                )

                database_already_exists = False

            elif allow_upgrade:
                logger.info(
                    "Existing database found. "
                    "Upgrade mode explicitly authorized. "
                    "Database will be preserved."
                )

            else:
                raise RuntimeError(
                    f"Database "
                    f"'{args.target_database}' "
                    "already exists. "
                    "Set ALLOW_DATABASE_UPGRADE=YES "
                    "to apply migrations without "
                    "recreating the database, or set "
                    "ALLOW_DATABASE_RECREATE=YES "
                    "for an intentional fresh rebuild."
                )


        # ----------------------------------------------------
        # Deploy SQL
        # ----------------------------------------------------

        deployment.deploy_all(
            repo_dir,
            existing_database=database_already_exists
        )

        # ----------------------------------------------------
        # Record successful database build/version
        # ----------------------------------------------------

        build_id = record_database_build(
            db=db,
            target_database=args.target_database,
            schema_version=schema_version,
            release_tag=args.version_tag,
            commit_sha=commit_sha,
            mysql_version=mysql_version
        )

        logger.info(
            "Database build version recorded | "
            f"build_id={build_id} | "
            f"schema_version={schema_version}"
        )

        #----------------------------------------------------
        # Record schema migration history
        #----------------------------------------------------

        record_schema_migrations(
            db=db,
            repo_dir=repo_dir,
            scripts=scripts,
            build_id=build_id
        )

        logger.info(
            "Schema migration history recorded | "
            f"build_id={build_id}"
        )

        # ----------------------------------------------------
        # Final validation summary
        # ----------------------------------------------------

        #db.connect(
         #   args.target_database
        #)

        cursor = db.connection.cursor()

        cursor.execute(
            """
            SELECT COUNT(*)
            FROM information_schema.tables
            WHERE table_schema = %s
              AND table_type = 'BASE TABLE'
            """,
            (args.target_database,)
        )

        table_count = cursor.fetchone()[0]

        cursor.execute(
            """
            SELECT COUNT(*)
            FROM information_schema.routines
            WHERE routine_schema = %s
            """,
            (args.target_database,)
        )

        routine_count = (
            cursor.fetchone()[0]
        )

        cursor.execute(
            """
            SELECT COUNT(*)
            FROM information_schema.triggers
            WHERE trigger_schema = %s
            """,
            (args.target_database,)
        )

        trigger_count = (
            cursor.fetchone()[0]
        )

        cursor.close()

        db.close()

        logger.info(
            "Build verification: "
            f"tables={table_count}, "
            f"routines={routine_count}, "
            f"triggers={trigger_count}"
        )

        logger.info(
            "BUILD SUCCEEDED | "
            f"build_id={build_id} | "
            f"schema_version={schema_version} | "
            f"tag={args.version_tag} | "
            f"commit={commit_sha} | "
            f"database={args.target_database}"
        )



        return 0

    except Exception as error:
        logger.error(
            f"BUILD FAILED: {error}"
        )

        return 1


if __name__ == "__main__":
    sys.exit(main())