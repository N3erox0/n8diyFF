# 技术文档

> 公众号草稿生产线 · n8n 自托管 · 2026-10-14 首次跑通
> 交互图见 [`architecture.md`](./architecture.md)

---

## 1. 它解决什么

选题从"采集"到"可发布成品"之间的手工活，全部自动化：

```
采集端给选题和原文 → 成文 → 事实核查 → 公众号排版 → 风险判定 → 成品落库
```

设计上坚持三条：

1. **n8n 不抓网页**。国内服务器抓海外站点实测超时，正文由推送方随选题带来（≥200 字，否则 422 拒写）。
2. **写入必须鉴权**。`/webhook/topic` 带 `X-Token`，令牌加密存 n8n 凭据。
3. **核查不能卡住出稿**。核查模型失败时限流/缺 Key 都容错跳过，标记 `needs_review` 交人工。

---

## 2. 环境要求

| 组件 | 版本 | 说明 |
|---|---|---|
| Docker + compose 插件 | 任意较新版本 | `dnf install -y docker-compose-plugin` |
| n8n | `n8nio/n8n:2.42.4` | 固定版本，避免 2.x 行为漂移 |
| Postgres | `postgres:16-alpine` | 与 n8n 同机容器 |
| 内存 | 2C4G 实测够用（加 2G Swap） | |

出网要求：能访问 `api.deepseek.com`、`open.bigmodel.cn`。抓不了海外网页不影响主链路。

---

## 3. 快速开始（新环境）

```bash
# 1) 把仓库放到服务器
git clone <repo> /opt/n8n && cd /opt/n8n

# 2) 一键部署：起容器 → 建 owner → 建表 → 生成 Token → 导工作流
bash bootstrap.sh

# 3) 填模型 Key（自带连通性自检）
bash /opt/n8n/set_deepseek_key.sh sk-你的Key
bash /opt/n8n/set_zhipu_key.sh 你的Key

# 4) 端到端验证
bash /opt/n8n/test_all.sh
```

Windows 本机不想敲命令：双击 `windows/1-配置DeepSeek.bat`、`windows/4-配置智谱.bat`。

> 脚本内路径写死为 `/opt/n8n`。换目录请 `sed -i 's|/opt/n8n|你的目录|g'`。

---

## 4. 目录结构

```
.
├── docker-compose.yml     n8n + Postgres
├── .env.example           环境变量模板（deploy.sh 会生成 .env）
├── bootstrap.sh           新环境一键部署入口
├── deploy.sh              起容器 + 生成 .env
├── init_owner.sh          建 n8n owner + 执行建表
├── sql/init.sql           topics / topic_sources / drafts / finals
├── workflows/             三条工作流定义（含占位符，导入时替换凭据 ID）
│   ├── wf1-intake.json
│   ├── wf2-writer.json
│   ├── wf3-review.json
│   └── wf1b-feishu-pull.json   （可选，国内受限环境可跳过）
├── create_wf1.sh / create_wf2.sh / create_wf3.sh / create_wf1b.sh
├── seed_keys.sh           把 .env 里的模型 Key 同步进 settings 表
├── set_deepseek_key.sh / set_zhipu_key.sh / set_feishu_config.sh
├── test_all.sh            端到端联调（会清库）
├── demo_grok.sh           手动投喂选题跑全流程（联调用）
├── demo_grok2.sh          同上，实测手记版素材
├── export_final.sh        导出最新成品 Markdown + 公众号 HTML 到 out/
├── run_wf3.sh             对指定/最新选题触发 WF3
├── tools/                 诊断脚本（查模型连通性、看核查结果）
├── windows/               双击执行的 .bat
└── docs/                  architecture.md / technical.md / intake-api.md / models-guide.md / feishu-setup.md
```

---

## 5. 环境变量

| 变量 | 用途 | 备注 |
|---|---|---|
| `POSTGRES_USER` / `PASSWORD` / `DB` | 数据库 | |
| `N8N_ENCRYPTION_KEY` | n8n 凭据加密主密钥 | **丢失 = 所有凭据作废**，务必异地备份 |
| `N8N_HOST` | 生成 webhook 地址用 | 填公网 IP 或域名 |
| `WEBHOOK_TOKEN` | WF1 接收鉴权 | 为空时 bootstrap 自动生成 |
| `DEEPSEEK_API_KEY` | 成文模型 | |
| `ZHIPU_API_KEY` | 核查模型 | |
| `ZHIPU_MODEL` | 核查模型名 | 默认 `glm-4.5-flash` |
| `FEISHU_*` | 飞书拉取（可选） | 受限环境可整体跳过 |

---

## 6. 数据库

```sql
topics         选题（topic_id 唯一，status）
topic_sources  信源（url + content 原文正文，按 topic_id+url 去重）
drafts         成稿（outline / body_md / body_html / facts / risk_flags / status）
finals         成品（body_md / body_html / decision）
settings       运行时配置（模型 Key、模型名）—— 工作流运行时读取
```

建表：`sql/init.sql`（幂等，`CREATE TABLE IF NOT EXISTS`）。`settings` 由 `seed_keys.sh` 创建并填充。

---

## 7. 工作流

### WF1 选题接收（`POST /webhook/topic`）

1. Webhook（Header Auth 校验 `X-Token`）→ 401/403 无 Token
2. Code 校验字段：缺字段 → 400 列出缺什么
3. 信源 URL 去重：重复 → 409
4. 写入 `topics` + `topic_sources` → 202 返回 `topic_id`

### WF2 写稿（`POST /webhook/write`）

