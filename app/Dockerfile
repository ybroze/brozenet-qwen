# Pin to a specific release for supply chain security.
# Check https://github.com/ggml-org/llama.cpp/pkgs/container/llama.cpp for tags.
FROM ghcr.io/ggml-org/llama.cpp:server-cuda

# Minimal additions: curl for model download, python3 for health proxy only
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3-minimal curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY run_server.py /run_server.py

EXPOSE 8080

ENTRYPOINT ["python3", "/run_server.py"]
