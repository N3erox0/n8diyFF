#!/usr/bin/env bash
# n8n + Postgres 一键部署（服务器上执行）
set -e
cd "$(dirname "$0")"

echo "==> 1/5 检查 docker / compose"
command -v docker >/dev/null 2>&1 || { echo "未安装 docker，请先安装"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "缺少 compose 插件：dnf install -y docker-compose-plugin"; exit 1; }

echo "==> 2/5 腾讯云内网镜像加速（daemon.json 不存在时才写）"
mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
  cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": ["https://mirror.ccs.tencentyun.com"]
}
EOF
  systemctl restart docker
fi

echo "==> 3/5 生成 .env（已存在则保留）"
if [ ! -f .env ]; then
  cp .env.example .env
  sed -i "s|CHANGE_ME_STRONG|$(openssl rand -hex 16)|" .env
  sed -i "s|CHANGE_ME_openssl_rand_hex_32|$(openssl rand -hex 32)|" .env
  chmod 600 .env
  echo "    .env 已生成：请立刻备份 N8N_ENCRYPTION_KEY（丢了所有凭据全废）"
else
  echo "    .env 已存在，保留"
fi

echo "==> 4/5 拉取镜像并启动"
docker compose pull
docker compose up -d

echo "==> 5/5 状态"
docker compose ps
echo
echo "n8n 编辑器: http://$(grep N8N_HOST .env | cut -d= -f2):5678"
echo "提醒：腾讯云安全组需放行 TCP 5678；后续务必尽快换成 https 域名"
