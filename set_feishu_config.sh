#!/usr/bin/env bash
# 用法： bash /opt/n8n/set_feishu_config.sh <AppID> <AppSecret> <app_token或整段网址> <table_id>
# 容错：第 3、4 个值直接粘整条网址/带 ?table&view 的碎片也能自动提取
set -e
cd /opt/n8n

clean() { printf '%s' "$1" | tr -d '\r\n"' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
A=$(clean "${1:-}"); B=$(clean "${2:-}"); C=$(clean "${3:-}"); D=$(clean "${4:-}")

# App ID：提取 cli_ 开头段
A=$(printf '%s' "$A" | grep -oE 'cli_[A-Za-z0-9]+' | head -1)
# app_token：取 /base/ 之后、? 或 & 之前
T=$(printf '%s' "$C" | sed -E 's|^.*/base/||; s|[?&].*$||; s|/$||')
# table_id：提取 tbl 开头段（第 4 个值优先，空则从第 3 个值里找）
D=$(printf '%s' "$D" | grep -oE 'tbl[A-Za-z0-9]+' | head -1)
[ -z "$D" ] && D=$(printf '%s' "$C" | grep -oE 'tbl[A-Za-z0-9]+' | head -1)

echo "==> 解析结果"
echo "  App ID    = $A"
echo "  AppSecret = $([ -n "$B" ] && echo '已填(不显示)' || echo '空')"
echo "  app_token = $T"
echo "  table_id  = $D"

if [ -z "$A" ] || [ -z "$B" ] || [ -z "$T" ] || [ -z "$D" ]; then
  echo "!! 有值没解析出来（AppID 要 cli_ 开头，table_id 要 tbl 开头）"
  exit 1
fi

write() {
  local key=$1 val=$2
  if grep -q "^$key=" /opt/n8n/.env; then
    sed -i "s|^$key=.*|$key=$val|" /opt/n8n/.env
  else
    echo "$key=$val" >> /opt/n8n/.env
  fi
}

write FEISHU_APP_ID "$A"
write FEISHU_APP_SECRET "$B"
write FEISHU_APP_TOKEN "$T"
write FEISHU_TABLE_ID "$D"
chmod 600 /opt/n8n/.env
echo ".env 已写入（覆盖旧值）"

echo "==> 部署 WF1b（含飞书 API 连通自检）"
bash /opt/n8n/create_wf1b.sh
