#!/usr/bin/env bash
# 确保 token 环境变量 → 创建 Postgres 凭据 → 导入 WF1 → 激活 → 端到端自测
set -e
cd /opt/n8n

# 1. 生成 webhook 鉴权 token
if ! grep -q '^WEBHOOK_TOKEN=' /opt/n8n/.env; then
  echo "WEBHOOK_TOKEN=$(openssl rand -hex 16)" >> /opt/n8n/.env
  echo "已生成 WEBHOOK_TOKEN"
fi
TOKEN=$(grep '^WEBHOOK_TOKEN=' /opt/n8n/.env | cut -d= -f2 | tr -d '\r\n')
echo "WEBHOOK_TOKEN=$TOKEN"

# 2. 让容器拿到新环境变量（仅在配置变化时重建）
docker compose up -d >/dev/null 2>&1
for i in $(seq 1 40); do curl -s -o /dev/null http://127.0.0.1:5678/healthz && break; sleep 2; done
sleep 3

PW=$(cat /opt/n8n/.owner_password | tr -d '\r\n')
curl -s -c /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"emailOrLdapLoginId":"admin@n8n.local","password":"%s"}' "$PW")" >/dev/null

PGPASS=$(grep POSTGRES_PASSWORD .env | cut -d= -f2 | tr -d '\r\n ')
CRED=$(curl -s -b /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/credentials \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"name":"Postgres n8n","type":"postgres","data":{"host":"postgres","port":5432,"database":"n8n","user":"n8n","password":"%s","ssl":"disable"}}' "$PGPASS")")
CRED_ID=$(printf '%s' "$CRED" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "CRED_ID=$CRED_ID"
echo "$CRED_ID" > /opt/n8n/.pg_cred_id
[ -n "$CRED_ID" ] || { echo "凭据创建失败：$CRED"; exit 1; }

# 如已存在旧版本先删除，避免重复
if [ -f /opt/n8n/.wf1_id ]; then
  OLD=$(cat /opt/n8n/.wf1_id | tr -d '\r\n')
  OLD_VER=$(curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/workflows/$OLD" | grep -o '"versionId":"[^"]*"' | head -1 | cut -d'"' -f4)
  curl -s -b /tmp/n8n_cj -X POST "http://127.0.0.1:5678/rest/workflows/$OLD/deactivate" \
    -H 'Content-Type: application/json' -d "$(printf '{"versionId":"%s"}' "$OLD_VER")" >/dev/null
  curl -s -b /tmp/n8n_cj -X DELETE "http://127.0.0.1:5678/rest/workflows/$OLD" >/dev/null
  echo "已删除旧版本 $OLD"
fi

# 建 Token 凭据（Webhook 节点用 headerAuth 校验，令牌加密存储）
if [ -f /opt/n8n/.token_cred_id ]; then
  TOKEN_CRED_ID=$(cat /opt/n8n/.token_cred_id | tr -d '\r\n')
else
  T=$(curl -s -b /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/credentials \
    -H 'Content-Type: application/json' \
    -d "$(printf '{"name":"Webhook Token","type":"httpHeaderAuth","data":{"name":"X-Token","value":"%s"}}' "$TOKEN")")
  TOKEN_CRED_ID=$(printf '%s' "$T" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "$TOKEN_CRED_ID" > /opt/n8n/.token_cred_id
fi
echo "TOKEN_CRED_ID=$TOKEN_CRED_ID"
[ -n "$TOKEN_CRED_ID" ] || { echo "Token 凭据创建失败"; exit 1; }

sed -e "s/__PG_CRED_ID__/$CRED_ID/g" -e "s/__TOKEN_CRED_ID__/$TOKEN_CRED_ID/g" /opt/n8n/workflows/wf1-intake.json > /tmp/wf1.json
WF=$(curl -s -b /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/workflows \
  -H 'Content-Type: application/json' -d @/tmp/wf1.json)
WF_ID=$(printf '%s' "$WF" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "WF_ID=$WF_ID"
[ -n "$WF_ID" ] || { echo "工作流创建失败：$WF" | head -c 600; exit 1; }
echo "$WF_ID" > /opt/n8n/.wf1_id

VER=$(curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/workflows/$WF_ID" \
  | grep -o '"versionId":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "VER=$VER"
echo "==> 激活"
curl -s -b /tmp/n8n_cj -X POST "http://127.0.0.1:5678/rest/workflows/$WF_ID/activate" \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"versionId":"%s"}' "$VER")" | head -c 160
echo

sleep 3
docker exec n8n-postgres-1 psql -U n8n -d n8n -c "DELETE FROM topics WHERE topic_id='undefined';" >/dev/null 2>&1
docker exec n8n-postgres-1 psql -U n8n -d n8n -c "ALTER TABLE topic_sources ADD COLUMN IF NOT EXISTS content TEXT;" >/dev/null

echo "==> 测试0 无 Token（应 401）"
curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:5678/webhook/topic \
  -H 'Content-Type: application/json' -d '{"title":"无令牌测试","sources":[{"url":"https://example.com/x"}]}'

echo "==> 测试1 正常推送（应 202）"
curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:5678/webhook/topic \
  -H 'Content-Type: application/json' -H "X-Token: $TOKEN" \
  -d '{"title":"测试选题：n8n 自托管的安全代价","angle":"从连续 CVSS 10.0 看自托管","direction":"AI 自动化","keywords":["n8n","安全"],"brief":"测试接收通路","pushed_by":"manual","sources":[{"url":"https://example.com/n8n-cve","title":"n8n 漏洞通报","content":"2026 年上半年，n8n 连续披露多个 CVSS 10.0 级别漏洞，包括 CVE-2026-21858（Ni8mare，未认证远程代码执行）、CVE-2026-21877（任意文件写入）与 CVE-2026-1470（工作流表达式 RCE）。由于 n8n 通常集中保存企业的 API Token、OAuth 凭据与数据库密钥，一旦实例被攻陷，影响范围往往覆盖半个基础设施。官方建议自托管用户尽快升级到 1.123.17、2.4.5、2.5.1 及以上版本，并避免将 Webhook 与表单端点直接暴露到公网。"}]}'

echo "==> 测试2 重复信源（应 409）"
curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:5678/webhook/topic \
  -H 'Content-Type: application/json' -H "X-Token: $TOKEN" \
  -d '{"title":"重复测试","source_urls":["https://example.com/n8n-cve"]}'

echo "==> 测试3 缺字段（应 400）"
curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:5678/webhook/topic \
  -H 'Content-Type: application/json' -H "X-Token: $TOKEN" -d '{"title":""}'

echo "==> 入库结果"
docker exec n8n-postgres-1 psql -U n8n -d n8n -c 'SELECT topic_id,title,pushed_by,status FROM topics;'
docker exec n8n-postgres-1 psql -U n8n -d n8n -c 'SELECT topic_id,url FROM topic_sources;'
