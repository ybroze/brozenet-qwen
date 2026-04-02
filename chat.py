#!/usr/bin/env python3
"""Interactive CLI for Qwen on Cloud Run."""

import json
import os
import sys

import requests

HOST = os.environ.get("QWEN_HOST", "https://qwen.broze.net")
API_KEY = os.environ.get("QWEN_API_KEY")
MODEL = "qwen3:30b-a3b"


def stream_chat(messages):
    resp = requests.post(
        f"{HOST}/api/chat",
        headers={"Authorization": f"Bearer {API_KEY}"},
        json={"model": MODEL, "messages": messages, "stream": True},
        stream=True,
    )
    resp.raise_for_status()

    full = ""
    for line in resp.iter_lines():
        if not line:
            continue
        chunk = json.loads(line)
        token = chunk.get("message", {}).get("content", "")
        print(token, end="", flush=True)
        full += token
    print()
    return full


def main():
    if not API_KEY:
        print("Set QWEN_API_KEY", file=sys.stderr)
        sys.exit(1)

    messages = []
    print("Ctrl-C to quit.\n")

    try:
        while True:
            try:
                user_input = input("> ")
            except EOFError:
                break

            if not user_input.strip():
                continue

            messages.append({"role": "user", "content": user_input})
            reply = stream_chat(messages)
            messages.append({"role": "assistant", "content": reply})
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()
