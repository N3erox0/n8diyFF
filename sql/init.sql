-- 选题表：一次推送 = 一条选题
CREATE TABLE IF NOT EXISTS topics (
  id           BIGSERIAL PRIMARY KEY,
  topic_id     TEXT UNIQUE NOT NULL,
  title        TEXT NOT NULL,
  angle        TEXT,                 -- 切入角度
  direction    TEXT,                 -- 内容方向
  keywords     TEXT,                 -- 关键词，逗号分隔
  brief        TEXT,                 -- 选题说明 / 已有的要点
  pushed_by    TEXT,                 -- 来源标识：grok_x / workbuddy / manual
  status       TEXT NOT NULL DEFAULT 'received',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 选题对应的信源（用于去重 + 后续抓原文）
CREATE TABLE IF NOT EXISTS topic_sources (
  id         BIGSERIAL PRIMARY KEY,
  topic_id   TEXT NOT NULL REFERENCES topics(topic_id) ON DELETE CASCADE,
  url        TEXT NOT NULL,
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_topics_status  ON topics(status);
CREATE INDEX IF NOT EXISTS idx_topics_created ON topics(created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_topic_sources_url ON topic_sources(topic_id, url);

-- 成稿表：写稿流水线产出
CREATE TABLE IF NOT EXISTS drafts (
  id          BIGSERIAL PRIMARY KEY,
  topic_id    TEXT NOT NULL REFERENCES topics(topic_id) ON DELETE CASCADE,
  version     INT  NOT NULL DEFAULT 1,
  outline     TEXT,
  body_md     TEXT,
  body_html   TEXT,
  facts       JSONB,                 -- 事实核查结果
  risk_flags  JSONB,                 -- 存疑句
  status      TEXT NOT NULL DEFAULT 'drafting',  -- drafting/review/approved/published/rejected
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_drafts_topic ON drafts(topic_id);

-- 成品表：WF3 核查/排版/审核通过后的可发布成品
CREATE TABLE IF NOT EXISTS finals (
  id          BIGSERIAL PRIMARY KEY,
  topic_id    TEXT NOT NULL REFERENCES topics(topic_id) ON DELETE CASCADE,
  draft_id    BIGINT,
  title       TEXT,
  body_md     TEXT,
  body_html   TEXT,                 -- 公众号排版后的 HTML（内联样式）
  facts       JSONB,                -- 事实核查结果
  risk_flags  JSONB,                -- 存疑句清单
  decision    TEXT NOT NULL,        -- approved / needs_review / rejected
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_finals_topic   ON finals(topic_id);
CREATE INDEX IF NOT EXISTS idx_finals_decision ON finals(decision);
