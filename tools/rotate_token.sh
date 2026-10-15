#!/usr/bin/env bash
# 轮换 WF1 的 WEBHOOK_TOKEN（疑似泄露 / 定期更换时用）
# 生成新值 -> 写 .env -> 删除旧 n8n 凭据 -> 重建凭据并重载 WF1 -> 自测
# 用法: bash /opt/n8n/tools/rotate_token.sh
set -e
cd /opt/n8n

echo '== 1/4 生成新 Token 并写入 .env =='
NEW=$(openssl rand -hex 16)
if grep -q '^WEBHOOK_TOKEN=' .env; then
  sed -i "s|^WEBHOOK_TOKEN=.*|WEBHOOK_TOKEN=$NEW|" .env
else
  echo "WEBHOOK_TOKEN=$NEW" >> .env
fi
chmod 600 .env
echo '已写入（不打印明文，需要时: grep WEBHOOK_TOKEN /opt/n8n/.env）'

echo
echo '== 2/4 登录 n8n 并删除旧 Token 凭据 =='
PW=$(cat /opt/n8n/.owner_password | tr -d '\r\n')
curl -s -c /tmp/n8n_cj -X POST http://127.0.0.1:5678/rest/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"emailOrLdapLoginId":"admin@n8n.local","password":"%s"}' "$PW")" >/dev/null
if [ -f /opt/n8n/.token_cred_id ]; then
  OLD=$(cat /opt/n8n/.token_cred_id | tr -d '\r\n')
  curl -s -b /tmp/n8n_cj -X DELETE "http://127.0.0.1:5678/rest/credentials/$OLD" >/dev/null
  rm -f /opt/n8n/.token_cred_id
  echo "已删除旧凭据 $OLD"
else
  echo '没有旧凭据记录，跳过'
fi

echo
echo '== 3/4 重建凭据并重载 WF1 =='
bash /opt/n8n/create_wf1.sh 2>&1 | tail -12

echo
echo '== 4/4 自测（新 Token 应 200，旧 Token 应 401）=='
TOKEN=$(grep '^WEBHOOK_TOKEN=' /opt/n8n/.env | cut -d= -f2 | tr -d '\r\n')
curl -s -o /dev/null -w '新 Token -> HTTP %{http_code}\n' --max-time 30 \
  -X POST http://127.0.0.1:5678/webhook/topic \
  -H 'Content-Type: application/json' -H "X-Token: $TOKEN" \
  -d '{"title":"","url":""}'
curl -s -o /dev/null -w '错误 Token -> HTTP %{http_code}\n' --max-time 30 \
  -X POST http://127.0.0.1:5678/webhook/topic \
  -H 'Content-Type: application/json' -H 'X-Token: 00000000000000000000000000000000' \
  -d '{"title":"","url":""}'
echo '完成'
