#!/bin/bash
set -e

APP_UID=1000
APP_GID=1000

WSPORT=${WSPORT:-7860}
ECHPORT=$((WSPORT+1))
export WSPORT ECHPORT

# ---------- 阶段1：root-only ----------
if [ "$(id -u)" -eq 0 ]; then
  # 改 DNS（能写就写，失败不退出）
  if [ -e /etc/resolv.conf ] && [ -w /etc/resolv.conf ]; then
    cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
    {
      echo "nameserver 1.1.1.1"
      echo "nameserver 1.0.0.1"
    } > /etc/resolv.conf 2>/dev/null || {
      mv /etc/resolv.conf.bak /etc/resolv.conf 2>/dev/null || true
    }
  fi

  # 其它 root-only 操作也放这（比如写系统文件、开低端口等）

  # ---------- 切到普通用户 ----------
  exec su-exec ${APP_UID}:${APP_GID} bash "$0"
fi

# ---------- 阶段2：普通用户跑服务 ----------
# 下载并启动 ECH（略，你现有逻辑放这里）
# ...

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
