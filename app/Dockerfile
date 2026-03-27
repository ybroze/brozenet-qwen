FROM ollama/ollama:latest
RUN apt-get update && apt-get install -y nginx gettext-base && rm -rf /var/lib/apt/lists/*
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
