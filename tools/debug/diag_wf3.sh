#!/usr/bin/env bash
# 打印 WF3 的节点与连线，以及最后一次执行的 runData
PW=$(cat /opt/n8n/.owner_password | tr -d '\r\n')
WF=$(cat /opt/n8n/.wf3_id | tr -d '\r\n')
curl -s -c /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"emailOrLdapLoginId":"admin@n8n.local","password":"%s"}' "$PW")" >/dev/null

curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/workflows/$WF" > /tmp/wf3.json
EID=$(docker exec n8n-postgres-1 psql -U n8n -d n8n -tAc \
  "select id from execution_entity where \"workflowId\" = '$WF' order by id desc limit 1")
curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/executions/$EID" > /tmp/e.json

python3 - <<PY
import json
wf = json.load(open('/tmp/wf3.json'))
if 'nodes' not in wf and isinstance(wf.get('data'), dict):
    wf = wf['data']
print('wf keys:', list(wf.keys())[:12])
nodes = wf.get('nodes') or []
conns = wf.get('connections') or {}
print('nodes:', len(nodes))
for n in nodes:
    print('  -', n.get('name'), '|', n.get('type'))
print('connections:')
for src, v in conns.items():
    for branch in (v.get('main') or []):
        print('  ', src, '->', [c.get('node') for c in branch])
print()
e = json.load(open('/tmp/e.json'))
rd = (e.get('data') or {}).get('resultData') or {}
print('execution', '$EID', 'last:', rd.get('lastNodeExecuted'))
print('runData nodes:', list((rd.get('runData') or {}).keys()))
print('error:', json.dumps(rd.get('error'), ensure_ascii=False)[:600] if rd.get('error') else 'none')
PY
