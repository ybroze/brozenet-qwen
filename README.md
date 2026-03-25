# Qwen Personal Assistant on GCP Cloud Run

Self-hosted LLM inference endpoint at `https://qwen.broze.net`, powered by [llama.cpp](https://github.com/ggml-org/llama.cpp) on a single NVIDIA L4 GPU. Designed as an OpenAI-compatible backend for [OpenClaw](https://openclaw.ai/).

### What you get

- **Qwen3-30B-A3B** (MoE, 3.3B active params) at Q4_K_M quantization — near-frontier quality at low compute cost
- **llama.cpp inference** — single C++ binary, minimal attack surface, no Python ML dependencies
- **Scale-to-zero** by default — no GPU charges when idle
- **Cloud Scheduler** auto-wakes at 7 AM, sleeps at 9 PM (configurable). Manual override scripts included.
- **OpenAI-compatible API** at the root path (no `/v1` prefix required) — drop-in for OpenClaw
- **Defense in depth** — Cloud Run IAM + IAP + llama-server API key
- **~$294/mo** on the default 7am-9pm schedule (L4 at $0.70/hr x 14 hrs/day)

---

## Initial Provisioning

### 1. GCP project

```bash
gcloud auth login
gcloud config set project broze-net
```

The playbook enables required APIs automatically (Cloud Run, Cloud Build, Secret Manager, IAP, Artifact Registry).

### 2. GPU quota

Request `nvidia-l4` quota for `us-central1`:

```
Cloud Console -> IAM & Admin -> Quotas -> filter "Cloud Run GPU"
```

### 3. Hugging Face token

Needed if the GGUF repo is gated. Create a read token at https://huggingface.co/settings/tokens.

### 4. Secrets file

Add to `~/Secrets/ziggy-ansible-secrets.yml`:

```yaml
project_id: "broze-net"
qwen_hf_token: "hf_your_token_here"
```

### 5. Deploy

```bash
pip install ansible   # if not installed
./deploy.sh
```

First deploy: ~10 min (container build). First cold start after that: ~5-10 min (GGUF download + model load into GPU).

### 6. DNS records

```bash
gcloud run domain-mappings describe --domain=qwen.broze.net --region=us-central1
```

Add the A/AAAA records to your DNS provider.

### 7. Enable IAP (one-time)

1. Cloud Console -> Cloud Run -> qwen-personal-assistant -> Security
2. Turn on Identity-Aware Proxy
3. Create OAuth consent screen if prompted (internal, single-user)
4. Add your Google account

### 8. Test

The GPU auto-wakes at 7:00 AM and sleeps at 9:00 PM (America/Chicago). To test immediately:

```bash
./wake.sh 1h
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
     https://qwen.broze.net/chat/completions \
     -d '{"model":"qwen","messages":[{"role":"user","content":"Hello"}]}'
```

---

## Wake / Sleep

The GPU costs ~$0.70/hr. Pay nothing when idle.

**Automatic (Cloud Scheduler):** The playbook creates two cron jobs:
- `0 7 * * *` — wake at 7:00 AM (sets min-instances=1)
- `0 21 * * *` — sleep at 9:00 PM (sets min-instances=0)

Timezone and schedule are configurable in `vars.yml`.

**Manual override:** The local scripts still work for ad-hoc use outside the schedule:

```bash
./wake.sh          # wake now (indefinitely)
./wake.sh 2h       # wake for 2 hours, then auto-sleep
./sleep.sh         # sleep now
```

Note: a manual wake will be overridden by the next scheduled sleep, and vice versa. This is usually what you want.

| Usage pattern | Monthly cost |
|---|---|
| 7am-9pm daily (default schedule) | ~$294 |
| 12 hrs/day, every day | ~$252 |
| 4 hrs/day, weekdays | ~$60 |
| On-demand, ~10 hrs/week | ~$30 |

---

## OpenClaw Integration

Configure OpenClaw with `qwen.broze.net` as an OpenAI-compatible provider. The proxy accepts requests with or without the `/v1` prefix:

```
https://qwen.broze.net/chat/completions      -> works
https://qwen.broze.net/v1/chat/completions   -> also works
https://qwen.broze.net/models                -> also works
```

No `/v1` suffix needed in the base URL. The proxy rewrites paths transparently for llama-server.

---

## Subsequent Deploys

```bash
./deploy.sh        # redeploy (idempotent)
./deploy.sh -vvv   # verbose mode
```

---

## Configuration

### `ansible/vars.yml` (committed, non-secret)

| Variable | Default | Description |
|---|---|---|
| `region` | `us-central1` | GCP region (must have L4 quota) |
| `service_name` | `qwen-personal-assistant` | Cloud Run service name |
| `custom_domain` | `qwen.broze.net` | Custom domain |
| `gpu_type` | `nvidia-l4` | GPU type |
| `cpu` | `8` | vCPUs |
| `memory` | `32Gi` | Container memory |
| `model_repo` | `bartowski/Qwen_Qwen3-30B-A3B-GGUF` | HuggingFace GGUF repo |
| `model_file` | `Qwen_Qwen3-30B-A3B-Q4_K_M.gguf` | GGUF filename |
| `llama_args` | `--n-gpu-layers 99 --ctx-size 16384` | Extra llama-server flags |
| `min_instances` | `0` | Min instances (0 = scale to zero) |
| `max_instances` | `1` | Max instances |
| `concurrency` | `4` | Max concurrent requests per instance |
| `wake_cron` | `0 7 * * *` | Cloud Scheduler wake cron expression |
| `sleep_cron` | `0 21 * * *` | Cloud Scheduler sleep cron expression |
| `schedule_timezone` | `America/Chicago` | Timezone for wake/sleep schedule |

### `~/Secrets/ziggy-ansible-secrets.yml` (never committed)

| Variable | Description |
|---|---|
| `project_id` | GCP project ID |
| `qwen_hf_token` | HuggingFace token (also used as llama-server API key) |

### Switching models

Change `model_repo` and `model_file` in `vars.yml`, then `./deploy.sh`. Some options:

| Model | GGUF file | VRAM (Q4_K_M) | Quality |
|---|---|---|---|
| Qwen3-30B-A3B (default) | `Qwen_Qwen3-30B-A3B-Q4_K_M.gguf` | 18.6 GB | Excellent, fast (MoE) |
| Qwen3-32B | `Qwen3-32B-Q4_K_M.gguf` | 19.8 GB | Excellent, dense |
| Qwen3-Coder-30B-A3B | `Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf` | 18.6 GB | Coding specialist |
| Gemma 3 27B | `gemma-3-27b-it-Q4_K_M.gguf` | 16.5 GB | Good + vision |
| Mistral Small 3.1 24B | `Mistral-Small-3.1-24B-Instruct-2503-Q4_K_M.gguf` | 14.3 GB | Compact, Apache 2.0 |

Verify exact filenames on HuggingFace before deploying. All fit on L4 (24 GB) at Q4_K_M.

---

## Architecture

```
OpenClaw Gateway (ziggy.broze.net)
  |
  | HTTPS
  v
qwen.broze.net (Cloud Run, IAP-protected)
  |
  | port 8080
  v
run_server.py (health proxy, ~50 lines Python)
  |  /health         -> 200 OK (always, keeps container alive during model download)
  |  /ready          -> checks llama-server /health (503 until loaded)
  |  /chat/...       -> rewrites to /v1/chat/... and proxies to llama-server
  |  /v1/chat/...    -> proxies directly to llama-server
  |
  | port 8081
  v
llama-server (single C++ binary, --api-key)
  |
  | Q4_K_M GGUF, n-gpu-layers=99
  v
Qwen3-30B-A3B on NVIDIA L4 (24 GB)
```

### File layout

| File | Purpose |
|---|---|
| `deploy.sh` | Loads secrets, runs Ansible playbook |
| `harden.sh` | Post-deploy security verification (IAP, IAM, billing alerts, image pin) |
| `wake.sh` | Sets min-instances=1, waits for ready, optional auto-sleep timer |
| `sleep.sh` | Sets min-instances=0, GPU scales to zero |
| `ansible/playbook.yml` | Full deployment: APIs, secrets, Artifact Registry, Cloud Build, Cloud Run, domain |
| `ansible/vars.yml` | Non-secret config (model, GPU, scaling) |
| `app/run_server.py` | Health proxy + model downloader + path rewriter (only Python in the container) |
| `app/Dockerfile` | llama.cpp server-cuda base + curl + python3-minimal |

---

## Security Profile

### Attack surface comparison (old vs new)

| | vLLM (old) | llama.cpp (current) |
|---|---|---|
| Inference engine | Python + CUDA (60+ pip packages) | Single C++ binary |
| Web framework | FastAPI + uvicorn | Built-in HTTP server |
| Dependencies in container | PyTorch, transformers, protobuf, etc. | curl, python3-minimal (proxy only) |
| Known critical CVEs | 5+ (RCE via pickle, SSRF, auto_map) | 2 (buffer overflow, OOB write) |
| Deserialization risk | pickle.loads on network data | None (GGUF is a flat binary format) |
| Plugin/extension system | Yes (entry points) | No |
| Docker image size | Multi-GB | ~hundreds of MB |

### Authentication layers

| Layer | What it does |
|---|---|
| **Cloud Run IAM** (`--no-allow-unauthenticated`) | Rejects requests without valid Google identity token |
| **Identity-Aware Proxy (IAP)** | Browser-based Google login, JWT validation |
| **llama-server API key** (`--api-key`) | Requires Bearer token on every API call |

### Secrets management

| Secret | Storage | Notes |
|---|---|---|
| HF token | GCP Secret Manager, mounted at runtime | Also used as llama-server API key. `no_log: true` in playbook. |
| Project ID | `~/Secrets/ziggy-ansible-secrets.yml` | Never committed |

### Residual risks

| Risk | Severity | Mitigation |
|---|---|---|
| GCP account compromise | High | 2FA on Google account |
| llama-server CVE (OOB write, buffer overflow) | Medium | Pin version, monitor releases |
| GGUF supply chain (malicious model file) | Low | Use reputable GGUF uploaders (bartowski, unsloth, official) |
| Model outputs harmful content | Medium | Raw model, no content filter. Don't expose to untrusted users. |

### Hardening script

Run after deploy and IAP setup to verify everything is locked down:

```bash
./harden.sh
```

Checks all six items automatically:

1. IAP is enabled on the Cloud Run service
2. No `allUsers` / `allAuthenticatedUsers` in Cloud Run IAM
3. Artifact Registry repo is not publicly readable
4. Secret Manager secret has no public access
5. A billing budget/alert exists on the project
6. Dockerfile is pinned to a specific llama.cpp version tag

Reports PASS/FAIL/WARN for each. Non-zero exit on any failure.
