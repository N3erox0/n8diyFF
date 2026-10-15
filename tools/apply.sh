#!/usr/bin/env bash
# 一键应用：密钥入库 -> 重导 WF2/WF3 -> 触发一次 WF3 核查 -> 打印结果
# 用法: bash /opt/n8n/tools/apply.sh
set -u
cd /opt/n8n

echo '== 1/4 同步密钥与模型到 settings 表 =='
bash tools/seed_keys.sh

echo
echo '== 2/4 重导工作流 =='
bash create_wf2.sh >/dev/null 2>&1 && echo 'WF2 已导入' || echo 'WF2 导入失败'
bash create_wf3.sh >/dev/null 2>&1 && echo 'WF3 已导入' || echo 'WF3 导入失败'

echo
echo '== 3/4 当前配置 =='
docker exec n8n-postgres-1 psql -U n8n -d n8n -tAc \
  "select key || ' = ' || left(coalesce(value,''),32) from settings order by key"

echo
echo '== 4/4 触发一次核查（最近一个选题）=='
TID=$(docker exec n8n-postgres-1 psql -U n8n -d n8n -tAc \
  "select topic_id from topics order by id desc limit 1")
echo "topic_id = $TID"

curl -s -o /tmp/review.out -w 'webhook HTTP %{http_code}\n' --max-time 180 \
  -X POST http://127.0.0.1:5678/webhook/review \
  -H 'Content-Type: application/json' \
  -d "{\"topic_id\":\"$TID\"}"
echo '--- webhook 返回 ---'
head -c 500 /tmp/review.out; echo

echo '--- finals 成品表 ---'
docker exec n8n-postgres-1 psql -U n8n -d n8n -c \
  "select id, topic_id, decision, length(coalesce(body_html,'')) as html_len, length(coalesce(facts::text,'')) as facts_len from finals order by id desc limit 3;"
