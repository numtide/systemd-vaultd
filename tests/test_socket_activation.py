#!/usr/bin/env python3

import time
import subprocess
from pathlib import Path

from command import Command, run
from random_service import random_service

def test_socket_activation(
        systemd_vaultd: Path, command: Command, tempdir: Path,
) -> None:
    secrets_dir = tempdir / "secrets"
    secrets_dir.mkdir()
    sock = tempdir / "sock"

    command.run(
        [
            "systemd-socket-activate",
            "--listen",
            str(sock),
            str(systemd_vaultd),
            "-secrets",
            str(secrets_dir),
            "-sock",
            str(sock),
        ]
    )

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
