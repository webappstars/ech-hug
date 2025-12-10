#!/bin/bash
set -e

# HF 必须外部监听 7860
WSPORT=${WSPORT:-7860}
ECHPORT=$((WSPORT + 1))
export WSPORT ECHPORT

# -------- DNS 强制（静默 + 失败不退出）--------
# 目标：尽量写入 1.1.1.1/1.0.0.1
# 行为：可写才改；先备份；失败回滚；全程不打印成功日志
if [ -e /etc/resolv.conf ] && [ -w /etc/resolv.conf ]; then
  if cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null; then
    {
      echo "nameserver 1.1.1.1"
      echo "nameserver 1.0.0.1"
    } > /etc/resolv.conf 2>/dev/null || {
      echo "WARN: DNS 強制設定失敗，已還原。" >&2
      mv /etc/resolv.conf.bak /etc/resolv.conf 2>/dev/null || true
    }
  else
    echo "WARN: 無法備份 resolv.conf，跳過 DNS 強制設定。" >&2
  fi
else
  echo "WARN: /etc/resolv.conf 不可寫或不存在，跳過 DNS 強制設定。" >&2
fi

# -------- 下载 ECH（二进制静默）--------
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|x64|amd64)
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64"
    ;;
  i386|i686)
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-386"
    ;;
  armv8|arm64|aarch64)
    ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64"
    ;;
  *)
    echo "不支持架构: $ARCH" >&2
    exit 1
    ;;
esac

curl -fsSL "$ECH_URL" -o /app/ech-server-linux
chmod +x /app/ech-server-linux

# -------- 启动 ECH（后台静默）--------
ECH_ARGS=(/app/ech-server-linux -l "ws://0.0.0.0:$ECHPORT")
if [ -n "$TOKEN" ]; then
  ECH_ARGS+=(-token "$TOKEN")
fi

nohup "${ECH_ARGS[@]}" > /app/ech.log 2>&1 &
ECH_PID=$!

# 存活检查（失败才输出）
sleep 1
if ! kill -0 "$ECH_PID" 2>/dev/null; then
  echo "ERROR: ECH 启动失败" >&2
  tail -n 50 /app/ech.log >&2 || true
  exit 1
fi

# -------- 前台启动 Caddy（HF 健康检查依赖 7860）--------
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
