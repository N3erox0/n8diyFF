#!/usr/bin/env bash
# 把 .env 里的模型 Key 同步进数据库 settings 表
# 工作流运行时从 settings 表读密钥（不用 n8n 凭据，换 Key 不必重导工作流）
cd /opt/n8n

docker exec n8n-postgres-1 psql -U n8n -d n8n -q -c \
  "CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT, updated_at TIMESTAMPTZ DEFAULT now());" >/dev/null
docker exec n8n-postgres-1 psql -U n8n -d n8n -q -c \
  "ALTER TABLE settings ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();" >/dev/null

seed() {
  local k=$1 v=$2
  [ -z "$v" ] && return
  docker exec n8n-postgres-1 psql -U n8n -d n8n -q -c \
    "INSERT INTO settings(key, value) VALUES('$k', '$v') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();"
}

DSK=$(grep '^DEEPSEEK_API_KEY=' /opt/n8n/.env | cut -d= -f2- | tr -d '\r\n ')
ZHK=$(grep '^ZHIPU_API_KEY=' /opt/n8n/.env | cut -d= -f2- | tr -d '\r\n ')
ZM=$(grep '^ZHIPU_MODEL=' /opt/n8n/.env | cut -d= -f2- | tr -d '\r\n ')
[ -z "$ZM" ] && ZM=glm-4-flash   # 实测：付费档(glm-5.x/glm-4.7/4.6/4.5)在余额不足时全部返回 429/1113，免费档仅 glm-4-flash 稳定可用
seed DEEPSEEK_API_KEY "$DSK"
seed ZHIPU_API_KEY "$ZHK"
seed ZHIPU_MODEL "$ZM"

echo "settings 已同步：DeepSeek=$([ -n "$DSK" ] && echo 已配置 || echo 未配置)，智谱=$([ -n "$ZHK" ] && echo 已配置 || echo 未配置)"
