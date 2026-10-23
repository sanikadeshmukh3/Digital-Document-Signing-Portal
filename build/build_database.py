#!/usr/bin/env python3

import argparse
import os
import re
import shutil
import sys
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
        help="Exact Git tag such as v1.0.0"
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
        # Existing DB protection
        # ----------------------------------------------------

        if db.database_exists(
            args.target_database
        ):
            if not allow_recreate:
                raise RuntimeError(
                    f"Database "
                    f"'{args.target_database}' "
                    "already exists. "
                    "Set "
                    "ALLOW_DATABASE_RECREATE=YES "
                    "only for intentional rebuilds."
                )

            logger.info(
                "Existing database found. "
                "Recreation explicitly authorized."
            )

            db.drop_database(
                args.target_database
            )

        # ----------------------------------------------------
        # Create database
        # ----------------------------------------------------

        db.create_database(
            args.target_database
        )

        logger.info(
            f"Created database "
            f"{args.target_database}"
        )

        # ----------------------------------------------------
        # Deploy SQL
        # ----------------------------------------------------

        deployment.deploy_all(
            repo_dir
        )

        # ----------------------------------------------------
        # Final validation summary
        # ----------------------------------------------------

        db.connect(
            args.target_database
        )

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