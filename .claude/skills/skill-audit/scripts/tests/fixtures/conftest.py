# This conftest exists to prevent pytest from auto-inserting fixture
# subdirectory paths into sys.path when collecting test_*.py fixture files.
# Fixture test files (e.g. py-edge-skill/scripts/tests/test_x.py) are
# reachability-graph fixture data, not test-suite members.
collect_ignore_glob = ["**/test_*.py"]
