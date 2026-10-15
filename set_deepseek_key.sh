#!/usr/bin/env bash
# 用法： bash /opt/n8n/set_deepseek_key.sh sk-你的Key
# 作用：直连自检 Key → 写入 .env → 重建 n8n 凭据 → 重导并激活 WF2
set -e
cd /opt/n8n
KEY=${1:-}
if [ -z "$KEY" ]; then
  echo "用法： bash /opt/n8n/set_deepseek_key.sh sk-你的Key"
  exit 1
fi

echo "==> 1/3 直连 DeepSeek 自检"
R=$(curl -s --max-time 30 https://api.deepseek.com/chat/completions \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"deepseek-flash","messages":[{"role":"user","content":"回复两个字：可用"}],"max_tokens":10}')
printf '%s' "$R" | head -c 300
echo
if ! printf '%s' "$R" | grep -q '"choices"'; then
  echo "!! Key 不可用（Key 错 / 余额为 0 / 服务器出网被墙）。上面是接口原样返回。"
  exit 1
fi
echo "Key 可用"

echo "==> 2/3 写入 .env"
if grep -q '^DEEPSEEK_API_KEY=' /opt/n8n/.env; then
  sed -i "s|^DEEPSEEK_API_KEY=.*|DEEPSEEK_API_KEY=$KEY|" /opt/n8n/.env
else
  echo "DEEPSEEK_API_KEY=$KEY" >> /opt/n8n/.env
fi
chmod 600 /opt/n8n/.env
echo "已写入（文件权限 600）"

echo "==> 3/3 同步密钥到数据库并重导 WF2"
bash /opt/n8n/seed_keys.sh
bash /opt/n8n/create_wf2.sh
