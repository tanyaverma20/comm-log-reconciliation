# Comm-Log Send Reconciliation

## 1. Objective

Finance reports a `target_base` of **22** for merchant 501, during October 2026, across Diwali campaigns. This repository reconciles that number from the supplied raw SQLite data. The purpose is not merely to reproduce 22, but to show why a straightforward count differs from Finance's reporting metric and to make each adjustment reproducible.

## Prerequisites

Use the SQLite command-line client with SQLite 3.25 or later (`ROW_NUMBER()` is used in the primary query). The supplied source data is included in [`data/`](data/): `comm_log.db` is the database used by the commands below, and the two CSV files are the corresponding raw extracts.

## 2. Dataset

The SQLite database contains two tables:

- `campaign` contains one row per campaign. Its `id` identifies the campaign, and `parent_id` links a retry campaign to the earlier campaign it re-attempts. `creation_status` and `processing_status` determine whether a campaign is eligible for official reporting.
- `communication_log` contains one row per individual send attempt. `communication_id` links the attempt to `campaign.id`; `customer_id` identifies the targeted customer; `sent_time` provides the reporting date; and `delivery_status` records the send outcome.

The scope used throughout is merchant 501, October 2026, communication type `'2'` (Campaign), and campaign names containing `Diwali`.

## 3. Business Definition

One qualifying `target_base` event is an in-scope send associated with a reporting-eligible campaign, treated according to its campaign structure:

- A campaign is eligible only when `creation_status` is one of `approved`, `aborted`, `resumed`, or `stopped`, **and** `processing_status = 'processed'`.
- A retry family consists of a root campaign plus every descendant connected through `parent_id`. Within an eligible retry family, a customer contributes once, even when multiple attempts occur across retry campaigns.
- A standalone campaign has no retry relationship. Each of its send rows remains a separate event, including repeated sends to the same customer.
- `delivery_status` is retained for audit, but is not itself a qualification filter. The documented rules define eligibility through campaign status and define retry treatment through campaign relationships.

## 4. Investigation Approach

The investigation began with the simplest reasonable count: all in-scope Diwali send attempts. Next, campaign records were checked for reporting eligibility, which exposed a processed but still approval-pending campaign. The remaining eligible campaigns were reconstructed into retry families to distinguish later attempts from new customer events. A separate check of the standalone campaign tested whether a repeated customer should be collapsed. Finally, a second SQL formulation aggregated at the campaign-family level to independently validate the result.

## 5. Reconciliation Bridge

| Step | Adjustment | Result | Change | Reason |
| --- | --- | ---: | ---: | --- |
| 0 | Naive in-scope send attempts | 30 | — | Starting point |
| 1 | Apply campaign reporting eligibility | 26 | -4 | Exclude campaign 9004 |
| 2 | Collapse repeated customers within eligible retry families | 22 | -4 | Four retry attempts represent existing customer events |
| Final | `target_base` | 22 | — | Reconciled result |

Campaign 9004 accounts for the first adjustment: it has four communication rows but is `approval_awaiting`, so it is not eligible for reporting. The second adjustment comprises three later attempts in the retry family rooted at 9001 and one later attempt in the retry family rooted at 9201.

## 6. Key Investigation Findings

The first eligible retry family is `9001 → 9002 → 9003`. Customer C2 appears in campaigns 9001 and 9002; C3 appears in all three campaigns. These are retries of the same underlying communication, so their later attempts do not add separate `target_base` events.

The second eligible retry family is `9201 → 9202`. Customer D1 is first attempted in 9201 and retried in 9202, producing one event rather than two. Campaign 9004 is another child of 9001, but it is `approval_awaiting` and therefore excluded before retry-family counting.

Campaign 9101 is standalone. Customer C20 appears twice in that campaign, in two distinct send rows on different dates, and both events count. A global `COUNT(DISTINCT customer_id)` is therefore wrong: it would collapse C20's legitimate standalone repeat and return 21 rather than 22.

## 7. SQL

The primary query is [reconciliation.sql](reconciliation.sql). It uses a recursive CTE to assign retry roots, applies campaign eligibility, and ranks customer attempts only within retry families.

```sh
sqlite3 data/comm_log.db < reconciliation.sql
```

The independent check is [validation.sql](validation.sql). It groups records at the campaign-family level and uses send attempts for standalone campaigns versus distinct customers for retry families.

```sh
sqlite3 data/comm_log.db < validation.sql
```

Both queries return `22`.

## 8. Validation

The primary query and the validation query reach 22 through different aggregation mechanics. The primary query allocates one contributing row to each customer within a retry family using `ROW_NUMBER()`. The validation query instead calculates each family's contribution after aggregation: all attempts for a standalone family, or distinct customers for a retry family. Their agreement provides an independent check that the result follows the stated campaign and retry rules rather than relying on a global distinct-customer count.

## 9. Supporting Analysis

- [Profiling queries](analysis/01_profiling.sql)
- [Intermediate reconciliation queries](analysis/02_reconciliation.sql)
- [Robustness and validation queries](analysis/03_validation.sql)
- [Row-level audit query](analysis/row_level_audit.sql)
- [Evidence-led reconciliation bridge](reconciliation_bridge.md)

## 10. Surprising / Non-obvious Data Observation

Repeated customers do not have a single universal treatment in this dataset. C2, C3, and D1 appear multiple times because campaigns were retried through `parent_id` relationships, so later attempts represent the same underlying communication. By contrast, C20 appears twice in standalone campaign 9101, where the README defines each send as its own event. That distinction is why retry-family customer deduplication is necessary, but global customer deduplication is incorrect.
