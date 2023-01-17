import subprocess
import time
from pathlib import Path

from command import Command
from random_service import random_service


def test_blocking_secret(systemd_vaultd: Path, command: Command, tempdir: Path) -> None:
    secrets_dir = tempdir / "secrets"
    sock = tempdir / "sock"
    command.run([str(systemd_vaultd), "-secrets", str(secrets_dir), "-sock", str(sock)])

    while not sock.exists():
        time.sleep(0.1)

    service = random_service(secrets_dir)

    proc = command.run(
        [
            "systemd-run",
            "-u",
            service.name,
            "--collect",
            "--user",
            "-p",
            f"LoadCredential={service.secret_name}:{sock}",
            "--wait",
            "--pipe",
            "cat",
            "${CREDENTIALS_DIRECTORY}/" + service.secret_name,
        ],
        stdout=subprocess.PIPE,
    )
    time.sleep(0.1)
    assert proc.poll() is None, "service should block for secret"
    service.write_secret("foo")
    assert proc.stdout is not None and proc.stdout.read() == "foo"
    assert proc.wait() == 0
