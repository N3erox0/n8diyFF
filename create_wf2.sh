#!/usr/bin/env bash
# 建 DeepSeek 占位凭据 → 导入 WF2 → 激活
set -e
cd /opt/n8n
API=http://127.0.0.1:5678/rest

PW=$(cat /opt/n8n/.owner_password | tr -d '\r\n')
curl -s -c /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"emailOrLdapLoginId":"admin@n8n.local","password":"%s"}' "$PW")" >/dev/null

PG_ID=""
if [ -f /opt/n8n/.pg_cred_id ]; then PG_ID=$(cat /opt/n8n/.pg_cred_id | tr -d '\r\n'); fi
if [ -z "$PG_ID" ]; then
  PGPASS=$(grep POSTGRES_PASSWORD .env | cut -d= -f2 | tr -d '\r\n ')
  C=$(curl -s -b /tmp/n8n_cj -X POST $API/credentials -H 'Content-Type: application/json' \
    -d "$(printf '{"name":"Postgres n8n","type":"postgres","data":{"host":"postgres","port":5432,"database":"n8n","user":"n8n","password":"%s","ssl":"disable"}}' "$PGPASS")")
  PG_ID=$(printf '%s' "$C" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "$PG_ID" > /opt/n8n/.pg_cred_id
fi
echo "PG_ID=$PG_ID"

DSKEY=$(grep '^DEEPSEEK_API_KEY=' /opt/n8n/.env | cut -d= -f2- | tr -d '\r\n ')
if [ -z "$DSKEY" ]; then DSKEY=sk-CHANGE_ME; echo "!! 未检测到 DEEPSEEK_API_KEY，仍写入占位值"; fi

# 旧凭据先删（n8n 只能重建不能原地改值），避免同名堆积
if [ -f /opt/n8n/.deep_cred_id ]; then
  OLD_D=$(cat /opt/n8n/.deep_cred_id | tr -d '\r\n')
  curl -s -b /tmp/n8n_cj -X DELETE "$API/credentials/$OLD_D" >/dev/null 2>&1
fi

echo "==> 创建 DeepSeek 凭据"
D=$(curl -s -b /tmp/n8n_cj -X POST $API/credentials -H 'Content-Type: application/json' \
  -d "$(printf '{"name":"DeepSeek API","type":"httpHeaderAuth","data":{"name":"Authorization","value":"Bearer %s"}}' "$DSKEY")")
DEEP_ID=$(printf '%s' "$D" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$DEEP_ID" ]; then
  L=$(curl -s -b /tmp/n8n_cj $API/credentials)
  DEEP_ID=$(printf '%s' "$L" | grep -o '"id":"[^"]*","name":"DeepSeek API"' | head -1 | cut -d'"' -f4)
fi
echo "DEEP_ID=$DEEP_ID"
[ -n "$DEEP_ID" ] || { echo "DeepSeek 凭据创建失败：$D"; exit 1; }
echo "$DEEP_ID" > /opt/n8n/.deep_cred_id

if [ -f /opt/n8n/.wf2_id ]; then
  OLD=$(cat /opt/n8n/.wf2_id | tr -d '\r\n')
  OV=$(curl -s -b /tmp/n8n_cj "$API/workflows/$OLD" | grep -o '"versionId":"[^"]*"' | head -1 | cut -d'"' -f4)
  curl -s -b /tmp/n8n_cj -X POST "$API/workflows/$OLD/deactivate" -H 'Content-Type: application/json' \
    -d "$(printf '{"versionId":"%s"}' "$OV")" >/dev/null 2>&1
  curl -s -b /tmp/n8n_cj -X DELETE "$API/workflows/$OLD" >/dev/null 2>&1
  echo "已删除旧 WF2"
fi

sed -e "s/__PG_CRED_ID__/$PG_ID/g" -e "s/__DEEP_CRED_ID__/$DEEP_ID/g" /opt/n8n/workflows/wf2-writer.json > /tmp/wf2.json
WF=$(curl -s -b /tmp/n8n_cj -X POST $API/workflows -H 'Content-Type: application/json' -d @/tmp/wf2.json)
WF_ID=$(printf '%s' "$WF" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "WF2_ID=$WF_ID"
[ -n "$WF_ID" ] || { echo "WF2 创建失败：$WF" | head -c 600; exit 1; }
echo "$WF_ID" > /opt/n8n/.wf2_id

VER=$(curl -s -b /tmp/n8n_cj "$API/workflows/$WF_ID" | grep -o '"versionId":"[^"]*"' | head -1 | cut -d'"' -f4)
curl -s -b /tmp/n8n_cj -X POST "$API/workflows/$WF_ID/activate" -H 'Content-Type: application/json' \
  -d "$(printf '{"versionId":"%s"}' "$VER")" | head -c 160
echo
echo "==> WF2 就绪：填入 DeepSeek Key 后即可触发 POST /webhook/write {topic_id}"
