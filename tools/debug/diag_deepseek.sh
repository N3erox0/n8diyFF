#!/usr/bin/env bash
# 直接用 .env 里的 Key 打一次 DeepSeek，看真实返回（余额/Key/模型名 一眼看出）
DSK=$(grep '^DEEPSEEK_API_KEY=' /opt/n8n/.env | cut -d= -f2- | tr -d '\r\n')
echo "key_len=${#DSK}  key_head=$(printf '%s' "$DSK" | cut -c1-6)"
echo "--- 调用 deepseek-flash ---"
curl -s --max-time 40 https://api.deepseek.com/chat/completions \
  -H "Authorization: Bearer $DSK" -H 'Content-Type: application/json' \
  -d '{"model":"deepseek-flash","messages":[{"role":"user","content":"回复两个字：可用"}],"max_tokens":10}'
echo
echo "--- 余额查询 ---"
curl -s --max-time 30 https://api.deepseek.com/user/balance -H "Authorization: Bearer $DSK"
echo
