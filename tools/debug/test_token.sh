#!/usr/bin/env bash
# 验证 WF1 的 X-Token 鉴权：无 Token / 当前 Token / 指定旧 Token 各打一次
# 用法: bash /opt/n8n/tools/debug/test_token.sh [旧Token]
cd /opt/n8n

NEW=$(grep '^WEBHOOK_TOKEN=' .env | cut -d= -f2 | tr -d '\r\n')
OLD=${1:-}
PAYLOAD='{"title":"轮换验证选题","angle":"a","direction":"d","keywords":["k"],"brief":"b","pushed_by":"manual","sources":[{"url":"https://example.com/x","title":"t","content":"c"}]}'

post() {
  if [ -z "$1" ]; then
    curl -s -o /tmp/tk.out -w '%{http_code}' --max-time 30 \
      -X POST http://127.0.0.1:5678/webhook/topic \
      -H 'Content-Type: application/json' -d "$PAYLOAD"
  else
    curl -s -o /tmp/tk.out -w '%{http_code}' --max-time 30 \
      -X POST http://127.0.0.1:5678/webhook/topic \
      -H 'Content-Type: application/json' -H "X-Token: $1" -d "$PAYLOAD"
  fi
}

printf '无 Token      -> HTTP %s\n' "$(post '')"
printf '当前 Token    -> HTTP %s\n' "$(post "$NEW")"
if [ -n "$OLD" ]; then
  printf '指定旧 Token  -> HTTP %s  (403 = 已作废)\n' "$(post "$OLD")"
fi
echo '--- 最后一次响应体 ---'
head -c 200 /tmp/tk.out; echo
