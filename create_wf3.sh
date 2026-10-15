#!/usr/bin/env bash
# 建智谱凭据 → 导入 WF3（核查→排版→审核→成品）→ 激活
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

ZKEY=$(grep '^ZHIPU_API_KEY=' /opt/n8n/.env | cut -d= -f2- | tr -d '\r\n ')
if [ -z "$ZKEY" ]; then ZKEY=PLACEHOLDER; echo "!! 未检测到 ZHIPU_API_KEY，核查节点会失败（已设为容错，排版仍会跑完）"; fi

if [ -f /opt/n8n/.zhipu_cred_id ]; then
  OLD_Z=$(cat /opt/n8n/.zhipu_cred_id | tr -d '\r\n')
  curl -s -b /tmp/n8n_cj -X DELETE "$API/credentials/$OLD_Z" >/dev/null 2>&1
fi

echo "==> 创建智谱凭据"
Z=$(curl -s -b /tmp/n8n_cj -X POST $API/credentials -H 'Content-Type: application/json' \
  -d "$(printf '{"name":"Zhipu API","type":"httpHeaderAuth","data":{"name":"Authorization","value":"Bearer %s"}}' "$ZKEY")")
Z_ID=$(printf '%s' "$Z" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "ZHIPU_ID=$Z_ID"
[ -n "$Z_ID" ] || { echo "智谱凭据创建失败：$Z"; exit 1; }
echo "$Z_ID" > /opt/n8n/.zhipu_cred_id

# 成品表（幂等）
docker exec n8n-postgres-1 psql -U n8n -d n8n -q -c "$(cat <<'SQL'
CREATE TABLE IF NOT EXISTS finals (
  id BIGSERIAL PRIMARY KEY,
  topic_id TEXT NOT NULL REFERENCES topics(topic_id) ON DELETE CASCADE,
  draft_id BIGINT,
  title TEXT,
  body_md TEXT,
  body_html TEXT,
  facts JSONB,
  risk_flags JSONB,
  decision TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL
)"
echo "finals 表就绪"

if [ -f /opt/n8n/.wf3_id ]; then
  OLD=$(cat /opt/n8n/.wf3_id | tr -d '\r\n')
  OV=$(curl -s -b /tmp/n8n_cj "$API/workflows/$OLD" | grep -o '"versionId":"[^"]*"' | head -1 | cut -d'"' -f4)
  curl -s -b /tmp/n8n_cj -X POST "$API/workflows/$OLD/deactivate" -H 'Content-Type: application/json' \
    -d "$(printf '{"versionId":"%s"}' "$OV")" >/dev/null 2>&1
  curl -s -b /tmp/n8n_cj -X DELETE "$API/workflows/$OLD" >/dev/null 2>&1
  echo "已删除旧 WF3"
fi

sed -e "s/__PG_CRED_ID__/$PG_ID/g" -e "s/__ZHIPU_CRED_ID__/$Z_ID/g" /opt/n8n/workflows/wf3-review.json > /tmp/wf3.json
WF=$(curl -s -b /tmp/n8n_cj -X POST $API/workflows -H 'Content-Type: application/json' -d @/tmp/wf3.json)
WF_ID=$(printf '%s' "$WF" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "WF3_ID=$WF_ID"
[ -n "$WF_ID" ] || { echo "WF3 创建失败：$WF" | head -c 600; exit 1; }
echo "$WF_ID" > /opt/n8n/.wf3_id

VER=$(curl -s -b /tmp/n8n_cj "$API/workflows/$WF_ID" | grep -o '"versionId":"[^"]*"' | head -1 | cut -d'"' -f4)
curl -s -b /tmp/n8n_cj -X POST "$API/workflows/$WF_ID/activate" -H 'Content-Type: application/json' \
  -d "$(printf '{"versionId":"%s"}' "$VER")" | head -c 160
echo
echo "==> WF3 就绪：POST /webhook/review {\"topic_id\":\"...\"}"
