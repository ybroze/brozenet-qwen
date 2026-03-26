# Logging

## How logs flow

Everything in this deployment logs to stdout/stderr, which Cloud Run automatically
captures and forwards to Cloud Logging.

```
llama-server  (stdout/stderr)  ──> Cloud Run container logs ──> Cloud Logging
Cloud Run platform             ──────────────────────────────> Cloud Logging (system logs)
```

## What gets logged

| Source | Content | Destination |
|---|---|---|
| Cloud Run platform | Instance startup/shutdown, health probe results, scaling events, revision deployments | Cloud Logging (`resource.type=cloud_run_revision`) |
| Entrypoint (curl) | Model download progress | Cloud Logging (stdout) |
| `llama-server` | Model loading, inference requests, token generation stats (tokens/s), errors | Cloud Logging (stderr) |

## What does NOT get logged

- **Request/response bodies** — no conversation content appears in logs. llama-server
  logs request metadata (timing, token counts) but not the prompts or completions.
- **API key / HF token** — llama-server does not echo the `--api-key` value. The Ansible
  playbook uses `no_log: true` when handling the token.

## Viewing logs

Recent logs:
```bash
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=qwen-llm" \
  --project=broze-net --limit=50 \
  --format="table(timestamp,textPayload)"
```

Filter to llama-server only (inference activity):
```bash
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=qwen-llm AND textPayload:\"slot\"" \
  --project=broze-net --limit=20 \
  --format="table(timestamp,textPayload)"
```

Errors only:
```bash
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=qwen-llm AND severity>=ERROR" \
  --project=broze-net --limit=20 \
  --format="table(timestamp,textPayload)"
```

Logs are also available in the Cloud Console at the URL printed by Ansible on deploy
failure, or via: Cloud Console -> Cloud Run -> `qwen-llm` -> Logs.

## Retention

Cloud Logging retains logs for **30 days** by default. There is no custom retention or
export configured. If longer retention is needed, set up a log sink to Cloud Storage or
BigQuery:

```bash
# Example: export to a Cloud Storage bucket (not currently configured)
gcloud logging sinks create qwen-log-archive \
  storage.googleapis.com/BUCKET_NAME \
  --log-filter="resource.type=cloud_run_revision AND resource.labels.service_name=qwen-llm" \
  --project=broze-net
```
