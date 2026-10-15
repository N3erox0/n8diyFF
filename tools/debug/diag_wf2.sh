#!/usr/bin/env bash
# 打印指定工作流最后一次执行的报错节点与原因
# 用法： bash /opt/n8n/diag_wf2.sh .wf2_id
PW=$(cat /opt/n8n/.owner_password | tr -d '\r\n')
WF=$(cat /opt/n8n/${1:-.wf2_id} | tr -d '\r\n')
curl -s -c /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"emailOrLdapLoginId":"admin@n8n.local","password":"%s"}' "$PW")" >/dev/null

curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/executions?limit=30" > /tmp/exec.json

EID=$(WF="$WF" python3 -c "
import json, os
d = json.load(open('/tmp/exec.json'))
rows = d.get('data') or []
rows = [r for r in rows if r.get('workflowId') == os.environ['WF']]
print(rows[0]['id'] if rows else '')
")
echo "workflow=$WF execution=$EID"
[ -n "$EID" ] || { echo "该工作流没有执行记录"; exit 1; }

curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/executions/$EID" > /tmp/exec_detail.json

python3 - <<'PY'
import json
det = json.load(open('/tmp/exec_detail.json'))
rd = (det.get('data') or {}).get('resultData') or {}
print('lastNode:', rd.get('lastNodeExecuted'))
if rd.get('error'):
    print('ERROR:', json.dumps(rd['error'], ensure_ascii=False)[:1500])
for name, runs in (rd.get('runData') or {}).items():
    for item in runs:
        if item.get('error'):
            print('--- NODE:', name)
            print(json.dumps(item['error'], ensure_ascii=False)[:1200])
PY
