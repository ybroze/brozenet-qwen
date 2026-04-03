# Qwen on Cloud Run

Ollama serving Qwen3 30B-A3B on an L4 GPU via Cloud Run. Scale-to-zero with a wake/sleep schedule. ~$294/mo at 7am–9pm daily.

## Prerequisites

- `pip install -r requirements.txt && pip install ansible`
- GPU quota: request 1x L4 in `us-east4` at [Cloud Console Quotas](https://console.cloud.google.com/iam-admin/quotas) (filter "Total Nvidia L4 GPU allocation without zonal redundancy")

## Deploy

```bash
./deploy.sh        # builds via Cloud Build, deploys to Cloud Run
./deploy.sh -vvv   # verbose
```

The first deploy generates an API key in Secret Manager. Retrieve it with:

```bash
gcloud secrets versions access latest --secret=qwen-api-key --project=broze-net
```

## Usage

Export your API key:

```bash
export QWEN_API_KEY=$(gcloud secrets versions access latest --secret=qwen-api-key --project=broze-net)
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
  https://qwen.broze.net/api/chat \
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
gcloud run services update qwen-llm --min-instances=1 --region=us-east4 --project=broze-net

# sleep
gcloud run services update qwen-llm --min-instances=0 --region=us-east4 --project=broze-net
```

## Architecture

- `app/Dockerfile` — Ollama + nginx, model baked in at build time
- `app/entrypoint.sh` — starts nginx (foreground) and Ollama (background)
- `app/nginx.conf.template` — bearer token auth, reverse proxy to Ollama
- `ansible/playbook.yml` — provisions APIs, SA, secrets, Cloud Build, Cloud Run, scheduler, domain
- `deploy.sh` — one-line wrapper around the Ansible playbook
