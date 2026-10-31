import json

import numpy as np
import pytest

from align_reference.fixtures import (
    FIXTURE_DIR,
    SCHEMA_VERSION,
    check_expected,
    fixture_paths,
    load_fixture,
    reference_block,
    replay,
)
from align_reference.generator import SCENARIOS, synthesize

PATHS = fixture_paths()
REQUIRED = set(SCENARIOS)


def test_all_required_fixtures_exist():
    assert {p.stem for p in PATHS} == REQUIRED


def test_fixture_total_size_is_small():
    total = sum(p.stat().st_size for p in PATHS)
    assert total < 1.25 * 1024 * 1024


@pytest.mark.parametrize("path", PATHS, ids=lambda p: p.stem)
def test_fixture_schema(path):
    fx = load_fixture(path)
    assert fx["schemaVersion"] == SCHEMA_VERSION
    assert fx["name"] == path.stem
    assert fx["sampleRateHz"] > 0
    ts = [s["t"] for s in fx["samples"]]
    assert all(b > a for a, b in zip(ts, ts[1:]))
    for s in fx["samples"][:50]:
        assert len(s["q"]) == 4 and len(s["g"]) == 3
    for key in ("calibrationOutcomes", "reminders", "episodes", "finalState", "tolerances"):
        assert key in fx["expected"]


@pytest.mark.parametrize("path", PATHS, ids=lambda p: p.stem)
def test_fixture_expected_outcomes(path):
    fx = load_fixture(path)
    errors = check_expected(fx, replay(fx))
    assert errors == []


@pytest.mark.parametrize("path", PATHS, ids=lambda p: p.stem)
def test_fixture_reference_is_current(path):
    """The stored `reference` (used by Swift for parity) equals the current Python output."""
    fx = load_fixture(path)
    assert json.loads(json.dumps(reference_block(replay(fx)))) == fx["reference"]


@pytest.mark.parametrize("name", sorted(REQUIRED))
def test_generator_is_deterministic(name):
    fx = load_fixture(FIXTURE_DIR / f"{name}.json")
    if fx["generator"]["numpy"] != np.__version__:
        pytest.skip("fixtures were generated with a different numpy version")
    regenerated, _ = synthesize(SCENARIOS[name]())
    regenerated = json.loads(json.dumps(regenerated))
    assert regenerated["samples"] == fx["samples"]
    assert regenerated["expected"] == fx["expected"]
