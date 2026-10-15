#!/usr/bin/env bash
# 从本机实测各家模型 API 连通性：401/400/422 = 可达；000 = 出不去（被墙或超时）
for U in \
  https://api.deepseek.com/chat/completions \
  https://open.bigmodel.cn/api/paas/v4/chat/completions \
  https://api.siliconflow.cn/v1/chat/completions \
  https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions \
  https://openrouter.ai/api/v1/chat/completions ; do
  C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 -X POST "$U" \
      -H 'Content-Type: application/json' -d '{}')
  printf '%-70s %s\n' "$U" "$C"
done
