import logging
from pathlib import Path


class BuildLogger:
    def __init__(self, log_dir: Path):
        log_dir.mkdir(parents=True, exist_ok=True)

        self.build_log = log_dir / "build.log"
        self.error_log = log_dir / "error.log"

        self.logger = logging.getLogger("database-build")
        self.logger.setLevel(logging.INFO)

        if self.logger.handlers:
            return

        formatter = logging.Formatter(
            "%(asctime)s | %(levelname)s | %(message)s"
        )

        build_handler = logging.FileHandler(self.build_log)
        build_handler.setFormatter(formatter)

        console_handler = logging.StreamHandler()
        console_handler.setFormatter(formatter)

        self.logger.addHandler(build_handler)
        self.logger.addHandler(console_handler)

    def info(self, message: str):
        self.logger.info(message)

    def error(self, message: str):
        self.logger.error(message)

        with open(self.error_log, "a", encoding="utf-8") as f:
            f.write(message + "\n")