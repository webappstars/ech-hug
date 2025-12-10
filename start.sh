#!/bin/bash
set -e

# HF 必须外部监听 7860
WSPORT=${WSPORT:-7860}
ECHPORT=$((WSPORT + 1))
export WSPORT ECHPORT

# 下载 ech 二进制（按架构）
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

# 静默下载：不显示进度、不打印成功信息
curl -fsSL "$ECH_URL" -o /app/ech-server-linux
chmod +x /app/ech-server-linux

# 后台启动 ECH，日志写入 ech.log，不输出到前台
ECH_ARGS=(/app/ech-server-linux -l "ws://0.0.0.0:$ECHPORT")
if [ -n "$TOKEN" ]; then
  ECH_ARGS+=(-token "$TOKEN")
fi

nohup "${ECH_ARGS[@]}" > /app/ech.log 2>&1 &
ECH_PID=$!

# 存活检查（失败时才输出错误）
sleep 1
if ! kill -0 "$ECH_PID" 2>/dev/null; then
  echo "ERROR: ECH 启动失败" >&2
  tail -n 50 /app/ech.log >&2 || true
  exit 1
fi

# 前台启动 Caddy（HF 需要 7860 上有服务）
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
