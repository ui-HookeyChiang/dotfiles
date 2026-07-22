# Prevent pytest from collecting this fixture's test_*.py into the main suite.
# This dir is a reachability-graph fixture, not a test-suite member.
import sys
from pathlib import Path

# Ensure imports resolve against this fixture's scripts/, not the parent suite's.
_HERE = Path(__file__).resolve().parent
_SCRIPTS = _HERE.parent  # py-edge-skill/scripts/
s = str(_SCRIPTS)
if s not in sys.path:
    sys.path.insert(0, s)
