#!/usr/bin/env bash
cd /opt/n8n
PW=$(cat /opt/n8n/.owner_password | tr -d '\r\n')
echo "PW_LEN=${#PW}"
curl -s -c /tmp/cj2 -w '\nLOGIN_HTTP:%{http_code}\n' -X POST http://127.0.0.1:5678/rest/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"email":"admin@n8n.local","password":"%s"}' "$PW")" | head -c 400
echo
echo "--- cookie jar ---"
grep -i n8n /tmp/cj2 | head -3 || cat /tmp/cj2 | head -5
echo "--- 用 cookie 试一个接口 ---"
curl -s -b /tmp/cj2 -w '\nHTTP:%{http_code}\n' http://127.0.0.1:5678/rest/workflows | head -c 200
