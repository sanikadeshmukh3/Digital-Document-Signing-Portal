import mysql.connector


class DatabaseManager:
    def __init__(
        self,
        host: str,
        port: int,
        user: str,
        password: str
    ):
        self.config = {
            "host": host,
            "port": port,
            "user": user,
            "password": password
        }

        self.connection = None
        self.current_database = None


    def connect(self, database=None):
        """
        Open a fresh MySQL connection.

        If an existing connection is open for a different database,
        close it first.
        """

        self.close()

        config = self.config.copy()

        if database:
            config["database"] = database

        self.connection = mysql.connector.connect(
            **config
        )

        self.current_database = database

        return self.connection


    def close(self):
        """
        Close and completely discard the current connection.
        """

        if self.connection is not None:
            try:
                if self.connection.is_connected():
                    self.connection.close()
            finally:
                self.connection = None
                self.current_database = None


    def test_connection(self):
        """
        Test server-level connectivity without selecting a database.
        """

        self.connect()

        cursor = self.connection.cursor()

        try:
            cursor.execute("SELECT VERSION();")
            version = cursor.fetchone()[0]
        finally:
            cursor.close()
            self.close()

        return version


    def database_exists(self, database_name: str):
        """
        Check whether a database already exists.
        """

        self.connect()

        cursor = self.connection.cursor()

        try:
            cursor.execute(
                """
                SELECT COUNT(*)
                FROM information_schema.schemata
                WHERE schema_name = %s
                """,
                (database_name,)
            )

            exists = cursor.fetchone()[0] > 0

        finally:
            cursor.close()
            self.close()

        return exists


    def drop_database(self, database_name: str):
        """
        Drop the target database using a server-level connection.
        """

        self.connect()

        cursor = self.connection.cursor()

        try:
            cursor.execute(
                f"DROP DATABASE `{database_name}`"
            )

            self.connection.commit()

        finally:
            cursor.close()
            self.close()


    def execute_statement(
        self,
        statement: str,
        database_name=None
    ):
        """
        Execute one SQL statement.

        Reconnect automatically when the requested database differs
        from the database associated with the current connection.
        """

        connection_invalid = (
            self.connection is None
            or not self.connection.is_connected()
            or self.current_database != database_name
        )

        if connection_invalid:
            self.connect(database_name)

        cursor = self.connection.cursor()

        try:
            cursor.execute(statement)

            if cursor.with_rows:
                rows = cursor.fetchall()

                for row in rows:
                    print(row)

            while cursor.nextset():
                if cursor.with_rows:
                    cursor.fetchall()

                    for row in rows:
                        print(row)

        finally:
            cursor.close()


    def commit(self):
        if (
            self.connection is not None
            and self.connection.is_connected()
        ):
            self.connection.commit()


    def rollback(self):
        if (
            self.connection is not None
            and self.connection.is_connected()
        ):
            self.connection.rollback()