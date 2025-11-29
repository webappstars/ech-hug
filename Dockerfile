# 選擇 Alpine Linux 作為基礎映像，因為它輕量且腳本中支援
FROM alpine:latest

# 設定工作目錄
WORKDIR /app

# 安裝必要的套件：curl 用於下載檔案，screen 雖然在 start.sh 中被替換，但為了讓 start.sh 腳本更容易理解，保留安裝步驟，但實際上我們將使用不同的方式啟動服務。
# 為了穩定和簡化，我們只安裝 curl 和 bash。由於是後台運行，不需要 screen。
RUN apk update && \
    apk add --no-cache bash curl

# 設定環境變數的預設值
# 這些變數對應您腳本中的交互式輸入
ENV OPERA=0 \
    COUNTRY=AM \
    IPS=4 \
    TOKEN="" \
    # 設置容器不會退出的預設命令
    KEEP_ALIVE_CMD="/bin/bash -c 'trap : TERM INT; sleep infinity & wait'"


# 將啟動腳本複製到容器中
COPY start.sh .

# 賦予啟動腳本執行權限
RUN chmod +x start.sh

# 定義容器啟動時執行的指令
# 執行 start.sh，並使用參數 1 執行 quicktunnel 邏輯
CMD ["./start.sh", "1"]

# 由於cloudflared可能會啟動web伺服器（metrics），暴露一個端口（雖然默認在127.0.0.1）
# 443 是 cloudflare 預設的對外連線端口 (透過 cloudflare tunnel)
# 8080 是 Metrics 端口的預設值
EXPOSE 7860
