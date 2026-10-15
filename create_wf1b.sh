#!/usr/bin/env bash
# 读取 .env 里的飞书配置 → 写入 settings 表 → 导入 WF1b → 激活 → 连通性自检
set -e
cd /opt/n8n

# 1. 校验 .env 四个值是否已填
for K in FEISHU_APP_ID FEISHU_APP_SECRET FEISHU_APP_TOKEN FEISHU_TABLE_ID; do
  if ! grep -q "^$K=" /opt/n8n/.env; then
    echo "$K=" >> /opt/n8n/.env
    echo "已在 .env 追加 $K=（待填）"
  fi
done
get() { grep "^$1=" /opt/n8n/.env | cut -d= -f2- | tr -d '\r\n ' | sed 's/^（待填）$//'; }
APP_ID=$(get FEISHU_APP_ID); APP_SECRET=$(get FEISHU_APP_SECRET)
APP_TOKEN=$(get FEISHU_APP_TOKEN); TABLE_ID=$(get FEISHU_TABLE_ID)

if [ -z "$APP_ID" ] || [ -z "$APP_SECRET" ] || [ -z "$APP_TOKEN" ] || [ -z "$TABLE_ID" ]; then
  echo "!! .env 里飞书配置还没填完："
  echo "   FEISHU_APP_ID=$APP_ID"
  echo "   FEISHU_APP_SECRET=$([ -n "$APP_SECRET" ] && echo '已填' || echo '空')"
  echo "   FEISHU_APP_TOKEN=$APP_TOKEN"
  echo "   FEISHU_TABLE_ID=$TABLE_ID"
  echo "填好后重跑本脚本。填法见 docs/feishu-setup.md"
  exit 1
fi

# 2. 写入 settings 表（n8n Code 节点读不到环境变量，故走 DB）
docker exec n8n-postgres-1 psql -U n8n -d n8n -q -c \
  "CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT, updated_at TIMESTAMPTZ DEFAULT now());"
docker exec n8n-postgres-1 psql -U n8n -d n8n -q -c \
  "ALTER TABLE settings ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();"
for KV in "feishu_app_id:$APP_ID" "feishu_app_secret:$APP_SECRET" "feishu_app_token:$APP_TOKEN" "feishu_table_id:$TABLE_ID"; do
  K=${KV%%:*}; V=${KV#*:}
  docker exec n8n-postgres-1 psql -U n8n -d n8n -q -c \
    "INSERT INTO settings(key,value) VALUES('$K','$V') ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=now();"
done
echo "settings 表已更新（密钥不进工作流导出文件）"

# 3. 连通性自检：不依赖 n8n，直接测飞书 API
echo "==> 飞书连通性自检"
TK=$(curl -s -X POST https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal \
  -H 'Content-Type: application/json; charset=utf-8' \
  -d "$(printf '{"app_id":"%s","app_secret":"%s"}' "$APP_ID" "$APP_SECRET")")
echo "token 返回: $(printf '%s' "$TK" | head -c 200)"
TENANT=$(printf '%s' "$TK" | grep -o '"tenant_access_token":"[^"]*"' | cut -d'"' -f4)
if [ -z "$TENANT" ]; then echo "!! 取 token 失败，检查 App ID/Secret"; exit 1; fi
echo
REC=$(curl -s "https://open.feishu.cn/open-apis/bitable/v1/apps/$APP_TOKEN/tables/$TABLE_ID/records?page_size=3" \
  -H "Authorization: Bearer $TENANT")
echo "记录返回: $(printf '%s' "$REC" | head -c 400)"
echo

PW=$(cat /opt/n8n/.owner_password | tr -d '\r\n')
curl -s -c /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"emailOrLdapLoginId":"admin@n8n.local","password":"%s"}' "$PW")" >/dev/null

CRED_ID=$(cat /opt/n8n/.pg_cred_id | tr -d '\r\n')
[ -n "$CRED_ID" ] || { echo "缺少 Postgres 凭据，先跑 create_wf1.sh"; exit 1; }

if [ -f /opt/n8n/.wf1b_id ]; then
  OLD=$(cat /opt/n8n/.wf1b_id | tr -d '\r\n')
  OLD_VER=$(curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/workflows/$OLD" | grep -o '"versionId":"[^"]*"' | head -1 | cut -d'"' -f4)
  curl -s -b /tmp/n8n_cj -X POST "http://127.0.0.1:5678/rest/workflows/$OLD/deactivate" \
    -H 'Content-Type: application/json' -d "$(printf '{"versionId":"%s"}' "$OLD_VER")" >/dev/null
  curl -s -b /tmp/n8n_cj -X DELETE "http://127.0.0.1:5678/rest/workflows/$OLD" >/dev/null
  echo "已删除旧版本 $OLD"
fi

sed "s/__PG_CRED_ID__/$CRED_ID/g" /opt/n8n/workflows/wf1b-feishu-pull.json > /tmp/wf1b.json
WF=$(curl -s -b /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/workflows \
  -H 'Content-Type: application/json' -d @/tmp/wf1b.json)
WF_ID=$(printf '%s' "$WF" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -n "$WF_ID" ] || { echo "工作流创建失败：$WF" | head -c 600; exit 1; }
echo "WF_ID=$WF_ID"
echo "$WF_ID" > /opt/n8n/.wf1b_id

VER=$(curl -s -b /tmp/n8n_cj "http://127.0.0.1:5678/rest/workflows/$WF_ID" \
  | grep -o '"versionId":"[^"]*"' | head -1 | cut -d'"' -f4)
curl -s -b /tmp/n8n_cj -X POST "http://127.0.0.1:5678/rest/workflows/$WF_ID/activate" \
  -H 'Content-Type: application/json' -d "$(printf '{"versionId":"%s"}' "$VER")" | head -c 160
echo
echo "==> 已激活，每 5 分钟拉一次。查看执行：n8n → Executions → WF1b 飞书选题拉取"
