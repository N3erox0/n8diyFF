#!/usr/bin/env bash
# 新环境一键部署：起容器 → 建 owner → 建表 → 生成 Token → 导入三条工作流 → 同步密钥
# 用法： bash bootstrap.sh
set -e

# 脚本内的路径写死为 /opt/n8n；若当前不在这个目录，先复制过去
if [ "$(pwd)" != "/opt/n8n" ]; then
  echo "==> 0/6 脚本内路径固定为 /opt/n8n，先复制过去"
  mkdir -p /opt/n8n
  cp -r ./. /opt/n8n/
  cd /opt/n8n
fi
chmod +x /opt/n8n/*.sh

echo "==> 1/6 起 n8n + Postgres（含 .env 生成、镜像加速）"
bash /opt/n8n/deploy.sh

echo "==> 2/6 等 n8n 就绪（最多 5 分钟）"
for i in $(seq 1 60); do
  if curl -sf http://127.0.0.1:5678/rest/settings >/dev/null 2>&1; then
    echo "    n8n 已就绪"
    break
  fi
  sleep 5
done

echo "==> 3/6 创建 owner 账号 + 建表"
bash /opt/n8n/init_owner.sh

echo "==> 4/6 生成 WEBHOOK_TOKEN（若为空）"
if [ -z "$(grep '^WEBHOOK_TOKEN=' /opt/n8n/.env | cut -d= -f2- | tr -d '\r\n ')" ]; then
  T=$(openssl rand -hex 16)
  if grep -q '^WEBHOOK_TOKEN=' /opt/n8n/.env; then
    sed -i "s|^WEBHOOK_TOKEN=.*|WEBHOOK_TOKEN=$T|" /opt/n8n/.env
  else
    echo "WEBHOOK_TOKEN=$T" >> /opt/n8n/.env
  fi
  docker compose -f /opt/n8n/docker-compose.yml up -d n8n >/dev/null
  sleep 12
  echo "    已生成 Token"
fi

echo "==> 5/6 导入三条工作流"
bash /opt/n8n/create_wf1.sh | tail -2
bash /opt/n8n/create_wf2.sh | tail -2
bash /opt/n8n/create_wf3.sh | tail -2

echo "==> 6/6 同步模型密钥到数据库"
bash /opt/n8n/seed_keys.sh | tail -1

echo
echo "=============================================="
echo " 部署完成。剩下的两步："
echo "   1) 填 DeepSeek Key： bash /opt/n8n/set_deepseek_key.sh sk-xxx"
echo "   2) 填智谱 Key：     bash /opt/n8n/set_zhipu_key.sh xxx"
echo "      或在本机双击 windows/ 下的 1-配置DeepSeek.bat、4-配置智谱.bat"
echo " 跑通验证： bash /opt/n8n/test_all.sh"
echo " 查看 Token： grep WEBHOOK_TOKEN /opt/n8n/.env"
echo "=============================================="
