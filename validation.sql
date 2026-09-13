-- Independent validation query.
-- Run with: sqlite3 data/comm_log.db < validation.sql
-- This groups at the campaign-family level instead of selecting a row rank.

WITH RECURSIVE family_members AS (
    SELECT
        id AS retry_root,
        id AS campaign_id
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    SELECT
        family.retry_root,
        child.id
    FROM family_members AS family
    JOIN campaign AS child
      ON child.parent_id = family.campaign_id
),

eligible_log AS (
    SELECT
        family.retry_root,
        log.id AS log_id,
        log.customer_id
    FROM family_members AS family
    JOIN campaign AS campaign
      ON campaign.id = family.campaign_id
    JOIN communication_log AS log
      ON log.communication_id = campaign.id
    WHERE log.merchant_id = 501
      AND log.communication_type = '2'
      AND log.sent_time >= '2026-10-01'
      AND log.sent_time <  '2026-11-01'
      AND campaign.name LIKE '%Diwali%'
      AND campaign.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND campaign.processing_status = 'processed'
),

family_sizes AS (
    SELECT
        retry_root,
        COUNT(*) AS campaign_count
    FROM family_members
    GROUP BY retry_root
),

family_counts AS (
    SELECT
        log.retry_root,
        size.campaign_count,
        COUNT(log.log_id) AS send_attempt_count,
        COUNT(DISTINCT log.customer_id) AS distinct_family_customers
    FROM eligible_log AS log
    JOIN family_sizes AS size
      ON size.retry_root = log.retry_root
    GROUP BY log.retry_root, size.campaign_count
)

SELECT SUM(
    CASE
        -- A true standalone has one campaign row, so retain every send event.
        WHEN campaign_count = 1 THEN send_attempt_count
        -- A retry family contributes each customer once across its campaigns.
        ELSE distinct_family_customers
    END
) AS target_base
FROM family_counts;
