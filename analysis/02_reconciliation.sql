-- Evidence-led intermediate reconciliation queries.

-- Step 0: reasonable naive count of every in-scope Diwali campaign send attempt.
SELECT COUNT(*) AS naive_target_base
FROM communication_log AS log
JOIN campaign AS campaign
  ON campaign.id = log.communication_id
WHERE log.merchant_id = 501
  AND log.communication_type = '2'
  AND log.sent_time >= '2026-10-01'
  AND log.sent_time <  '2026-11-01'
  AND campaign.name LIKE '%Diwali%';

-- Inspect campaign-level eligibility and the rows affected by it.
SELECT
    campaign.id AS campaign_id,
    campaign.name,
    campaign.creation_status,
    campaign.processing_status,
    COUNT(log.id) AS send_attempts,
    CASE
        WHEN campaign.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
         AND campaign.processing_status = 'processed'
        THEN 'included'
        ELSE 'excluded'
    END AS reporting_treatment
FROM campaign
JOIN communication_log AS log
  ON log.communication_id = campaign.id
WHERE log.merchant_id = 501
  AND log.communication_type = '2'
  AND log.sent_time >= '2026-10-01'
  AND log.sent_time <  '2026-11-01'
  AND campaign.name LIKE '%Diwali%'
GROUP BY campaign.id
ORDER BY campaign.id;

-- Step 1: count after campaign reporting eligibility.
SELECT COUNT(*) AS eligible_send_attempts
FROM communication_log AS log
JOIN campaign AS campaign
  ON campaign.id = log.communication_id
WHERE log.merchant_id = 501
  AND log.communication_type = '2'
  AND log.sent_time >= '2026-10-01'
  AND log.sent_time <  '2026-11-01'
  AND campaign.name LIKE '%Diwali%'
  AND campaign.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
  AND campaign.processing_status = 'processed';

-- Step 2 diagnostic: retry-family attempts versus unique customers.
WITH RECURSIVE campaign_tree AS (
    SELECT id, parent_id, id AS retry_root
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    SELECT child.id, child.parent_id, tree.retry_root
    FROM campaign AS child
    JOIN campaign_tree AS tree
      ON child.parent_id = tree.id
),
eligible_sends AS (
    SELECT
        log.id,
        log.customer_id,
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
)
SELECT
    retry_root,
    CASE
        WHEN is_retry_family THEN 'retry family'
        ELSE 'standalone campaign'
    END AS campaign_treatment,
    COUNT(*) AS eligible_attempts,
    COUNT(DISTINCT customer_id) AS customers_if_family_collapsed,
    CASE
        WHEN is_retry_family THEN COUNT(*) - COUNT(DISTINCT customer_id)
        ELSE 0
    END AS retry_family_duplicate_attempts,
    CASE
        WHEN is_retry_family THEN 0
        ELSE COUNT(*) - COUNT(DISTINCT customer_id)
    END AS standalone_repeated_send_rows
FROM eligible_sends
GROUP BY retry_root, is_retry_family
ORDER BY retry_root;
