#!/bin/bash
set -e

envsubst '${PORT} ${API_KEY}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
nginx

export OLLAMA_HOST="127.0.0.1:11434"
ollama serve &

echo "Waiting for Ollama..."
until ollama list >/dev/null 2>&1; do sleep 1; done

echo "Pulling ${OLLAMA_MODEL}..."
ollama pull "${OLLAMA_MODEL}"

wait
