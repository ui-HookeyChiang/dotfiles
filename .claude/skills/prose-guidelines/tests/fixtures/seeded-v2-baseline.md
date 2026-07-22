# Seeded v2 baseline — prose-guidelines detection fixture

Our backend service handles user requests through two main subsystems running on the same cluster. The new caching layer might reduce database load by half once the rollout finishes next quarter. We will publish numbers afterward.

## Section A — lexical cases

We leverage the cache to facilitate faster reads across the entire production cluster. The team chose various backends over the years to keep operations flexible during outages. Other teams also benefit from this pipeline daily.

在 開始 rollout 之前 我們 進行 一份 完整 的 performance benchmark 並 在 lab 環境 收集 metric 與 trace 資料。 之後 團隊 會 做出 決策 是否 將 此 cache layer 推 到 production cluster。 基本上 staging 環境 已 跑 過 兩 週 並 通過 大部分 regression test 用例。

The migration script handles every edge case we have seen so far. Running it under canary load is really straightforward once the secrets are wired in. The on-call team simply checks the exit code afterward.

## Section B — meta cases

This section describes the way the new cache layer fits into our existing request pipeline. The flow has three stages and each stage reports its own metric to Prometheus for downstream alerting. Operators can also inspect each stage via the admin dashboard.

本文 將 介紹 新 的 backup pipeline 與 既 有 batch job 之間 的 整合 方式。 整 套 流程 會 在 每 晚 兩 點 觸發 並 寫 入 archive bucket。 之後 由 dashboard 顯示 結果。

## TL;DR

The new gateway probably scales beyond the current 10x baseline without further tuning across all data-center regions. Internal load tests show p99 latency below 12 ms at 5x baseline load. Public docs will land before launch.

## Section C — negatives (must NOT flag)

The new index service leverages a 10k-entry LRU cache to serve hot keys without database round-trips. Bench numbers show 4 ms median lookup at peak load. We added Prometheus counters for cache hit ratio.

### Snippet

```python
def compute(values):
    # essentially the same algorithm as v1
    return sum(values) / len(values)
```

## Relevant references

Older designs influenced our cache shape, and the LFU paper from 2019 is probably the closest match. The team can also read prior incident postmortems for more historical context. These docs are linked from the wiki.

## Risks

The new cache might break under stale-key conditions if Redis is partitioned between regions. We also worry that traffic spikes could probably tip the failover threshold during peak hours. Mitigation work is tracked in the sibling spec.

## Section D — hard-token survival

The retry handler basically performs 3 retries on ETIMEDOUT via the /refresh endpoint, but does not retry on ECONNREFUSED, as documented in validate-findings.sh.

## Section E — just intensifier

The deploy script just rotates the Bearer JWT every 15-minute window so operators do not need to touch the secret store during a routine canary rollout afterward.

## Section F — meta then fact

This section describes the alert routing flow. The pipeline runs 3 retries on ETIMEDOUT before paging the on-call operator through PagerDuty.
