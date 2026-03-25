# Qwen3.5-122B Personal Assistant on GCP Cloud Run (Ansible + IAP + qwen.broze.net)

One-command repeatable deployment of the 122B-A10B MoE model (FP8) with:
- Always-warm instance (min-instances=1)
- IAP auth (secure personal use)
- Custom domain qwen.broze.net

## Quick Start
1. `cp ansible/vars.yml ansible/vars.yml` and fill in your project_id + HF_TOKEN
2. `./deploy.sh`
3. Add the DNS records that gcloud prints
4. One-time: Enable IAP in Cloud Console → Security tab (OAuth consent if first time)

First deploy ≈ 15–20 min (model download). After that: instant.
