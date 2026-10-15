#!/usr/bin/env bash
# 把 /opt/n8n 这个代码包推送到 GitHub（SSH 走 ~/.ssh/id_ed25519_github）
# 用法: bash /opt/n8n/tools/git_push.sh "提交说明"
set -e
cd /opt/n8n

MSG=${1:-"更新 n8n 内容流水线代码包"}
REMOTE=git@github.com:N3erox0/n8diyFF.git

git init -q
git config user.name  n8diyff
git config user.email admin@n8diyff.local
git config core.autocrlf input

git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE"

git add -A

echo '--- 待提交文件（确认无 .env / 密钥）---'
git status --short | head -80

# 安全阀：任何敏感文件都不许进包
BAD=$(git diff --cached --name-only | grep -E '(^|/)\.env$|owner_password|_id$|\.pem$' || true)
if [ -n "$BAD" ]; then
  echo "!! 检测到敏感文件，已中止推送:"; echo "$BAD"; exit 1
fi

if git diff --cached --quiet; then
  echo '没有需要提交的改动'
else
  git commit -q -m "$MSG"
  echo "已提交: $MSG"
fi

git branch -M main
git push -u origin main
echo '推送完成'
