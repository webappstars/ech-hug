FROM caddy:2.8-alpine

WORKDIR /app

# 安装 bash / curl 以及常用依赖
RUN apk add --no-cache \
    bash \
    curl \
    ca-certificates \
    tzdata \
    coreutils \
 && update-ca-certificates

# 静态页与 Caddy 配置
COPY index.html /srv/index.html
COPY Caddyfile /etc/caddy/Caddyfile

# 启动脚本
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh \
 && chown -R 1000:1000 /app

# 默认环境变量（按需覆盖）
# 关键：WSPORT 固定 7860 以满足 HF app_port/健康检查
ENV IPS=4 OPERA=0 WSPORT=7860

# Hugging Face 运行时会强制 UID=1000，这里显式设置可让本地行为一致
USER 1000:1000

# 由 start.sh 负责启动 ech/cloudflared/opera，并 exec caddy 前台守护
CMD ["bash", "/app/start.sh"]
