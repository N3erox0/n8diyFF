#!/usr/bin/env bash
# 实测稿：真人体验视角写 Grok Bot（素材 = 作者实测手记 + 调研报告摘要）
# 跑 WF1→WF2→WF3 并导出成品
cd /opt/n8n
TOKEN=$(grep '^WEBHOOK_TOKEN=' /opt/n8n/.env | cut -d= -f2 | tr -d '\r\n')

python3 - "$TOKEN" <<'PY'
import json, sys, urllib.request, urllib.error

BASE = 'http://127.0.0.1:5678'
TOKEN = sys.argv[1]

SRC1 = """【素材性质】作者本人实测手记（第一人称，真实体验，配图见占位标记）。
【登录卡点】首先是下载和账号登录这一关。Grok Bot 客户端对账号有门槛，幸好我是 Cursor 用户，直接用 Cursor 账号顺利登录，没有额外折腾。客户端覆盖 Windows、macOS、Linux 桌面端和 iOS 手机端。说实话，下载之前我读到不少负面评价——有人说它不如 Meta 的 Muse，有人说功能不如国内 Agent，我是带着挑刺的心态装的。【配图：客户端图标】
【UI 惊艳】客户端打开之后，第一感受是 UI 交互惊艳：富有互动性的极简风，对话应答时那只小毛球的眼睛会转啊转，UX 是弹球风格，很像那个黑色弹球的音乐游戏，手感极好。【配图：对话界面】
【克制的反馈】对话过程全程简洁。它不会给我展示一大堆"调用了 a、b、c、d"的代码滚来滚去，没头没尾没完没了；反而会告诉我"已经在干嘛了，一会回来"。这非常符合用户预期：我交给你，我在手机上看结果。相比之下，国内很多 Agent 还是"端侧的任务端侧看"——手机端看不到云主机上的任务，甚至同一个账号在不同终端上任务列表都不互通。多端打通这一点必须好评。
【细节】传输 key 时会有一个单独的加密输入框，体感舒适。它可以接得住一段话里的多个问题，也接得住连续多次发送，像个贴心的男朋友，句句有回应、件件有着落。
【实测任务】任务指导也不在话下：我远程指导它完成了飞书订阅消息推送的配置，以及用 lark-cli 往多维表格写入数据。
【唯一遗憾】一个下午，快乐的 5 个小时，免费额度就告罄了，提示我升级付费。【配图：额度告罄提示条】"""

SRC2 = """【素材性质】产品背景要点（基于公开报道整理，供事实支撑，勿引用为"据官网称"）。
【产品定位】Grok Bot 是 xAI 于 2026 年 8 月 11 日推出的 AI 智能体产品，定位"AI 队友/数字员工"，不再是聊天机器人：每个 Bot 自带一台持久化云端 Linux 虚拟机（约 8 核 16G 内存、120GB SSD，含浏览器、文件系统、终端），可 24/7 离线自主执行任务。xAI 于 2026 年 2 月被 SpaceX 收购，公司后更名为 SpaceXSI。
【关键时间线】2026.8.11 公测（绑定 SuperGrok Heavy / Cursor Ultra 等高门槛订阅）→ 9.1 门槛降至 20 美元/月（Cursor Pro 档）→ 10.7 接入 Claude Opus 5.5 / Midjourney / Suno 动态模型路由（用户免付 API 费）→ 10.10 推出专属邮箱 @mail.grokbot.com → 10.12 推出 X Subscription 统一订阅（8-200 美元四档，X Premium + Grok + Grok Bot + Cursor 打包）→ 10.13 演示自主购物闭环（Stripe 一次性虚拟卡）→ 10.14 Grok Imagine Video 1.5 音乐视频发布。
【核心功能】Teach-a-Task 录屏教学（演示一遍流程，Bot 自动学会重复执行）；多 Bot 群聊协作（像拉微信群一样组一支 AI 团队）；Computer Use 视觉操作无 API 的网页；Routines 定时任务；专属邮箱；自主购物；支持支付宝/微信支付人民币结算；开源微信插件可把 AI 变成微信好友。多端覆盖 macOS/Windows/Linux/iOS/Android，移动端可接管会话。
【竞争背景】2026 年 Agent 元年：Meta Muse（9.8 发布，免费档更宽松、隔离 VM 更安全但被动）、OpenAI Dots（9.29 发布，插件生态强）同期竞发；Grok Bot 是首个"模型聚合器"型智能体，按任务自动路由到对手最强模型，被解读为对 OpenAI 的围剿。"""

