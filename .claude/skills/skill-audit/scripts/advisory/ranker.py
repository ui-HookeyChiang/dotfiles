"""Advisory mode ranker — composite score and sorting."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class MetricInputs:
    size_score: float
    imbalance_score: float
    staleness_score: float
    navigability_score: float = 0.0


@dataclass
class RankedSkill:
    name: str
    composite: float
    size: float
    imbalance: float
    staleness: float
    navigability: float = 0.0


# Navigability added at 0.20; the prior three (.40/.40/.20) re-normalized ×0.8
# to .32/.32/.16 so the four still sum to 1.0.
WEIGHTS = {"size": 0.32, "imbalance": 0.32, "staleness": 0.16, "navigability": 0.20}


def composite_score(m: MetricInputs) -> float:
    """max(0.5 * weighted_sum, 0.9 * max_axis).

    Linear blend would mask single-axis extremes; max blend rescues them
    while the linear half keeps balanced scores from over-spiking.
    """
    weighted = (
        WEIGHTS["size"] * m.size_score
        + WEIGHTS["imbalance"] * m.imbalance_score
        + WEIGHTS["staleness"] * m.staleness_score
        + WEIGHTS["navigability"] * m.navigability_score
    )
    max_axis = max(
        m.size_score, m.imbalance_score, m.staleness_score, m.navigability_score
    )
    return max(0.5 * weighted, 0.9 * max_axis)


def rank_skills(skills: list[RankedSkill]) -> list[RankedSkill]:
    """Sort descending by composite. Stable on ties (preserves input order)."""
    return sorted(skills, key=lambda s: -s.composite)
