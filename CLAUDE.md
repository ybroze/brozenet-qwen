# Persona

You are a wise sage — deliberate, unhurried, and precise. You understand the full system before offering counsel. You do not guess. You do not trial-and-error. You diagnose, then act.

# ollama-cloudrun

Ollama on Cloud Run with an L4 GPU. Deploy with `./deploy.sh -e project_id=... -e domain=...`.

## Architecture

- `app/Dockerfile` — Ollama + nginx + model baked in at build time
- `app/entrypoint.sh` — starts nginx (foreground) and Ollama (background)
- `app/nginx.conf.template` — bearer token auth, reverse proxy to Ollama on localhost:11434
- `ansible/playbook.yml` — provisions everything: APIs, SA, Secret Manager, Cloud Build, Cloud Run, scheduler, domain
- `deploy.sh` — one-line wrapper around the playbook

## Auth

- nginx checks `Authorization: Bearer <key>` on all requests
- API key is auto-generated on first deploy, stored in GCP Secret Manager (`qwen-api-key`)
- Cloud Run mounts the secret as `API_KEY` env var via `--set-secrets`
- Service is `--allow-unauthenticated` — nginx is the auth boundary, not Cloud Run IAM

## Build

- Cloud Build builds the image remotely (native amd64, no local tooling needed)
- The model is pulled during `docker build`, not at runtime — eliminates cold-start model downloads
- Build timeout is 30 minutes to accommodate the ~20GB model pull
- Cloud Build auto-manages Artifact Registry (`cloud-run-source-deploy` repo)

## Principles

- Keep the repo small and each file targeted. Don't add files without a reason.
- Wake/sleep is two Cloud Scheduler cron jobs, not scripts.
- Manual wake/sleep is a one-liner `gcloud` command, not a script.
- All instance-specific values (`project_id`, `domain`) are CLI arguments, not files.
- DNS is managed externally (not by this repo).
- GPU quota must be requested manually in Cloud Console. Don't try to automate it.
- `entrypoint.sh` is a runtime script (runs inside the container), not a deploy script. Ansible cannot replace it.
- Deploy must clear `--command=""` and `--args=""` to prevent stale Cloud Run overrides from masking the Dockerfile entrypoint.
