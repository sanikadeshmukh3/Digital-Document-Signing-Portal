from pathlib import Path
import hashlib


class DeploymentEngine:

    def __init__(
        self,
        database_manager,
        target_database: str,
        logger
    ):
        self.db = database_manager
        self.target_database = target_database
        self.logger = logger

    def calculate_checksum(self, script_path: Path):
        sha256 = hashlib.sha256()

        with open(script_path, "rb") as file:
            while True:
                chunk = file.read(8192)

                if not chunk:
                    break

                sha256.update(chunk)

        return sha256.hexdigest()


    def schema_migration_table_exists(self):
        self.db.connect(
            self.target_database
        )

        cursor = self.db.connection.cursor()

        cursor.execute(
            """
            SELECT COUNT(*)
            FROM information_schema.tables
            WHERE table_schema = %s
            AND table_name = 'SchemaMigration'
            AND table_type = 'BASE TABLE'
            """,
            (self.target_database,)
        )

        exists = (
            cursor.fetchone()[0] == 1
        )

        cursor.close()
        self.db.close()

        return exists


    def get_applied_migration(self, script_name: str):
        self.db.connect(
            self.target_database
        )

        cursor = self.db.connection.cursor()

        cursor.execute(
            """
            SELECT
                VersionNumber,
                ScriptChecksum
            FROM SchemaMigration
            WHERE ScriptName = %s
            """,
            (script_name,)
        )

        row = cursor.fetchone()

        cursor.close()
        self.db.close()

        return row


    def should_execute_migration(self, relative_path: str, script_path: Path):
        current_checksum = (
            self.calculate_checksum(
                script_path
            )
        )

        applied = (
            self.get_applied_migration(
                relative_path
            )
        )

        # Script has never been recorded.
        if applied is None:
            return True

        version_number = applied[0]
        recorded_checksum = applied[1]

        # Script already ran and has not changed.
        if (
            recorded_checksum
            == current_checksum
        ):
            self.logger.info(
                "Skipping previously applied "
                "migration | "
                f"version={version_number} | "
                f"script={relative_path}"
            )

            return False

        # Same migration name, different contents.
        raise RuntimeError(
            "Previously applied migration "
            "has been modified | "
            f"version={version_number} | "
            f"script={relative_path} | "
            f"recorded_checksum="
            f"{recorded_checksum} | "
            f"current_checksum="
            f"{current_checksum}"
        )

    def load_manifest(self, repo_dir: Path):
        manifest_path = (
            repo_dir
            / "database"
            / "manifest.txt"
        )

        if not manifest_path.exists():
            raise RuntimeError(
                "Missing database/manifest.txt"
            )

        scripts = []

        for raw_line in manifest_path.read_text(
            encoding="utf-8"
        ).splitlines():

            line = raw_line.strip()

            if not line:
                continue

            if line.startswith("#"):
                continue

            script_path = repo_dir / line

            if not script_path.exists():
                raise RuntimeError(
                    f"Manifest references missing file: {line}"
                )

            scripts.append(
                (line, script_path)
            )

        if not scripts:
            raise RuntimeError(
                "Manifest contains no SQL scripts."
            )

        return scripts

    def prepare_sql(self, sql: str):
        return sql.replace(
            "{{TARGET_DB}}",
            self.target_database
        )

    def split_sql_statements(self, sql: str):
        """
        Split MySQL SQL while honoring DELIMITER commands.

        Example:

            DELIMITER //

            CREATE PROCEDURE ...
            BEGIN
                ...
            END//

            DELIMITER ;
        """

        statements = []

        delimiter = ";"
        buffer = []

        for raw_line in sql.splitlines():
            stripped = raw_line.strip()

            if stripped.upper().startswith(
                "DELIMITER "
            ):
                new_delimiter = stripped.split(
                    None,
                    1
                )[1]

                delimiter = new_delimiter
                continue

            buffer.append(raw_line)

            combined = "\n".join(buffer).rstrip()

            if combined.endswith(delimiter):
                statement = combined[
                    :-len(delimiter)
                ].strip()

                if statement:
                    statements.append(statement)

                buffer = []

        remaining = "\n".join(buffer).strip()

        if remaining:
            statements.append(remaining)

        return statements

    def deploy_script(
        self,
        relative_path: str,
        script_path: Path,
        use_database: bool = True
    ):
        self.logger.info(
            f"Executing {relative_path}"
        )

        sql = script_path.read_text(
            encoding="utf-8"
        )

        sql = self.prepare_sql(sql)

        statements = self.split_sql_statements(
            sql
        )

        if use_database:
            database_name = self.target_database
        else:
            database_name = None

        try:
            for statement in statements:
                self.db.execute_statement(
                    statement,
                    database_name
                )

            self.db.commit()

        except Exception:
            self.db.rollback()
            raise

        finally:
            self.db.close()

        self.logger.info(
            f"Succeeded: {relative_path}"
        )



    def deploy_all(self, repo_dir):
        scripts = self.load_manifest(repo_dir)

        for relative_path, script_path in scripts:

            use_database = (
                relative_path
                != "database/00_create_database.sql"
            )

            # ------------------------------------------------
            # Database creation is deployment/bootstrap logic,
            # not a tracked schema migration.
            # ------------------------------------------------

            if (relative_path == "database/00_create_database.sql"):
                self.deploy_script(
                    relative_path,
                    script_path,
                    use_database=False
                )

                continue

            # ------------------------------------------------
            # Bootstrap migration tables.
            #
            # On a fresh database SchemaMigration does not
            # exist yet, so 005_versioning_tables.sql must run.
            #
            # On an existing versioned database, the table
            # already exists, so the bootstrap script should
            # not be executed again.
            # ------------------------------------------------

            if relative_path.endswith("005_versioning_tables.sql"):
                if (not self.schema_migration_table_exists()):
                    self.deploy_script(
                        relative_path,
                        script_path,
                        use_database=True
                    )
                else:
                    self.logger.info(
                        "Versioning tables already "
                        "exist; skipping bootstrap | "
                        f"script={relative_path}"
                    )

                continue

            # ------------------------------------------------
            # Validation scripts should always run.
            #
            # They validate the final database state and are
            # not schema migrations.
            # ------------------------------------------------

            if relative_path.startswith("database/05_validation/"):
                self.deploy_script(
                    relative_path,
                    script_path,
                    use_database=True
                )

                continue

            # ------------------------------------------------
            # Normal tracked schema/deployment scripts.
            # ------------------------------------------------

            if (self.schema_migration_table_exists()):
                should_execute = (
                    self.should_execute_migration(
                        relative_path,
                        script_path
                    )
                )

                if not should_execute:
                    continue



            self.deploy_script(
                relative_path,
                script_path,
                use_database=True
            )