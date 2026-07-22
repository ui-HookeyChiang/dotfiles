"""reader — defines a module-level function that NO in-skill alias calls. The
only matching attribute site in the skill is on a stdlib file object
(`x = open(...)`), an unresolved qualifier, so it must stay (c) — collision guard."""


def read() -> str:
    return ""
