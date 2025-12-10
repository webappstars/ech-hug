FROM caddy:2.8-alpine

WORKDIR /app

RUN apk add --no-cache \
    bash curl ca-certificates tzdata coreutils \
 && update-ca-certificates

COPY index.html /srv/index.html
COPY Caddyfile /etc/caddy/Caddyfile
COPY start.sh /app/start.sh

RUN chmod +x /app/start.sh \
 && chown -R 1000:1000 /app

# HF 默认只路由 7860
ENV WSPORT=7860

USER 1000:1000
CMD ["bash", "/app/start.sh"]
