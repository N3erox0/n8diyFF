#!/usr/bin/env bash
# 列出所有工作流及其激活状态，并测试 webhook 路径是否存在
PW=$(cat /opt/n8n/.owner_password | tr -d '\r\n')
curl -s -c /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"emailOrLdapLoginId":"admin@n8n.local","password":"%s"}' "$PW")" >/dev/null
curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/workflows" > /tmp/wfs.json

python3 - <<'PY'
import json
d = json.load(open('/tmp/wfs.json'))
rows = d.get('data')
if isinstance(rows, dict):
    rows = rows.get('data') or rows.get('results') or []
print('workflows:', len(rows))
for w in rows:
    if not isinstance(w, dict):
        print('  RAW:', str(w)[:120]); continue
    print(' ', w.get('id'), '| active=', w.get('active'), '|', w.get('name'))
PY

echo "--- 路径探测 ---"
for P in topic write review zzz-nonexistent; do
  printf '%-18s' "$P"
  curl -s -o /tmp/out.txt -w '%{http_code}' --max-time 20 -X POST "http://127.0.0.1:5678/webhook/$P" \
    -H 'Content-Type: application/json' -d '{"topic_id":"probe"}'
  echo "  body=$(head -c 120 /tmp/out.txt)"
done
