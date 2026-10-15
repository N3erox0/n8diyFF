#!/usr/bin/env bash
# 跳过飞书：本地手动推送一条 Grok Bot 选题，跑完 WF1→WF2→WF3，并打印成品
# 素材为人工整理（非原站抓取），仅用于联调；正式内容由采集端补齐原文
cd /opt/n8n
TOKEN=$(grep '^WEBHOOK_TOKEN=' /opt/n8n/.env | cut -d= -f2 | tr -d '\r\n')

python3 - "$TOKEN" <<'PY'
import json, sys, urllib.request, urllib.error

BASE = 'http://127.0.0.1:5678'
TOKEN = sys.argv[1]

CONTENT = """【素材性质】人工整理的背景资料，用于联调流水线，非原站抓取，发布前需复核。
【要点1】Grok 由 xAI 开发，直接内置在 X（原 Twitter）里：用户在时间线、评论区 @grok 即可调用，不需要额外安装 App，也不用注册新账号。
【要点2】模型迭代：Grok-1、Grok-2 之后，2025 年发布 Grok 3，主打推理能力，提供 Think（深度推理）与 Big Brain（更大算力）两种模式；随后 Grok 4 于 2025 年 7 月发布。
【要点3】功能形态：除对话外还有 DeepSearch（多步检索、给出带引用的综述）、语音模式，以及 Grok Imagine（文生图与视频）；xAI 还推出过百科式产品 Grokipedia。
【要点4】接入方式：普通用户通过 X 的订阅档位获得使用额度，开发者通过 x.ai 提供的 API 调用，模型名形如 grok-4、grok-3。
【要点5】风险面：Grok 曾因回答失控引发公关风波，说明把大模型直接嵌进社交平台，内容安全与品牌风险会被同步放大——这对任何想在产品里内置对话式 AI 的团队都是提醒。
【建议落点】从产品经理视角看：把 AI 助手嵌进社交平台，换来极低的分发成本，也把模型的全部不确定性直接暴露在公共舆论场。"""

payload = {
    "title": "Grok Bot：把 AI 助手塞进社交平台，换来的是什么",
    "angle": "从产品收益与风险暴露的双视角看内置式 AI 助手",
    "direction": "AI行业",
    "keywords": ["Grok", "xAI", "AI助手", "社交平台"],
    "brief": "联调用选题。素材为人工整理，非目标网页原文，稿件中不要写“据官网称”这类引用句式。",
    "pushed_by": "manual",
    "sources": [{
        "url": "https://x.ai/",
        "title": "人工整理：Grok Bot 背景资料（非该页原文）",
        "content": CONTENT
    }]
}

def post(path, body, extra=None):
    h = {'Content-Type': 'application/json'}
    if extra:
        h.update(extra)
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode('utf-8'), headers=h, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            return r.status, r.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')

print('素材字数:', len(CONTENT))
code, txt = post('/webhook/topic', payload, {'X-Token': TOKEN})
print('WF1 接收:', code, txt[:300])
if code != 202:
    sys.exit('WF1 失败')
tid = json.loads(txt).get('topic_id')
print('topic_id =', tid)

print('WF2 写稿中（DeepSeek 提纲+成文，约 1-3 分钟）...')
code, txt = post('/webhook/write', {'topic_id': tid})
print('WF2:', code, txt[:300])

print('WF3 核查+排版...')
code, txt = post('/webhook/review', {'topic_id': tid})
print('WF3:', code, txt[:600])
PY

docker exec -i n8n-postgres-1 psql -U n8n -d n8n <<'SQL'
\pset pager off
select id, decision, length(coalesce(body_md,'')) as md_len, length(coalesce(body_html,'')) as html_len from finals order by id desc limit 3;
SQL
