import pytest
from pathlib import Path
from advisory.metrics import compute_size, compute_imbalance

FIXTURES = Path(__file__).parent / "fixtures" / "boundary"


def test_empty_no_crash():
    p = FIXTURES / "empty.md"
    s = compute_size(p)
    i = compute_imbalance(p, None)
    assert s.fenced_blocks == 0
    assert i.substantive_blocks == 0


def test_no_fence_zero_count():
    p = FIXTURES / "no-fence.md"
    s = compute_size(p)
    i = compute_imbalance(p, None)
    assert s.fenced_blocks == 0
    assert i.substantive_blocks == 0


def test_single_line_below_threshold():
    p = FIXTURES / "single-line.md"
    s = compute_size(p)
    i = compute_imbalance(p, None)
    assert s.fenced_blocks == 1
    assert i.substantive_blocks == 0  # 1 line < threshold 3


def test_unclosed_fence_no_crash():
    p = FIXTURES / "unclosed-fence.md"
    s = compute_size(p)
    i = compute_imbalance(p, None)
    # The parser must not raise; the unclosed block is silently dropped
    # from the substantive count because it never reaches the close branch.
    assert s.fenced_blocks == 1  # opener was counted
    assert i.substantive_blocks == 0


def test_frontmatter_fence_ignored():
    p = FIXTURES / "frontmatter-fence.md"
    s = compute_size(p)
    i = compute_imbalance(p, None)
    # The ``` inside YAML is now skipped via _strip_frontmatter.
    assert s.fenced_blocks == 0
    assert i.substantive_blocks == 0
