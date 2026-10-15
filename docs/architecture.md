# 架构与交互图

一句话：**采集端把「选题 + 原文全文」推给 n8n，n8n 负责成文、核查、排版、判定，成品落库等待发布。**
n8n 自己不抓网页——国内服务器抓不了海外站点，正文必须由推送方随选题一起带来。

---

## 1. 系统架构

```mermaid
graph LR
    subgraph 采集层
        A1["Grok Bot / WorkBuddy<br/>（抓原文 + 推送选题）"]
        A2["手动投喂<br/>（demo_grok.sh / 飞书表）"]
    end

    subgraph n8n["n8n 2.42.4（服务器 175.178.120.171）"]
        W1["WF1 选题接收<br/>POST /webhook/topic<br/>X-Token 鉴权"]
        W2["WF2 写稿流水线<br/>POST /webhook/write"]
        W3["WF3 核查·排版·审核<br/>POST /webhook/review"]
    end

    subgraph 存储层["Postgres 16"]
        DB[("topics / topic_sources<br/>drafts / finals<br/>settings")]
    end

    subgraph 模型层
        M1["DeepSeek<br/>deepseek-flash<br/>提纲 + 成文"]
        M2["智谱 GLM<br/>glm-4.5-flash<br/>事实核查"]
    end

    A1 -->|"JSON + X-Token"| W1
    A2 -->|"JSON + X-Token"| W1
    W1 --> DB
    W2 --> DB
    W3 --> DB
    W1 -.->|"返回 topic_id"| A1
    DB --> W2
    W2 -->|"提纲请求"| M1
    W2 -->|"成文请求"| M1
    DB --> W3
    W3 -->|"成稿 + 原文"| M2
    W3 --> DB
    DB --> Out["成品导出<br/>export_final.sh<br/>Markdown / 公众号 HTML"]
```

---

## 2. 数据流（一次选题的一生）

```mermaid
graph TD
    S["推送选题<br/>title / angle / sources[].content"] -->|WF1| T["topics 表<br/>status=received"]
    S -->|WF1| TS["topic_sources 表<br/>url + 原文正文"]
    T -->|"WF2 触发"| G1["取选题 + 取信源 → 汇总原料"]
    TS --> G1
    G1 --> C{"原文 ≥ 200 字?"}
    C -->|否| R422["422 拒写<br/>提示补原文"]
    C -->|是| O["DeepSeek 出提纲"]
    O --> B["DeepSeek 成文<br/>1500-2500 字"]
    B --> D["drafts 表<br/>status=drafting"]
    D -->|"WF3 触发"| K["智谱核查<br/>逐句对照原文"]
    TS -.->|"原文作为核查依据"| K
    K --> P["排版 Markdown → 公众号 HTML"]
    P --> J{"风险判定"}
    J -->|"low / 无存疑"| AP["approved"]
    J -->|"high / 有 contradicted<br/>或核查失败"| NR["needs_review"]
    AP --> F["finals 表"]
    NR --> F
    F --> E["导出成品 / 人工复核后发布"]
```

---

## 3. 时序图（从推送到成品）

```mermaid
sequenceDiagram
    participant AG as 采集端 Agent
    participant W1 as WF1 接收
    participant DB as Postgres
    participant W2 as WF2 写稿
    participant DS as DeepSeek
    participant W3 as WF3 核查
    participant ZP as 智谱 GLM

    AG->>W1: POST /webhook/topic (X-Token)
    W1->>W1: 校验字段 / 信源去重
    W1->>DB: INSERT topics + topic_sources
    W1-->>AG: 202 {topic_id} / 409 重复 / 400 缺字段 / 403 无 Token

    AG->>W2: POST /webhook/write {topic_id}
    W2->>DB: 取选题 + 取信源
    alt 原文不足 200 字
        W2-->>AG: 422 拒写
    else 原文充足
        W2->>DS: 提纲请求
        DS-->>W2: outline JSON
        W2->>DS: 成文请求
        DS-->>W2: Markdown 正文
        W2->>DB: INSERT drafts (status=drafting)
        W2-->>AG: 200 {chars}
    end

    AG->>W3: POST /webhook/review {topic_id}
    W3->>DB: 取成稿 + 取信源 + 取密钥
    W3->>ZP: 核查请求（成稿 + 原文）
    alt 模型限流 / Key 缺失
        ZP-->>W3: 1305 / 401（节点容错继续）
        W3->>W3: risk=unknown → needs_review
    else 正常返回
        ZP-->>W3: issues / risk_level / summary
    end
    W3->>W3: 排版 Markdown → 内联样式 HTML
    W3->>DB: UPDATE drafts（facts / body_html / status）
    W3->>DB: INSERT finals（decision）
    W3-->>AG: 200 {decision, issue_count, html_len}
```

---

## 4. 状态机

```mermaid
stateDiagram-v2
    [*] --> received: WF1 接收选题
    received --> drafting: WF2 产出成稿
    drafting --> approved: WF3 核查通过（low / 无存疑）
    drafting --> review: WF3 发现存疑 或 核查未返回结果
    review --> approved: 人工复核通过
    review --> rejected: 人工判定不可用
    approved --> [*]: 导出发布
    rejected --> [*]
```

| 表 | 字段 | 取值 |
|---|---|---|
| `topics.status` | 选题状态 | `received` |
| `drafts.status` | 成稿状态 | `drafting` → `approved` / `review` |
| `finals.decision` | 成品判定 | `approved` / `needs_review` |

---

## 5. 接口一览

| 方法 | 路径 | 触发 | 成功响应 |
|---|---|---|---|
| POST | `/webhook/topic` | 采集端推送选题 | 202 `{ok, topic_id, source_count}` |
| POST | `/webhook/write` | 对某选题触发写稿 | 200 `{ok, chars}` / 422 原文不足 |
| POST | `/webhook/review` | 对某选题触发核查排版 | 200 `{ok, decision, issue_count}` / 404 无成稿 |

鉴权：仅 `/webhook/topic` 需要 `X-Token`（Webhook 节点 Header Auth，令牌加密存储）。
字段契约与错误码见 [`intake-api.md`](./intake-api.md)。

---

## 6. 三次模型调用

| # | 工作流 | 模型 | 输入 | 输出 | 失败处理 |
|---|---|---|---|---|---|
| 1 | WF2 | DeepSeek `deepseek-flash` | 选题 + 原文素材 | 提纲 JSON | 工作流报错（HTTP 500） |
| 2 | WF2 | DeepSeek `deepseek-flash` | 提纲 + 素材 | Markdown 正文 1500-2500 字 | 工作流报错 |
| 3 | WF3 | 智谱 `glm-4.5-flash` | 成稿 + 原文 | `issues / risk_level / summary` | **容错继续**：risk=unknown → needs_review，不阻塞出稿 |

第 3 步容错是刻意的：核查是"加分项"，不能因为免费档限流就卡住整条流水线。
