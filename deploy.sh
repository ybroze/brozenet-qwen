#!/bin/bash
set -e
SECRETS=~/Secrets/ziggy-ansible-secrets.yml
echo "=== Qwen Personal Assistant Deploy (llama.cpp + L4 + IAP) ==="
if [ ! -f "$SECRETS" ]; then
  echo "ERROR: Secrets file not found at $SECRETS"
  exit 1
fi
ansible-playbook ansible/playbook.yml --extra-vars "@$SECRETS" "$@"
echo "Done! Check the debug output above for DNS records and IAP link."
