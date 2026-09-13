# Comm-log reconciliation bridge

## Result

`target_base` is **22** for merchant 501, October 2026, across Diwali campaigns.

| Step | Treatment | Count | Change |
|---:|---|---:|---:|
| 0 | All in-scope Diwali `communication_log` send attempts | 30 | — |
| 1 | Keep only reporting-eligible campaigns | 26 | -4 |
| 2 | Treat customer repeats within retry families as one underlying communication | 22 | -4 |

## Step 0: all in-scope attempts

The reasonable first pass joins `communication_log` to `campaign` and filters merchant 501, October 2026, campaign type `'2'`, and Diwali campaign names. It counts one row per send attempt, yielding 30.

## Step 1: campaign reporting eligibility

README defines official reporting eligibility at the campaign level:

- `creation_status` must be one of `approved`, `aborted`, `resumed`, or `stopped`.
- `processing_status` must be `processed`.

Campaign 9004, `Diwali Cart Recovery - Retry C (pending)`, is `approval_awaiting` despite being `processed`. Its four communication rows, log IDs 14–17 for customers C11–C14, do not contribute. This changes 30 to 26.

## Step 2: retry-family treatment

The eligible family rooted at 9001 contains 9001 → 9002 → 9003. It has 13 attempts but 10 customer events:

- C2 appears in log IDs 2 and 3; the second attempt is not a new underlying communication.
- C3 appears in log IDs 4, 5, and 6; the two later attempts are not new underlying communications.
- C1 and C4–C10 appear once.

This family reduces by 3.

The eligible family rooted at 9201 contains 9201 → 9202. It has 6 attempts but 5 customer events:

- D1 appears in log IDs 25 and 26; the second is a retry.
- D2–D5 appear once.

This family reduces by 1.

Campaign 9101 is standalone: it has no parent and no child. It retains all 7 send events, including both successful C20 sends (log IDs 18 and 19, on different dates). README says repeated sends in a standalone campaign are separate events, not retries.

## Why not global `COUNT(DISTINCT customer_id)`?

A global customer-level distinct count would collapse the two legitimate standalone C20 sends and return 21. Distinct-customer treatment applies only inside a retry family; standalone campaigns count each log row as its own event.

## Delivery status

No query filters `delivery_status`. README describes `1100` as a soft failure that may be retried, but does not define a delivered-only eligibility rule. The failed first attempts for C2, C3, and D1 are represented in the retry-family audit and do not create additional target-base events.
