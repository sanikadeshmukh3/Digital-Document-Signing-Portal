import mysql.connector
from mysql.connector import Error


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

    def connect(self, database=None):
        config = self.config.copy()

        if database:
            config["database"] = database

        self.connection = mysql.connector.connect(
            **config
        )

        return self.connection

    def close(self):
        if (
            self.connection
            and self.connection.is_connected()
        ):
            self.connection.close()

    def test_connection(self):
        self.connect()

        cursor = self.connection.cursor()
        cursor.execute("SELECT VERSION();")

        version = cursor.fetchone()[0]

        cursor.close()
        self.close()

        return version

    def database_exists(self, database_name: str):
        self.connect()

        cursor = self.connection.cursor()

        cursor.execute(
            """
            SELECT COUNT(*)
            FROM information_schema.schemata
            WHERE schema_name = %s
            """,
            (database_name,)
        )

        exists = cursor.fetchone()[0] > 0

        cursor.close()
        self.close()

        return exists

    def create_database(self, database_name: str):
        self.connect()

        cursor = self.connection.cursor()

        cursor.execute(
            f"""
            CREATE DATABASE `{database_name}`
            CHARACTER SET utf8mb4
            COLLATE utf8mb4_0900_ai_ci
            """
        )

        cursor.close()
        self.close()

    def drop_database(self, database_name: str):
        self.connect()

        cursor = self.connection.cursor()

        cursor.execute(
            f"DROP DATABASE `{database_name}`"
        )

        cursor.close()
        self.close()

    def execute_statement(
        self,
        statement: str,
        database_name=None
    ):
        if (
            self.connection is None
            or not self.connection.is_connected()
        ):
            self.connect(database_name)

        cursor = self.connection.cursor()

        try:
            cursor.execute(statement)

        finally:
            cursor.close()

    def commit(self):
        if self.connection:
            self.connection.commit()

    def rollback(self):
        if self.connection:
            self.connection.rollback()