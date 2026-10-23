from pathlib import Path


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

        try:
            for statement in statements:
                self.db.execute_statement(
                    statement,
                    self.target_database
                    if use_database else None
                )

            self.db.commit()

        except Exception:
            self.db.rollback()
            raise

        self.logger.info(
            f"Succeeded: {relative_path}"
        )

    def deploy_all(self, repo_dir: Path):
        scripts = self.load_manifest(
            repo_dir
        )

        for relative_path, script_path in scripts:
            self.deploy_script(
                relative_path,
                script_path,
                use_database=(relative_path != "database/01_schema/00_create_database.sql")
            )