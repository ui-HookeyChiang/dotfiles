#!/usr/bin/env python3
"""Entry point for the property-skill fixture."""
from mod import Item, process


def main() -> int:
    items = [Item(1), Item(0), Item(2)]
    live = process(items)
    return len(live)


if __name__ == "__main__":
    raise SystemExit(main())
