-- Row-level audit of every communication_log record and its target-base treatment.

WITH RECURSIVE campaign_tree AS (
    SELECT id, parent_id, id AS retry_root
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    SELECT child.id, child.parent_id, tree.retry_root
    FROM campaign AS child
    JOIN campaign_tree AS tree ON child.parent_id = tree.id
),
all_log_rows AS (
    SELECT
        log.id AS communication_log_id,
        log.merchant_id,
        log.communication_id AS campaign_id,
        tree.retry_root,
        log.customer_id,
        log.delivery_status,
        log.communication_type,
        log.sent_time,
        campaign.name AS campaign_name,
        campaign.creation_status,
        campaign.processing_status,
        CASE
            WHEN campaign.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
             AND campaign.processing_status = 'processed'
            THEN 'eligible'
            ELSE 'ineligible'
        END AS campaign_eligibility,
        CASE
            WHEN log.merchant_id = 501
             AND log.communication_type = '2'
             AND log.sent_time >= '2026-10-01'
             AND log.sent_time <  '2026-11-01'
             AND campaign.name LIKE '%Diwali%'
            THEN 1
            ELSE 0
        END AS is_in_scope,
        EXISTS (
            SELECT 1
            FROM campaign AS child
            WHERE child.parent_id = tree.retry_root
        ) AS is_retry_family
    FROM communication_log AS log
    JOIN campaign AS campaign ON campaign.id = log.communication_id
    JOIN campaign_tree AS tree ON tree.id = campaign.id
),
eligible_ranked AS (
    SELECT
        communication_log_id,
        CASE
            WHEN is_retry_family THEN ROW_NUMBER() OVER (
                PARTITION BY retry_root, customer_id
                ORDER BY sent_time, communication_log_id
            )
            ELSE 1
        END AS contribution_rank
    FROM all_log_rows
    WHERE is_in_scope = 1
      AND campaign_eligibility = 'eligible'
)
SELECT
    audit.communication_log_id,
    audit.campaign_id,
    audit.retry_root,
    audit.customer_id,
    audit.delivery_status,
    audit.campaign_eligibility,
    CASE
        WHEN ranked.contribution_rank = 1 THEN 'yes'
        ELSE 'no'
    END AS contributes_to_target_base,
    CASE
        WHEN audit.is_in_scope = 0 THEN 'Outside merchant, date, type, or Diwali scope'
        WHEN audit.campaign_eligibility = 'ineligible' THEN 'Campaign is not reporting-eligible'
        WHEN audit.is_retry_family = 0 THEN 'Standalone campaign: each send is a separate event'
        WHEN ranked.contribution_rank = 1 THEN 'First customer event in eligible retry family'
        ELSE 'Later attempt for same customer in eligible retry family'
    END AS reason
FROM all_log_rows AS audit
LEFT JOIN eligible_ranked AS ranked
  ON ranked.communication_log_id = audit.communication_log_id
ORDER BY audit.communication_log_id;
