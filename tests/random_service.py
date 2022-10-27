#!/usr/bin/env python3

import random
import string
import json
from dataclasses import dataclass
from pathlib import Path


def rand_word(n: int) -> str:
    return "".join(random.choices(string.ascii_uppercase + string.digits, k=n))


@dataclass
class Service:
    name: str
    secret_name: str
    secret_path: Path

    def write_secret(self, val: str) -> None:
        tmp = self.secret_path.with_name(self.secret_path.name + ".tmp")
        tmp.write_text(json.dumps({self.secret_name: val}))
        tmp.rename(self.secret_path)


def random_service(secrets_dir: Path) -> Service:
    service = f"test-service-{rand_word(8)}.service"
    secret_name = "foo"
    secret = f"{service}.json"
    secret_path = secrets_dir / secret
    return Service(service, secret_name, secret_path)
