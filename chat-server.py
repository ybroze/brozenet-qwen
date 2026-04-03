#!/usr/bin/env python3
"""Web UI for Qwen on Cloud Run."""

import json
import os
import sys

import requests
from flask import Flask, Response, request

HOST = os.environ.get("QWEN_HOST", "https://qwen.broze.net")
API_KEY = os.environ.get("QWEN_API_KEY")
MODEL = "qwen3:30b-a3b"

app = Flask(__name__)

HTML = """\
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Qwen</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: system-ui, sans-serif; background: #1a1a1a; color: #e0e0e0; height: 100vh; display: flex; flex-direction: column; }
  #messages { flex: 1; overflow-y: auto; padding: 1rem; }
  .msg { max-width: 48rem; margin: 0 auto 1rem; padding: 0.75rem 1rem; border-radius: 0.5rem; white-space: pre-wrap; word-wrap: break-word; }
  .user { background: #2a4a7f; margin-right: 0; margin-left: auto; }
  .assistant { background: #2a2a2a; margin-left: 0; margin-right: auto; }
  #input-bar { display: flex; padding: 0.75rem; background: #111; gap: 0.5rem; }
  #input { flex: 1; padding: 0.75rem; border: 1px solid #333; border-radius: 0.5rem; background: #222; color: #e0e0e0; font-size: 1rem; font-family: inherit; resize: none; }
  #input:focus { outline: none; border-color: #4a7abf; }
  button { padding: 0.75rem 1.5rem; border: none; border-radius: 0.5rem; background: #2a4a7f; color: #e0e0e0; font-size: 1rem; cursor: pointer; }
  button:hover { background: #3a5a9f; }
  button:disabled { opacity: 0.5; cursor: default; }
</style>
</head>
<body>
<div id="messages"></div>
<div id="input-bar">
  <textarea id="input" rows="1" placeholder="Say something..." autofocus></textarea>
  <button id="send" onclick="send()">Send</button>
</div>
<script>
const messages = [];
const messagesEl = document.getElementById('messages');
const inputEl = document.getElementById('input');
const sendBtn = document.getElementById('send');

inputEl.addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
});

function addMsg(role, text) {
  const div = document.createElement('div');
  div.className = 'msg ' + role;
  div.textContent = text;
  messagesEl.appendChild(div);
  messagesEl.scrollTop = messagesEl.scrollHeight;
  return div;
}

async function send() {
  const text = inputEl.value.trim();
  if (!text) return;
  inputEl.value = '';
  sendBtn.disabled = true;

  messages.push({role: 'user', content: text});
  addMsg('user', text);
  const div = addMsg('assistant', '');

  try {
    const resp = await fetch('/api/chat', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({messages}),
    });
    const reader = resp.body.getReader();
    const decoder = new TextDecoder();
    let full = '';

    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      const chunk = decoder.decode(value);
      for (const line of chunk.split('\\n')) {
        if (!line) continue;
        try {
          const token = JSON.parse(line).token;
          if (token) { full += token; div.textContent = full; }
        } catch {}
      }
      messagesEl.scrollTop = messagesEl.scrollHeight;
    }
    messages.push({role: 'assistant', content: full});
  } catch (err) {
    div.textContent = 'Error: ' + err.message;
  }
  sendBtn.disabled = false;
  inputEl.focus();
}
</script>
</body>
</html>
"""


@app.route("/")
def index():
    return HTML


@app.route("/api/chat", methods=["POST"])
def chat():
    messages = request.json["messages"]

    def generate():
        resp = requests.post(
            f"{HOST}/api/chat",
            headers={"Authorization": f"Bearer {API_KEY}"},
            json={"model": MODEL, "messages": messages, "stream": True},
            stream=True,
        )
        resp.raise_for_status()
        for line in resp.iter_lines():
            if not line:
                continue
            chunk = json.loads(line)
            token = chunk.get("message", {}).get("content", "")
            if token:
                yield json.dumps({"token": token}) + "\n"

    return Response(generate(), content_type="application/x-ndjson")


if __name__ == "__main__":
    if not API_KEY:
        print("Set QWEN_API_KEY", file=sys.stderr)
        sys.exit(1)

    import logging

    logging.getLogger("werkzeug").setLevel(logging.ERROR)

    port = int(os.environ.get("PORT", 5000))
    url = f"http://localhost:{port}"
    print(f"Open \033]8;;{url}\033\\{url}\033]8;;\033\\ in your browser. Ctrl-C to quit.")
    app.run(port=port)
