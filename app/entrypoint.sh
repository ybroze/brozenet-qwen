#!/bin/bash
set -e

export OLLAMA_HOST="0.0.0.0:${PORT:-8080}"

ollama serve &

echo "Waiting for Ollama..."
until curl -sf "http://localhost:${PORT:-8080}/" >/dev/null 2>&1; do sleep 1; done

echo "Pulling ${OLLAMA_MODEL}..."
ollama pull "${OLLAMA_MODEL}"

wait
