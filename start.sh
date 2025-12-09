#!/bin/bash
set -e

# ---------------- utils ----------------

# 获取一个“尽量空闲”的随机端口（最多尝试 20 次）
# 若 ss 不存在，则退化为纯随机端口（保持原脚本风格）
get_free_port() {
    local p
    for _ in {1..20}; do
        p=$(( ( RANDOM % 20000 ) + 10000 ))
        if command -v ss >/dev/null 2>&1; then
            if ! ss -lnt 2>/dev/null | awk '{print $4}' | grep -q ":$p$"; then
                echo "$p"; return 0
            fi
        else
            echo "$p"; return 0
        fi
    done
    echo "ERROR: 無法找到空閒端口" >&2
    exit 1
}

cleanup() {
  kill ${OPERA_PID:-} ${ECH_PID:-} ${CF_PID:-} 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# 根据固定/随机 Argo 参数，设置模式并在需要时生成配置
# ARGO_MODE:
#   json          -> ARGO_AUTH 是 TunnelSecret(JSON)，生成 tunnel.json/yml
#   token         -> ARGO_AUTH 是 token，使用 --token 启动
#   trycloudflare -> 未提供固定参数，走临时隧道
argo_type() {
  if [[ -n "${ARGO_AUTH}" && -n "${ARGO_DOMAIN}" ]]; then
    if [[ $ARGO_AUTH =~ TunnelSecret ]]; then
      echo "$ARGO_AUTH" > tunnel.json
      cat > tunnel.yml << EOF
tunnel: $(cut -d\" -f12 <<< "$ARGO_AUTH")
credentials-file: $(pwd)/tunnel.json
protocol: http2

ingress:
  - hostname: $ARGO_DOMAIN
    service: http://localhost:$ECHPORT
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
      ARGO_MODE="json"
    else
      ARGO_MODE="token"
    fi
  else
    ARGO_MODE="trycloudflare"
  fi
}

quicktunnel() {
    echo "--- 正在強制設定 DNS 為 1.1.1.1/1.0.0.1 ---"
    # 加强保护：可写才改；先备份；失败则回滚；失败不退出脚本
    if [ -e /etc/resolv.conf ] && [ -w /etc/resolv.conf ]; then
        if cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null; then
            {
                echo "nameserver 1.1.1.1"
                echo "nameserver 1.0.0.1"
            } > /etc/resolv.conf 2>/dev/null || {
                echo "WARN: DNS 強制設定失敗，已還原。"
                mv /etc/resolv.conf.bak /etc/resolv.conf 2>/dev/null || true
            }
        else
            echo "WARN: 無法備份 resolv.conf，跳過 DNS 強制設定。"
        fi
    else
        echo "WARN: /etc/resolv.conf 不可寫或不存在，跳過 DNS 強制設定。"
    fi

    echo "--- 正在下載服務二進制文件 ---"

    local ARCH
    ARCH=$(uname -m)

    local ECH_URL=""
    local OPERA_URL=""
    local CLOUDFLARED_URL=""

    case "$ARCH" in
        x86_64 | x64 | amd64 )
            ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64"
            OPERA_URL="https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-amd64"
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        i386 | i686 )
            ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-386"
            OPERA_URL="https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-386"
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386"
            ;;
        armv8 | arm64 | aarch64 )
            ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64"
            OPERA_URL="https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-arm64"
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        * )
            echo "當前架構 $ARCH 沒有适配。退出。"
            exit 1
            ;;
    esac

    curl -fL "$ECH_URL" -o ech-server-linux
    curl -fL "$OPERA_URL" -o opera-linux
    curl -fL "$CLOUDFLARED_URL" -o cloudflared-linux

    chmod +x cloudflared-linux ech-server-linux opera-linux

    local COUNTRY_UPPER="${COUNTRY^^}"

    echo "--- 啟動服務 ---"

    # 端口分配：
    # Caddy = WSPORT
    # ECH   = WSPORT + 1
    if [ -z "$WSPORT" ]; then
        WSPORT=$(get_free_port)
        echo "WSPORT 未設置，自動選取給 Caddy 的端口: $WSPORT"
    else
        echo "使用自定義 WSPORT 給 Caddy: $WSPORT"
    fi

    ECHPORT=$((WSPORT + 1))
    export WSPORT ECHPORT
    echo "ECH Server 將使用端口: $ECHPORT"

    # 1) Opera Proxy
    if [ "$OPERA" = "1" ]; then
        operaport=$(get_free_port)
        echo "啟動 Opera Proxy (port: $operaport, country: $COUNTRY_UPPER)..."
        nohup ./opera-linux \
            -country "$COUNTRY_UPPER" \
            -socks-mode \
            -bind-address "127.0.0.1:$operaport" \
            > /dev/null 2>&1 &
        OPERA_PID=$!
    fi

    # 2) ECH Server
    sleep 1

    ECH_ARGS=(./ech-server-linux -l "ws://0.0.0.0:$ECHPORT")

    if [ -n "$TOKEN" ]; then
        ECH_ARGS+=(-token "$TOKEN")
        echo "ECH Server 已設置 token（不在前台顯示）"
    else
        echo "ECH Server 未設置 token"
    fi

    if [ "$OPERA" = "1" ]; then
        ECH_ARGS+=(-f "socks5://127.0.0.1:$operaport")
    fi

    echo "啟動 ECH Server (port: $ECHPORT)..."
    nohup "${ECH_ARGS[@]}" > /dev/null 2>&1 &
    ECH_PID=$!

    # 3) Cloudflared -> ECHPORT (固定/隨機模式，無 metrics)
    echo "啟動 Cloudflared Tunnel..."

    argo_type

    if [[ "$ARGO_MODE" = "json" ]]; then
        echo "--- 使用固定 Tunnel(JSON) 配置啟動 Cloudflared（后台静默）---"
        nohup ./cloudflared-linux tunnel --config tunnel.yml run \
            > /dev/null 2>&1 &
        CF_PID=$!
        sleep 1
        if ! kill -0 "$CF_PID" 2>/dev/null; then
            echo "ERROR: cloudflared 固定隧道(JSON) 啟動失敗（無日志輸出）"
            exit 1
        fi

    elif [[ "$ARGO_MODE" = "token" ]]; then
        echo "--- 使用固定 Tunnel(Token) 配置啟動 Cloudflared（后台静默）---"
        nohup ./cloudflared-linux tunnel run --token "$ARGO_AUTH" \
            > /dev/null 2>&1 &
        CF_PID=$!
        sleep 1
        if ! kill -0 "$CF_PID" 2>/dev/null; then
            echo "ERROR: cloudflared 固定隧道(Token) 啟動失敗（無日志輸出）"
            exit 1
        fi

    else
        echo "--- 使用臨時 TryCloudflare 隧道啟動 Cloudflared ---"
        # 随机隧道：日志只写 argo.log，不输出到终端
        nohup ./cloudflared-linux \
            --edge-ip-version "$IPS" \
            --protocol http2 \
            tunnel --url "127.0.0.1:$ECHPORT" \
            > argo.log 2>&1 &
        CF_PID=$!

        # 从 argo.log 读取域名并前台显示（加超时避免死循环）
        local max_tries=60
        local tries=0
        while true; do
            ARGO_DOMAIN=$(grep -oE "https://[a-zA-Z0-9.-]+trycloudflare\.com" argo.log \
                | sed 's@https://@@' | tail -n 1)

            if [[ -n "$ARGO_DOMAIN" ]]; then
                echo "--- Cloudflared 臨時隧道啟動成功 ---"
                if [ -z "$TOKEN" ]; then
                    echo "未設置 token, 連接為: $ARGO_DOMAIN:443"
                else
                    echo "已設置 token, 連接為: $ARGO_DOMAIN:443 （token 不顯示）"
                fi
                break
            fi

            tries=$((tries+1))
            if [[ $tries -ge $max_tries ]]; then
                echo "ERROR: 2分鐘內未獲取到 trycloudflare 域名"
                echo "--- argo.log 最後 50 行 ---"
                tail -n 50 argo.log || true
                exit 1
            fi

            echo "未獲取到 trycloudflare 域名，2秒後重試..."
            sleep 2
        done
    fi
}

