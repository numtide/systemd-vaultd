#!/usr/bin/env python3

import random
import string
from dataclasses import dataclass
from pathlib import Path


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
