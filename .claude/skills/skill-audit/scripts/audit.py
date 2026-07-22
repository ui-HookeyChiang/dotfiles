# Compat shim — DO NOT add logic here. The syntax-engine module was renamed
# audit.py -> syntax_audit.py during the task-6 engine relocation, but the
# relocated tests still import it as `audit`. Re-export the full public surface
# (wildcard, not a name list, so a new test import never silently breaks).
from syntax_audit import *  # noqa: F401, F403
