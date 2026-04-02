FROM ollama/ollama:latest

RUN apt-get update && apt-get install -y nginx gettext-base curl && rm -rf /var/lib/apt/lists/*

ENV OLLAMA_HOST=0.0.0.0:11434
ENV OLLAMA_KEEP_ALIVE=-1
ENV OLLAMA_MODELS=/models
ENV OLLAMA_NO_CLOUD=1

ARG OLLAMA_MODEL=qwen3:30b-a3b
RUN ollama serve & sleep 5 && ollama pull ${OLLAMA_MODEL} && pkill ollama

COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
