#!/usr/bin/env python3

from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Iterator

import pytest


@pytest.fixture
def tempdir() -> Iterator[Path]:
    with TemporaryDirectory() as dir:
        yield Path(dir)
