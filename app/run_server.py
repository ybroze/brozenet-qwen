import http.server
import socketserver
import threading
import http.client
import subprocess
import shlex
import os
import sys

LLAMA_PORT = 8081
PORT = int(os.environ.get("PORT", 8080))
MAX_BODY = 10 * 1024 * 1024  # 10 MB

# Paths that OpenClaw sends without /v1 prefix — rewrite for llama-server
OPENAI_PATHS = ("/chat/completions", "/completions", "/models", "/embeddings")

# Hop-by-hop headers that must not be forwarded
HOP_BY_HOP = frozenset(
    ["transfer-encoding", "connection", "keep-alive", "te", "trailers", "upgrade"]
)


def check_llama_health():
    try:
        conn = http.client.HTTPConnection("localhost", LLAMA_PORT, timeout=2)
        conn.request("GET", "/health")
        resp = conn.getresponse()
        return resp.status == 200
    except Exception:
        return False


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/health", "/healthz", "/", "/ping"):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
            return
        if self.path == "/ready":
            if check_llama_health():
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"OK")
            else:
                self.send_response(503)
                self.end_headers()
                self.wfile.write(b"not ready")
            return
        self.proxy_request()

    def do_POST(self):
        self.proxy_request()

    def proxy_request(self):
        headers_sent = False
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            if content_length > MAX_BODY:
                self.send_response(413)
                self.end_headers()
                self.wfile.write(b"Request body too large")
                return

            # Rewrite: add /v1 prefix if path matches an OpenAI endpoint without it
            path = self.path
            if not path.startswith("/v1/"):
                for p in OPENAI_PATHS:
                    if path == p or path.startswith(p + "?"):
                        path = "/v1" + path
                        break

            body = self.rfile.read(content_length)
            conn = http.client.HTTPConnection("localhost", LLAMA_PORT, timeout=600)

            # Forward headers, skipping hop-by-hop
            fwd_headers = {
                k: v
                for k, v in self.headers.items()
                if k.lower() not in HOP_BY_HOP
            }
            fwd_headers["Host"] = f"localhost:{LLAMA_PORT}"
            conn.request(self.command, path, body=body, headers=fwd_headers)
            resp = conn.getresponse()

            self.send_response(resp.status)
            for header, value in resp.getheaders():
                if header.lower() not in HOP_BY_HOP:
                    self.send_header(header, value)
            self.end_headers()
            headers_sent = True

            # Stream response in chunks (supports SSE/streaming completions)
            while True:
                chunk = resp.read(4096)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except Exception:
            if not headers_sent:
                self.send_response(503)
                self.end_headers()
                self.wfile.write(b"llama-server not ready")

    def log_message(self, format, *args):
        pass


def download_model():
    model_repo = os.environ.get("MODEL_REPO", "")
    model_file = os.environ.get("MODEL_FILE", "")
    model_path = f"/tmp/models/{model_file}"

    if os.path.exists(model_path):
        print(f"Model already exists: {model_path}")
        return model_path

    os.makedirs("/tmp/models", exist_ok=True)
    url = f"https://huggingface.co/{model_repo}/resolve/main/{model_file}"

    cmd = ["curl", "-L", "--fail", "--http1.1", "-o", model_path, "--progress-bar"]
    hf_token = os.environ.get("HF_TOKEN", "")
    if hf_token:
        cmd.extend(["-H", f"Authorization: Bearer {hf_token}"])
    cmd.append(url)

    print(f"Downloading {model_file} from {model_repo}...")
    result = subprocess.run(cmd)
    if result.returncode != 0:
        print("Model download failed!", file=sys.stderr)
        sys.exit(1)

    size_mb = os.path.getsize(model_path) / (1024 * 1024)
    print(f"Download complete: {model_path} ({size_mb:.0f} MB)")
    return model_path


def run_llama(model_path):
    extra_args = shlex.split(os.environ.get("LLAMA_ARGS", ""))
    cmd = [
        "llama-server",
        "--host", "0.0.0.0",
        "--port", str(LLAMA_PORT),
        "--model", model_path,
    ] + extra_args

    # Use HF_TOKEN as API key for defense-in-depth
    hf_token = os.environ.get("HF_TOKEN", "")
    if hf_token:
        cmd.extend(["--api-key", hf_token])

    print(f"Starting: {' '.join(cmd[:6])} ...")
    subprocess.run(cmd)


if __name__ == "__main__":
    # Start health proxy immediately (passes Cloud Run health checks during download)
    server = socketserver.ThreadingTCPServer(("", PORT), ProxyHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"Health proxy listening on :{PORT}")

    # Download GGUF model from HuggingFace
    model_path = download_model()

    # Start llama-server (blocks forever)
    run_llama(model_path)
