import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import importlib.util
spec = importlib.util.spec_from_file_location(
    "skill_audit_mod",
    str(pathlib.Path(__file__).resolve().parents[1] / "skill-audit.py"))
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)


def test_rollup_error_wins():
    assert mod.rollup_exit([0, 2], any_error=True) == 1


def test_rollup_problem_when_any_zero():
    assert mod.rollup_exit([2, 0, 2], any_error=False) == 0


def test_rollup_clean_when_all_two():
    assert mod.rollup_exit([2, 2, 2], any_error=False) == 2

# test_aggregate_groups_by_engine removed in task-4: aggregate() deleted, report
# formatting now delegated to skill-audit/scripts/run.sh.
