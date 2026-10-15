# 公众号草稿生产线 · 当前状态（2026-10-14）

服务器：腾讯云 Lighthouse `175.178.120.171`（OpenCloudOS，2C4G + 2G Swap）

## 分工（已定）

```
【采集 · Agent】  Grok Bot(X) / WorkBuddy(国内文章)  →  抓原文 + 推送选题
【加工 · n8n】    接收 → 成文 → 核查 → 排版 → 回传
【决策 · 你】     飞书表里挑选题、审成品
```

n8n **不抓网页**（国内服务器抓不了海外站点，已实测 `r.jina.ai` 超时），正文由推送方随选题一起带来。

## 进度

| 组件 | 状态 |
|---|---|
| n8n 2.42.4 + Postgres 16 | ✅ 运行中 |
| WF1 选题接收通路（含 Token 鉴权） | ✅ 已激活，自测 403/202/409/400 全过 |
| ~~WF1b 飞书选题拉取~~ | 🚫 本地环境禁止调用飞书，已跳过（脚本保留在 `create_wf1b.sh`） |
| WF2 写稿流水线 | ✅ 已激活，已产出成稿（DeepSeek，2554 字） |
| 接口文档 | ✅ `docs/intake-api.md` |
| DeepSeek Key | ✅ 已配置（余额 19.83） |
| WF3 核查 → 排版 → 审核 → 成品入库 | ✅ 已激活，成品已入库（Markdown 2554 字 / HTML 4906） |
| 智谱 Key | ✅ 已配置，模型 `glm-4.5-flash`（4.7-flash 免费档常被限流 1305/1302，可在 `settings` 表一键切） |
| 事实核查 | ✅ 真实生效：两篇成稿均 `risk=low / 0 存疑 / approved` |

> 密钥存放方式：**不用 n8n 凭据**，改为存进 Postgres `settings` 表、工作流运行时读取
> （原因：n8n 凭据里的 Key 实测没被用上，一直 401；换 Key 也不用重导工作流）
> 同步命令：`bash /opt/n8n/seed_keys.sh`

## 进界面

```bash
ssh -L 5678:127.0.0.1:5678 root@175.178.120.171
# http://localhost:5678   admin@n8n.local / N8n#d90fdfb243
```

## 待办

1. 配飞书：建自建应用 + 多维表格 + 加协作者 → 填 `.env` 四个值 → `bash /opt/n8n/create_wf1b.sh`
2. n8n → Credentials → `DeepSeek API` → 换成 `Bearer sk-真Key`（**单独新建一个 Key，别共用**）
2. 验证：`ssh root@175.178.120.171 "bash /opt/n8n/test_all.sh"` → `drafts` 表应出现成稿
3. 决定公网入口（现在 5678 未放行）：放行端口 / Cloudflare Tunnel / 飞书表中转

## 模型

| 档位 | 模型 | 状态 |
|---|---|---|
| 成文（精活） | DeepSeek `deepseek-flash` | ✅ 已接 |
| 核查（精活） | 智谱 GLM | ✅ 已跑通，当前 `glm-4-flash`（免费档）；充值后切 `glm-5.3`：`update settings set value='glm-5.3' where key='ZHIPU_MODEL'`（不用重导工作流） |
| 粗活 | 硅基流动免费模型池 | 待接 |

详见 `docs/models-guide.md`（含服务器实测连通性、三档分工、不推荐清单）。

## 关键命令

```bash
# 重部署 WF1（会重建工作流）
ssh root@... "bash /opt/n8n/create_wf1.sh"
# 重部署 WF2
ssh root@... "bash /opt/n8n/create_wf2.sh"
# 端到端联调
ssh root@... "bash /opt/n8n/test_all.sh"
# 配 DeepSeek Key（自带连通性自检）
ssh root@... "bash /opt/n8n/set_deepseek_key.sh sk-你的Key"
# 配智谱 Key（自带连通性自检）——或双击 4-配置智谱.bat
ssh root@... "bash /opt/n8n/set_zhipu_key.sh 你的Key"
# 跳过飞书、本地手动投喂选题跑全流程
ssh root@... "bash /opt/n8n/demo_grok.sh"
# 导出最新成品（Markdown + 公众号 HTML）到 out/
ssh root@... "bash /opt/n8n/export_final.sh"
# 测各家模型 API 从本机能不能出去
ssh root@... "bash /opt/n8n/check_api.sh"
# 查 Token
ssh root@... "grep WEBHOOK_TOKEN /opt/n8n/.env"
# 备份
ssh root@... "docker exec n8n-postgres-1 pg_dump -U n8n n8n > /opt/n8n/n8n_$(date +%F).sql"
```

## 安全

- `N8N_ENCRYPTION_KEY` 在 `/opt/n8n/.env`（600），**异地备份**，丢了所有凭据全废
- Webhook 有 `X-Token` 鉴权，令牌加密存在 n8n 凭据里
- n8n 近半年连续爆 CVSS 10.0，实例里存着所有 API Token，别裸奔公网
