#!/usr/bin/env bash
# 服务器清理：加 swap / 清 PM2+kook-admin 残留 / 停 MySQL（数据保留）
set -e

echo "==> 1/3 加 2G Swap"
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -w vm.swappiness=10 >/dev/null
  grep -q 'vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
fi
swapon --show

echo "==> 2/3 清理 PM2 + kook-admin 残留"
command -v pm2 >/dev/null 2>&1 && { pm2 kill || true; pm2 unstartup systemd 2>/dev/null || true; } || echo "  pm2 不存在"
pkill -f 'kook-admin/server/dist/main.js' 2>/dev/null || true
rm -rf /opt/kook-admin
echo "  kook-admin 已清理"

echo "==> 3/3 停止并禁用 MySQL（数据文件保留在 /var/lib/mysql）"
systemctl stop mysqld 2>/dev/null || systemctl stop mysql 2>/dev/null || true
systemctl disable mysqld 2>/dev/null || systemctl disable mysql 2>/dev/null || true
echo "  mysql 已停止"

echo
echo "==> python3 app.py 按你未确认处理：保持原状不动"
echo "==> 当前内存："
free -m
