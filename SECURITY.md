# Security

## Threat profile

This is a single-user LLM endpoint exposed to the public internet. The
primary threats are unauthorized usage (running up GPU costs) and prompt
injection via the Ollama API. There is no user data, no database, and no
multi-tenancy.

## Auth model

Authentication is a single bearer token checked by nginx at the edge.
Cloud Run IAM is **not** the auth boundary (`--allow-unauthenticated`).

- API key: auto-generated `secrets.token_urlsafe(48)` (64 characters,
  288 bits of entropy), stored in GCP Secret Manager.
- Cloud Run mounts the secret as the `API_KEY` environment variable.
- nginx rejects any request without `Authorization: Bearer <key>`.
- There is no session management, no OAuth, no user accounts.

## Attack surface

| Layer | Exposure | Mitigation |
|---|---|---|
| nginx | Public internet on port 443 (via Cloud Run) | Bearer token required on every request |
| Ollama | localhost:11434 only | Not reachable from outside the container |
| Cloud Run | `--allow-unauthenticated` | nginx is the auth boundary |
| Secret Manager | GCP IAM | Only the `qwen-runner` SA has `secretAccessor` |
| Scheduler | GCP IAM | Uses OAuth SA impersonation, not a stored key |
| Container | Ollama + nginx + base image | No SSH, no shell access, ephemeral filesystem |

## What this does not protect against

- Compromise of the bearer token (shared secret, no rotation mechanism).
- Prompt injection or model abuse by an authenticated caller.
- Supply-chain attacks in the Ollama base image.
- GCP account compromise.

## Credential rotation

No automated rotation exists. To rotate the API key:

```bash
printf "$(python3 -c "import secrets; print(secrets.token_urlsafe(48), end='')")" \
  | gcloud secrets versions add qwen-api-key --data-file=- --project=broze-net
gcloud run services update qwen-llm --region=us-east4  # picks up latest secret version
```

## Scale-to-zero as defense

When the service is sleeping (9 PM -- 7 AM CT), there are zero running
instances. No container means no attack surface beyond GCP's own control
plane.
