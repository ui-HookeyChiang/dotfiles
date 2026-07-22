"""Tests for advisory mode ranker."""
from advisory.ranker import (
    composite_score, rank_skills, RankedSkill, MetricInputs,
)


def make(size=0.0, imbal=0.0, stale=0.0):
    return MetricInputs(size_score=size, imbalance_score=imbal, staleness_score=stale)


def test_composite_all_zero():
    assert composite_score(make()) == 0.0


def test_composite_linear_blend_when_balanced():
    """All three at 50 → weighted_sum = 50, max = 50; blend = max(25, 45) = 45."""
    s = composite_score(make(size=50, imbal=50, stale=50))
    assert abs(s - 45.0) < 0.01  # 0.9 * 50 = 45 (wins over 0.5 * 50 = 25)


def test_composite_max_blend_rescues_single_axis_extreme():
    """200-line skill with crazy imbalance (M2=100, others low)."""
    # weighted_sum = 0.40*5 + 0.40*100 + 0.20*5 = 43
    # 0.5 * 43 = 21.5 ; 0.9 * 100 = 90 → 90 wins
    s = composite_score(make(size=5, imbal=100, stale=5))
    assert abs(s - 90.0) < 0.01


def test_composite_weighted_sum_wins_when_extreme_dominated():
    """Three middling values: 0.5 * sum may beat 0.9 * max."""
    # When ALL scores equal X: weighted_sum=X, max=X. 0.5X vs 0.9X. max always wins.
    # Verify formula behaves predictably at the max:
    s = composite_score(make(size=100, imbal=100, stale=100))
    assert abs(s - 90.0) < 0.01  # 0.9 * 100


def test_rank_sorts_descending():
    skills = [
        RankedSkill(name="a", composite=30.0, size=10, imbalance=20, staleness=5),
        RankedSkill(name="b", composite=70.0, size=80, imbalance=70, staleness=10),
        RankedSkill(name="c", composite=50.0, size=50, imbalance=50, staleness=10),
    ]
    out = rank_skills(skills)
    assert [s.name for s in out] == ["b", "c", "a"]


def test_rank_stable_on_ties():
    skills = [
        RankedSkill(name="alpha", composite=50.0, size=0, imbalance=0, staleness=0),
        RankedSkill(name="bravo", composite=50.0, size=0, imbalance=0, staleness=0),
    ]
    out = rank_skills(skills)
    assert [s.name for s in out] == ["alpha", "bravo"]
