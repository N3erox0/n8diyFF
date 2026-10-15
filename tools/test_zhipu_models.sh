#!/usr/bin/env bash
# 测试智谱 GLM 各版本的可用性：拉官方模型清单 -> 逐个最小调用探测
# 用法: bash tools/test_zhipu_models.sh
set -u

KEY=$(docker exec n8n-postgres-1 psql -U n8n -d n8n -tAc \
  "select coalesce((select value from settings where key='ZHIPU_API_KEY'),'')")

if [ -z "$KEY" ]; then
  echo "未配置 ZHIPU_API_KEY，先运行: bash windows/../set_zhipu_key.sh <你的Key>"
  exit 1
fi
echo "Key 长度: ${#KEY}"

echo
echo "== 官方模型清单 (open.bigmodel.cn) =="
curl -s --max-time 25 https://open.bigmodel.cn/api/paas/v4/models \
  -H "Authorization: Bearer $KEY" > /tmp/zmodels.json

python3 - <<'PY'
import json
try:
    d = json.load(open('/tmp/zmodels.json'))
except Exception as e:
    print('清单解析失败:', e)
    raise SystemExit(1)
ms = d.get('data') or []
ids = [m.get('id') for m in ms if isinstance(m, dict) and m.get('id')]
print('共 %d 个: %s' % (len(ids), ', '.join(ids)))
open('/tmp/zids.txt', 'w').write('\n'.join(ids))
PY

[ -s /tmp/zids.txt ] || exit 1

echo
echo "== 逐个探测（max_tokens=300，看真实 content）=="
while read -r M; do
  [ -z "$M" ] && continue
  CODE=$(curl -s -o /tmp/z.out -w '%{http_code}' --max-time 60 \
    https://open.bigmodel.cn/api/paas/v4/chat/completions \
    -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$M\",\"messages\":[{\"role\":\"user\",\"content\":\"只回复OK两个字母\"}],\"max_tokens\":300}")
  python3 - "$M" "$CODE" <<'PY'
import json, sys
m, code = sys.argv[1], sys.argv[2]
try:
    d = json.load(open('/tmp/z.out'))
except Exception:
    print('%-16s HTTP %s :: (非JSON) %s' % (m, code, open('/tmp/z.out').read()[:120]))
    raise SystemExit
if 'error' in d:
    print('%-16s HTTP %s :: 失败 %s %s' % (m, code, d['error'].get('code'), d['error'].get('message')))
else:
    msg = (d.get('choices') or [{}])[0].get('message', {})
    c = (msg.get('content') or '').strip()
    r = (msg.get('reasoning_content') or '').strip()
    print('%-16s HTTP %s :: content=%r %s' % (m, code, c[:40], ('思考链%d字' % len(r)) if r else ''))
PY
done < /tmp/zids.txt

echo
echo "== 免费模型 JSON 模式测试（核查节点要用 response_format=json_object）=="
for M in glm-4.7-flash glm-5.3-flash glm-5.3-flashx glm-5-turbo glm-4-flash; do
  CODE=$(curl -s -o /tmp/z2.out -w '%{http_code}' --max-time 60 \
    https://open.bigmodel.cn/api/paas/v4/chat/completions \
    -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$M\",\"messages\":[{\"role\":\"user\",\"content\":\"输出JSON:{\\\"ok\\\":true}\"}],\"response_format\":{\"type\":\"json_object\"},\"max_tokens\":400}")
  BODY=$(python3 -c "
import json
try:
    d=json.load(open('/tmp/z2.out'))
    m=(d.get('choices') or [{}])[0].get('message',{})
    print(repr((m.get('content') or '')[:60]))
except Exception as e:
    print(open('/tmp/z2.out').read()[:120])
")
  printf 'JSON %-16s HTTP %s :: %s\n' "$M" "$CODE" "$BODY"
done
