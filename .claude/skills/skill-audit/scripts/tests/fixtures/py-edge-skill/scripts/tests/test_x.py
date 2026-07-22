"""Test that imports test_helper only — no non-test importer."""
from detectors import test_helper


def test_helper_returns_42():
    assert test_helper.helper() == 42