# ---------------- main ----------------

MODE="${1:-1}"  # 默认模式 1

if [ "$MODE" = "1" ]; then
    # Opera 参数检查
    if [ "$OPERA" = "1" ]; then
        echo "已啟用 Opera 前置代理。"
        COUNTRY=${COUNTRY:-AM}
        COUNTRY=${COUNTRY^^}
        if [ "$COUNTRY" != "AM" ] && [ "$COUNTRY" != "AS" ] && [ "$COUNTRY" != "EU" ]; then
            echo "錯誤：請設置正確的 OPERA_COUNTRY (AM/AS/EU)。目前值: $COUNTRY"
            exit 1
        fi
    elif [ "$OPERA" != "0" ]; then
        echo "錯誤：OPERA 變數只能是 0 或 1。目前值: $OPERA"
        exit 1
    fi

    # IPS 参数检查
    if [ "$IPS" != "4" ] && [ "$IPS" != "6" ]; then
        echo "錯誤：IPS 變數只能是 4 或 6。目前值: $IPS"
        exit 1
    fi

    quicktunnel
else
    echo "使用非預期模式啟動。"
    exit 1
fi

echo "--- 啟動 Caddy 前台服務（port: $WSPORT）---"
# 最后用 exec 让 caddy 占据 PID1，容器不会退出
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
