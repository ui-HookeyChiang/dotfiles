"""mod — fixture module for the @property false-positive regression test."""
from dataclasses import dataclass
from typing import List


@dataclass
class Item:
    value: int

    @property
    def flag(self) -> bool:
        return self.value > 0

    @property
    def dead_prop(self) -> int:
        # a @property NEVER accessed anywhere in the corpus — must still be
        # (c). Guards against blanket @property suppression (ignoring
        # property_accessed()).
        return 0

    @property
    def prose_only_prop(self) -> int:
        # a @property mentioned ONLY in SKILL.md prose (`item.prose_only_prop`),
        # never accessed in any .py source. Must still be (c): a prose `obj.name`
        # mention is not a real edge. Guards the python-only scan (review H3).
        return 1


def process(items: List[Item]) -> List[Item]:
    result = []
    for obj in items:
        if obj.flag:
            result.append(obj)
    return result


def really_dead() -> None:
    pass


def shared() -> None:
    pass


def _trigger_unknown_local() -> None:
    x = object()
    x.shared  # noqa: B018
