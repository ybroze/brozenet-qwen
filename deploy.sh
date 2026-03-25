#!/bin/bash
set -e
echo "=== Qwen3.5-122B GCP Cloud Run Deploy (Ansible + IAP + qwen.broze.net) ==="
ansible-playbook ansible/playbook.yml "$@"
echo "✅ Done! Check the debug output above for DNS records and IAP link."