SRC3 = """【素材性质】口碑与争议要点（基于公开报道整理，用于对比与平衡视角）。
【负面评价参考1·虎嗅实测】虎嗅《马斯克吹爆的AI员工，我用完只想仅退款》：实测发现营销与实际落差大——订票比价任务翻车（推荐凌晨 4 点赶飞机的不合理航班）、回复充满"AI 味"碎句、任务易陷入"混沌循环"；结论是"昂贵的实验品"，更像开箱即用的数字办公室，适合个人开发者和小微企业，尚不能替代人类复杂决策。
【负面评价参考2·Reddit 横评】r/AI_Agents 热帖《Grok Bot vs Muse: 20 hours with both》：Grok Bot 更聪明、更主动，擅长代码/仪表盘/监控等复杂任务，但额度消耗极快——重度使用 3-4 小时耗尽周额度，有用户单日花费 500 美元；Muse 更便宜（免费档每周 100M token）、更安全（隔离 VM + 审批机制）但较被动。社区结论：技术流选 Grok Bot，生活流选 Muse。
【其他槽点】价格贵（入门 20-30 美元/月，旗舰 200-300 美元/月）；模型自动路由，用户无选择权；中文语境自然度逊于豆包、Kimi 等国产模型；生活服务类任务（订票比价）不如国内成熟 App。
【安全争议】2025.8 有 37 万条共享聊天记录被搜索引擎索引泄露；2026.10 有 XMTP CEO 的 Bot 把个人银行数据误发到公司 Slack——根因是同账号多个 Bot 共享同一云电脑环境，"只读"不等于"私有"；另有英国 ICO/Ofcom、爱尔兰 DPC 监管调查与生物识别集体诉讼。这些是评估"该给它多少权限"时必须知道的背景。"""

payload = {
    "title": "Grok Bot 实测：一个下午之后，我想让它常驻桌面",
    "angle": "真人实测视角：从下载登录的卡点，到被 UI 和多端体验打动，最后到免费额度告罄；穿插与国内 Agent、Muse、国产模型的对比",
    "direction": "AI工具",
    "keywords": ["Grok Bot", "AI智能体", "实测", "多端", "微信"],
    "brief": "第一人称实测文，科技博主风，语气简洁流畅不堆砌。结构建议：1) 下载与登录卡点（Cursor 账号救场），先讲「带着负面评价入场」；2) UI 交互惊艳（极简风、眼睛转动、弹球式 UX）；3) 克制的任务反馈与多端互通（对比国内 Agent 端侧任务不互通的痛点）；4) 实测任务（飞书订阅推送、lark-cli 多维表）；5) 免费额度 5 小时告罄；6) 对比环节（与 Muse、国内 Agent、豆包/Kimi，引虎嗅与 Reddit 横评的观点做平衡）；7) 结尾升华：遥想微信当年的极简产品理念（把复杂功能藏进聊天框）与 iPhone 滑窗解锁当年的惊艳体感，好的产品都是「顺手」的；8) 结论：如果经济允许，我愿意让这个小毛球常驻我的桌面。文中【配图】占位标记保留，发布时人工补图。不要编造素材之外的数据。",
    "pushed_by": "manual",
    "sources": [
        {"url": "https://unite.ai/xai-launches-grok-bot-always-on-ai-teammates-with-their-own-cloud-computers", "title": "作者实测手记（第一人称，非该页原文）", "content": SRC1},
        {"url": "https://m.36kr.com/p/4017776872312966", "title": "产品背景要点（基于公开报道整理）", "content": SRC2},
        {"url": "https://m.huxiu.com/article/4897154.html", "title": "口碑与争议要点（基于公开报道整理）", "content": SRC3}
    ]
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

print('素材字数:', len(SRC1), len(SRC2), len(SRC3))
code, txt = post('/webhook/topic', payload, {'X-Token': TOKEN})
print('WF1:', code, txt[:200])
if code != 202:
    sys.exit('WF1 失败')
tid = json.loads(txt).get('topic_id')
print('topic_id =', tid)

print('WF2 写稿中...')
code, txt = post('/webhook/write', {'topic_id': tid})
print('WF2:', code, txt[:250])

print('WF3 核查+排版...')
code, txt = post('/webhook/review', {'topic_id': tid})
print('WF3:', code, txt[:400])
PY

bash /opt/n8n/export_final.sh
docker exec -i n8n-postgres-1 psql -U n8n -d n8n <<'SQL'
\pset pager off
select id, decision, length(coalesce(body_md,'')) as md_len from finals order by id desc limit 3;
SQL
