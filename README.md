# Ollama on Cloud Run

*Do you want Qwen? Because this is how we get Qwen.*

Ollama serving an LLM on a Cloud Run GPU instance. Scale-to-zero with a wake/sleep schedule.

## Configuration

Nothing is hardcoded. You provide two values everywhere they're needed:

| Variable | Where | Example |
|----------|-------|---------|
| `project_id` | `deploy.sh` `-e` arg | `my-gcp-project` |
| `domain` | `deploy.sh` `-e` arg | `llm.example.com` |
| `QWEN_HOST` | Environment variable for client scripts | `https://llm.example.com` |
| `QWEN_API_KEY` | Environment variable for client scripts | *(auto-generated on first deploy)* |

## Prerequisites

- `pip install -r requirements.txt && pip install ansible`
- GPU quota: request 1x L4 in your target region at [Cloud Console Quotas](https://console.cloud.google.com/iam-admin/quotas) (filter "Total Nvidia L4 GPU allocation without zonal redundancy")
- A custom domain with DNS managed by you (point it at the Cloud Run service after first deploy)

## Deploy

```bash
./deploy.sh -e project_id=my-gcp-project -e domain=llm.example.com
```

The first deploy generates an API key in Secret Manager. Retrieve it with:

```bash
gcloud secrets versions access latest --secret=qwen-api-key --project=my-gcp-project
```

## Usage

All client scripts require `QWEN_HOST` and `QWEN_API_KEY`:

```bash
export QWEN_HOST=https://llm.example.com
export QWEN_API_KEY=$(gcloud secrets versions access latest --secret=qwen-api-key --project=my-gcp-project)
```

### Interactive Chat

```bash
./chat.py
```

Streams responses token-by-token. Maintains conversation history within the session. `Ctrl-C` to quit.

### Web UI

```bash
./chat-server.py
```

Then open [http://localhost:5000](http://localhost:5000) in your browser.

### One-Shot API Call

```bash
curl -H "Authorization: Bearer $QWEN_API_KEY" \
  "$QWEN_HOST/api/chat" \
  -d '{"model":"qwen3:30b-a3b","messages":[{"role":"user","content":"Hello"}],"stream":false}'
```

### Smoke Tests

```bash
./test.sh
```

Checks health endpoint, auth rejection, model listing, and a round-trip chat completion.

## Wake / Sleep

Automatic via Cloud Scheduler: wakes at 7 AM, sleeps at 9 PM (America/Chicago).

Manual override:

```bash
# wake
gcloud run services update qwen-llm --min-instances=1 --region=us-east4 --project=my-gcp-project

# sleep
gcloud run services update qwen-llm --min-instances=0 --region=us-east4 --project=my-gcp-project
```

## Architecture

- `app/Dockerfile` — Ollama + nginx, model baked in at build time
- `app/entrypoint.sh` — starts nginx (foreground) and Ollama (background)
- `app/nginx.conf.template` — bearer token auth, reverse proxy to Ollama
- `ansible/playbook.yml` — provisions APIs, SA, secrets, Cloud Build, Cloud Run, scheduler, domain
- `deploy.sh` — one-line wrapper around the Ansible playbook
