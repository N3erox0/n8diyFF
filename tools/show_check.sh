#!/usr/bin/env bash
# 查看核查结果：风险等级、存疑句、最终判定
docker exec -i n8n-postgres-1 psql -U n8n -d n8n <<'SQL'
\pset pager off
select id, topic_id, status, facts->>'risk_level' as risk,
       jsonb_array_length(coalesce(facts->'issues','[]'::jsonb)) as issues
from drafts order by id desc limit 3;
select id, decision, left(facts->>'summary', 160) as summary,
       jsonb_array_length(coalesce(facts->'issues','[]'::jsonb)) as issues
from finals order by id desc limit 3;
select jsonb_pretty(coalesce(facts->'issues','[]'::jsonb)) as issues_detail
from finals order by id desc limit 1;
SQL
