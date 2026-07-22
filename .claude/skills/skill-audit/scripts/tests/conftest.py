import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parents[1]  # skill-audit/scripts/

# Insert scripts/ so all three import styles resolve correctly:
#   from advisory.X import ...      (syntax tests)
#   from detectors import ...       (semantic tests)
#   import reachability             (deadcode tests)
#   import syntax_audit / semantic_audit
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))
