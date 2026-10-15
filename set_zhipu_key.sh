#!/usr/bin/env bash
# 用法： bash /opt/n8n/set_zhipu_key.sh 你的智谱APIKey
# 作用：自检 Key（自动挑一个当前不被限流的免费模型）→ 写 .env → 同步数据库 → 重导 WF3
set -e
cd /opt/n8n
KEY=${1:-}
if [ -z "$KEY" ]; then
  echo "用法： bash /opt/n8n/set_zhipu_key.sh 你的智谱APIKey"
  exit 1
fi

echo "==> 1/3 直连智谱自检（自动挑选可用的免费档模型）"
PICK=""
BUSY=0
# 顺序：免费档优先，付费档兜底（充值后自动挑到 glm-5.3）
for M in glm-4-flash glm-4.7-flash glm-5.3-flash glm-5.3-flashx glm-5.3; do
  for i in 1 2; do
    R=$(curl -s --max-time 60 https://open.bigmodel.cn/api/paas/v4/chat/completions \
      -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
      -d "{\"model\":\"$M\",\"messages\":[{\"role\":\"user\",\"content\":\"回复两个字：可用\"}],\"max_tokens\":10}")
    printf '%-16s 第%s次: ' "$M" "$i"; printf '%s' "$R" | head -c 150; echo
    if printf '%s' "$R" | grep -q '"choices"'; then PICK="$M"; break 2; fi
    # 1113 = 需要付费，直接换下一个模型
    if printf '%s' "$R" | grep -q '"1113"'; then break; fi
    # 1305/1302 = 模型忙或账户限流：说明鉴权已通过，只是免费档挤
    if printf '%s' "$R" | grep -qE '"(1305|1302)"'; then BUSY=1; fi
    sleep 6
  done
done

if [ -z "$PICK" ]; then
  if [ "$BUSY" = "1" ]; then
    PICK="glm-4-flash"
    echo "鉴权已通过，但模型此时全部限流（1305/1302）。先按 glm-4-flash 保存，低峰期可自动用上；"
    echo "想改模型： docker exec n8n-postgres-1 psql -U n8n -d n8n -c \"update settings set value='glm-5.3' where key='ZHIPU_MODEL'\""
  else
    echo "!! Key 不可用（Key 错 / 未开通 / 出网被挡）。上面是接口原样返回。"
    exit 1
  fi
fi
echo "选定模型：$PICK"

echo "==> 2/3 写入 .env"
if grep -q '^ZHIPU_API_KEY=' /opt/n8n/.env; then
  sed -i "s|^ZHIPU_API_KEY=.*|ZHIPU_API_KEY=$KEY|" /opt/n8n/.env
else
  echo "ZHIPU_API_KEY=$KEY" >> /opt/n8n/.env
fi
if grep -q '^ZHIPU_MODEL=' /opt/n8n/.env; then
  sed -i "s|^ZHIPU_MODEL=.*|ZHIPU_MODEL=$PICK|" /opt/n8n/.env
else
  echo "ZHIPU_MODEL=$PICK" >> /opt/n8n/.env
fi
chmod 600 /opt/n8n/.env
echo "已写入（文件权限 600）"

echo "==> 3/3 同步密钥到数据库并重导 WF3"
bash /opt/n8n/seed_keys.sh
bash /opt/n8n/create_wf3.sh
