# Qwen / Ollama on Cloud Run

*Do you want Qwen? Because this is how you get Qwen.*

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

Then open [http://localhost:5678](http://localhost:5678) in your browser.

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

## Novice's Guide

If Yuri gave you an API key and you've never used a terminal before, this section is for you.

### 1. Open a terminal

- **Mac** — Open Spotlight (`Cmd + Space`), type `Terminal`, press Enter.
- **Windows** — Install [Git for Windows](https://gitforwindows.org/). It includes Git Bash, which is your terminal. Open it from the Start menu.
- **Linux** — You already know where your terminal is.

### 2. Install Git

- **Mac** — The first time you run `git` in Terminal, macOS will prompt you to install the Command Line Tools. Say yes and wait for it to finish.
- **Windows** — Git for Windows (step 1) includes Git. You're done.
- **Linux** — `sudo apt install git` (Debian/Ubuntu) or `sudo dnf install git` (Fedora).

Verify it worked:

```bash
git --version
```

### 3. Install Python

You need Python 3.

- **Mac** — macOS includes Python 3 on recent versions. Check with `python3 --version`. If it's missing, install it from [python.org](https://www.python.org/downloads/).
- **Windows** — Download from [python.org](https://www.python.org/downloads/). During installation, **check the box that says "Add Python to PATH"**.
- **Linux** — `sudo apt install python3 python3-pip` or equivalent.

### 4. Get the code

```bash
git clone https://github.com/ybroze/brozenet-qwen.git
cd brozenet-qwen
```

### 5. Install dependencies

```bash
pip install -r requirements.txt
```

(Use `pip3` instead of `pip` if your system distinguishes them.)

### 6. Set your environment variables

Yuri will give you an API key. Set it in your terminal session like this:

```bash
export QWEN_HOST=https://qwen.broze.net
export QWEN_API_KEY=paste-your-key-here
```

These only last for the current terminal session. If you close the terminal, you'll need to set them again. To make them permanent, add those two lines to your shell profile:

- **Mac / Linux** — `~/.bashrc` or `~/.zshrc`
- **Windows (Git Bash)** — `~/.bashrc`

Then restart your terminal (or run `source ~/.bashrc`).

### 7. Chat

```bash
./chat.py
```

Type your message and press Enter. The AI responds in real time. Press `Ctrl-C` to quit.

Or, for a web interface:

```bash
./chat-server.py
```

Then open [http://localhost:5678](http://localhost:5678) in your browser.

## Architecture

- `app/Dockerfile` — Ollama + nginx, model baked in at build time
- `app/entrypoint.sh` — starts nginx (foreground) and Ollama (background)
- `app/nginx.conf.template` — bearer token auth, reverse proxy to Ollama
- `ansible/playbook.yml` — provisions APIs, SA, secrets, Cloud Build, Cloud Run, scheduler, domain
- `deploy.sh` — one-line wrapper around the Ansible playbook
