-- Primary reconciliation query.
-- Run with: sqlite3 data/comm_log.db < reconciliation.sql
-- The metric is not filtered by delivery_status: README defines campaign
-- eligibility and retry/standalone treatment, but no delivered-only rule.

WITH RECURSIVE campaign_tree AS (
    -- Start one retry family at every campaign with no parent.
    SELECT
        id,
        parent_id,
        id AS retry_root
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    -- Carry the same root through retry chains of any depth.
    SELECT
        child.id,
        child.parent_id,
        tree.retry_root
    FROM campaign AS child
    JOIN campaign_tree AS tree
      ON child.parent_id = tree.id
),

eligible_sends AS (
    SELECT
        log.id AS log_id,
        log.customer_id,
        log.sent_time,
        tree.retry_root,
        EXISTS (
            SELECT 1
            FROM campaign AS child
            WHERE child.parent_id = tree.retry_root
        ) AS is_retry_family
    FROM communication_log AS log
    JOIN campaign AS campaign
      ON campaign.id = log.communication_id
    JOIN campaign_tree AS tree
      ON tree.id = campaign.id
    WHERE log.merchant_id = 501
      AND log.communication_type = '2'
      AND log.sent_time >= '2026-10-01'
      AND log.sent_time <  '2026-11-01'
      AND campaign.name LIKE '%Diwali%'
      AND campaign.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND campaign.processing_status = 'processed'
),

ranked_sends AS (
    SELECT
        *,
        CASE
            -- Retry-family customers contribute only on their first attempt.
            WHEN is_retry_family THEN ROW_NUMBER() OVER (
                PARTITION BY retry_root, customer_id
                ORDER BY sent_time, log_id
            )
            -- Standalone sends remain separate events, including repeated customers.
            ELSE 1
        END AS contribution_rank
    FROM eligible_sends
)

SELECT SUM(CASE WHEN contribution_rank = 1 THEN 1 ELSE 0 END) AS target_base
FROM ranked_sends;
