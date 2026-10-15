# 模型配置指南（DeepSeek + 两个免费模型）

## 零、服务器连通性实测（2026-10-14，本机实测）

| 平台 | 端点 | 结果 |
|---|---|---|
| DeepSeek | api.deepseek.com | ✅ 可达 |
| 智谱 BigModel | open.bigmodel.cn | ✅ 可达 |
| 硅基流动 | api.siliconflow.cn | ✅ 可达 |
| 阿里百炼 | dashscope.aliyuncs.com | ✅ 可达 |
| OpenRouter | openrouter.ai | ✅ 可达（但海外，延迟/稳定性不保险） |

---

## 一、配 DeepSeek（主力写稿模型）

### 1. 去哪配

**网址：https://platform.deepseek.com**（这是 API 开放平台，不是 chat.deepseek.com 那个聊天页面，别走错）

登录方式三选一：**手机号验证码**（未注册的手机号自动注册）/ 密码 / 微信扫码。

> 账号密码是你自己注册的，我没有也不会有——API Key 属于你的付费资产，只能你本人创建。

### 2. 每一步

| 步 | 在哪 | 做什么 |
|---|---|---|
| 1 | 首页 | 手机号登录（收验证码） |
| 2 | 左侧菜单 **API keys** | 点「创建 API key」，名字随便起，建议写 `n8n-公众号` |
| 3 | 弹出框 | **立刻复制那串 `sk-` 开头的密钥**——**关掉窗口就再也看不到了**，只能重新创建 |
| 4 | 左侧菜单 **充值** | 最低 10 元。**不充值调用会报 402 余额不足**，这步不能省 |
| 5 | 你的电脑终端 | 执行下面那条命令 |

> Key 建议**单独建一个给 n8n 用**，别和其他项目共用：方便看用量、方便随时吊销。

### 3. 现在该用哪个模型名（重要）

官方更新日志：`deepseek-chat` / `deepseek-reasoner` **已于 2026-07-24 停止使用**。

| 用途 | 模型 ID | 说明 |
|---|---|---|
| **我们流水线用这个** | `deepseek-flash` | DeepSeek-V4.1-Flash，1M 上下文，原生多模态，最便宜 |
| 需要更强推理时 | `deepseek-v4-pro` | V4-Pro，1M 上下文，价格约为 flash 的 3 倍 |

工作流里已经改成 `deepseek-flash` 了，你不用管。

### 4. 价格（USD / 百万 tokens，官方现价）

| | 非高峰 | 高峰 |
|---|---|---|
| `deepseek-flash` 输入（缓存未命中） | $0.15 | $0.30 |
| `deepseek-flash` 输出 | $0.60 | $1.20 |

**高峰时段 = UTC 周一至周五 01:00–04:00 和 06:00–10:00**（即北京时间 09:00–12:00、14:00–18:00），其余时间（含周末全天）**半价**。

按每天 2 篇成品算，一篇约 ¥0.03，**10 元能跑好几个月**。

### 5. 一条命令配好

```bash
ssh root@175.178.120.171 "bash /opt/n8n/set_deepseek_key.sh sk-你的Key"
```

脚本会做三件事，全绿才算成功：

1. **直连 DeepSeek 自检**（Key 错 / 余额 0 会当场报错并停下）
2. Key 写进 `/opt/n8n/.env`（权限 600）
3. 重建 n8n 凭据 `DeepSeek API` → 重新导入并激活 WF2

### 3. 验证出稿

```bash
ssh root@175.178.120.171 "bash /opt/n8n/test_all.sh"
```

看最后 `--- drafts ---` 有没有一行 `body_len` 大于 2000。有就是真出稿了。

---

## 二、两个免费模型，我建议接这两个

### 推荐 A：智谱 GLM 🇨🇳（免费档要实测，付费档要充值）

| 项 | 值 |
|---|---|
| 端点 | `https://open.bigmodel.cn/api/paas/v4`（OpenAI 兼容） |
| 拿 Key | https://open.bigmodel.cn → 控制台 → API Key |

**2026-10-14 实测（同一把 Key，官方 `/v1/models` 全量拉清单后逐个探测）**

官方 11 个模型：`glm-4.5 / 4.5-air / 4.6 / 4.7 / 5 / 5-turbo / 5.1 / 5.2 / 5.3 / 5.3-flash / 5.3-flashx`

