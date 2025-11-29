#!/bin/bash

# 獲取一個隨機端口
get_free_port() {
    # 選擇一個高端口號以避免衝突
    echo $(( ( RANDOM % 20000 ) + 10000 ))
}

# 執行核心服務啟動邏輯
quicktunnel() {
    echo "--- 正在下載服務二進制文件 ---"

    local ARCH=$(uname -m)
    local ECH_URL=""
    local OPERA_URL=""
    local CLOUDFLARED_URL=""

    case "$ARCH" in
        x86_64 | x64 | amd64 )
            ECH_URL="https://www.baipiao.eu.org/ech/ech-server-linux-amd64"
            OPERA_URL="https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-amd64"
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        i386 | i686 )
            ECH_URL="https://www.baipiao.eu.org/ech/ech-server-linux-386"
            OPERA_URL="https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-386"
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386"
            ;;
        armv8 | arm64 | aarch64 )
            ECH_URL="https://www.baipiao.eu.org/ech/ech-server-linux-arm64"
            OPERA_URL="https://github.com/Snawoot/opera-proxy/releases/latest/download/opera-proxy.linux-arm64"
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        * )
            echo "當前架構 $ARCH 沒有适配。退出。"
            exit 1
            ;;
    esac

    curl -L $ECH_URL -o ech-server-linux
    curl -L $OPERA_URL -o opera-linux
    curl -L $CLOUDFLARED_URL -o cloudflared-linux

    if [ $? -ne 0 ]; then
        echo "下載一個或多個二進制文件失敗。退出。"
        exit 1
    fi

    chmod +x cloudflared-linux ech-server-linux opera-linux
    
    local COUNTRY_UPPER=${COUNTRY^^}

    # 服務啟動
    echo "--- 啟動服務 ---"

    # 1. 啟動 Opera Proxy (如果 $OPERA=1)
    if [ "$OPERA" = "1" ]; then
        operaport=$(get_free_port)
        echo "啟動 Opera Proxy (port: $operaport, country: $COUNTRY_UPPER)..."
        ./opera-linux -country "$COUNTRY_UPPER" -socks-mode -bind-address "127.0.0.1:$operaport" &
    fi

    # 2. 啟動 ECH Server (處理 WSPORT)
    sleep 1
    
    if [ -z "$WSPORT" ]; then
        wsport=$(get_free_port)
        echo "WSPORT 環境變數未設置，自動選取端口: $wsport"
    else
        wsport="$WSPORT"
        echo "使用自定義的 WSPORT 端口: $wsport"
    fi

    # *** 修改點 1: ECH Server 監聽所有介面 (0.0.0.0) ***
    ECH_CMD="./ech-server-linux -l ws://0.0.0.0:$wsport"
    
    if [ -n "$TOKEN" ]; then
        ECH_CMD="$ECH_CMD -token $TOKEN"
    fi

    # Opera 代理仍使用 127.0.0.1 進行內部轉發
    if [ "$OPERA" = "1" ]; then
        ECH_CMD="$ECH_CMD -f socks5://127.0.0.1:$operaport"
    fi

    echo "啟動 ECH Server (port: $wsport)..."
    eval "$ECH_CMD" &

    # 3. 啟動 Cloudflared Tunnel
    metricsport=$(get_free_port)
    echo "啟動 Cloudflared Tunnel (metrics port: $metricsport)..."
    ./cloudflared-linux update
    # *** 修改點 2: Cloudflared Tunnel 目標使用 0.0.0.0 ***
    ./cloudflared-linux --edge-ip-version $IPS --protocol http2 tunnel --url 0.0.0.0:$wsport --metrics 0.0.0.0:$metricsport &
    
    # 獲取 Argo Hostname
    while true; do
        echo "正在嘗試獲取 Argo 域名..."
        RESP=$(curl -s "http://127.0.0.1:$metricsport/metrics") 
        if echo "$RESP" | grep -q 'userHostname='; then
            echo "獲取成功，正在解析..."
            DOMAIN=$(echo "$RESP" | grep 'userHostname="' | sed -E 's/.*userHostname="https?:\/\/([^"]+)".*/\1/')
            
            echo "--- 服務啟動成功 ---"
            if [ -z "$TOKEN" ]; then
                echo "未設置 token, 連接為: $DOMAIN:443"
            else
                echo "已設置 token, 連接為: $DOMAIN:443 身份令牌: $TOKEN"
            fi
            echo "您可以透過日誌或 Docker inspect 查找連接信息。"
            
            break
        else
            echo "未獲取到 userHostname，5秒後重試..."
            sleep 5
        fi
    done

    echo "--- 保持容器運行 ---"
    # 使用 tail -f 來保持容器運行並輸出日誌
    tail -f /dev/null
}

# 根據傳入的參數執行對應模式
if [ "$1" == "1" ]; then
    # 檢查並處理 Opera 模式的設定
    if [ "$OPERA" = "1" ]; then
        echo "已啟用 Opera 前置代理。"
        COUNTRY=${COUNTRY:-AM} 
        COUNTRY=${COUNTRY^^} 
        if [ "$COUNTRY" != "AM" ] && [ "$COUNTRY" != "AS" ] && [ "$COUNTRY" != "EU" ]; then
            echo "錯誤：請設置正確的 OPERA_COUNTRY (AM/AS/EU)。目前值: $COUNTRY"
            exit 1
        fi
    elif [ "$OPERA" != "0" ]; then
         echo "錯誤：OPERA 變數只能是 0 (不啟用) 或 1 (啟用)。目前值: $OPERA"
         exit 1
    fi
    
    # 檢查並處理 IP 模式的設定
    if [ "$IPS" != "4" ] && [ "$IPS" != "6" ]; then
        echo "錯誤：IPS 變數只能是 4 或 6。目前值: $IPS"
        exit 1
    fi

    quicktunnel
else
    echo "使用非預期模式啟動。請參閱 Dockerfile。"
    exit 1
fi
