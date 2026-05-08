# Baseline Performance Report (2026-02-13)

Environment: `development`  
Method: synthetic dataset seeding + repeatable Rails benchmark task (`performance:capture_baseline`)  
Benchmark runs: `7` per scenario (`1` warmup)

## Dataset Snapshots

- 5k run: `supporters_active_count=5008`
- 10k run: `supporters_active_count=10008`
- 30k run: `supporters_active_count=30008`

## Timing + Query Baseline

### 5k dataset

| Scenario | p50 (ms) | p95 (ms) | avg SQL queries |
|---|---:|---:|---:|
| supporters_index_default | 5.20 | 5.66 | 3.0 |
| supporters_index_filtered_search | 5.77 | 10.81 | 4.0 |
| dashboard_show_payload | 11.33 | 22.07 | 7.0 |
| war_room_index_payload | 35.90 | 41.86 | 42.0 |
| poll_watcher_index_payload | 3.77 | 6.87 | 3.0 |

### 10k dataset

| Scenario | p50 (ms) | p95 (ms) | avg SQL queries |
|---|---:|---:|---:|
| supporters_index_default | 6.55 | 7.27 | 3.0 |
| supporters_index_filtered_search | 8.98 | 14.19 | 4.0 |
| dashboard_show_payload | 18.20 | 38.69 | 7.0 |
| war_room_index_payload | 39.44 | 71.35 | 42.0 |
| poll_watcher_index_payload | 3.76 | 5.25 | 3.0 |

### 30k dataset

| Scenario | p50 (ms) | p95 (ms) | avg SQL queries |
|---|---:|---:|---:|
| supporters_index_default | 12.37 | 14.19 | 3.0 |
| supporters_index_filtered_search | 14.06 | 18.96 | 4.0 |
| dashboard_show_payload | 16.95 | 22.26 | 7.0 |
| war_room_index_payload | 44.52 | 54.03 | 42.0 |
| poll_watcher_index_payload | 4.34 | 7.01 | 3.0 |

## Raw JSON Reports

- `docs/performance/baseline-20260213-165539.json`
- `docs/performance/baseline-20260213-165549.json`
- `docs/performance/baseline-20260213-165604.json`
- `docs/performance/baseline-latest.json`

## Notes

- `war_room_index_payload` has the highest query count and remains the first optimization target for `11.3`.
- Poll report volume is currently low (`poll_reports_today_count=0`), so election-day heavy-write/load conditions still need a separate targeted run.
- UI interaction latency should be captured with the manual checklist below and attached to this baseline.

## 11.3 Early Optimization Snapshot (2026-02-13)

Optimization applied:

- Refactored `war_room` payload aggregation to precompute precinct/supporter metrics in bulk (removed per-village count/sum queries).
- Added supporter indexes:
  - `[:status, :village_id]`
  - `[:status, :village_id, :motorcade_available]`

30k dataset comparison (`before` vs `after`):

| Scenario | Metric | Before | After |
|---|---|---:|---:|
| war_room_index_payload | p50 (ms) | 44.52 | 7.88 |
| war_room_index_payload | p95 (ms) | 54.03 | 8.84 |
| war_room_index_payload | avg SQL queries | 42.0 | 5.0 |

Compared files:

- Before: `docs/performance/baseline-20260213-165604.json`
- After: `docs/performance/baseline-20260213-170308.json`

## 11.3 Second Optimization Snapshot (2026-02-13)

Optimization applied:

- Reduced dashboard aggregate work by reusing preloaded village totals instead of extra `SUM/COUNT` queries.
- Added supporter list/sort indexes:
  - `supporters(created_at)`
  - `supporters(village_id, created_at)`
  - `supporters(precinct_id, created_at)`

30k dataset comparison (`before second pass` vs `after second pass`):

| Scenario | Metric | Before | After |
|---|---|---:|---:|
| supporters_index_default | p50 (ms) | 10.69 | 5.47 |
| dashboard_show_payload | p50 (ms) | 18.62 | 12.59 |
| war_room_index_payload | p50 (ms) | 7.88 | 4.05 |

Compared files:

- Before: `docs/performance/baseline-20260213-170308.json`
- After: `docs/performance/baseline-20260213-170506.json`

Note:

- `supporters_index_filtered_search` showed volatile p95 in this sample window (single high outlier). This path remains a candidate for follow-up in `11.3` (possibly trigram index/search strategy).

## 11.3 Third Optimization Snapshot (2026-02-13)

Optimization applied:

- Added trigram-backed search indexes:
  - `GIN (LOWER(print_name) gin_trgm_ops)`
  - `GIN (contact_number gin_trgm_ops)`
- Updated supporter search predicate to:
  - lowercase name match
  - digit-normalized phone match (`regexp_replace(contact_number, '\\D', '', 'g')`)

30k dataset comparison (`before third pass` vs `after third pass`):

| Scenario | Metric | Before | After |
|---|---|---:|---:|
| supporters_index_filtered_search | p50 (ms) | 11.34 | 9.28 |
| supporters_index_filtered_search | p95 (ms) | 42.44 | 14.84 |
| supporters_index_default | p50 (ms) | 5.47 | 5.02 |

Compared files:

- Before: `docs/performance/baseline-20260213-170506.json`
- After: `docs/performance/baseline-20260213-170652.json`

Note:

- Non-search scenarios show run-to-run variance in development environment; search-path improvement is the primary validated outcome of this pass.

## Election-Day Load Check (Poll Reports Seeded)

Load setup:

- Seeded synthetic same-day poll reports:
  - `RESET_TODAY=true bundle exec rails "data:seed_synthetic_poll_reports[8]"`
  - Result: `472` poll reports today (`59 precincts * 8`)
- Added index:
  - `poll_reports(reported_at)` to support `today` and `last_hour` range scans.

Primary post-load benchmark (first run after seeding):

- File: `docs/performance/baseline-20260213-170925.json`
- Key values:
  - `war_room_index_payload`: p50 `12.31ms`, p95 `25.26ms`, avg SQL `7.0`
  - `poll_watcher_index_payload`: p50 `6.32ms`, p95 `9.32ms`, avg SQL `3.0`

Stability note:

- Additional repeated runs in dev (`170929`, `170939`) showed heavy timing variance unrelated to SQL query counts, indicating local environment contention/noise.
- For hard sign-off thresholds, re-run this same benchmark harness in an isolated/staging environment.
- Staging run checklist + one-command helper:
  - Checklist: `docs/performance/staging-benchmark-checklist.md`
  - Script: `api/bin/performance_staging_run`

## Manual UI Latency Checklist (delegated QA)

Use browser devtools Performance tab and record interaction-to-paint timing:

1. `/admin/supporters` search keystroke response time (20+ character query).
2. `/admin/supporters` filter + sort toggle latency.
3. `/admin` dashboard first render latency after hard refresh.
4. `/admin/war-room` initial card grid render + refresh cycle.
5. `/admin/poll-watcher` village filter + precinct list update latency.

Capture median + worst case for each and append to this report.
