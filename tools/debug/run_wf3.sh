#!/usr/bin/env bash
# 对最新一条选题触发 WF3，并打印结果与成品表
cd /opt/n8n
TID=${1:-$(docker exec n8n-postgres-1 psql -U n8n -d n8n -tAc "select topic_id from topics order by id desc limit 1")}
echo "TID=$TID"
BODY=$(printf '{"topic_id":"%s"}' "$TID")
curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:5678/webhook/review \
  -H 'Content-Type: application/json' -d "$BODY"

docker exec -i n8n-postgres-1 psql -U n8n -d n8n <<'SQL'
\pset pager off
select id, "workflowId", status, "startedAt", "stoppedAt" from execution_entity order by id desc limit 3;
select id, topic_id, status, length(coalesce(body_html,'')) as html_len, facts is not null as has_facts from drafts order by id desc limit 3;
select id, decision, length(coalesce(body_html,'')) as html_len from finals order by id desc limit 3;
SQL
