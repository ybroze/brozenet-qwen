#!/bin/bash
envsubst '${PORT} ${API_KEY}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
ollama serve &
exec nginx -g 'daemon off;'
