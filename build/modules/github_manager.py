import subprocess
from pathlib import Path


class GitHubManager:
    def __init__(
        self,
        owner: str,
        repository: str,
        version_tag: str,
        logger
    ):
        self.owner = owner
        self.repository = repository
        self.version_tag = version_tag
        self.logger = logger

    def _run(self, command):
        result = subprocess.run(
            command,
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            raise RuntimeError(
                result.stderr.strip()
                or result.stdout.strip()
            )

        return result.stdout.strip()

    def clone_release(self, repo_dir: Path):
        repo_url = (
            f"https://github.com/"
            f"{self.owner}/"
            f"{self.repository}.git"
        )

        self.logger.info(
            f"Cloning repository {self.owner}/{self.repository}"
        )

        self._run([
            "git",
            "clone",
            "--quiet",
            "--no-checkout",
            repo_url,
            str(repo_dir)
        ])

        self.logger.info(
            f"Fetching tag {self.version_tag}"
        )

        self._run([
            "git",
            "-C",
            str(repo_dir),
            "fetch",
            "--quiet",
            "--depth",
            "1",
            "origin",
            (
                f"refs/tags/{self.version_tag}:"
                f"refs/tags/{self.version_tag}"
            )
        ])

        self._run([
            "git",
            "-C",
            str(repo_dir),
            "checkout",
            "--quiet",
            "--detach",
            f"refs/tags/{self.version_tag}"
        ])

        resolved_tag = self._run([
            "git",
            "-C",
            str(repo_dir),
            "describe",
            "--exact-match",
            "--tags",
            "HEAD"
        ])

        commit_sha = self._run([
            "git",
            "-C",
            str(repo_dir),
            "rev-parse",
            "HEAD"
        ])

        if resolved_tag != self.version_tag:
            raise RuntimeError(
                f"Requested tag {self.version_tag}, "
                f"but resolved tag was {resolved_tag}."
            )

        self.logger.info(
            f"Verified tag={resolved_tag}; "
            f"commit={commit_sha}"
        )

        return commit_sha