取选题 → 取信源 → 汇总原料 → **原文 < 200 字则 422 拒写** → 取密钥 → DeepSeek 出提纲 → DeepSeek 成文 → 写 `drafts`。

### WF3 核查·排版·审核（`POST /webhook/review`）

构造查询（找不到成稿 → 404）→ 取密钥 → 取信源 → 智谱核查 → 解析结果 → **Markdown → 公众号 HTML 内联样式排版** → 风险判定 → 更新 `drafts` → 写入 `finals` → 200。

判定规则：

| 条件 | decision | drafts.status |
|---|---|---|
| `risk_level=low` 且无 contradicted/unsupported | `approved` | `approved` |
| `risk_level=high` / 有硬伤 / 核查未返回结果 | `needs_review` | `review` |

---

## 8. 密钥管理：为什么不用 n8n 凭据

n8n 凭据里的 Key 实测**没有被 HTTP 节点用上**（一直 401，而同一个 Key 直接 curl 是通的）。
改为：**密钥写进 Postgres `settings` 表，工作流运行时用 SQL 读出来，塞进 HTTP 请求头**。

```sql
select value from settings where key = 'DEEPSEEK_API_KEY';
select value from settings where key = 'ZHIPU_MODEL';   -- 模型名也可热改
```

好处：换 Key 不用重导工作流；模型名可一行 SQL 切换。
代价：Key 明文在库里 → 数据库别暴露，`.env` 权限 600。

---

## 9. 模型策略

| 档位 | 模型 | 角色 |
|---|---|---|
| 精活·成文 | DeepSeek `deepseek-flash` | 提纲 + 成文 |
| 精活·核查 | 智谱 `glm-4-flash`（免费档） | 事实核查，与成文模型交叉验证 |
| 粗活 | 硅基流动免费模型池 | 待接 |

**2026-10-14 实测**：智谱官方 11 个模型里，`glm-5.3 / 5.3-flash / 5.3-flashx / 5.2 / 5.1 / 5 / 5-turbo / 4.7 / 4.6 / 4.5 / 4.5-air`
在账户余额为 0 时**全部**返回 `429 / 1113 余额不足或无可用资源包`；只有 `glm-4-flash` 稳定可用（JSON 模式也正常）。
`glm-4.7-flash` 首次可用、随后 429，且作为**思考模型**会把 token 消耗在 `reasoning_content` 上，
`max_tokens` 不足时 `content` 为空 —— 这正是早期核查结果为空的原因。

切换模型（改数据库即可，无需重导工作流）：

```bash
docker exec n8n-postgres-1 psql -U n8n -d n8n -c "update settings set value='glm-5.3' where key='ZHIPU_MODEL'"
```

自查：`bash /opt/n8n/tools/test_zhipu_models.sh`（拉官方清单 + 逐个探测 + 测 JSON 模式）。

WF3 的核查节点已配置 `retryOnFail`（3 次，间隔 8 秒）+ `onError=continueRegularOutput`。

---

## 10. 故障排查（今天真实踩过的坑）

| 现象 | 根因 | 解法 |
|---|---|---|
| Code 节点 `access to env vars denied` | n8n 2.x Code 沙箱读不到环境变量 | 密钥改存 `settings` 表，SQL 读取 |
| HTTP 节点 401，但同 Key 直接 curl 成功 | n8n 凭据未被实际使用 | 同上，改为运行时注入 Header |
| 工作流"执行成功"但什么都没做，响应 200 空 | 上一节点返回 0 行 → 下游不执行 → 没走到响应节点 | 让 SQL 永远返回一行（`LEFT JOIN (SELECT 1)`）；表达式用 `$('节点名')` 取值而非 `$json` |
| `column "undefined" does not exist` | 下游节点用 `$json` 取的是上一步输出（如 UPDATE 只返回 id/status） | 显式写 `$('排版与决策').first().json.xxx` |
| IF 节点 `Conversion error: the string '1' can't be converted to an object` | 条件操作符类型与数据类型不匹配（数字用了 object 判断） | 用 `{{ '' + ($json.id ?? '') }}` + string/notEmpty |
| 智谱返回 1305/1302 | 免费档限流（**鉴权其实通过了**） | 换 `glm-4.5-flash`；节点加自动重试 + 容错跳过 |
| 核查结果解析失败 | 模型输出被 `max_tokens` 截断，JSON 未闭合 | `max_tokens: 4096` + 解析时补全闭合括号 |

自查工具：`tools/diag_zhipu.sh`（模型连通性）、`tools/show_check.sh`（看核查结论）、`tools/check_api.sh`（各家 API 出网测试）。

---

## 11. 扩展点

- **成品推送**：现在只落库 + 导出，接微信草稿箱 / 企业微信 / 邮件只需在 WF3 末尾加一个节点。
- **飞书选题拉取（WF1b）**：脚本已备好，受限环境跳过；配置见 `docs/feishu-setup.md`。
- **硅基流动粗活档**：标题分级、素材清洗等低价值调用可切过去，省 DeepSeek 额度。
- **人工审核台**：`finals.decision='needs_review'` 的条目可做成待办列表（飞书表 / 简单网页）。

---

## 12. 安全

- `N8N_ENCRYPTION_KEY` 在 `.env`（600），**异地备份**。
- 5678 端口目前直连公网，仅靠 `X-Token` 保护；上域名后加 nginx + https，并把端口改回 `127.0.0.1:5678:5678`。
- n8n 近半年连续爆 CVSS 10.0 级漏洞，实例里存着所有模型 Key，**不要裸奔**。
