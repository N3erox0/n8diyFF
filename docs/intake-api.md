# 选题推送接口 v1（给 Grok Bot / WorkBuddy / 任何采集 Agent）

## 1. 接口

```
POST  http://<HOST>/webhook/topic
Content-Type: application/json
X-Token: 6eb524ac20dbf1a070e8cae3a403efb8
```

| 场景 | `<HOST>` | 状态 |
|---|---|---|
| 服务器本机 / SSH 隧道 | `http://127.0.0.1:5678` | ✅ 现在就能用 |
| 公网直连 | `http://175.178.120.171:5678` | ❌ 需腾讯云安全组放行 5678 |
| 未来域名 + HTTPS | `https://你的域名` | 待配 nginx |

> Token 存在服务器 `/opt/n8n/.env` 的 `WEBHOOK_TOKEN`，同时以加密凭据形式存在 n8n 里。
> 换 Token：改 `.env` 后重启容器，并到 n8n → Credentials → `Webhook Token` 同步改值。

## 2. 请求体

```json
{
  "title": "选题标题（必填）",
  "angle": "切入角度（建议填，决定文章走向）",
  "direction": "内容方向，如 AI工具 / AI行业 / 自动化玩法",
  "keywords": ["关键词1", "关键词2"],
  "brief": "你的判断：为什么值得写（选填，但很有用）",
  "pushed_by": "grok_x",
  "sources": [
    {
      "url": "https://原文链接",
      "title": "原文标题",
      "content": "原文正文全文（必带，≥200 字）"
    }
  ]
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `title` | ✅ | 空则直接 400 |
| `sources[].url` | ✅ | 至少 1 个 http(s) 链接，没有就 400 |
| `sources[].content` | ✅（强烈） | **原文正文**。服务器在国内抓不了海外站点，不带正文就写不了稿（WF2 返回 422） |
| `angle` | 推荐 | 不填模型自己发挥，质量会飘 |
| `pushed_by` | 选填 | 标识来源，默认 `manual` |

兼容旧格式：`"source_urls": ["https://a", "https://b"]`（但会缺正文）。

## 3. 响应

| 码 | 含义 | 示例 |
|---|---|---|
| **202** | 收下 | `{"ok":true,"topic_id":"Tmv85ok6sit6o","has_content":true}` |
| 400 | 字段不合法 | `{"ok":false,"details":["title 必填"]}` |
| 403 | Token 错/缺失 | `Authorization data is wrong!` |
| 409 | 信源已存在（重复选题） | `{"ok":false,"error":"该信源已存在"}` |
| 500 | 服务端异常 | `{"message":"Error in workflow"}` |

**去重规则**：按 `sources[0].url` 判重，同一条原文推第二次就是 409。

## 4. 触发写稿（内部接口，无需 Token）

```
POST http://127.0.0.1:5678/webhook/write
{"topic_id": "Tmv85ok6sit6o"}
```
返回 `{"ok":true,"chars":2310,"draft_status":"drafting"}`。原文不足会返回 422。

## 5. 直接复制给 Agent 的指令

把下面这段整段发给 Grok Bot / WorkBuddy（按需改 `pushed_by` 和方向）：

---

你负责采集，并把结果推送到我的选题系统。

**接口**
```
POST http://127.0.0.1:5678/webhook/topic
Content-Type: application/json
X-Token: 6eb524ac20dbf1a070e8cae3a403efb8
```

**请求体（只输出纯 JSON，不要任何寒暄、解释、markdown 代码围栏）**
```json
{
  "title": "选题标题",
  "angle": "切入角度",
  "direction": "内容方向",
  "keywords": ["关键词"],
  "brief": "为什么值得写",
  "pushed_by": "grok_x",
  "sources": [
    { "url": "https://真实链接", "title": "原文标题", "content": "原文正文全文" }
  ]
}
```

**硬性规则**
1. `sources[0].content` 必须是你抓到的**原文正文**，不少于 200 字，**不要摘要、不要改写、不要截断**
2. 每条必须有**真实可点击的 URL**，编造或不给链接的整条作废，不要推送
3. 一次请求只发一个 JSON 对象，不要包成数组，不要加 ```json 代码块
4. 返回 202 = 成功，记下 `topic_id`；409 = 这条已经推过，跳过；400 = 字段有问题，修正后重发；403 = Token 错了
5. 同一条原文不要重复推送

---

## 6. 已知限制

- 服务器在国内：`r.jina.ai` 等海外抓取代理不通，所以**正文必须由推送方提供**
- 5678 未对公网放行：现阶段 Agent 若在境外，需先解决入口（放行端口 / 隧道 / 表中转）
