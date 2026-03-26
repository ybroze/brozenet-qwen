# Qwen Personal Assistant on GCP Cloud Run

Self-hosted LLM inference endpoint at `https://qwen.broze.net`, powered by [llama.cpp](https://github.com/ggml-org/llama.cpp) on a single NVIDIA L4 GPU. Designed as an OpenAI-compatible backend for [OpenClaw](https://openclaw.ai/).

### What you get

- **Qwen3-30B-A3B** (MoE, 3.3B active params) at Q4_K_M quantization — near-frontier quality at low compute cost
- **llama.cpp inference** — single C++ binary, minimal attack surface, no Python ML dependencies
- **Scale-to-zero** by default — no GPU charges when idle
- **Cloud Scheduler** auto-wakes at 7 AM, sleeps at 9 PM (configurable). Manual override scripts included.
- **OpenAI-compatible API** at the root path (no `/v1` prefix required) — drop-in for OpenClaw
- **Defense in depth** — Cloud Run IAM + llama-server API key
- **~$294/mo** on the default 7am-9pm schedule (L4 at $0.70/hr x 14 hrs/day)

---

## Initial Provisioning

### 1. GCP project

```bash
gcloud auth login
gcloud config set project broze-net
```

The playbook enables required APIs automatically (Cloud Run, Secret Manager, Artifact Registry, Cloud Scheduler).

### 2. GPU quota (manual step — requires human approval)

Cloud Run GPU instances require quota that **cannot be fully automated**. The playbook
attempts a programmatic quota request via `gcloud beta quotas preferences create`, but
GCP typically auto-denies these for GPU resources and sets `grantedValue: 0`. This is a
Google-side policy: GPU quota requests are routed to a human reviewer regardless of how
they are submitted.

**Steps to request quota manually:**

1. Go to the [Cloud Console Quotas page](https://console.cloud.google.com/iam-admin/quotas)
   for your project.
2. Filter for **"Total Nvidia L4 GPU allocation without zonal redundancy"**.
3. Select the `us-east4` row and click **Edit Quotas**.
4. Set the new limit to `1` and provide a justification (e.g., "Single L4 for LLM inference on Cloud Run").
5. Submit and wait for the approval email (typically hours to a couple of days for a single GPU).
6. Once approved, re-run `./deploy.sh` — the playbook will detect the granted quota and proceed.

### 3. Hugging Face token

Needed if the GGUF repo is gated. Create a read token at https://huggingface.co/settings/tokens.

### 4. Secrets file

Copy `secrets.example.yml` and fill in your values:

```yaml
project_id: "your-gcp-project-id"
qwen_hf_token: "hf_your_token_here"
```

### 5. Deploy

```bash
pip install ansible   # if not installed
./deploy.sh --extra-vars @/path/to/secrets.yml
```

First deploy: ~10 min (container build). First cold start after that: ~5-10 min (GGUF download + model load into GPU).

### 6. DNS records

```bash
gcloud beta run domain-mappings describe --domain=qwen.broze.net --region=us-east4
```

Add the A/AAAA records to your DNS provider.

### 7. Test

The GPU auto-wakes at 7:00 AM and sleeps at 9:00 PM (America/Chicago). To test immediately:

```bash
./wake.sh @/path/to/secrets.yml 1h
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
     https://qwen.broze.net/v1/chat/completions \
     -d '{"model":"qwen","messages":[{"role":"user","content":"Hello"}]}'
```

---

## Wake / Sleep

The GPU costs ~$0.70/hr. Pay nothing when idle.

**Automatic (Cloud Scheduler):** The playbook creates two cron jobs:
- `0 7 * * *` — wake at 7:00 AM (sets min-instances=1)
- `0 21 * * *` — sleep at 9:00 PM (sets min-instances=0)

Timezone and schedule are configurable in `ansible/vars.yml`.

**Manual override:**

```bash
./wake.sh @/path/to/secrets.yml          # wake now (indefinitely)
./wake.sh @/path/to/secrets.yml 2h       # wake for 2 hours, then auto-sleep
./sleep.sh @/path/to/secrets.yml         # sleep now
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

Configure OpenClaw with `qwen.broze.net` as an OpenAI-compatible provider. The service accepts requests with or without the `/v1` prefix:

```
https://qwen.broze.net/chat/completions      -> works
https://qwen.broze.net/v1/chat/completions   -> also works
https://qwen.broze.net/models                -> also works
```

---

## Subsequent Deploys

```bash
./deploy.sh --extra-vars @/path/to/secrets.yml        # redeploy (idempotent)
./deploy.sh --extra-vars @/path/to/secrets.yml -vvv   # verbose mode
```

---

## Configuration

All non-secret config lives in `ansible/vars.yml`. See that file for the full list with comments. Key settings:

| Variable | Default | Description |
|---|---|---|
| `region` | `us-east4` | GCP region (must have L4 quota) |
| `service_name` | `qwen-llm` | Cloud Run service name |
| `model_repo` / `model_file` | Qwen3-30B-A3B Q4_K_M | HuggingFace GGUF to download |
| `llama_image` | stock llama.cpp server-cuda | Base container image |
| `wake_cron` / `sleep_cron` | 7am / 9pm | Cloud Scheduler cron expressions |
| `schedule_timezone` | `America/Chicago` | Timezone for wake/sleep schedule |

Secrets (`project_id`, `qwen_hf_token`) are passed at deploy time via `--extra-vars @/path/to/secrets.yml`. See `secrets.example.yml` for the template.

### Switching models

Change `model_repo` and `model_file` in `ansible/vars.yml`, then redeploy. Some options:

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
OpenClaw Gateway
  |
  | HTTPS
  v
qwen.broze.net (Cloud Run, no unauthenticated access)
  |
  | port 8080
  v
llama-server (single C++ binary, --api-key)
  |
  | Q4_K_M GGUF, n-gpu-layers=99
  v
Qwen3-30B-A3B on NVIDIA L4 (24 GB)
```

The container runs the stock llama.cpp `server-cuda` image. At startup, an inline entrypoint downloads the GGUF from HuggingFace and launches `llama-server` on port 8080 with the API key from Secret Manager.

### File layout

| File | Purpose |
|---|---|
| `deploy.sh` | Loads secrets, runs Ansible playbook |
| `harden.sh` | Post-deploy security verification (IAM, billing alerts, image pin) |
| `wake.sh` / `sleep.sh` | Manual GPU wake/sleep (sets min-instances 1 or 0) |
| `ansible/playbook.yml` | Full deployment: APIs, secrets, Artifact Registry, Cloud Run, domain, scheduler |
| `ansible/vars.yml` | Non-secret config (model, GPU, scaling, schedule) |
| `secrets.example.yml` | Template for the secrets file |

---

## Security & Hardening

See [SECURITY.md](SECURITY.md) for the full threat model and design decisions.

Run `./harden.sh @/path/to/secrets.yml` after deploy to verify:

1. No `allUsers` / `allAuthenticatedUsers` in Cloud Run IAM
2. Artifact Registry repo is not publicly readable
3. Secret Manager secret has no public access
4. A billing budget/alert exists on the project
5. llama.cpp image is pinned to a specific version tag

## Logging

See [LOGGING.md](LOGGING.md) for log sources, viewing commands, and retention policy.
