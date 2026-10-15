#!/usr/bin/env bash
# 逐个试智谱的免费档模型，看哪个当前不被限流
ZKEY=$(docker exec n8n-postgres-1 psql -U n8n -d n8n -tAc "select value from settings where key = 'ZHIPU_API_KEY'" | tr -d '\r\n')
for M in glm-4.7-flash glm-4.5-flash glm-4.5-air glm-4.6; do
  printf '%-16s' "$M"
  R=$(curl -s --max-time 45 https://open.bigmodel.cn/api/paas/v4/chat/completions \
    -H "Authorization: Bearer $ZKEY" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$M\",\"messages\":[{\"role\":\"user\",\"content\":\"回复两个字：可用\"}],\"max_tokens\":10}")
  printf '%s' "$R" | head -c 160
  echo
  sleep 6
done
