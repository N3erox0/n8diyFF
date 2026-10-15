#!/usr/bin/env bash
# 用数据库 settings 表里的 Key 直连智谱自检（重试 3 次，看真实返回）
ZKEY=$(docker exec n8n-postgres-1 psql -U n8n -d n8n -tAc "select value from settings where key = 'ZHIPU_API_KEY'" | tr -d '\r\n')
echo "key_len=${#ZKEY}  head=$(printf '%s' "$ZKEY" | cut -c1-10)"
for i in 1 2 3; do
  echo "--- 第 $i 次 ---"
  curl -s --max-time 60 https://open.bigmodel.cn/api/paas/v4/chat/completions \
    -H "Authorization: Bearer $ZKEY" -H 'Content-Type: application/json' \
    -d '{"model":"glm-4.7-flash","messages":[{"role":"user","content":"回复两个字：可用"}],"max_tokens":10}'
  echo
  sleep 6
done
