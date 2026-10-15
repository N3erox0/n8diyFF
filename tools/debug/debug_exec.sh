#!/usr/bin/env bash
cd /opt/n8n
PW=$(cat /opt/n8n/.owner_password | tr -d '\r\n')
curl -s -c /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"emailOrLdapLoginId":"admin@n8n.local","password":"%s"}' "$PW")" >/dev/null

EX=$(curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/executions?limit=1")
ID=$(printf '%s' "$EX" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "EXEC_ID=$ID"

curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/executions/$ID?includeData=true" > /tmp/exec.json
echo "--- 错误信息 ---"
grep -o '"message":"[^"]\{0,400\}"' /tmp/exec.json | head -6
echo "--- 节点运行轨迹 ---"
grep -o '"node":"[^"]*"' /tmp/exec.json | head -12
echo "--- 原始片段 ---"
head -c 1200 /tmp/exec.json
