#!/usr/bin/env bash
# 导出最新一篇成品：Markdown 正文 + 公众号排版 HTML
mkdir -p /opt/n8n/out
docker exec -i n8n-postgres-1 psql -U n8n -d n8n -At <<'SQL' > /opt/n8n/out/grok-bot.md
select body_md from finals order by id desc limit 1;
SQL
docker exec -i n8n-postgres-1 psql -U n8n -d n8n -At <<'SQL' > /opt/n8n/out/grok-bot.html
select '<meta charset="utf-8"><div style="max-width:680px;margin:20px auto">' || body_html || '</div>' from finals order by id desc limit 1;
SQL
wc -c /opt/n8n/out/grok-bot.md /opt/n8n/out/grok-bot.html
