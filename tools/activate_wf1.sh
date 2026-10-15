#!/usr/bin/env bash
# 激活 WF1 并执行端到端自测
set -e
cd /opt/n8n

PW=$(cat /opt/n8n/.owner_password | tr -d '\r\n')
curl -s -c /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"emailOrLdapLoginId":"admin@n8n.local","password":"%s"}' "$PW")" >/dev/null

WF_ID=$(cat /opt/n8n/.wf1_id | tr -d '\r\n')
echo "WF_ID=$WF_ID"

VER=$(curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/workflows/$WF_ID" \
  | grep -o '"versionId":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "VER=$VER"

echo "==> 激活"
curl -s -b /tmp/n8n_cj -X POST "http://127.0.0.1:5678/rest/workflows/$WF_ID/activate" \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"versionId":"%s"}' "$VER")" | head -c 200
echo

sleep 4
echo "==> 测试1 正常推送（应 202）"
curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:5678/webhook/topic \
  -H 'Content-Type: application/json' \
  -d '{"title":"测试选题：n8n 自托管的安全代价","angle":"从连续 CVSS 10.0 看自托管","direction":"AI 自动化","keywords":["n8n","安全"],"brief":"测试接收通路","pushed_by":"manual","source_urls":["https://example.com/n8n-cve"]}'

echo "==> 测试2 重复信源（应 409）"
curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:5678/webhook/topic \
  -H 'Content-Type: application/json' \
  -d '{"title":"重复测试","source_urls":["https://example.com/n8n-cve"]}'

echo "==> 测试3 缺字段（应 400）"
curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:5678/webhook/topic \
  -H 'Content-Type: application/json' -d '{"title":""}'

echo "==> 入库结果"
docker exec n8n-postgres-1 psql -U n8n -d n8n -c 'SELECT topic_id,title,pushed_by,status FROM topics;'
docker exec n8n-postgres-1 psql -U n8n -d n8n -c 'SELECT topic_id,url FROM topic_sources;'
