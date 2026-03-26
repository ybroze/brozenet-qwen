# Security: Threat Model & Design Decisions

This document records how we think about the threat profile for the Qwen personal
assistant deployment on Cloud Run, and why we chose the architecture we did.

## What we're protecting

A single-user LLM inference endpoint. The asset value is:

1. **Compute cost** — an L4 GPU at $0.70/hr can run up a bill if hijacked.
2. **The HF token / API key** — reusable credential, though scoped to read-only HF access.
3. **Conversation content** — queries and responses may contain personal or business context.
4. **The GCP project** — broader blast radius if an attacker pivots from the service to the project.

There is no user data store, no PII database, no multi-tenant access. The threat model
is weighted toward **unauthorized compute usage** and **credential exposure**, not data
breach.

## Threat actors we care about

| Actor | Motivation | Likelihood |
|---|---|---|
| Opportunistic scanner | Crypto mining, GPU abuse via exposed API | High (automated) |
| Credential stuffer | Reuse leaked creds to access GCP | Medium |
| Targeted attacker | Access conversation content or pivot to GCP project | Low |
| Supply chain (model) | Malicious GGUF file | Low (flat binary format, no code exec) |
| Insider (self) | Accidental misconfiguration exposing the service | Medium |

We do **not** model nation-state or APT-level threats. The value of this target does not
justify that level of concern.

## Defense-in-depth architecture

Two independent authentication layers are active, either of which blocks unauthorized
access:

### Layer 1: Cloud Run IAM (`--no-allow-unauthenticated`)

Requests without a valid Google identity token are rejected at the infrastructure level
before they reach our container. This is enforced by Google's frontend proxy, not our
code. It stops all opportunistic scanning and unauthenticated access.

### Layer 2: llama-server API key (`--api-key`)

The HF token is reused as a Bearer token on every API call to llama-server. Even if IAM
is somehow bypassed (e.g., `allUsers` accidentally granted), the attacker still needs the
API key to get a response from the model.

### Why two layers?

Either layer alone can fail:
- IAM can be misconfigured (`allUsers` accidentally granted)
- An API key alone is brute-forceable given enough time

The overlap means a misconfiguration in one layer doesn't result in exposure. The
`harden.sh` script verifies both are active.

## Network exposure decisions

We evaluated three network topologies:

1. **Public endpoint with auth stack** (chosen) — Cloud Run's `.run.app` URL is publicly
   reachable regardless of DNS configuration. Adding `qwen.broze.net` as a CNAME to
   `ghs.googlehosted.com` doesn't change the attack surface; it adds a human-readable
   name to an already-public endpoint. Security relies entirely on the auth layers above,
   not network isolation.

2. **Internal-only (`--ingress=internal`)** — Restricts traffic to VPC. Rejected because
   it requires a VPC connector (~$7-10/mo), and any external client (OpenClaw) would need
   VPN or Interconnect access. Adds cost and complexity without meaningful security gain
   given the auth stack already rejects unauthenticated requests at the infrastructure
   level.

3. **Internal + Cloud Load Balancer** — Enables Cloud Armor (WAF, DDoS, geo-blocking).
   Rejected because the load balancer costs ~$18/mo and Cloud Run already has built-in
   DDoS protection. Overkill for a single-user service.

**Key insight:** For a single-user service with two auth layers, network isolation adds
operational cost without proportional security benefit. The auth boundary *is* the
security boundary.

## DNS and TLS

- DNS for `broze.net` is managed via Cloudflare.
- The `qwen` CNAME uses **DNS-only mode** (no Cloudflare proxy) because Cloud Run must
  terminate TLS directly to provision its managed certificate.
- TLS certificates are Google-managed and auto-renewed.

## Service account isolation

The Cloud Run service uses a dedicated `qwen-runner` service account rather than the
default compute SA. This follows least-privilege: the SA only has `secretmanager.secretAccessor`
on the HF token secret and `run.developer` on the service itself. A compromise of this
SA cannot pivot to other GCP resources.

## Container attack surface

| Property | Value | Security implication |
|---|---|---|
| Inference engine | llama.cpp (single C++ binary) | No Python ML stack, no pickle deserialization, no plugin system |
| Model format | GGUF (flat binary) | No code execution on load, unlike PyTorch/safetensors with auto_map |
| Container dependencies | curl, python3 (proxy only) | Minimal surface; proxy is ~100 lines of stdlib-only Python |
| Base image | `ghcr.io/ggml-org/llama.cpp:server-cuda` | Should be pinned to a specific tag in `app/Dockerfile` |

## Residual risks

| Risk | Severity | Mitigation | Status |
|---|---|---|---|
| GCP account compromise | High | 2FA on Google account | Owner responsibility |
| llama-server CVE | Medium | Pin image version, monitor releases | Pin tag in `app/Dockerfile` |
| Accidental IAM misconfiguration | Medium | `harden.sh` checks, two-layer redundancy | Active |
| GGUF supply chain | Low | Use reputable uploaders (bartowski, unsloth, official) | Ongoing judgment call |
| Model outputs harmful content | Medium | Raw model, no content filter | Acceptable for single-user personal assistant |
| Billing runaway | Medium | Cloud Scheduler sleep cron, billing alerts | `harden.sh` checks for budget alert |
| Cloudflare proxy accidentally enabled | Low | Breaks TLS cert provisioning (visible failure, not silent) | Self-correcting |

## What we explicitly chose not to do

- **IAP (Identity-Aware Proxy)** — would add a third auth layer, but project is not under
  a GCP organization, which makes IAP setup manual and hard to automate. Revisit if the
  project moves under an org.
- **VPC / private networking** — cost and complexity disproportionate to threat model.
- **Cloud Armor / WAF** — Cloud Run's built-in protections suffice for single-user.
- **Content filtering** — this is a personal assistant, not a public-facing product.
- **Zonal redundancy** — single instance, single user; zone failure = brief downtime, not data loss.
- **Separate API key management** — reusing HF token as API key is a pragmatic tradeoff;
  rotating it means updating one secret, not two.
