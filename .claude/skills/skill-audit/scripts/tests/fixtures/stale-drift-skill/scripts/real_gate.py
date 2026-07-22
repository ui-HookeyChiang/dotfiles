"""A real, live mechanism the green case correctly documents."""


def enforce_base_branch(branch: str) -> bool:
    """Block merges to a protected branch. Referenced by SKILL.md green case."""
    return branch != "main"
