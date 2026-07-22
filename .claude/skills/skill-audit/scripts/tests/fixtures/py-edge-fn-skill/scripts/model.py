"""model — a class exercising self-qualified method/property edges, a dunder
invoked implicitly, an unused property, and a non-dunder dead method."""


class Para:
    def __init__(self, tokens: list) -> None:
        self.tokens = tokens

    @property
    def is_candidate(self) -> bool:
        return len(self.tokens) > 0

    @property
    def never_used(self) -> bool:
        return False

    def bump(self, n: int) -> None:
        self.tokens.append(n)

    def dead_method(self) -> None:
        return None

    def summarize(self) -> bool:
        if self.is_candidate:
            self.bump(1)
        return self.is_candidate

    def __contains__(self, item: object) -> bool:
        return item in self.tokens
