# 選擇 Debian 作為基礎映像
FROM debian:latest

# 設定工作目錄
WORKDIR /app

# 安裝必要的套件：bash 和 curl
RUN apt-get update &&\
    apt-get install -y curl

# 設定環境變數的預設值，這些變數對應腳本的配置
# 注意：WSPORT 預設為空，在 start.sh 中會檢查並隨機分配
ENV OPERA=0 \
    COUNTRY=AM \
    IPS=4 \
    TOKEN="" \
    WSPORT=""

# 將啟動腳本複製到容器中
COPY start.sh .

# 賦予啟動腳本執行權限
RUN chmod +x start.sh

# 定義容器啟動時執行的指令
CMD ["./start.sh", "1"]

# 暴露端口僅為說明用途，實際連線透過 Cloudflare Tunnel (443)
EXPOSE 7860
