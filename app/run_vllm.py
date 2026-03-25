import http.server
import socketserver
import threading
import http.client
import time
import os

VLLM_PORT = 8081
PORT = 8080

class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in ["/health", "/healthz", "/", "/ping"]:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK - starting up...")
            return
        self.proxy_request()

    def do_POST(self):
        self.proxy_request()

    def proxy_request(self):
        try:
            conn = http.client.HTTPConnection("localhost", VLLM_PORT, timeout=30)
            conn.request(self.command, self.path, body=self.rfile.read(int(self.headers.get('Content-Length', 0))), headers=dict(self.headers))
            resp = conn.getresponse()
            self.send_response(resp.status)
            for header, value in resp.getheaders():
                self.send_header(header, value)
            self.end_headers()
            self.wfile.write(resp.read())
        except Exception:
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b"vLLM still starting...")

def run_vllm():
    os.system("python3 -m vllm.entrypoints.openai.api_server " + " ".join(os.environ.get("CMD_ARGS", "").split()))

if __name__ == "__main__":
    threading.Thread(target=run_vllm, daemon=True).start()
    with socketserver.ThreadingTCPServer(("", PORT), ProxyHandler) as httpd:
        httpd.serve_forever()
