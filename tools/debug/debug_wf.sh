#!/usr/bin/env bash
# 只读诊断：取指定工作流最近一次执行并解码报错
# 用法：bash debug_wf.sh [.wf1_id|.wf2_id]
cd /opt/n8n
F=${1:-.wf1_id}
PW=$(cat /opt/n8n/.owner_password | tr -d '\r\n')
curl -s -c /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"emailOrLdapLoginId":"admin@n8n.local","password":"%s"}' "$PW")" >/dev/null

WF=$(cat /opt/n8n/$F | tr -d '\r\n')
LIST=$(curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/executions?limit=1&workflowId=$WF")
ID=$(printf '%s' "$LIST" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "WF=$WF  EXEC_ID=$ID"
curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/executions/$ID?includeData=true" > /tmp/exec.json
python3 decode_exec.py
