#!/usr/bin/env bash
# 端到端联调：WF1 收选题 → WF2 写稿（无 Key 时应在 DeepSeek 调用处失败，属预期）
cd /opt/n8n

docker exec n8n-postgres-1 psql -U n8n -d n8n -c "DELETE FROM finals; DELETE FROM drafts; DELETE FROM topic_sources; DELETE FROM topics;" >/dev/null

TOKEN=$(grep '^WEBHOOK_TOKEN=' /opt/n8n/.env | cut -d= -f2 | tr -d '\r\n')

RESP=$(curl -s -X POST http://127.0.0.1:5678/webhook/topic -H 'Content-Type: application/json' -H "X-Token: $TOKEN" \
  -d '{"title":"测试选题：n8n 自托管的安全代价","angle":"从连续 CVSS 10.0 看自托管","direction":"AI 自动化","keywords":["n8n","安全"],"brief":"测试接收通路","pushed_by":"manual","sources":[{"url":"https://example.com/n8n-cve","title":"n8n 漏洞通报","content":"2026 年上半年，n8n 连续披露多个 CVSS 10.0 级别漏洞，包括 CVE-2026-21858（Ni8mare，未认证远程代码执行）、CVE-2026-21877（任意文件写入）与 CVE-2026-1470（工作流表达式 RCE）。由于 n8n 通常集中保存企业的 API Token、OAuth 凭据与数据库密钥，一旦实例被攻陷，影响范围往往覆盖半个基础设施。官方建议自托管用户尽快升级到 1.123.17、2.4.5、2.5.1 及以上版本，并避免将 Webhook 与表单端点直接暴露到公网。"}]}')
echo "WF1 => $RESP"
TID=$(printf '%s' "$RESP" | grep -o '"topic_id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "TID=$TID"

echo "WF2 =>"
curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:5678/webhook/write \
  -H 'Content-Type: application/json' -d "$(printf '{"topic_id":"%s"}' "$TID")"

echo "--- topics ---"
docker exec n8n-postgres-1 psql -U n8n -d n8n -c "SELECT topic_id, left(title,24) AS title, status FROM topics;"
echo "--- topic_sources ---"
docker exec n8n-postgres-1 psql -U n8n -d n8n -c "SELECT topic_id, url, length(content) AS content_len FROM topic_sources;"
echo "--- drafts ---"
docker exec n8n-postgres-1 psql -U n8n -d n8n -c "SELECT id, topic_id, status, length(coalesce(body_md,'')) AS body_len FROM drafts;"

echo "WF3 =>"
curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:5678/webhook/review \
  -H 'Content-Type: application/json' -d "$(printf '{"topic_id":"%s"}' "$TID")"

echo "--- finals ---"
docker exec n8n-postgres-1 psql -U n8n -d n8n -c "SELECT id, topic_id, decision, length(coalesce(body_html,'')) AS html_len FROM finals;"