| 结果 | 模型 |
|---|---|
| ✅ 可用（免费档） | `glm-4-flash`（含 JSON 模式，返回正常） |
| ⚠️ 不稳定 | `glm-4.7-flash`（首次 200，随后 429；**且是思考模型**，`content` 会被 `reasoning_content` 吃掉，核查节点会拿到空结果） |
| ❌ 429 `1113 余额不足或无可用资源包` | 其余全部（`glm-5.3` / `glm-5.3-flash` / `glm-5.2` / `glm-4.7` / `glm-4.6` / `glm-4.5` …） |

结论：**不是模型版本老，是账户余额为 0。** 充值后把 `settings` 表改一行即可切到 `glm-5.3`，不用重导工作流：

```bash
docker exec n8n-postgres-1 psql -U n8n -d n8n -c "update settings set value='glm-5.3' where key='ZHIPU_MODEL'"
```

自查脚本（会拉官方清单 + 逐个探测 + 测 JSON 模式）：

```bash
ssh root@175.178.120.171 "bash /opt/n8n/tools/test_zhipu_models.sh"
```

> 避坑：思考模型（`glm-4.7-flash` 及 5.x）会把 token 花在 `reasoning_content` 上，`max_tokens` 给小了 `content` 就是空的。**核查节点要么避开思考模型，要么把 `max_tokens` 给到 4096 以上。**

### 推荐 B：硅基流动 SiliconFlow 🇨🇳 免费模型池

| 项 | 值 |
|---|---|
| 端点 | `https://api.siliconflow.cn/v1`（OpenAI 兼容） |
| 价格 | 一批模型**永久免费**，另有注册/实名赠送额度 |
| 限制 | 免费模型高峰可能限流；额度按模型独立计算，每月重置 |
| 拿 Key | https://cloud.siliconflow.cn → API 密钥（需手机号实名） |

免费模型名单会变，拿到 Key 后自己查（在能联网的机器上跑）：

```bash
curl https://api.siliconflow.cn/v1/models -H "Authorization: Bearer 你的Key" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);[print(m['id']) for m in d['data']]"
```

**为什么选它**：模型池大（Qwen 系列为主），适合跑**粗活**——摘要、初筛打分、格式转换、去重判断。这类活一天几十次，全免费能省下不少。

---

## 三、三档分工建议

| 环节 | 模型 | 理由 |
|---|---|---|
| **成文（精活）** | DeepSeek（付费，极便宜） | 中文长文最稳，一天两篇成本几毛钱 |
| **事实核查（精活）** | **GLM**（免费档 `glm-4-flash`，充值后 `glm-5.3`） | 长上下文装得下全文+全部信源；**换厂商交叉验证**，避免"自己查自己" |
| **摘要/初筛/格式（粗活）** | 硅基流动免费模型 | 量最大、要求最低，全走免费 |

> 交叉验证那点值得强调：如果写稿和核查用同一个模型，它会倾向于认同自己的说法。**用不同厂商互相查，才查得出真问题。**

---

## 四、我看过但不建议当主力的

| 平台 | 不推荐原因 |
|---|---|
| OpenRouter `:free` | 能连通，但海外节点、免费模型频繁上下架、限流随机，做主力会半夜崩 |
| Kimi / MiniMax | 是"注册赠送 token 包"，**用完即止**，不是长期免费，不适合常驻流水线 |
| Groq / NVIDIA NIM / Gemini free | 海外，延迟和合规都不划算 |
| 各种 API 中转站（如 ofox） | 多一层依赖和跑路风险，官方直连没那么麻烦 |

---

## 五、拿到 Key 之后

把这两个值发我（或自己填进 `/opt/n8n/.env`）：

```
ZHIPU_API_KEY=xxx
SILICONFLOW_API_KEY=sk-xxx
```

我来接进工作流：把 WF2/WF3 的模型调用改成**可在节点里切换的凭据 + 模型名**，以后哪家免费额度没了，改一个参数就能换。

> 提醒：免费模型会下线（GLM-4.5-Flash 就是活例子）。所以我在 n8n 里会做成"主模型 + 备模型"，主模型挂了自动切，不会让整条线停摆。
