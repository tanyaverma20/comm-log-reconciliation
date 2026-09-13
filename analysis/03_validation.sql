-- Read-only robustness and independent-validation checks.

-- Delivery-status sensitivity. A delivered-only result is not the business rule.
SELECT 'all_in_scope' AS population, COUNT(*) AS row_count
FROM communication_log AS log
JOIN campaign AS campaign ON campaign.id = log.communication_id
WHERE log.merchant_id = 501
  AND log.communication_type = '2'
  AND log.sent_time >= '2026-10-01'
  AND log.sent_time <  '2026-11-01'
  AND campaign.name LIKE '%Diwali%'
UNION ALL
SELECT 'all_in_scope_delivered_only', COUNT(*)
FROM communication_log AS log
JOIN campaign AS campaign ON campaign.id = log.communication_id
WHERE log.merchant_id = 501
  AND log.communication_type = '2'
  AND log.delivery_status = 900
  AND log.sent_time >= '2026-10-01'
  AND log.sent_time <  '2026-11-01'
  AND campaign.name LIKE '%Diwali%'
UNION ALL
SELECT 'eligible_all_delivery_statuses', COUNT(*)
FROM communication_log AS log
JOIN campaign AS campaign ON campaign.id = log.communication_id
WHERE log.merchant_id = 501
  AND log.communication_type = '2'
  AND log.sent_time >= '2026-10-01'
  AND log.sent_time <  '2026-11-01'
  AND campaign.name LIKE '%Diwali%'
  AND campaign.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
  AND campaign.processing_status = 'processed'
UNION ALL
SELECT 'eligible_delivered_only', COUNT(*)
FROM communication_log AS log
JOIN campaign AS campaign ON campaign.id = log.communication_id
WHERE log.merchant_id = 501
  AND log.communication_type = '2'
  AND log.delivery_status = 900
  AND log.sent_time >= '2026-10-01'
  AND log.sent_time <  '2026-11-01'
  AND campaign.name LIKE '%Diwali%'
  AND campaign.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
  AND campaign.processing_status = 'processed';

-- Independent, family-level formulation. It returns 22.
WITH RECURSIVE family_members AS (
    SELECT id AS retry_root, id AS campaign_id
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    SELECT family.retry_root, child.id
    FROM family_members AS family
    JOIN campaign AS child ON child.parent_id = family.campaign_id
),
eligible_log AS (
    SELECT family.retry_root, log.id, log.customer_id
    FROM family_members AS family
    JOIN campaign AS campaign ON campaign.id = family.campaign_id
    JOIN communication_log AS log ON log.communication_id = campaign.id
    WHERE log.merchant_id = 501
      AND log.communication_type = '2'
      AND log.sent_time >= '2026-10-01'
      AND log.sent_time <  '2026-11-01'
      AND campaign.name LIKE '%Diwali%'
      AND campaign.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND campaign.processing_status = 'processed'
),
family_sizes AS (
    SELECT retry_root, COUNT(*) AS campaign_count
    FROM family_members
    GROUP BY retry_root
),
family_counts AS (
    SELECT
        log.retry_root,
        size.campaign_count,
        COUNT(log.id) AS attempt_count,
        COUNT(DISTINCT log.customer_id) AS customer_count
    FROM eligible_log AS log
    JOIN family_sizes AS size ON size.retry_root = log.retry_root
    GROUP BY log.retry_root, size.campaign_count
)
SELECT
    retry_root,
    campaign_count,
    attempt_count,
    customer_count,
    CASE WHEN campaign_count = 1 THEN attempt_count ELSE customer_count END AS contribution
FROM family_counts
ORDER BY retry_root;
