import subprocess

from dataclasses import dataclass
from command import Command, run
from pathlib import Path
import time

import string
import random


def rand_word(n: int) -> str:
    return "".join(random.choices(string.ascii_uppercase + string.digits, k=n))


@dataclass
class Service:
    name: str
    secret_name: str
    secret_path: Path


def random_service(secrets_dir: Path) -> Service:
    service = f"test-service-{rand_word(8)}.service"
    secret_name = "foo"
    secret = f"{service}-{secret_name}"
    secret_path = secrets_dir / secret
    return Service(service, secret_name, secret_path)


def test_socket_activation(
    systemd_vault: Path, command: Command, tempdir: Path
) -> None:
    secrets_dir = tempdir / "secrets"
    secrets_dir.mkdir()
    sock = tempdir / "sock"

    command.run(["systemd-socket-activate", "--listen", str(sock), str(systemd_vault), "-secrets", str(secrets_dir), "-sock", str(sock)])

    while not sock.exists():
        time.sleep(0.1)

    service = random_service(secrets_dir)
    service.secret_path.write_text("foo")

    # should not block
    out = run(
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
    assert out.stdout == "foo"
    assert out.returncode == 0


def test_blocking_secret(systemd_vault: Path, command: Command, tempdir: Path) -> None:
    secrets_dir = tempdir / "secrets"
    sock = tempdir / "sock"
    command.run([str(systemd_vault), "-secrets", str(secrets_dir), "-sock", str(sock)])

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
    service.secret_path.write_text("foo")
    assert proc.stdout is not None and proc.stdout.read() == "foo"
    assert proc.wait() == 0
