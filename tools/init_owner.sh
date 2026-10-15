#!/usr/bin/env bash
# 创建 n8n owner 账号 + 初始化数据库表
set -e
cd /opt/n8n

if curl -s http://127.0.0.1:5678/rest/settings | grep -q '"showSetupOnFirstLoad":true'; then
  PW="N8n#$(openssl rand -hex 5)"
  echo "==> 创建 owner 账号"
  curl -s -X POST http://127.0.0.1:5678/rest/owner/setup \
    -H 'Content-Type: application/json' \
    -d "$(printf '{"email":"admin@n8n.local","firstName":"Admin","lastName":"Ops","password":"%s"}' "$PW")" \
    | head -c 300
  echo
  echo "OWNER_EMAIL=admin@n8n.local"
  echo "OWNER_PASSWORD=$PW"
  echo "$PW" > /opt/n8n/.owner_password
  chmod 600 /opt/n8n/.owner_password
else
  echo "owner 已存在，跳过"
fi

echo "==> 初始化数据表"
docker exec -i n8n-postgres-1 psql -U n8n -d n8n < /opt/n8n/sql/init.sql
docker exec n8n-postgres-1 psql -U n8n -d n8n -c '\dt'
