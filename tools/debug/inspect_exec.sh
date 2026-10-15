#!/usr/bin/env bash
# 直接查 n8n 执行表，看最近几次执行的状态和报错
docker exec -i n8n-postgres-1 psql -U n8n -d n8n <<'SQL'
\pset pager off
select id, "workflowId", status, "startedAt", "stoppedAt" from execution_entity order by id desc limit 8;
select id, "workflowId", status, coalesce(data->'resultData'->>'lastNodeExecuted','-') as last_node,
       left(coalesce(data->'resultData'->'error'->>'message','-'), 300) as err_msg
from execution_entity order by id desc limit 5;
SQL
