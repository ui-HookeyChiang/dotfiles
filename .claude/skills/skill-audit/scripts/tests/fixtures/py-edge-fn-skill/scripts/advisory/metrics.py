"""metrics — the first function is reached only through a module alias (live).
The second is defined but never called (genuinely dead)."""


def compute_size(rows: list) -> int:
    return len(rows)


def dead_fn() -> int:
    return 0
