#!/usr/bin/env bash
# 只读诊断：取 WF2 最近一次执行并解码报错
cd /opt/n8n
PW=$(cat /opt/n8n/.owner_password | tr -d '\r\n')
curl -s -c /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"emailOrLdapLoginId":"admin@n8n.local","password":"%s"}' "$PW")" >/dev/null

WF2=$(cat /opt/n8n/.wf2_id | tr -d '\r\n')
LIST=$(curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/executions?limit=2&workflowId=$WF2")
ID=$(printf '%s' "$LIST" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "WF2_ID=$WF2  EXEC_ID=$ID"

curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/executions/$ID?includeData=true" > /tmp/exec.json
python3 decode_exec.py
