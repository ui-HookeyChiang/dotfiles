#!/usr/bin/env python3
"""Entry point for the py-edge fixture skill."""
from detectors import foo


def main() -> int:
    foo.detect()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
