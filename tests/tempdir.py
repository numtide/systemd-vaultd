#!/usr/bin/env python3

import pytest
from tempfile import TemporaryDirectory
from pathlib import Path
from typing import Iterator


@pytest.fixture
def tempdir() -> Iterator[Path]:
    with TemporaryDirectory() as dir:
        yield Path(dir)
