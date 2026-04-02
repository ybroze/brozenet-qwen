# Qwen on Cloud Run

Ollama + L4 GPU on Cloud Run. Scale-to-zero. ~$294/mo on a 7am–9pm schedule.

## Prerequisites

- `pip install ansible`
- GPU quota: request 1x L4 in `us-east4` at [Cloud Console Quotas](https://console.cloud.google.com/iam-admin/quotas) (filter "Total Nvidia L4 GPU allocation without zonal redundancy")

## Deploy

```bash
./deploy.sh        # builds via Cloud Build, deploys to Cloud Run
./deploy.sh -vvv   # verbose
```

## API Key

The first deploy generates an API key in Secret Manager. Retrieve it with:

```bash
gcloud secrets versions access latest --secret=qwen-api-key --project=broze-net
```

## Test

```bash
curl -H "Authorization: Bearer <api-key>" \
  https://qwen.broze.net/v1/chat/completions \
  -d '{"model":"qwen3:30b-a3b","messages":[{"role":"user","content":"Hello"}]}'
```

## Wake / Sleep

Automatic via Cloud Scheduler: wakes at 7 AM, sleeps at 9 PM (America/Chicago).

Manual override:
```bash
gcloud run services update qwen-llm --min-instances=1 --region=us-east4 --project=broze-net  # wake
gcloud run services update qwen-llm --min-instances=0 --region=us-east4 --project=broze-net  # sleep
```
