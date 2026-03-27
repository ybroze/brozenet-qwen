#!/bin/bash
set -e
gcloud run services update qwen-llm --min-instances=0 --region=us-east4 --project=broze-net
