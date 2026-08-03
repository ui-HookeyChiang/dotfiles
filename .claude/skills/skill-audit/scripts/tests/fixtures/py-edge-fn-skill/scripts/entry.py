#!/usr/bin/env python3
"""Entry point for the py-edge-fn fixture skill."""
from advisory import metrics as M
from model import Para


def main() -> int:
    p = Para([1, 2, 3])
    size = M.compute_size(p.tokens)
    p.summarize()
    if 2 in p:
        size += 1
    x = open("/dev/null")
    x.read()
    x.close()
    return size


if __name__ == "__main__":
    raise SystemExit(main())
