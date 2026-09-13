-- Read-only profiling queries used to understand the supplied SQLite data.

-- Tables and their creation SQL.
SELECT name, sql
FROM sqlite_master
WHERE type = 'table'
ORDER BY name;

-- Column schemas.
PRAGMA table_info(campaign);
PRAGMA table_info(communication_log);

-- Row counts.
SELECT 'campaign' AS table_name, COUNT(*) AS row_count FROM campaign
UNION ALL
SELECT 'communication_log', COUNT(*) FROM communication_log;

-- Campaign records, names, statuses, and parent-child keys.
SELECT
    id,
    merchant_id,
    parent_id,
    name,
    creation_status,
    processing_status
FROM campaign
ORDER BY id;

-- Important observed status/type values.
SELECT creation_status, processing_status, COUNT(*) AS campaign_count
FROM campaign
GROUP BY creation_status, processing_status
ORDER BY creation_status, processing_status;

SELECT communication_type, COUNT(*) AS row_count
FROM communication_log
GROUP BY communication_type;

SELECT delivery_status, COUNT(*) AS row_count
FROM communication_log
GROUP BY delivery_status;

SELECT channel, COUNT(*) AS row_count
FROM communication_log
GROUP BY channel;

-- Date range and basic consistency checks.
SELECT
    MIN(sent_time) AS first_sent_time,
    MAX(sent_time) AS last_sent_time,
    SUM(sent_time <> scheduled_time) AS sent_schedule_mismatches,
    MIN(credit_used) AS min_credit_used,
    MAX(credit_used) AS max_credit_used
FROM communication_log;

-- Customers with multiple send attempts.
SELECT
    customer_id,
    COUNT(*) AS attempt_count,
    COUNT(DISTINCT communication_id) AS campaign_count
FROM communication_log
GROUP BY customer_id
HAVING COUNT(*) > 1
ORDER BY customer_id;

-- Parent-child campaign relationships.
SELECT
    parent.id AS parent_campaign_id,
    parent.name AS parent_campaign_name,
    child.id AS child_campaign_id,
    child.name AS child_campaign_name,
    child.creation_status,
    child.processing_status
FROM campaign AS child
JOIN campaign AS parent
  ON parent.id = child.parent_id
ORDER BY parent.id, child.id;
